#!/usr/bin/env python3
"""run.py: start and stop a whole run of OpenCode sessions (docs/process/OPERATOR.md).

  make start-run [DRY=1]          admit the run and open one iTerm tab per session of work/roster.toml
  make stop-run [WAIT=<minutes>]  drain, integrate, release every lock, reset the state, close the tabs
  make run-status                 what the roster's sessions are doing (heartbeats, locks, hand-offs)

`work/roster.toml` lists the sessions: name, role, OpenCode model id, reasoning-effort variant and
the heading of the prompt block in docs/process/START-AGENT.md (`## The prompt for <heading>`).
`start` writes each prompt to build/run/<name>.prompt.md, sets the shared control to `running` (the
human's admission: this command is the human's), and opens an iTerm tab per session running
tools/agent/open_session.sh, which starts `opencode mini --model <model>#<variant> --prompt "<the
block>"` in the main checkout. Session pids and iTerm ids go to build/run/<name>.json so `stop` can
close exactly what `start` opened.

`stop` is the graceful shutdown: control `draining` (no new claims; holders finish and hand off), wait
for the roster's heartbeats to say `stopped` (up to WAIT minutes, default 20), `make integrate` for
everything handed off, then the reset: every remaining lock released with an operator record, merged
clean worktrees removed and their branches deleted, heartbeats marked stopped, control `stopped`, the
OpenCode processes terminated and their tabs closed. Branches with unmerged commits are kept (the next
claimer continues from them) and listed. The clone is then ready for `make start-run` again.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import signal
import subprocess
import sys
import time
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402
import heartbeat  # noqa: E402

ROSTER = common.ROOT / "work/roster.toml"
START_AGENT = common.ROOT / "docs/process/START-AGENT.md"
RUN_DIR = common.ROOT / "build/run"
OPEN_SESSION = common.ROOT / "tools/agent/open_session.sh"


def roster() -> list[dict]:
    rows = tomllib.loads(ROSTER.read_text()).get("session", [])
    for r in rows:
        check_session(r)
    return rows


def check_session(r: dict) -> None:
    for k in ("name", "role", "model", "variant", "heading"):
        if not r.get(k):
            raise ValueError("work/roster.toml: every session needs %s" % k)
    common.identifier(r["name"], "session name")
    common.identifier(r["variant"], "variant")
    if "#" in r["model"]:
        raise ValueError("work/roster.toml: model is the id without a #variant suffix")


def model_spec(r: dict) -> str:
    """The OpenCode `--model` value: `<provider/model>#<variant>`."""
    return "%s#%s" % (r["model"], r["variant"])


def prompt_block(text: str, heading: str) -> str:
    """The ````markdown fenced block under `## The prompt for <heading>` in START-AGENT.md."""
    m = re.search(r"^## The prompt for %s\s*\n(?:.*?\n)*?````markdown\n(.*?)\n````" % re.escape(heading),
                  text, re.S | re.M)
    if not m:
        raise ValueError("docs/process/START-AGENT.md has no prompt block '## The prompt for %s'" % heading)
    return m.group(1).rstrip() + "\n"


def osascript(script: str) -> str:
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("osascript: %s" % r.stderr.strip())
    return r.stdout.strip()


def open_tab(name: str, first: bool) -> str:
    """Open an iTerm tab running open_session.sh for `name`; return the iTerm session id."""
    cmd = "cd %s && exec sh %s %s" % (common.ROOT, OPEN_SESSION, name)
    if first:
        script = ('tell application "iTerm"\n activate\n set w to (create window with default profile)\n'
                  ' tell current session of w\n  write text "%s"\n  return unique id\n end tell\nend tell' % cmd)
    else:
        script = ('tell application "iTerm"\n tell current window\n  set t to (create tab with default profile)\n'
                  '  tell current session of t\n   write text "%s"\n   return unique id\n  end tell\n end tell\nend tell' % cmd)
    return osascript(script)


def close_tab(session_id: str) -> None:
    script = ('tell application "iTerm"\n repeat with w in windows\n  repeat with t in tabs of w\n'
              '   repeat with s in sessions of t\n    if unique id of s is "%s" then\n     close t\n     return\n'
              '    end if\n   end repeat\n  end repeat\n end repeat\nend tell' % session_id)
    try:
        osascript(script)
    except RuntimeError:
        pass


def admit(state: str, reason: str) -> None:
    subprocess.run([sys.executable, str(common.ROOT / "tools/agent/control.py"), "--state", state,
                    "--operator", "--reason", reason], cwd=common.ROOT, check=True)


def start(dry: bool) -> int:
    main_dir = common.main_checkout()
    if common.ROOT.resolve() != main_dir.resolve() or common.git("branch", "--show-current") != "main":
        raise ValueError("start-run runs in the main checkout on branch main")
    if common.git("status", "--porcelain", "--untracked-files=no", "--", "src", "re", "tools", "tests"):
        raise ValueError("main has uncommitted changes in src/, re/, tools/ or tests/: commit them first")
    rows = roster()
    text = START_AGENT.read_text()
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    prompts = {r["name"]: prompt_block(text, r["heading"]) for r in rows}
    owners = [common.fields(p.read_text()).get("agent") for p in common.lock_dir().glob("*.lock")]
    held = [r["name"] for r in rows if r["name"] in owners]
    if held:
        raise ValueError("these roster names still hold locks: %s; run make stop-run first" % ", ".join(held))
    for r in rows:
        (RUN_DIR / (r["name"] + ".prompt.md")).write_text(prompts[r["name"]])
    if dry:
        for r in rows:
            print("start-run: would open a tab for %s (%s, %s) with %d bytes of prompt" % (
                r["name"], r["role"], model_spec(r), len(prompts[r["name"]])))
        return 0
    admit("running", "human: make start-run admitted the roster %s" % ", ".join(r["name"] for r in rows))
    run_id = control.state().get("run_id", "")
    for k, r in enumerate(rows):
        meta = {"name": r["name"], "role": r["role"], "model": r["model"], "variant": r["variant"],
                "run_id": run_id, "started": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
        (RUN_DIR / (r["name"] + ".json")).write_text(json.dumps(meta, indent=1))
        meta["iterm_session"] = open_tab(r["name"], first=(k == 0))
        (RUN_DIR / (r["name"] + ".json")).write_text(json.dumps(meta, indent=1))
        print("start-run: %s (%s, %s) opened in iTerm" % (r["name"], r["role"], model_spec(r)))
        time.sleep(1.0)
    print("start-run: %d sessions started; watch with make run-status or make watch-agents" % len(rows))
    return 0


def session_meta() -> list[dict]:
    out = []
    for p in sorted(RUN_DIR.glob("*.json")) if RUN_DIR.exists() else []:
        try:
            out.append(json.loads(p.read_text()))
        except ValueError:
            continue
    return out


def pid_of(name: str) -> int | None:
    p = RUN_DIR / (name + ".pid")
    try:
        return int(p.read_text().strip())
    except (OSError, ValueError):
        return None


def alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def beat_state(name: str) -> str:
    p = heartbeat.heartbeat_dir() / (name + ".txt")
    if not p.exists():
        return "none"
    return common.fields(p.read_text()).get("state", "?")


def status() -> int:
    names = [r["name"] for r in roster()]
    for n in names:
        pid = pid_of(n)
        print("%-14s heartbeat %-8s process %s" % (n, beat_state(n), ("alive pid %d" % pid) if alive(pid) else "gone"))
    subprocess.run(["make", "locks"], cwd=common.ROOT)
    subprocess.run(["make", "handoffs"], cwd=common.ROOT, capture_output=True)
    subprocess.run([sys.executable, str(common.ROOT / "tools/agent/inbox.py")], cwd=common.ROOT)
    return 0


def stop(wait_minutes: float) -> int:
    main_dir = common.main_checkout()
    names = [r["name"] for r in roster()]
    admit("draining", "human: make stop-run; finish current tasks, hand off, stop")
    deadline = time.monotonic() + wait_minutes * 60
    print("stop-run: draining; waiting up to %.0f minutes for %s to hand off" % (wait_minutes, ", ".join(names)))
    while time.monotonic() < deadline:
        busy = [n for n in names if beat_state(n) not in ("stopped", "none") and alive(pid_of(n))]
        if not busy:
            break
        time.sleep(15)
    else:
        print("stop-run: still working after the wait: %s; stopping them anyway" % ", ".join(busy))
    # Everything handed off lands now; what is not handed off stays on its branch.
    subprocess.run(["make", "integrate"], cwd=main_dir)
    kept = []
    for p in sorted(common.lock_dir().glob("*.lock")):
        key = p.stem
        f = common.fields(p.read_text())
        branch = f.get("branch", "")
        ahead = common.git("rev-list", "--count", "main..%s" % branch, cwd=main_dir) if branch and \
            common.git("branch", "--list", branch, cwd=main_dir) else "0"
        subprocess.run([sys.executable, str(common.ROOT / "tools/agent/unlock.py"), key, "--operator", "--force",
                        "--reason", "human: make stop-run; work kept on %s (%s commits beyond main)" % (branch, ahead)],
                       cwd=main_dir)
        if ahead != "0":
            kept.append("%s (%s, %s commits beyond main, worktree kept)" % (key, branch, ahead))
    # Merged, clean worktrees go; anything with commits beyond main or uncommitted files stays.
    for row in common.git("worktree", "list", "--porcelain", cwd=main_dir).split("\n\n"):
        fld = dict(line.split(" ", 1) for line in row.splitlines() if " " in line)
        wt, ref = fld.get("worktree"), fld.get("branch", "")
        if not wt or not ref.startswith(("refs/heads/unit/", "refs/heads/review/", "refs/heads/task/")):
            continue
        branch = ref[len("refs/heads/"):]
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=wt, capture_output=True, text=True).stdout
        ahead = common.git("rev-list", "--count", "main..%s" % branch, cwd=main_dir)
        if dirty or ahead != "0":
            if not any(branch in k for k in kept):
                kept.append("%s (%s commits beyond main%s)" % (branch, ahead, ", uncommitted files" if dirty else ""))
            continue
        subprocess.run(["git", "worktree", "remove", wt], cwd=main_dir, capture_output=True)
        subprocess.run(["git", "branch", "-d", branch], cwd=main_dir, capture_output=True)
    for n in names:
        pid = pid_of(n)
        if alive(pid):
            os.kill(pid, signal.SIGTERM)
    time.sleep(3)
    for n in names:
        pid = pid_of(n)
        if alive(pid):
            os.kill(pid, signal.SIGKILL)
        if beat_state(n) not in ("stopped", "none"):
            heartbeat.beat(n, "stopped by make stop-run", done=True)
    for meta in session_meta():
        if meta.get("iterm_session"):
            close_tab(meta["iterm_session"])
        for ext in (".json", ".pid"):
            (RUN_DIR / (meta["name"] + ext)).unlink(missing_ok=True)
    admit("stopped", "human: make stop-run finished; state reset")
    print("stop-run: done. locks: %d; control: stopped" % len(list(common.lock_dir().glob("*.lock"))))
    for k in kept:
        print("stop-run: kept %s" % k)
    subprocess.run([sys.executable, str(common.ROOT / "tools/agent/inbox.py")], cwd=main_dir)
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("action", choices=("start", "stop", "status"))
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--wait", type=float, default=20.0, help="minutes to wait for workers to hand off (stop)")
    a = ap.parse_args(argv)
    try:
        if a.action == "start":
            return start(a.dry)
        if a.action == "stop":
            return stop(a.wait)
        return status()
    except (ValueError, RuntimeError, OSError) as e:
        print("run: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

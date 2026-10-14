#!/usr/bin/env python3
"""run.py: start and stop a whole run of agent sessions (docs/process/OPERATOR.md).

  make start-run [DRY=1]          admit the run and open one iTerm tab per session of work/roster.toml
  make stop-run [WAIT=<minutes>]  drain, let workers hand off, integrate, release every lock, reset, close
  make run-status                 what the roster's sessions are doing (heartbeats, locks, hand-offs)

`work/roster.toml` lists the sessions: `name`, `role` and OpenCode `model` id, and optionally `mode`.
A session runs in one of two modes:

  worker       the default for `decompiler` and `reviewer`: the tab runs the supervisor of
               docs/process/WORKER.md (`tools/agent/worker.py`), which claims, starts one fresh
               `opencode run` session per batch of routines (or per review), verifies, hands off and
               claims again until the control is no longer `running`. A model that ends its turn or
               fills its context costs one batch, never the run. Optional fields: `variant` (OpenCode
               model variant, passed as `<model>#<variant>`), `batch` (routines per session) and
               `timeout` (minutes per session).
  interactive  the default for every other role (orchestrator, expert, documentarian): the tab runs
               `opencode mini --model <model> --prompt "<the block>"` with the prompt block of
               docs/process/START-AGENT.md named by `heading` (`## The prompt for <heading>`). Such a
               session lives for as long as its model keeps working in one turn; nothing prompts it again.

2026-10-13 run review: every decompiler and the reviewer of an all-interactive roster stopped on their
own within 90 minutes while work remained, each at a "clean boundary" as its context grew. Worker mode
is the fix the supervisor already provided.

`start` writes each interactive prompt to build/run/<name>.prompt.md and each session's settings to
build/run/<name>.json, sets the shared control to `running` (the human's admission: this command is the
human's), and opens an iTerm tab per session running tools/agent/open_session.sh, which hands a worker
session to `run.py session <name>` (the supervisor in this process, its output also appended to
build/run/<name>.log) and an interactive one to `opencode mini`. Session pids and iTerm ids go to
build/run/ so `stop` can close exactly what `start` opened.

`stop` is the graceful shutdown: control `draining` (no new claims; holders finish and hand off), wait
for the roster's heartbeats to say `stopped` (up to WAIT minutes, default 20), then SIGTERM to every
session still running; a worker answers it by killing its model session, saving uncommitted changes and
handing its branch off, and `stop` waits for that (up to five minutes) before `make integrate` merges
everything handed off. Then the reset: every remaining lock released with an operator record, merged
clean worktrees removed and their branches deleted, heartbeats marked stopped, control `stopped`, the
tabs closed. Branches with unmerged commits are kept (the next claimer continues from them) and listed.
The clone is then ready for `make start-run` again.
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
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


WORKER_ROLES = ("decompiler", "reviewer")
WORKER_STOP_SECONDS = 300            # a worker's hand-off after SIGTERM runs make check (about a minute)


def mode_of(row: dict) -> str:
    return row.get("mode") or ("worker" if row.get("role") in WORKER_ROLES else "interactive")


def roster() -> list[dict]:
    rows = tomllib.loads(ROSTER.read_text()).get("session", [])
    for r in rows:
        for k in ("name", "role", "model"):
            if not r.get(k):
                raise ValueError("work/roster.toml: every session needs %s" % k)
        common.identifier(r["name"], "session name")
        mode = mode_of(r)
        if mode not in ("worker", "interactive"):
            raise ValueError("work/roster.toml: %s: mode is worker or interactive, not %r" % (r["name"], mode))
        if mode == "worker" and r["role"] not in WORKER_ROLES:
            raise ValueError("work/roster.toml: %s: only decompilers and reviewers run as workers" % r["name"])
        if mode == "interactive" and not r.get("heading"):
            raise ValueError("work/roster.toml: %s: an interactive session needs heading" % r["name"])
        for k in ("batch", "timeout"):
            if k in r and (isinstance(r[k], bool) or not isinstance(r[k], (int, float)) or r[k] <= 0):
                raise ValueError("work/roster.toml: %s: %s must be a positive number" % (r["name"], k))
    return rows


def worker_argv(row: dict, run_id: str) -> list[str]:
    """The supervisor's arguments for a worker-mode roster row (docs/process/WORKER.md)."""
    variant = row.get("variant", "")
    argv = ["--agent", row["name"], "--role", row["role"], "--harness", "opencode", "--model", row["model"],
            "--session", "%s-run-%s" % (row["name"], (run_id or "none")[:8]),
            "--session-model", row["model"] + ("#" + variant if variant else "")]
    if variant:
        argv += ["--variant", variant]
    for key, opt in (("batch", "--batch"), ("timeout", "--timeout")):
        if key in row:
            argv += [opt, str(row[key])]
    return argv


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
    prompts = {r["name"]: prompt_block(text, r["heading"]) for r in rows if mode_of(r) == "interactive"}
    owners = [common.fields(p.read_text()).get("agent") for p in common.lock_dir().glob("*.lock")]
    held = [r["name"] for r in rows if r["name"] in owners]
    if held:
        raise ValueError("these roster names still hold locks: %s; run make stop-run first" % ", ".join(held))
    # A worker registers its name at start; a name whose heartbeat is still active cannot be registered
    # again, and the tab of a worker that exits at once is easy to miss.
    active = [r["name"] for r in rows if mode_of(r) == "worker" and beat_state(r["name"]) not in ("stopped", "none")]
    if active:
        raise ValueError("these worker names still have an active heartbeat: %s; run make stop-run first "
                         "or rename them" % ", ".join(active))
    for name, prompt in prompts.items():
        (RUN_DIR / (name + ".prompt.md")).write_text(prompt)
    if dry:
        for r in rows:
            what = ("make worker %s" % " ".join(worker_argv(r, "dry")) if mode_of(r) == "worker" else
                    "opencode mini with %d bytes of prompt" % len(prompts[r["name"]]))
            print("start-run: would open a tab for %s (%s, %s): %s" % (r["name"], r["role"], r["model"], what))
        return 0
    admit("running", "human: make start-run admitted the roster %s" % ", ".join(r["name"] for r in rows))
    run_id = control.state().get("run_id", "")
    for k, r in enumerate(rows):
        meta = {"name": r["name"], "role": r["role"], "model": r["model"], "mode": mode_of(r), "run_id": run_id,
                "started": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
        if meta["mode"] == "worker":
            meta["worker_argv"] = worker_argv(r, run_id)
        (RUN_DIR / (r["name"] + ".json")).write_text(json.dumps(meta, indent=1))
        meta["iterm_session"] = open_tab(r["name"], first=(k == 0))
        (RUN_DIR / (r["name"] + ".json")).write_text(json.dumps(meta, indent=1))
        print("start-run: %s (%s, %s, %s) opened in iTerm" % (r["name"], r["role"], r["model"], meta["mode"]))
        time.sleep(1.0)
    print("start-run: %d sessions started; watch with make run-status or make watch-agents" % len(rows))
    return 0


class Tee(io.TextIOBase):
    """Write to the terminal and to the session log at once."""

    def __init__(self, *streams):
        self.streams = streams

    def write(self, s: str) -> int:
        for st in self.streams:
            st.write(s)
            st.flush()
        return len(s)

    def flush(self) -> None:
        for st in self.streams:
            st.flush()


def session(name: str) -> int:
    """The process of one roster tab (open_session.sh execs it for a worker-mode session)."""
    meta = json.loads((RUN_DIR / (common.identifier(name, "session name") + ".json")).read_text())
    if meta.get("mode") != "worker":
        raise ValueError("%s is not a worker-mode session; open_session.sh starts opencode mini for it" % name)
    import worker
    with (RUN_DIR / (name + ".log")).open("a") as log:
        out, err = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = Tee(out, log), Tee(err, log)
        try:
            print("session %s: worker %s" % (name, " ".join(meta["worker_argv"])), flush=True)
            rc = worker.main(meta["worker_argv"])
        finally:
            sys.stdout, sys.stderr = out, err
    if rc not in (0, 130):
        print("session %s: the worker exited with %d (log: build/run/%s.log); press Enter to close" % (name, rc, name))
        try:
            input()
        except (EOFError, KeyboardInterrupt):
            pass
    return rc


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
    for r in roster():
        n = r["name"]
        pid = pid_of(n)
        print("%-16s %-11s heartbeat %-8s process %s" % (n, mode_of(r), beat_state(n),
                                                         ("alive pid %d" % pid) if alive(pid) else "gone"))
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
    # SIGTERM before integrating: a worker answers it with a hand-off (make check, then make handoff),
    # which must land in this integration, and no lock may be released under a live supervisor.
    signal_sessions(names, signal.SIGTERM)
    deadline = time.monotonic() + WORKER_STOP_SECONDS
    while time.monotonic() < deadline and any(alive(pid_of(n)) for n in names):
        time.sleep(5)
    signal_sessions(names, signal.SIGKILL)
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


def signal_sessions(names: list[str], sig: int) -> None:
    for n in names:
        pid = pid_of(n)
        if alive(pid):
            try:
                os.kill(pid, sig)
            except OSError:
                pass


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("action", choices=("start", "stop", "status", "session"))
    ap.add_argument("name", nargs="?", default="", help="the roster session (session)")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--wait", type=float, default=20.0, help="minutes to wait for workers to hand off (stop)")
    a = ap.parse_args(argv)
    try:
        if a.action == "start":
            return start(a.dry)
        if a.action == "stop":
            return stop(a.wait)
        if a.action == "session":
            return session(a.name)
        return status()
    except (ValueError, RuntimeError, OSError) as e:
        print("run: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

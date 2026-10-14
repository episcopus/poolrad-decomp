#!/usr/bin/env python3
"""integrator.py: the scripted integration loop of a run (docs/process/OPERATOR.md).

  .venv/bin/python tools/agent/integrator.py --agent int-loop [--interval 120] [--model <provider/model>
      --variant <v> --session <label> --session-model <provider/model#variant>] [--timeout 30] [--once]

Why (2026-10-14 run): the interactive orchestrator session wrote a good report, said "I'm continuing the
loop", ended its turn and was idle for an hour while five hand-offs waited and the reviewer starved.
Integration is a script (`make integrate`); keeping it moving needs no model. `make start-run` starts
this loop for a roster entry with `role = "integrator"` (mode `script`), in its own tab like a worker.

Every INTERVAL seconds while the shared control is `running` or `draining` (paused: wait; stopped: exit):

  1. `make integrate` when a branch hand-off waits (integrate.py holds an exclusive lock, so a run of
     it by a human or an orchestrator at the same time is skipped, not doubled).
  2. A hand-off `make integrate` rejected for a merge conflict or a red check gets at most
     RESOLVE_ATTEMPTS tries per pinned commit, in the branch's worktree (the worker's, or a new one
     under ../poolrad-worktrees/<key>), which must be clean:
       a. mechanical: `git merge main`, `make rename APPLY=1`, `make check`; green means re-integrate;
       b. otherwise, when a resolver model is configured, ONE fresh model session from
          tools/agent/resolve_prompt.md does the same with judgment (keep both sides), killed and
          interrupted after TIMEOUT minutes like a worker's session; its result must leave the tree clean,
          free of conflict markers, with main merged in, or every commit since is saved as patches
          (build/integrator/<key>-commits/) and the branch reset.
     Then `make integrate KEY=<key>`. A rejection for lost records (merge-check) or a missing branch is
     never retried: it stays in `make inbox` for the human. So does a hand-off whose attempts are spent.
  3. `make expert-scan` when the human admitted an expert budget for this run and dispatch is not
     frozen (expert.py skips matched routines and caps the waiting queue itself).
  4. A heartbeat saying what waits.

SIGTERM or SIGINT (make stop-run): a running integration finishes (it is atomic and takes a minute or
two), a resolver session is killed and interrupted and its branch reset, then a `stopped` heartbeat.
Attempts live in poolrad-integrator.json in the clone's git directory; logs in build/integrator/.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402
import heartbeat  # noqa: E402
import identity  # noqa: E402
import integrate  # noqa: E402
import worker  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_INTERVAL = 120
DEFAULT_TIMEOUT_MINUTES = 30
RESOLVE_ATTEMPTS = 2
RETRYABLE = ("merge conflict", "make check failed")


def state_path() -> Path:
    return common.common_dir() / "poolrad-integrator.json"


def load_state() -> dict:
    try:
        data = json.loads(state_path().read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(data: dict) -> None:
    common.atomic_write(state_path(), json.dumps(data, indent=1, sort_keys=True) + "\n")


def rejected() -> list[tuple[Path, dict]]:
    """Branch hand-offs make integrate rejected, oldest first."""
    out = []
    for p in sorted(integrate.handoff_dir().glob("*.md"), key=lambda p: p.stat().st_mtime):
        f = common.fields(p.read_text())
        if f.get("state") in integrate.BRANCH_STATES and f.get("integrate") == "rejected":
            out.append((p, f))
    return out


def worktree_of(branch: str, main_dir: Path) -> Path | None:
    for row in common.git("worktree", "list", "--porcelain", cwd=main_dir).split("\n\n"):
        fld = dict(line.split(" ", 1) for line in row.splitlines() if " " in line)
        if fld.get("branch") == "refs/heads/" + branch:
            return Path(fld["worktree"])
    return None


def git_ok(args: list[str], cwd: Path) -> bool:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True).returncode == 0


class Loop:
    def __init__(self, agent: str, interval: float, session_cmd: str, session_model: str, timeout_minutes: float,
                 harness: str = "", model: str = "", session: str = "", variant: str = "", sleep=None):
        self.agent = common.identifier(agent, "agent")
        if self.agent == integrate.AGENT:
            raise ValueError("the loop needs its own name: %r is the identity make integrate registers" % agent)
        self.interval = interval
        self.session_cmd = session_cmd
        self.session_model = session_model
        self.timeout_s = timeout_minutes * 60
        self.identity = (harness, model, session, variant)
        self.sleep = sleep or time.sleep
        self.main = common.main_checkout()
        self.logs = self.main / "build/integrator"
        self.stopping = False
        self.in_session = False
        self.py = sys.executable

    # ---- small helpers
    def say(self, note: str, done: bool = False) -> None:
        print("integrator %s: %s" % (self.agent, " ".join(note.split())), flush=True)
        try:
            heartbeat.beat(self.agent, note, done=done)
        except Exception:
            pass

    def tool(self, args: list[str], log: Path | None = None) -> tuple[int, str]:
        """Run a tools/agent script from the main checkout; (exit code, output), output also logged."""
        r = subprocess.run([self.py, *args], cwd=self.main, capture_output=True, text=True)
        out = r.stdout + r.stderr
        if log:
            log.parent.mkdir(parents=True, exist_ok=True)
            with log.open("a") as f:
                f.write("\n$ %s   (%s)\n%s$ exit %d\n" % (" ".join(args), now(), out, r.returncode))
        return r.returncode, out

    def make(self, wt: Path, args: list[str], log: Path) -> int:
        return worker.run_make(wt, args, log)

    def handle_signal(self, signum, _frame):
        self.stopping = True
        if self.in_session:                                  # kill the resolver now; integrations finish
            raise worker.Interrupted(signal.Signals(signum).name)

    # ---- the loop
    def run(self, once: bool = False) -> int:
        harness, model, session, variant = self.identity
        if model:
            identity.ensure(self.agent, "orchestrator", harness or "script", model, session or self.agent, variant)
        else:
            identity.ensure(self.agent, "orchestrator", "script", "script", self.agent)
        self.say("integrator started; every %d s" % self.interval)
        while not self.stopping:
            st = control.state()["state"]
            if st == "stopped":
                break
            if st != "paused":
                try:
                    note = self.step()
                except worker.Interrupted:
                    break
                except Exception as e:                       # noqa: BLE001  keep looping; report it
                    note = "pass failed: %s: %s" % (type(e).__name__, " ".join(str(e).split())[:200])
                self.say(note)
            if once:
                break
            waited = 0.0
            while waited < self.interval and not self.stopping:
                self.sleep(min(5.0, self.interval - waited))
                waited += 5.0
        self.say("integrator stopped (%s)" % ("signal" if self.stopping else "control is stopped"), done=True)
        return 0

    def step(self) -> str:
        notes = []
        waiting = integrate.pending()
        if waiting:
            rc, out = self.tool([str(HERE / "integrate.py")], self.logs / "integrate.log")
            merged = len(re.findall(r"^integrate: main is now", out, re.M))
            notes.append("integrated %d of %d%s" % (merged, len(waiting), " (busy: another integrate ran)" if rc == 3 else ""))
        for path, f in rejected():
            if self.stopping:
                break
            notes.append(self.resolve(path, f))
        scanned = self.expert_scan()
        if scanned:
            notes.append(scanned)
        left = integrate.pending()
        held = rejected()
        notes.append("waiting %d, rejected %d%s" % (len(left), len(held),
                     " (%s)" % ", ".join(p.stem for p, _ in held) if held else ""))
        return "; ".join(notes)

    # ---- rejected hand-offs
    def resolve(self, path: Path, f: dict) -> str:
        key, branch, commit = path.stem, f.get("branch", ""), f.get("commit", "")
        reason = f.get("integrate_reason", "")
        if not reason.startswith(RETRYABLE):
            return "%s left for the human (%s)" % (key, reason[:60])
        data = load_state()
        entry = data.get(key) if data.get(key, {}).get("commit") == commit else None
        entry = entry or {"commit": commit, "attempts": 0}
        if entry["attempts"] >= RESOLVE_ATTEMPTS:
            return "%s left for the human (%d resolve attempts spent)" % (key, entry["attempts"])
        wt = worktree_of(branch, self.main)
        if wt is None:
            wt = self.main.parent / "poolrad-worktrees" / key
            if wt.exists() or not git_ok(["worktree", "add", str(wt), branch], self.main):
                return "%s: no worktree for %s and none could be made" % (key, branch)
            integrate.link_tools(self.main, wt)
        if common.git("status", "--porcelain", "--untracked-files=no", cwd=wt):
            return "%s: worktree %s has uncommitted changes; not touched" % (key, wt)
        entry["attempts"] += 1
        entry["last"] = now()
        data[key] = entry
        save_state(data)
        self.logs.mkdir(parents=True, exist_ok=True)
        log = self.logs / ("%s-resolve.log" % key)
        start = worker.head_of(wt)
        self.say("resolving %s (attempt %d): %s" % (key, entry["attempts"], reason[:80]))
        how = self.mechanical(wt, log, start)
        if not how and self.session_cmd and self.session_model:
            how = self.model_session(wt, log, start, key, f)
        if not how:
            return "%s: could not be brought up to date with main (attempt %d, log %s)" % (key, entry["attempts"], log)
        rc, out = self.tool([str(HERE / "integrate.py"), "--key", key], log)
        if rc == 0:
            data = load_state()
            data.pop(key, None)
            save_state(data)
            control.event("integrator-resolved", agent=self.agent, key=key, how=how)
            return "%s resolved (%s) and integrated" % (key, how)
        return "%s resolved (%s) but make integrate still rejects it (log %s)" % (key, how, log)

    def mechanical(self, wt: Path, log: Path, start: str) -> str:
        """`git merge main` with no conflict, the recorded renames, a green check: no model needed."""
        r = subprocess.run(["git", "merge", "--no-edit", "main"], cwd=wt, capture_output=True, text=True)
        with log.open("a") as fh:
            fh.write("\n$ git merge main   (%s)\n%s%s$ exit %d\n" % (now(), r.stdout, r.stderr, r.returncode))
        if r.returncode:
            git_ok(["merge", "--abort"], wt)
            return ""
        if self.make(wt, ["rename", "APPLY=1"], log) == 0 and common.git("status", "--porcelain", "--untracked-files=no", cwd=wt):
            common.git("commit", "-qam", "re: replay recorded renames after merging main (integrator)",
                       "--trailer", "Agent: %s" % self.agent, cwd=wt)
        if self.make(wt, ["check"], log) == 0:
            return "mechanical merge of main"
        worker.reset_batch(wt, start, self.logs / ("%s-mechanical-commits" % wt.name))
        return ""

    def model_session(self, wt: Path, log: Path, start: str, key: str, f: dict) -> str:
        prompt = self.logs / ("%s-resolve.prompt.md" % key)
        prompt.parent.mkdir(parents=True, exist_ok=True)
        prompt.write_text(worker.render(HERE / "resolve_prompt.md", dict(
            worktree=str(wt), branch=f.get("branch", ""), key=key, owner=f.get("agent", "?"),
            state=f.get("state", "?"), reason=f.get("integrate_reason", ""),
            integrate_log=f.get("integrate_log", "(none)"), agent=self.agent)))
        flag = " --model " + shlex.quote(self.session_model)
        self.in_session = True
        try:
            result = worker.run_session(self.session_cmd, prompt, wt, log, self.timeout_s, flag,
                                        "%s resolve-%s" % (self.agent, key))
        except worker.Interrupted:
            self.in_session = False
            self.abandon(wt, start, key, log)
            raise
        finally:
            self.in_session = False
        unfinished = git_ok(["rev-parse", "-q", "--verify", "MERGE_HEAD"], wt)
        if unfinished:                                     # the session gave up inside the merge
            git_ok(["merge", "--abort"], wt)
        dirty = worker.salvage(wt, self.logs / ("%s-resolve.patch" % key))
        markers = git_ok(["grep", "-q", "-E", r"^(<<<<<<<|>>>>>>>) ", "HEAD", "--"], wt)
        merged = git_ok(["merge-base", "--is-ancestor", "main", "HEAD"], wt)
        if result.timed_out or unfinished or dirty or markers or not merged or worker.head_of(wt) == start:
            self.abandon(wt, start, key, log)
            return ""
        return "model session %s" % (result.session_id or "")

    def abandon(self, wt: Path, start: str, key: str, log: Path) -> None:
        git_ok(["merge", "--abort"], wt)
        n = worker.reset_batch(wt, start, self.logs / ("%s-resolve-commits" % key))
        with log.open("a") as fh:
            fh.write("$ abandoned: %d commit(s) saved and %s reset to %s\n" % (n, wt, start[:12]))

    # ---- the expert queue
    def expert_scan(self) -> str:
        policy = common.common_dir() / "poolrad-expert" / "policy.json"
        try:
            p = json.loads(policy.read_text())
        except (OSError, ValueError):
            return ""
        if p.get("run_id") != control.state().get("run_id") or p.get("frozen"):
            return ""
        rc, out = self.tool([str(HERE / "expert.py"), "scan", "--agent", self.agent], self.logs / "expert-scan.log")
        try:
            queued = [c for c in json.loads(out.strip().splitlines()[-1]) if c.get("case_id")]
        except (ValueError, IndexError, AttributeError):
            return ""
        return "queued %d expert case(s)" % len(queued) if queued else ""


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--agent", default="int-loop")
    ap.add_argument("--interval", type=float, default=DEFAULT_INTERVAL)
    ap.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_MINUTES, help="minutes per resolver session")
    ap.add_argument("--session-cmd", default=worker.DEFAULT_SESSION_CMD)
    ap.add_argument("--session-model", default="", help="the resolver's OpenCode model (provider/model#variant); empty: no model")
    ap.add_argument("--harness", default="")
    ap.add_argument("--model", default="")
    ap.add_argument("--session", default="")
    ap.add_argument("--variant", default="")
    ap.add_argument("--once", action="store_true", help="one pass, then exit")
    a = ap.parse_args(argv)
    try:
        loop = Loop(a.agent, a.interval, a.session_cmd, a.session_model, a.timeout,
                    a.harness, a.model, a.session, a.variant)
    except (ValueError, RuntimeError, OSError) as e:
        print("integrator: %s" % e, file=sys.stderr)
        return 2
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, loop.handle_signal)
    return loop.run(a.once)


if __name__ == "__main__":
    sys.exit(main())

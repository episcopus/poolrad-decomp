#!/usr/bin/env python3
"""heartbeat.py: tell the human what you are doing, so a quiet agent is not mistaken for a hung one.

  make heartbeat AGENT=<you> NOTE="<what you are doing now, what comes next>"  [DONE=1 when you stop]
  make agents                                       (everyone's last heartbeat, oldest first, with its age)

Every agent posts a heartbeat when it starts a step (claim, each routine, a long `make check`, a hand-off)
and at least every QUIET_MINUTES while it works; `make claim` and `make handoff` post one on their own, and
`make match`, `make check`, `make packet` and `make tpc` refresh the heartbeat of whoever holds the lock on
the current branch (`--auto`), keeping its last note and recording the command as its last activity, so an
agent that works without posting still shows as alive.
A heartbeat is a small file in the clone's git directory next to the locks and hand-offs
(tools/agent/common.py), so every worktree sees it and nothing is committed. Each agent has one file,
overwritten by its next heartbeat. `make agents` marks an agent QUIET when its last heartbeat is older
than QUIET_MINUTES and it has not said it stopped: the orchestrator reports those to the human, who
decides whether the agent is hung (a quiet agent is never unlocked for that alone; playbook 90).
"""
from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

QUIET_MINUTES = 20


def heartbeat_dir() -> Path:
    d = common.common_dir() / "poolrad-heartbeats"
    d.mkdir(exist_ok=True)
    return d


def fields(text: str) -> dict:
    return dict(l.split(" = ", 1) for l in text.splitlines() if " = " in l)


def beat(agent: str, note: str, done: bool = False) -> Path:
    try:
        branch = common.git("rev-parse", "--abbrev-ref", "HEAD", cwd=Path.cwd())
    except RuntimeError:
        branch = "?"
    p = heartbeat_dir() / ("%s.txt" % agent)
    p.write_text("agent = %s\ntime = %s\nbranch = %s\nstate = %s\nnote = %s\n" % (
        agent, dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), branch,
        "stopped" if done else "working", " ".join(note.split())))
    return p


def lock_owner(branch: str) -> str | None:
    """The agent whose lock names `branch` (unit/<id>, review/<id>, task/<name>), if any."""
    for lk in common.lock_dir().glob("*.lock"):
        f = fields(lk.read_text())
        if f.get("branch") == branch:
            return f.get("agent")
    return None


def auto(activity: str) -> str | None:
    """Refresh the heartbeat of the agent that holds the lock on the current branch; never fails."""
    try:
        branch = common.git("rev-parse", "--abbrev-ref", "HEAD", cwd=Path.cwd())
        agent = lock_owner(branch)
        if not agent:
            return None
        p = heartbeat_dir() / ("%s.txt" % agent)
        old = fields(p.read_text()) if p.exists() else {}
        p.write_text("agent = %s\ntime = %s\nbranch = %s\nstate = working\nnote = %s\nactivity = %s\n" % (
            agent, dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), branch,
            old.get("note", "working"), " ".join(activity.split())))
        return agent
    except Exception:                                          # a heartbeat must never break a build
        return None


def listing(now: dt.datetime | None = None) -> list[str]:
    now = now or dt.datetime.now(dt.timezone.utc)
    rows = []
    for p in heartbeat_dir().glob("*.txt"):
        f = fields(p.read_text())
        age = int((now - dt.datetime.fromisoformat(f["time"])).total_seconds() // 60)
        flag = "stopped" if f.get("state") == "stopped" else ("QUIET" if age > QUIET_MINUTES else "ok")
        note = f.get("note", "") + (" | last: %s" % f["activity"] if f.get("activity") else "")
        rows.append((-age, "%-8s %-10s %4d min ago  %-22s %s" % (flag, f["agent"], age, f.get("branch", "?"), note)))
    return [r for _, r in sorted(rows)]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--agent", default="")
    ap.add_argument("--note", default="")
    ap.add_argument("--done", action="store_true", help="you are stopping: no longer reported as QUIET")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--auto", metavar="ACTIVITY", help="refresh the lock owner's heartbeat (used by make targets)")
    a = ap.parse_args(argv)
    if a.auto is not None:
        auto(a.auto)
        return 0
    if a.list:
        rows = listing()
        print("\n".join(rows) if rows else "agents: no heartbeat yet")
        quiet = sum(r.startswith("QUIET") for r in rows)
        print("agents: %d, %d quiet for more than %d minutes (%s)" % (len(rows), quiet, QUIET_MINUTES,
                                                                       heartbeat_dir()))
        return 0
    if not a.agent or not a.note.strip():
        print('heartbeat: need AGENT=<you> NOTE="<what you are doing now>"', file=sys.stderr)
        return 2
    beat(a.agent, a.note, a.done)
    print("heartbeat: %s, %s" % (a.agent, "stopped" if a.done else "working"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

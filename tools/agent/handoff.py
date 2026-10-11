#!/usr/bin/env python3
"""handoff.py: tell the orchestrator a branch is ready to merge (playbooks 30, 70, 90).

  make handoff AGENT=<you> UNIT=<id> STATE=<state> NOTE="..."     (decompiler or reviewer)
  make handoffs                                                   (orchestrator: what is waiting)
  make handoff-done UNIT=<id> [REVIEW=1]                          (orchestrator, after merging)

STATE is one of: complete, partial, blocked, review-passed, review-failed. A hand-off is a small file in
the clone's git directory next to the locks (tools/agent/common.py), so every worktree sees it and nothing
is committed. It records the agent, the unit, the branch (the current one), its head commit, the state,
the note and the time.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

STATES = ("complete", "partial", "blocked", "review-passed", "review-failed")


def handoff_dir() -> Path:
    d = common.common_dir() / "poolrad-handoffs"
    d.mkdir(exist_ok=True)
    return d


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--unit", default=os.environ.get("UNIT", ""))
    ap.add_argument("--agent", default=os.environ.get("AGENT", ""))
    ap.add_argument("--state", default=os.environ.get("STATE", ""))
    ap.add_argument("--note", default=os.environ.get("NOTE", ""))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--done", action="store_true", help="remove the hand-off of UNIT (after the merge)")
    a = ap.parse_args(argv)
    if a.list:
        files = sorted(handoff_dir().glob("*.md"), key=lambda p: p.stat().st_mtime)
        for p in files:
            print(p.read_text().strip() + "\n")
        print("handoffs: %d waiting (%s)" % (len(files), handoff_dir()))
        return 0
    unit = a.unit.lower()
    if not unit:
        print("handoff: need UNIT=<id>", file=sys.stderr)
        return 2
    if a.done:                                       # the orchestrator names the hand-off: <id> or review-<id>
        (handoff_dir() / ("%s.md" % unit)).unlink(missing_ok=True)
        print("handoff: cleared %s" % unit)
        return 0
    branch = common.git("rev-parse", "--abbrev-ref", "HEAD")
    key = ("review-" + unit) if branch.startswith("review/") else unit
    path = handoff_dir() / ("%s.md" % key)
    if a.state not in STATES or not a.agent:
        print("handoff: need AGENT=<you> and STATE=%s" % "|".join(STATES), file=sys.stderr)
        return 2
    if common.git("status", "--porcelain", "--", "src", "re", "docs", "work", "tools", "tests"):
        print("handoff: commit your work first (git status is not clean)", file=sys.stderr)
        return 1
    head = common.git("rev-parse", "--short", "HEAD")
    path.write_text("unit = %s\nagent = %s\nbranch = %s\ncommit = %s\nstate = %s\ntime = %s\nnote = %s\n" % (
        unit, a.agent, branch, head, a.state, dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        a.note))
    print("handoff: %s (%s, %s) is waiting for the orchestrator" % (branch, a.state, head))
    return 0


if __name__ == "__main__":
    sys.exit(main())

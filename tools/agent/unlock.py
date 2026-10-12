#!/usr/bin/env python3
"""Release a lock only from main, after integration, or with an explicit operator recovery reason.

  make unlock AGENT=orch UNIT=ovl00
  make unlock UNIT=ovl00 OPERATOR=1 FORCE=1 REASON="human confirmed holder stopped"

The operator recovery path never discards work or removes a worktree. Actor names/flags are misuse
guards, not authentication; harness permissions must prevent workers impersonating the operator.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import control


def releasable(record: dict) -> None:
    branch = record.get("branch", "")
    if not branch.startswith(("unit/", "review/", "task/")):
        raise ValueError("lock has no valid work branch; use the operator recovery path")
    if not common.git("branch", "--list", branch):
        raise ValueError("branch is missing; use operator recovery rather than guessing that work was merged")
    common.git("merge-base", "--is-ancestor", branch, "main")
    for row in common.git("worktree", "list", "--porcelain").split("\n\n"):
        fields = dict(line.split(" ", 1) for line in row.splitlines() if " " in line)
        if fields.get("branch") == "refs/heads/" + branch:
            if common.git("status", "--porcelain", cwd=Path(fields["worktree"])):
                raise ValueError("worktree still has uncommitted or untracked work; leave its lock and files alone")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit", nargs="?", default=os.environ.get("UNIT", ""))
    ap.add_argument("--agent", default=os.environ.get("AGENT", ""))
    ap.add_argument("--operator", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--reason", default="")
    a = ap.parse_args(argv)
    try:
        key = common.identifier(a.unit, "unit or lock key")
        common.require_main("unlock")
        if a.operator:
            if not a.force or not a.reason.strip():
                raise ValueError("operator recovery needs FORCE=1 and REASON=<human instruction>")
            common.single_line(a.reason, "reason")
        elif a.agent != "orch" or a.force:
            raise ValueError("normal release needs AGENT=orch; workers never unlock, and FORCE requires OPERATOR=1")
        with control.coordination_lock():
            path = common.lock_path(key)
            if not path.exists():
                print("unlock: %s is not locked" % key)
                return 0
            record = common.fields(path.read_text())
            if not a.operator:
                if common.pending_handoff(key):
                    raise ValueError("hand-off is still pending; integrate and clear it before releasing")
                releasable(record)
            control.event("unlock", key=key, owner=record.get("agent"), agent=a.agent,
                          operator=a.operator, reason=a.reason)
            path.unlink()
        print("unlock: released %s; worktrees and branches untouched" % key)
        return 0
    except (ValueError, RuntimeError, OSError) as e:
        print("unlock: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

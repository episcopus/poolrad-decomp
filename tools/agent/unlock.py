#!/usr/bin/env python3
"""Release a lock only from main, after integration, or with an explicit operator recovery reason.

  make unlock AGENT=orch UNIT=ovl00
  make unlock UNIT=ovl00 OPERATOR=1 FORCE=1 REASON="human confirmed holder stopped"
  .venv/bin/python tools/agent/unlock.py ovl00 --agent dec-1 --owner      (a supervisor giving back an
                                                                           untouched claim)

The operator recovery path never discards work or removes a worktree. Actor names/flags are misuse
guards, not authentication; harness permissions must prevent workers impersonating the operator.

The owner path (`--owner`, used by tools/agent/worker.py) releases a claim that produced nothing: the
lock's `agent` must equal `--agent`, no hand-off may be pending for the key, the branch must have zero
commits beyond main and the worktree must be clean. It then removes the lock, the worktree and the
branch (there is nothing in them that main does not have) and records an `unlock` event with
`owner_release = True`. Anything else is refused: a claim with commits is handed off, never released.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import control
import identity


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


def worktree_of(branch: str) -> Path | None:
    for row in common.git("worktree", "list", "--porcelain").split("\n\n"):
        fields = dict(line.split(" ", 1) for line in row.splitlines() if " " in line)
        if fields.get("branch") == "refs/heads/" + branch:
            return Path(fields["worktree"])
    return None


def owner_release(key: str, agent: str, record: dict) -> str:
    """Release an untouched claim of `agent`: nothing beyond main, worktree clean, no hand-off. Removes the
    worktree and the branch too (an abandoned worktree is what the recovery path exists to protect, but
    one that holds nothing is only clutter). Returns a one-line description of what was removed."""
    common.identifier(agent, "agent")
    if record.get("agent") != agent:
        raise ValueError("%s is held by %s, not %s; an owner release needs the holder" % (
            key, record.get("agent"), agent))
    if common.pending_handoff(key):
        raise ValueError("hand-off is still pending; the orchestrator clears it after integration")
    branch = record.get("branch", "")
    if not branch.startswith(("unit/", "review/", "task/")):
        raise ValueError("lock has no valid work branch; use the operator recovery path")
    removed = []
    if common.git("branch", "--list", branch):
        if int(common.git("rev-list", "--count", "main.." + branch) or 0):
            raise ValueError("%s has commits beyond main; hand it off instead of releasing it" % branch)
        wt = worktree_of(branch)
        if wt is not None:
            if common.git("status", "--porcelain", cwd=wt):
                raise ValueError("worktree %s has uncommitted or untracked work; save or commit it first" % wt)
            common.git("worktree", "remove", "--force", str(wt))
            removed.append("worktree %s" % wt)
        common.git("branch", "-D", branch)
        removed.append("branch %s" % branch)
    return ", ".join(removed) or "nothing else"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit", nargs="?", default=os.environ.get("UNIT", ""))
    ap.add_argument("--agent", default=os.environ.get("AGENT", ""))
    ap.add_argument("--operator", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--reason", default="")
    ap.add_argument("--owner", action="store_true",
                    help="the holder gives back a claim that has no commits beyond main (worker.py)")
    a = ap.parse_args(argv)
    try:
        key = common.identifier(a.unit, "unit or lock key")
        common.require_main("unlock")
        if a.owner:
            if a.operator or a.force:
                raise ValueError("an owner release takes no OPERATOR or FORCE")
            if not a.agent:
                raise ValueError("an owner release needs --agent <the lock holder>")
        elif a.operator:
            if not a.force or not a.reason.strip():
                raise ValueError("operator recovery needs FORCE=1 and REASON=<human instruction>")
            common.single_line(a.reason, "reason")
        elif not identity.is_orchestrator(a.agent) or a.force:
            raise ValueError("normal release needs AGENT=orch, or an agent registered as orchestrator; "
                             "workers never unlock, and FORCE requires OPERATOR=1")
        with control.coordination_lock():
            path = common.lock_path(key)
            if not path.exists():
                print("unlock: %s is not locked" % key)
                return 0
            record = common.fields(path.read_text())
            if a.owner:
                removed = owner_release(key, a.agent, record)
                control.event("unlock", key=key, owner=record.get("agent"), agent=a.agent,
                              operator=False, owner_release=True, reason="owner release: nothing beyond main")
                path.unlink()
                print("unlock: released %s (owner release, nothing beyond main); removed %s" % (key, removed))
                return 0
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

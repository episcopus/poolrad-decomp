#!/usr/bin/env python3
"""claim.py: start work on a unit in one step (SPEC 9.5, playbook 30).

  make claim AGENT=<name> [UNIT=<id>]
  make claim AGENT=<name> REVIEW=1 [UNIT=<id>]    a review: a complete unit not reviewed yet (playbook 70)
  make claim AGENT=<name> TASK=<name>              other work (a whitepaper chapter `doc-<chapter>`, the
                                                   map `map`): lock <name>, branch task/<name>

1. Picks UNIT, or the next unit of work/queue.toml that is neither locked nor complete.
2. Locks it atomically (tools/agent/common.py; shared by every worktree of the clone). Two agents
   claiming at the same moment get different units.
3. Creates the worktree <clone>/../poolrad-worktrees/<id> on branch unit/<id> from main (or reuses the
   branch if it exists).
4. Links what is not in git from the main checkout into it: .venv, build/toolchain (the compiler),
   build/re (the extracted overlays), tools/vendor (emu2), tools/setup/env.local.sh.

A review claim locks `review-<id>` and creates branch review/<id> (worktree poolrad-worktrees/review-<id>)
from main, where the unit was merged when it became complete.

Prints the worktree path. Work there; hand off to the orchestrator, which releases the lock after merging.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402
import heartbeat  # noqa: E402
import identity  # noqa: E402
import lock  # noqa: E402
import next as nxt  # noqa: E402

LINKS = (".venv", "build/toolchain", "build/re", "tools/vendor", "tools/setup/env.local.sh")


def main(argv=None) -> int:
    try:
        with control.coordination_lock():
            return claim(argv)
    except (ValueError, RuntimeError, OSError) as e:
        print("claim: %s" % e, file=sys.stderr)
        return 2


def claim(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--unit", default=os.environ.get("UNIT", ""))
    ap.add_argument("--agent", default=os.environ.get("AGENT", ""))
    ap.add_argument("--base", default="main", help="branch the unit branch starts from")
    ap.add_argument("--review", action="store_true", help="claim a review instead of a unit")
    ap.add_argument("--task", default="", help="claim a named task (doc-<chapter>, map) instead of a unit")
    ap.add_argument("--harness", default=os.environ.get("POOLRAD_HARNESS", ""))
    ap.add_argument("--model", default=os.environ.get("POOLRAD_MODEL", ""))
    ap.add_argument("--session", default=os.environ.get("POOLRAD_SESSION_ID", ""))
    ap.add_argument("--variant", default=os.environ.get("POOLRAD_VARIANT", ""))
    a = ap.parse_args(argv)
    if not a.agent:
        print("claim: need AGENT=<name> (a name unique to this agent session)", file=sys.stderr)
        return 2
    common.identifier(a.agent, "agent")
    if a.unit:
        common.identifier(a.unit, "unit")
        if a.unit not in {u["id"] for u in common.queue()}:
            raise ValueError("unit is not a queued game unit: %s" % a.unit)
    if a.task:
        common.identifier(a.task, "task")
    if a.task and (a.unit or a.review):
        raise ValueError("TASK cannot be combined with UNIT or REVIEW")
    control.admit()
    main_dir = common.main_checkout()
    dirty = common.git("status", "--porcelain", "--untracked-files=no", cwd=main_dir)
    if dirty:
        print("claim: main has uncommitted tracked changes; a work branch starts from committed %s. "
              "Wait for the orchestrator; never stash, reset or clean main:\n%s" % (a.base, dirty), file=sys.stderr)
        return 1
    role = "reviewer" if a.review else ("mapper" if a.task == "map" else
            ("documentarian" if a.task.startswith("doc-") else ("tooling" if a.task else "decompiler")))
    a.identity = identity.ensure(a.agent, role, a.harness, a.model, a.session, a.variant)
    if a.task:
        task = a.task.lower()
        if common.pending_handoff(task):
            raise ValueError("%s has a hand-off waiting; do not duplicate unmerged work" % task)
        if not common.try_lock(task, lock.body(task, a.agent, "task/%s" % task)):
            print("claim: %s is locked:\n%s" % (task, common.lock_path(task).read_text()), file=sys.stderr)
            return 1
        return setup(main_dir, task, "task/%s" % task, a, "task " + task)
    unit = a.unit.lower()
    prefix = "review-" if a.review else ""
    if a.review and unit and not common.unit_complete(unit):
        print("claim: %s is not complete on this checkout; review a unit after it is merged complete" % unit,
              file=sys.stderr)
        return 1
    a.reused = False
    for _attempt in range(50):
        if not unit:
            n = nxt.next_review() if a.review else nxt.next_unit()
            if n is None:
                print("claim: nothing to claim (queue empty, or every unit locked or complete)")
                return 1
            unit = n[0]
        if owned(prefix + unit, a.agent):
            # The owner comes back to its own lock (after a stop, or after `make integrate` rejected its
            # hand-off): the worktree and branch are reused, nothing is duplicated.
            a.reused = True
            break
        if common.pending_handoff(prefix + unit):
            raise ValueError("%s has a hand-off waiting; do not duplicate unmerged work" % unit)
        if common.try_lock(prefix + unit, lock.body(prefix + unit, a.agent,
                                                    "%s/%s" % ("review" if a.review else "unit", unit))):
            break
        if a.unit:
            print("claim: %s is locked:\n%s" % (prefix + unit, common.lock_path(prefix + unit).read_text()),
                  file=sys.stderr)
            return 1
        unit = ""                                    # someone took it a moment ago: take the next one
    else:
        print("claim: could not take a unit", file=sys.stderr)
        return 1
    branch = "%s/%s" % ("review" if a.review else "unit", unit)
    return setup(main_dir, prefix + unit, branch, a, unit)


def owned(key: str, agent: str) -> bool:
    """True when `agent` already holds the lock on `key` (its own earlier claim)."""
    path = common.lock_path(key)
    if not path.exists():
        return False
    try:
        return common.fields(path.read_text()).get("agent") == agent
    except ValueError:
        return False


def rejection(key: str) -> str:
    """The reason `make integrate` rejected this key's hand-off, or an empty string."""
    path = common.common_dir() / "poolrad-handoffs" / (key + ".md")
    if not path.exists():
        return ""
    f = common.fields(path.read_text())
    if f.get("integrate") != "rejected":
        return ""
    return "%s (log %s)" % (f.get("integrate_reason", ""), f.get("integrate_log", ""))


def blocker_notes(main_dir: Path, unit: str) -> list[str]:
    """The items of work/blockers.md (the orchestrator's notes, on main) that name `unit`: instructions
    for whoever takes it next, such as how to bring a reverted branch back."""
    p = main_dir / "work/blockers.md"
    if not unit or not p.exists():
        return []
    text = re.sub(r"<!--.*?-->", "", p.read_text(), flags=re.S)
    items = re.split(r"\n(?=- )", "\n" + text)
    word = re.compile(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(unit), re.I)
    return [" ".join(i.split()) for i in items if i.lstrip().startswith("- ") and word.search(i)]


def setup(main_dir: Path, key: str, branch: str, a, unit: str) -> int:
    """Create (or reuse) the worktree for `key` on `branch` and link the untracked tools into it."""
    wt = main_dir.parent / "poolrad-worktrees" / key
    try:
        if wt.exists():
            actual = common.git("branch", "--show-current", cwd=wt)
            if actual != branch:
                raise ValueError("existing worktree %s is on %s, not %s; leave it alone" % (wt, actual, branch))
        else:
            wt.parent.mkdir(parents=True, exist_ok=True)
            exists = bool(common.git("branch", "--list", branch, cwd=main_dir))
            if exists:
                common.git("worktree", "add", str(wt), branch, cwd=main_dir)
            else:
                common.git("worktree", "add", "-b", branch, str(wt), a.base, cwd=main_dir)
        for rel in LINKS:
            src, dst = main_dir / rel, wt / rel
            if src.exists() and not dst.exists():
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.symlink_to(src)
        common.git("config", "core.hooksPath", "tools/agent/hooks", cwd=main_dir)   # the pre-commit guard
    except (RuntimeError, ValueError, OSError) as e:
        common.lock_path(key).unlink(missing_ok=True)
        print("claim: %s (lock released)" % e, file=sys.stderr)
        return 1
    if getattr(a, "reused", False):
        print("claim: %s is already locked for %s; reusing its worktree and branch" % (key, a.agent))
        why = rejection(key)
        if why:
            print("claim: the last hand-off of %s was rejected by make integrate: %s" % (key, why))
    else:
        print("claim: %s locked for %s" % (key, a.agent))
        task = identity.task_snapshot(key, unit, a.identity, branch)
        path = common.lock_path(key)
        common.atomic_write(path, path.read_text() + "agent_id = %s\ntask_id = %s\n" % (
            a.identity["agent_id"], task["task_id"]))
        control.event("claim", agent=a.agent, key=key, branch=branch, worktree=str(wt), task_id=task["task_id"],
                      agent_id=a.identity["agent_id"], base=task["base"])
    heartbeat.beat(a.agent, "claimed %s, worktree %s (branch %s)" % (key, wt, branch))
    print("claim: worktree %s (branch %s)" % (wt, branch))
    if a.task:
        print("claim: next: cd %s   (playbook 60 for doc-*, playbook 10 for map)" % wt)
    elif a.review:
        print("claim: next: cd %s && cp work/reviews/TEMPLATE.md work/reviews/%s.md   (playbook 70)" % (wt, unit))
    else:
        print("claim: next: cd %s && make packet UNIT=%s   (playbook 30)" % (wt, unit))
    notes = blocker_notes(main_dir, unit)
    if notes:
        print("claim: READ FIRST, the orchestrator's notes on %s in work/blockers.md (do these before anything else):" % unit)
        for n in notes:
            print("  " + n)
    return 0


if __name__ == "__main__":
    sys.exit(main())

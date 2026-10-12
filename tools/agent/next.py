#!/usr/bin/env python3
"""next.py: print the next unit from work/queue.toml (SPEC 9.4).

Work for a decompiler, first that applies: a unit whose review failed (open must-fix findings in
work/reviews/<id>.md) and that nobody holds; then the first unit that is neither locked nor complete
(every routine at L2 or L3 in re/symbols.toml) and not waiting: a unit is waiting when every routine not
yet at L2 or L3 has a `blocked` note in re/symbols.toml (judged per routine, so a unit with any routine
still workable stays in the queue). It comes back once a routine is unblocked.
With --review: the first complete unit that has no passed review, no review lock (`review-<id>`) and no
open must-fix finding (those wait for a decompiler's fixes first)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402


BLOCKED = re.compile(r"(?<![A-Za-z])blocked(?![A-Za-z])", re.I)


def is_init(r: dict) -> bool:
    return str(r.get("name", "")).lower().endswith("_init")


def waiting(uid: str, rs: list[dict]) -> bool:
    """Nothing to do until something changes: every routine not yet at L2 or L3 is blocked. The unit's
    initialisation part does not count while other routines are left: the matcher proves it only in the
    whole-unit comparison, which runs once no stubs remain, so it can never be the work that is left."""
    left = [r for r in rs if r["unit"] == uid and r.get("level") not in ("L2", "L3")]
    rest = [r for r in left if not is_init(r)] or left
    return bool(rest) and all(BLOCKED.search(str(r.get("notes", ""))) for r in rest)


def next_unit() -> tuple[str, str, int, int] | None:
    rs = common.routines()
    for u in common.queue():                         # failed reviews come back first
        uid = u["id"]
        findings = common.open_must_fix(uid)
        if findings and not common.lock_path(uid).exists() and not common.pending_handoff(uid):
            n = sum(1 for r in rs if r["unit"] == uid)
            return uid, "review failed: fix the %d must-fix findings in work/reviews/%s.md" % (len(findings), uid), n, n
    for u in common.queue():
        uid = u["id"]
        if common.lock_path(uid).exists() or common.pending_handoff(uid) or common.unit_complete(uid, rs) or waiting(uid, rs):
            continue
        mine = [r for r in rs if r["unit"] == uid]
        return uid, u.get("reason", ""), sum(r.get("level") in ("L2", "L3") for r in mine), len(mine)
    return None


def reviewed(uid: str, rs: list[dict]) -> bool:
    mine = [r for r in rs if r["unit"] == uid]
    return bool(mine) and all(str(r.get("review", "")).startswith("passed") for r in mine)


def next_review() -> tuple[str, str, int, int] | None:
    rs = common.routines()
    for u in common.queue():
        uid = u["id"]
        if common.unit_complete(uid, rs) and not reviewed(uid, rs) and not common.lock_path("review-" + uid).exists() \
                and not common.pending_handoff("review-" + uid) and not common.open_must_fix(uid):
            n = sum(1 for r in rs if r["unit"] == uid)
            return uid, u.get("reason", ""), n, n
    return None


def main() -> int:
    if "--review" in sys.argv[1:]:
        n = next_review()
        print("next review: %s (%s; %d routines)" % n[:3] if n else "next review: none waiting")
        return 0
    n = next_unit()
    if n is None:
        print("next: queue empty, or every unit locked or complete")
        return 0
    print("next: %s (%s; %d of %d routines at L2)" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())

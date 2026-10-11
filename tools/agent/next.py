#!/usr/bin/env python3
"""next.py: print the next unit from work/queue.toml (SPEC 9.4): the first that is neither locked nor
complete (every routine of it at L2 or L3 in re/symbols.toml). With --review: the first complete unit
that has no passed review and no review lock (`review-<id>`)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402


def next_unit() -> tuple[str, str, int, int] | None:
    rs = common.routines()
    for u in common.queue():
        uid = u["id"]
        if common.lock_path(uid).exists() or common.unit_complete(uid, rs):
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
        if common.unit_complete(uid, rs) and not reviewed(uid, rs) and not common.lock_path("review-" + uid).exists():
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

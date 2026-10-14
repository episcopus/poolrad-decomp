#!/usr/bin/env python3
"""next.py: print the next unit from work/queue.toml (SPEC 9.4).

Work for a decompiler, first that applies: a unit whose review failed (open must-fix findings in
work/reviews/<id>.md) and that nobody holds, unless workers already spent their attempts on those
findings (frontier entry `<id>:review-fix` marked exhausted, tools/agent/worker.py; `make inbox` lists
it); then the first unit that is neither locked nor complete
(every routine at L2 or L3 in re/symbols.toml) and not waiting: a unit is waiting when every routine not
yet at L2 or L3 has a `blocked` note in re/symbols.toml (judged per routine, so a unit with any routine
still workable stays in the queue). It comes back once a routine is unblocked.
A routine the cheap tier is done with (TIER1_ATTEMPTS sessions failed on it, the frontier of
tools/agent/worker.py, or a session wrote a `blocked` note) counts as waiting too, so cheap workers do
not claim and give back such a unit every few minutes; it goes to the escalation tier.
With --escalate: the first unit, not locked and with no hand-off waiting, that holds a stuck routine the
escalation tier has not given up on (stuck(); `escalation_exhausted` in its frontier entry marks one
that tier failed too, which then waits for the human in `make inbox`).
With --review: the first complete unit that has no passed review, no review lock (`review-<id>`) and no
open must-fix finding (those wait for a decompiler's fixes first)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402


BLOCKED = re.compile(r"(?<![A-Za-z])blocked(?![A-Za-z])", re.I)
PHANTOM = re.compile(r"not a routine", re.I)    # a map entry inside a real routine (its note says so)
TIER1_ATTEMPTS = 2                              # = worker.DEFAULT_MAX_ATTEMPTS (worker imports this module)


def frontier(uid: str) -> dict:
    """The worker frontier of a unit: {routine id: {"attempts": n, "escalations": m, ...}}."""
    path = common.common_dir() / "poolrad-frontier" / ("%s.json" % uid)
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def stuck(r: dict, entry: dict) -> bool:
    """A routine the cheap tier is done with: blocked, or out of frontier attempts. Not a phantom entry
    (the map's guess inside a real routine) and not the initialisation part (it is proven last)."""
    if r.get("level") in ("L2", "L3") or r.get("external") or is_init(r):
        return False
    notes = str(r.get("notes", ""))
    if PHANTOM.search(notes):
        return False
    return bool(BLOCKED.search(notes)) or int(entry.get("attempts", 0)) >= TIER1_ATTEMPTS


def escalatable(r: dict, entry: dict) -> bool:
    return stuck(r, entry) and not entry.get("escalation_exhausted")


def is_init(r: dict) -> bool:
    return str(r.get("name", "")).lower().endswith("_init")


def waiting(uid: str, rs: list[dict]) -> bool:
    """Nothing to do until something changes: every routine not yet at L2 or L3 is blocked. The unit's
    initialisation part does not count while other routines are left: the matcher proves it only in the
    whole-unit comparison, which runs once no stubs remain, so it can never be the work that is left."""
    left = [r for r in rs if r["unit"] == uid and r.get("level") not in ("L2", "L3") and not r.get("external")]
    rest = [r for r in left if not is_init(r)] or left
    fr = frontier(uid)
    return bool(rest) and all(BLOCKED.search(str(r.get("notes", ""))) or
                              int(fr.get(r["id"], {}).get("attempts", 0)) >= TIER1_ATTEMPTS for r in rest)


def next_escalation() -> tuple[str, str, int, int] | None:
    """The escalation tier's next unit: stuck routines the cheap tier gave up on (see stuck())."""
    rs = common.routines()
    for u in common.queue():
        uid = u["id"]
        if common.lock_path(uid).exists() or common.pending_handoff(uid):
            continue
        fr = frontier(uid)
        hard = [r for r in rs if r["unit"] == uid and escalatable(r, fr.get(r["id"], {}))]
        if hard:
            return uid, "escalation: %d stuck routine(s): %s" % (len(hard), ", ".join(r["id"] for r in hard[:6])), \
                len(hard), sum(1 for r in rs if r["unit"] == uid)
    return None


def fix_exhausted(uid: str) -> bool:
    """Workers spent their attempts on this unit's review findings: leave it to the human (make inbox)."""
    path = common.common_dir() / "poolrad-frontier" / ("%s.json" % uid)
    try:
        entry = json.loads(path.read_text()).get("%s:review-fix" % uid, {})
    except (OSError, ValueError, AttributeError):
        return False
    return bool(entry.get("exhausted"))


def next_unit() -> tuple[str, str, int, int] | None:
    rs = common.routines()
    for u in common.queue():                         # failed reviews come back first
        uid = u["id"]
        findings = common.open_must_fix(uid)
        if findings and not common.lock_path(uid).exists() and not common.pending_handoff(uid) and not fix_exhausted(uid):
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
    if "--escalate" in sys.argv[1:]:
        n = next_escalation()
        print("next escalation: %s (%s)" % n[:2] if n else "next escalation: none waiting")
        return 0
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

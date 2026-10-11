#!/usr/bin/env python3
"""next.py: print the next unit from work/queue.toml (SPEC 9.4): the first that is neither locked nor
complete (every routine of it at L2 or L3 in re/symbols.toml)."""
from __future__ import annotations

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    path = ROOT / "work/queue.toml"
    if not path.exists():
        print("next: work/queue.toml missing", file=sys.stderr)
        return 1
    queue = tomllib.loads(path.read_text()).get("unit", [])
    routines = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
    locks = ROOT / "work/locks"
    for u in queue:
        uid = u["id"]
        if (locks / ("%s.lock" % uid)).exists():
            continue
        rs = [r for r in routines if r["unit"] == uid]
        if rs and all(r.get("level") in ("L2", "L3") for r in rs):
            continue
        done = sum(r.get("level") in ("L2", "L3") for r in rs)
        print("next: %s (%s; %d of %d routines at L2)" % (uid, u.get("reason", ""), done, len(rs)))
        return 0
    print("next: queue empty, or every unit locked or complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())

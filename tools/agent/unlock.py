#!/usr/bin/env python3
"""unlock.py: release a unit lock (SPEC 9.4).

Usage:
  make unlock UNIT=res00
  make unlock UNIT=res00 FORCE=1   # break a stale lock
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("unit", nargs="?", help="unit id")
    args = ap.parse_args(argv[1:])
    unit = args.unit or os.environ.get("UNIT", "")
    if unit.startswith("UNIT="):
        unit = unit.split("=", 1)[1]
    force = os.environ.get("FORCE", "") in ("1", "true", "yes")
    if not unit:
        print("unlock: need UNIT=<id>", file=sys.stderr)
        return 2
    path = ROOT / "work" / "locks" / ("%s.lock" % unit)
    if not path.exists():
        print("unlock: %s is not locked" % unit)
        return 0
    text = path.read_text()
    if not force:
        # warn if older than 24h but still require FORCE to break foreign locks? Spec: orchestrator may FORCE
        started = None
        for line in text.splitlines():
            if line.startswith("started = "):
                try:
                    started = dt.datetime.fromisoformat(line.split("=", 1)[1].strip())
                except ValueError:
                    pass
        if started and (dt.datetime.now(dt.timezone.utc) - started).total_seconds() > 86400:
            print(
                "unlock: lock is older than 24h; re-run with FORCE=1 to break:\n%s" % text,
                file=sys.stderr,
            )
            return 1
    path.unlink()
    print("unlock: released %s" % unit)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""lock.py: claim a unit for exclusive work (SPEC 9.4).

Usage:
  python3 tools/agent/lock.py UNIT=res00
  make lock UNIT=res00
"""
from __future__ import annotations

import argparse
import datetime as dt
import getpass
import os
import socket
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("unit", nargs="?", help="unit id (or UNIT=id)")
    ap.add_argument("--agent", default=os.environ.get("POOLRAD_AGENT", getpass.getuser()))
    ap.add_argument("--branch", default="")
    args = ap.parse_args(argv[1:])
    unit = args.unit or ""
    if unit.startswith("UNIT="):
        unit = unit.split("=", 1)[1]
    if not unit:
        # Makefile passes UNIT= via env
        unit = os.environ.get("UNIT", "")
    if not unit:
        print("lock: need UNIT=<id>", file=sys.stderr)
        return 2

    lock_dir = ROOT / "work" / "locks"
    lock_dir.mkdir(parents=True, exist_ok=True)
    path = lock_dir / ("%s.lock" % unit)
    if path.exists():
        print("lock: %s already locked:\n%s" % (unit, path.read_text()), file=sys.stderr)
        return 1
    branch = args.branch or ("unit/%s" % unit)
    body = (
        "unit = %s\n"
        "agent = %s\n"
        "host = %s\n"
        "branch = %s\n"
        "started = %s\n"
    ) % (unit, args.agent, socket.gethostname(), branch, dt.datetime.now(dt.timezone.utc).isoformat())
    path.write_text(body)
    print("lock: claimed %s -> %s" % (unit, path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""lock.py: claim a unit for exclusive work (SPEC 9.4).

  make lock UNIT=res05 [AGENT=name]
  make locks                         list the current locks

Locks are shared by every worktree of this clone (tools/agent/common.py) and created atomically, so two
agents cannot hold the same unit. `make claim` locks and sets up a worktree in one step.
"""
from __future__ import annotations

import argparse
import datetime as dt
import getpass
import os
import socket
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402


def body(unit: str, agent: str, branch: str) -> str:
    return ("unit = %s\nagent = %s\nhost = %s\nbranch = %s\nstarted = %s\n" % (
        unit, agent, socket.gethostname(), branch, dt.datetime.now(dt.timezone.utc).isoformat()))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit", nargs="?", default=os.environ.get("UNIT", ""))
    ap.add_argument("--agent", default=os.environ.get("AGENT") or os.environ.get("POOLRAD_AGENT") or getpass.getuser())
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args(argv)
    if a.list:
        locks = sorted(common.lock_dir().glob("*.lock"))
        for p in locks:
            print("%s\n" % p.read_text().strip())
        print("locks: %d (%s)" % (len(locks), common.lock_dir()))
        return 0
    unit = a.unit
    if not unit:
        print("lock: need UNIT=<id>", file=sys.stderr)
        return 2
    try:
        common.identifier(unit, "unit")
        common.identifier(a.agent, "agent")
        with control.coordination_lock():
            control.admit()
            if common.pending_handoff(unit):
                raise ValueError("%s has a hand-off waiting" % unit)
            if not common.try_lock(unit, body(unit, a.agent, "unit/%s" % unit)):
                print("lock: %s already locked:\n%s" % (unit, common.lock_path(unit).read_text()), file=sys.stderr)
                return 1
            control.event("lock", agent=a.agent, key=unit)
    except (ValueError, RuntimeError, OSError) as e:
        print("lock: %s" % e, file=sys.stderr)
        return 2
    print("lock: claimed %s -> %s" % (unit, common.lock_path(unit)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

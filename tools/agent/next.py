#!/usr/bin/env python3
"""next.py: print the next unit from work/queue.toml (SPEC 9.4)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    path = ROOT / "work/queue.toml"
    if not path.exists():
        print("next: work/queue.toml missing", file=sys.stderr)
        return 1
    text = path.read_text()
    units = re.findall(r'^id\s*=\s*"([^"]+)"', text, re.M)
    # skip units that already have a lock
    locks = ROOT / "work/locks"
    for uid in units:
        if locks.exists() and (locks / ("%s.lock" % uid)).exists():
            continue
        # print with reason if present
        m = re.search(
            r'id\s*=\s*"%s"\s*\nreason\s*=\s*"([^"]*)"' % re.escape(uid),
            text,
        )
        reason = m.group(1) if m else ""
        print("next: %s%s" % (uid, (" (%s)" % reason) if reason else ""))
        return 0
    print("next: queue empty or all locked")
    return 0


if __name__ == "__main__":
    sys.exit(main())

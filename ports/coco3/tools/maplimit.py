#!/usr/bin/env python3
"""maplimit.py MAP SYMBOL MAX_HEX: fail if the linker map's SYMBOL is above MAX_HEX.
Guards the demo's fixed layout (the core must end below the staging area)."""
import re
import sys

found = []
for line in open(sys.argv[1], encoding="latin-1"):
    m = re.match(rf"^Symbol: {re.escape(sys.argv[2])} \(.*\) = ([0-9A-Fa-f]+)", line)
    if m:
        found.append(int(m.group(1), 16))
if not found:
    sys.exit(f"{sys.argv[1]}: no symbol {sys.argv[2]}")
if max(found) > int(sys.argv[3], 16):
    sys.exit(f"{sys.argv[1]}: {sys.argv[2]} = ${max(found):04X} exceeds ${int(sys.argv[3], 16):04X}")

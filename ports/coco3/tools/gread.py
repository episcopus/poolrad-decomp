#!/usr/bin/env python3
"""gread.py PREFIX NAME [LEN]: the bytes of a DGROUP global as the CoCo has them at the end of a run (PREFIX.core, PREFIX.pages),
found through the layout table of the build; for debugging a session (hex, in the CoCo's byte order)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
gen = os.path.join(HERE, "../build/gen/vm")
prefix, name = sys.argv[1], sys.argv[2]
core = open(prefix + ".core", "rb").read()
pages = open(prefix + ".pages", "rb").read()
cl = [(int(m.group(1), 16), int(m.group(2)), m.group(3), int(m.group(4), 16))
      for m in re.finditer(r"\{0x([0-9A-F]+), (\d+), '(\w)', \d+, 0x([0-9A-F]+)\}", open(gen + "/vmlayout.c").read())]
off = size = None
for ln in open(gen + "/globals.txt"):
    f = ln.split()
    if len(f) >= 3 and f[2] == name:
        off, size = int(f[0], 16), int(f[1])
if off is None:
    raise SystemExit("gread: no global " + name)
n = int(sys.argv[3]) if len(sys.argv) > 3 else size
for lo, sz, c, new in cl:
    if lo <= off < lo + sz:
        a = new + off - lo
        if c == "N":
            print("%s DS:%04X native %04X: %s" % (name, off, a, core[a - 0x2000:a - 0x2000 + n].hex()))
        else:
            p, o = (a >> 13) - 4, a & 0x1FFF
            print("%s DS:%04X paged %04X: %s" % (name, off, a, pages[p * 0x2000 + o:p * 0x2000 + o + n].hex()))
        break

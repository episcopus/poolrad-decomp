#!/usr/bin/env python3
"""assetstats.py: what the game's data costs on a disk and what a better packing would save (step 8.9b).
Every DAX file of poolrad/ is split into its blocks (the unit the game loads); per family (the name without its trailing digit) the table gives the number of
blocks, the sizes as shipped (the original's run length coding, which the CoCo image keeps), unpacked, and what each block would be alone under zlib level 9 and
LZMA (bounds for ZX0 or LZSA, which are about zlib's size or a little better on this kind of data and unpack in about 20 to 40 cycles a byte on a 6809)."""
import collections
import lzma
import os
import re
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../tools/re"))
import dax  # noqa: E402

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../poolrad")
fam = collections.defaultdict(lambda: [0, 0, 0, 0, 0])
for f in sorted(os.listdir(root)):
    if not f.upper().endswith(".DAX"):
        continue
    name = re.sub(r"\d*\.DAX$", "", f.upper())
    for b in dax.read_dax(os.path.join(root, f)):
        raw = dax.unrle(b["data"])
        a = fam[name]
        a[0] += 1
        a[1] += b["packed"]
        a[2] += len(raw)
        a[3] += len(zlib.compress(raw, 9))
        a[4] += len(lzma.compress(raw, format=lzma.FORMAT_RAW, filters=[{"id": lzma.FILTER_LZMA2, "preset": 9, "dict_size": 1 << 16}]))
tot = [0, 0, 0, 0, 0]
print("%-10s %6s %9s %9s %9s %9s %7s" % ("family", "blocks", "shipped", "unpacked", "zlib9", "lzma", "zlib/sh"))
for k, a in sorted(fam.items(), key=lambda kv: -kv[1][1]):
    print("%-10s %6d %9d %9d %9d %9d %6.0f%%" % (k, a[0], a[1], a[2], a[3], a[4], 100.0 * a[3] / max(1, a[1])))
    tot = [x + y for x, y in zip(tot, a)]
print("%-10s %6d %9d %9d %9d %9d %6.0f%%" % ("total", tot[0], tot[1], tot[2], tot[3], tot[4], 100.0 * tot[3] / tot[1]))

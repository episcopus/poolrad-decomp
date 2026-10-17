#!/usr/bin/env python3
"""constplace.py: where the typed constants of DGROUP (the 17,370-byte image, read-only in practice)
could live, by the units that name them in the generated C (step 8.1c).
Usage: constplace.py REPO SIZES_TSV

A constant named by one unit goes into that unit's bank (rodata); one named by several is shared (kept
pinned or copied into each bank); one named by none is data nobody reads by name (tables reached by
offset, the font, padding). Prints, per unit, code + constants + its own constants against the 16 KB window.
"""
import csv
import glob
import re
import sys

repo, sizes = sys.argv[1], sys.argv[2]
IMG_END = 0x43DC
best = {}
for l in open(repo + "/c/game/globals.txt"):
    p = l.split()
    if len(p) >= 3:
        o, s, n = int(p[0], 16), int(p[1]), p[2]
        if o < IMG_END and (o not in best or s > best[o][0]):
            best[o] = (s, n)
users = {}
for path in glob.glob(repo + "/c/game/*.c"):
    unit = path.split("/")[-1][:-2]
    if not unit.startswith(("ovl", "res")):
        continue
    text = re.sub(r"/\*.*?\*/", "", open(path).read(), flags=re.S)
    words = set(re.findall(r"\b[A-Za-z_]\w*\b", text))
    for o, (s, n) in best.items():
        if n in words:
            users.setdefault(o, set()).add(unit)

cover_one, cover_many, cover_none = bytearray(IMG_END), bytearray(IMG_END), bytearray(IMG_END)
own = {}
for o, (s, n) in best.items():
    u = users.get(o, set())
    if len(u) == 1:
        cover_one[o:o + s] = b"\x01" * s
        own.setdefault(next(iter(u)), bytearray(IMG_END))[o:o + s] = b"\x01" * s
    elif u:
        cover_many[o:o + s] = b"\x01" * s
    else:
        cover_none[o:o + s] = b"\x01" * s
one = sum(1 for i in range(2, IMG_END) if cover_one[i] and not cover_many[i])
many = sum(1 for i in range(2, IMG_END) if cover_many[i])
none = sum(1 for i in range(2, IMG_END) if not cover_one[i] and not cover_many[i])
print(f"constants image {IMG_END - 2:,} bytes: named by one unit {one:,}, by several {many:,}, not named by any unit {none:,} "
      f"(overlapping entries counted once)")

size = {r["unit"]: int(r["cmoc_code"]) + int(r["rodata"]) for r in csv.DictReader(open(sizes), delimiter="\t")}
print(f"{'unit':8} {'code+rodata':>11} {'own consts':>10} {'total':>7}  over 16 KB")
for u in sorted(size):
    c = sum(own[u]) if u in own else 0
    t = size[u] + c
    if t >= 12000 or c >= 2000:
        print(f"{u:8} {size[u]:11,d} {c:10,d} {t:7,d}  {'YES' if t > 16384 else ''}")

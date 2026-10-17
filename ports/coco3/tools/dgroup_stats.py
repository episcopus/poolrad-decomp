#!/usr/bin/env python3
"""dgroup_stats.py: which part of DGROUP the game actually writes (step 8.1, open question Q4).

  dgroup_stats.py REPO DUMP [DUMP ...]     DUMP: a DGROUP file written at the end of a replayed
                                           session by a heap-stats build of c/ (POOL_DGROUP_DUMP)

DGROUP is 34,656 bytes: the typed-constant image (17,370 bytes at DS:0002, initialised by the
program file) followed by zeroed variables. A byte of the image that no session changed is
constant in practice and can live in banked read-only data; a variable byte that is zero at the end
of every session is untouched in practice. Both are lower bounds on what a play session writes (a
byte written and restored is not seen), so "written" is a floor and "constant" a ceiling.
"""
import re
import sys

repo, dumps = sys.argv[1], sys.argv[2:]
IMG_ORG, IMG_SIZE, TOTAL = 0x0002, 17370, 0x8760
src = open(f"{repo}/c/game/image.c").read()
body = src[src.index("pool_image[] = {") + len("pool_image[] = {"):]
img = bytes(int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{2})", body))
assert len(img) == IMG_SIZE, len(img)
base = bytearray(TOTAL)
base[IMG_ORG:IMG_ORG + IMG_SIZE] = img
ends = [open(d, "rb").read() for d in dumps]

changed = [any(e[i] != base[i] for e in ends) for i in range(TOTAL)]
img_end = IMG_ORG + IMG_SIZE
img_changed = sum(changed[IMG_ORG:img_end])
bss = TOTAL - img_end
bss_touched = sum(changed[img_end:])
print(f"DGROUP {TOTAL} bytes: DS:0000-0001 {IMG_ORG} (Turbo Pascal's), image {IMG_SIZE}, variables {bss}")
print(f"  image bytes changed in at least one of {len(ends)} sessions: {img_changed} ({img_changed * 100 // IMG_SIZE}%)")
print(f"  variable bytes nonzero at the end of at least one session: {bss_touched} ({bss_touched * 100 // bss}%)")

# per global: the largest entry at each offset, then flagged by whether any byte changed
best = {}
for l in open(f"{repo}/c/game/globals.txt"):
    p = l.split()
    if len(p) >= 3:
        o, s, n = int(p[0], 16), int(p[1]), p[2]
        if o not in best or s > best[o][0]:
            best[o] = (s, n)
inimg = never = written = 0
rows = []
for o, (s, n) in sorted(best.items()):
    if o < img_end and o >= IMG_ORG:
        if any(changed[o:o + s]):
            written += s
        else:
            never += s
        rows.append((s, o, n, any(changed[o:o + s])))
print(f"  named globals inside the image: {never} bytes never changed, {written} bytes changed")
print("  largest never-changed image globals:")
for s, o, n, w in sorted((r for r in rows if not r[3]), reverse=True)[:8]:
    print(f"    {o:04X} {s:6d} {n}")
print("  largest changed image globals:")
for s, o, n, w in sorted((r for r in rows if r[3]), reverse=True)[:8]:
    print(f"    {o:04X} {s:6d} {n}")
# the runtime's share: System variables, Input/Output, the saved interrupt vectors
runtime = [(0x43DC, 0x4430), (0x84F0, 0x8508), (0x8508, 0x8708), (0x8708, TOTAL)]
print("  Borland runtime data: " + ", ".join(f"{a:04X}-{b - 1:04X} ({b - a})" for a, b in runtime)
      + f" = {sum(b - a for a, b in runtime)} bytes")

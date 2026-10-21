#!/usr/bin/env python3
"""heaptab.py: the two heaps of a run, read from the harness' dump of the core (build/run/game-<session>.core, $2000..$7FFF).

  heaptab.py build/run/game-shop-buy.core [more.core ...]

The tables of src/game/rtl_heap.c are at HEAPDATA ($4E80): struct HeapData, 64 entries of the mapped heap and 640 of the banked heap (4 bytes: offset,
size with bit 0 = in use), then the banked table's length, its rover, the bytes live in the banked and in the mapped heap, the mapped table's length and the ready flag. Prints, per run and per heap, the bytes in
use, the free bytes, the largest free block and the blocks in use by size (at the end of the run, or at the fatal stop of one that ran out: that is the
failure state). The banked heap is eight pages of 7,680 usable bytes: a block never crosses a page, so the largest free block is the number that matters."""
import struct
import sys
from collections import Counter

CORE_BASE = 0x2000
HEAPDATA = 0x4E80
NBLKM, NBLKB = 64, 640
PAGE = 0x2000


def entries(core, first, n):
    o = HEAPDATA - CORE_BASE + 4 * first
    return [struct.unpack(">HH", core[o + 4 * i:o + 4 * i + 4]) for i in range(n)]


def report(title, blk, pages):
    used = [(off, sz & 0xFFF8) for off, sz in blk if sz & 1]
    free = [(off, sz & 0xFFF8) for off, sz in blk if not sz & 1]
    sizes = Counter(s for _, s in used)
    perpage = Counter(off // PAGE for off, _ in used)
    print("  %-7s %3d table entries, %6d bytes in use (%3d blocks), %6d free, largest free %5d" %
          (title, len(blk), sum(s for _, s in used), len(used), sum(s for _, s in free), max((s for _, s in free), default=0)))
    print("          in use by size: " + ", ".join("%dx%d" % (n, s) for s, n in sorted(sizes.items(), reverse=True)))
    if pages:
        print("          bytes in use by page: " + " ".join("%d:%d" % (p, sum(s for off, s in used if off // PAGE == p)) for p in range(pages)))


def main(argv):
    for f in argv[1:]:
        core = open(f, "rb").read()
        base = HEAPDATA - CORE_BASE + 4 * (NBLKM + NBLKB)
        nb, rover, blive, mlive = struct.unpack(">HHHH", core[base:base + 8])
        nm = core[base + 8]
        print("%s: mapped table %d entries (%d bytes live), banked table %d (rover %d, %d bytes live)" % (f, nm, mlive, nb, rover, blive))
        report("mapped", entries(core, 0, nm), 0)
        report("banked", entries(core, NBLKM, nb), 8)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

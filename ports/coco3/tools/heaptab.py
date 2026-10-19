#!/usr/bin/env python3
"""heaptab.py: the mapped heap of a run, read from the harness' dump of the core (build/run/game-<session>.core, $2000..$7FFF).

  heaptab.py build/run/game-shop-buy.core [more.core ...]

The table of src/game/rtl_heap.c is at HEAPDATA ($4C80): 128 entries of 4 bytes (offset, size with bit 0 = in use), then 16 entries of the
banked heap, then the two counts. Prints, per run, the bytes in use, the free bytes, the largest free block and the blocks in use by size
(at the end of the run, or at the fatal stop of one that ran out: that is the failure state)."""
import struct
import sys
from collections import Counter

CORE_BASE = 0x2000
HEAPDATA = 0x4C80
NBLKM, NBLKB = 128, 16


def table(core):
    o = HEAPDATA - CORE_BASE
    blk = [struct.unpack(">HH", core[o + 4 * i:o + 4 * i + 4]) for i in range(NBLKM)]
    nm = core[o + 4 * (NBLKM + NBLKB)]
    return blk[:nm]


def main(argv):
    for f in argv[1:]:
        core = open(f, "rb").read()
        blk = table(core)
        used = [(off, sz & 0xFFF8) for off, sz in blk if sz & 1]
        free = [(off, sz & 0xFFF8) for off, sz in blk if not sz & 1]
        total = sum(s for _, s in used) + sum(s for _, s in free)
        sizes = Counter(s for _, s in used)
        print("%s: %d blocks in the table, %d bytes of heap, %d in use (%d blocks), %d free, largest free %d" %
              (f, len(blk), total, sum(s for _, s in used), len(used), sum(s for _, s in free), max((s for _, s in free), default=0)))
        print("   in use by size: " + ", ".join("%dx%d" % (n, s) for s, n in sorted(sizes.items(), reverse=True)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

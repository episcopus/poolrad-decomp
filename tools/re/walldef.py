#!/usr/bin/env python3
"""walldef.py: decode Pool of Radiance WALLDEF#.DAX wallsets (whitepaper 4.2.4).

  python3 tools/re/walldef.py verify poolrad/
  python3 tools/re/walldef.py list poolrad/WALLDEF1.DAX
  python3 tools/re/walldef.py dump poolrad/WALLDEF1.DAX 1

LoadWallSet (ovl29:0E08) requires the loaded size to be a multiple of 0x30C (780)
and copies each 780-byte wallset into the wall buffer. It indexes walls with a
stride of 0x9C (156), so each wallset is five 156-byte wall records **[V]**.
Bytes are tile indices into the area's 8x8D set **[H]** (values are small ids;
pixel expansion not done here).
"""
from __future__ import annotations

import glob
import json
import os
import sys

import dax

WALLSET_SIZE = 0x30C  # 780; LoadWallSet divisor
WALL_SIZE = 0x9C      # 156; LoadWallSet inner stride
WALLS_PER_SET = WALLSET_SIZE // WALL_SIZE  # 5


def decode_walldef(raw: bytes) -> dict:
    if len(raw) == 0 or len(raw) % WALLSET_SIZE:
        raise ValueError("WALLDEF size %d is not a positive multiple of %d" % (len(raw), WALLSET_SIZE))
    sets = []
    for si in range(len(raw) // WALLSET_SIZE):
        base = si * WALLSET_SIZE
        walls = []
        for wi in range(WALLS_PER_SET):
            chunk = raw[base + wi * WALL_SIZE:base + (wi + 1) * WALL_SIZE]
            walls.append({"index": wi, "bytes": list(chunk)})
        sets.append({"index": si, "walls": walls})
    return {
        "wallset_size": WALLSET_SIZE,
        "wall_size": WALL_SIZE,
        "wallset_count": len(sets),
        "wallsets": sets,
    }


def verify_tree(root: str) -> int:
    files = sorted(glob.glob(os.path.join(root, "WALLDEF*.DAX")))
    n = bad = 0
    for path in files:
        for b in dax.read_dax(path):
            n += 1
            try:
                info = decode_walldef(dax.unrle(b["data"]))
                assert info["wallset_count"] * WALLSET_SIZE == b["raw"]
            except (ValueError, AssertionError) as e:
                bad += 1
                print("%s#%d: %s" % (path, b["id"], e))
    print("walldef: %d files, %d blocks, %s" % (len(files), n, "OK" if not bad else "%d problems" % bad))
    return 0 if files and not bad else 1


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("verify", "list", "dump"):
        print(__doc__)
        return 2
    cmd, target = argv[1], argv[2]
    if cmd == "verify":
        return verify_tree(target)
    blocks = dax.read_dax(target)
    if cmd == "list":
        for b in blocks:
            raw = dax.unrle(b["data"])
            print("block %3d  raw %d  wallsets %d" % (b["id"], len(raw), len(raw) // WALLSET_SIZE))
        return 0
    if len(argv) < 4:
        print("dump: need block id"); return 2
    bid = int(argv[3])
    for b in blocks:
        if b["id"] == bid:
            print(json.dumps(decode_walldef(dax.unrle(b["data"])), indent=2))
            return 0
    print("block %d not found" % bid)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

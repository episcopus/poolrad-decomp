#!/usr/bin/env python3
"""geo.py: list, verify and dump Pool of Radiance GEO#.DAX maps (whitepaper section 4.2).

  python3 tools/re/geo.py verify poolrad/              # every GEO block: size and planes
  python3 tools/re/geo.py list poolrad/GEO1.DAX        # block ids and sizes
  python3 tools/re/geo.py dump poolrad/GEO1.DAX 18     # one map as JSON (cells)

Each decompressed GEO block is 0x402 bytes. Load3DMap (ovl29:10C7) rejects any other
size, skips the leading u16 (always 1024), and copies four 256-byte planes into the
map buffer. Plane roles (wall art, events, doors) match the pre-UA Gold Box layout
used by ImHex GB_GEO and coab; byte values are taken from our files.
"""
from __future__ import annotations

import glob
import json
import os
import sys

import dax

GEO_SIZE = 0x402
GEO_PAYLOAD = 1024
MAP_W = MAP_H = 16
PLANE = MAP_W * MAP_H  # 256


def decode_geo(raw: bytes) -> dict:
    if len(raw) != GEO_SIZE:
        raise ValueError("GEO block is %d bytes, expected %d" % (len(raw), GEO_SIZE))
    declared = int.from_bytes(raw[:2], "little")
    if declared != GEO_PAYLOAD:
        raise ValueError("GEO header u16 is %d, expected %d" % (declared, GEO_PAYLOAD))
    body = raw[2:]
    ne, sw, event, door = (body[i * PLANE:(i + 1) * PLANE] for i in range(4))
    cells = []
    for y in range(MAP_H):
        row = []
        for x in range(MAP_W):
            i = y * MAP_W + x
            b_ne, b_sw, b_ev, b_door = ne[i], sw[i], event[i], door[i]
            row.append({
                "x": x,
                "y": y,
                "wall_north": (b_ne >> 4) & 0xF,
                "wall_east": b_ne & 0xF,
                "wall_west": b_sw & 0xF,
                "wall_south": (b_sw >> 4) & 0xF,
                "event_id": b_ev & 0x7F,
                "interior": bool(b_ev & 0x80),
                "door_north": b_door & 0x3,
                "door_east": (b_door >> 2) & 0x3,
                "door_south": (b_door >> 4) & 0x3,
                "door_west": (b_door >> 6) & 0x3,
            })
        cells.append(row)
    return {
        "width": MAP_W,
        "height": MAP_H,
        "payload_bytes": declared,
        "cells": cells,
    }


def iter_geo_files(root: str):
    return sorted(glob.glob(os.path.join(root, "GEO*.DAX")))


def verify_tree(root: str) -> int:
    files = iter_geo_files(root)
    n = bad = 0
    for path in files:
        try:
            for b in dax.read_dax(path):
                n += 1
                raw = dax.unrle(b["data"])
                decode_geo(raw)
        except ValueError as e:
            bad += 1
            print("%s: %s" % (path, e))
    print("geo: %d files, %d blocks, %s" % (len(files), n, "OK" if not bad else "%d problems" % bad))
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
            print("block %3d  raw %d" % (b["id"], len(raw)))
        return 0
    if len(argv) < 4:
        print("dump: need block id"); return 2
    bid = int(argv[3])
    for b in blocks:
        if b["id"] == bid:
            print(json.dumps(decode_geo(dax.unrle(b["data"])), indent=2, sort_keys=True))
            return 0
    print("block %d not in %s" % (bid, target))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

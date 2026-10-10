#!/usr/bin/env python3
"""items.py: decode the global ITEMS type table (whitepaper 4.3).

  python3 tools/re/items.py verify poolrad/ITEMS
  python3 tools/re/items.py dump poolrad/ITEMS

File layout **[V]** (size 2050; coab ItemDataTable seeks 2 then reads 16-byte rows):

  u16  skipped                  ; unused header word (0x7600 in our file)
  ItemData[128]                 ; 16 bytes each (PoR has 0x80 rows; Curse uses 0x81)

Each ItemData row: slot, hands, dice, bonus, attacks, range, classFlags, flags
(coab Classes/ItemData.cs field names **[H]**).
"""
from __future__ import annotations

import json
import os
import sys

ITEMS_SIZE = 2050
HDR = 2
ROW = 16
ROWS = 0x80  # 128; 2 + 128*16 = 2050


def decode_items(raw: bytes) -> dict:
    if len(raw) != ITEMS_SIZE:
        raise ValueError("ITEMS is %d bytes, expected %d" % (len(raw), ITEMS_SIZE))
    hdr = int.from_bytes(raw[:2], "little")
    body = raw[HDR:]
    if len(body) != ROWS * ROW:
        raise ValueError("ITEMS body length")
    table = []
    for i in range(ROWS):
        r = body[i * ROW:(i + 1) * ROW]
        table.append({
            "type_id": i,
            "item_slot": r[0],
            "hands_count": r[1],
            "dice_count_large": r[2],
            "dice_size_large": r[3],
            "bonus_large": r[4] if r[4] < 128 else r[4] - 256,
            "number_attacks": r[5],
            "field_6": r[6],
            "field_7": r[7],
            "field_8": r[8],
            "dice_count_normal": r[9],
            "dice_size_normal": r[10],
            "bonus_normal": r[11] if r[11] < 128 else r[11] - 256,
            "range": r[12],
            "class_flags": r[13],
            "flags": r[14],
            "field_f": r[15],
        })
    return {"header_u16": hdr, "count": ROWS, "types": table}


def encode_items(info: dict) -> bytes:
    """Round-trip from decode_items (rewrites rows from fields)."""
    out = bytearray(info["header_u16"].to_bytes(2, "little"))
    for row in info["types"]:
        def u8(v):
            return v & 0xFF
        out += bytes([
            u8(row["item_slot"]),
            u8(row["hands_count"]),
            u8(row["dice_count_large"]),
            u8(row["dice_size_large"]),
            u8(row["bonus_large"]),
            u8(row["number_attacks"]),
            u8(row["field_6"]),
            u8(row["field_7"]),
            u8(row["field_8"]),
            u8(row["dice_count_normal"]),
            u8(row["dice_size_normal"]),
            u8(row["bonus_normal"]),
            u8(row["range"]),
            u8(row["class_flags"]),
            u8(row["flags"]),
            u8(row["field_f"]),
        ])
    if len(out) != ITEMS_SIZE:
        raise ValueError("encode size")
    return bytes(out)


def verify_path(path: str) -> int:
    raw = open(path, "rb").read()
    info = decode_items(raw)
    if encode_items(info) != raw:
        print("%s: round-trip mismatch" % path)
        return 1
    print("items: %s, %d types, OK" % (path, info["count"]))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("verify", "dump"):
        print(__doc__)
        return 2
    cmd, target = argv[1], argv[2]
    if os.path.isdir(target):
        target = os.path.join(target, "ITEMS")
    if cmd == "verify":
        return verify_path(target)
    info = decode_items(open(target, "rb").read())
    print(json.dumps(info, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

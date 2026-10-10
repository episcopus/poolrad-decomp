#!/usr/bin/env python3
"""records.py: Pool of Radiance character, item and affect records (whitepaper 4.3–4.4).

Shared by MON*CHA/ITM/SPC DAX blocks and SAVE/CHRDAT* files.

  python3 tools/re/records.py verify poolrad/
  python3 tools/re/records.py dump-char poolrad/MON1CHA.DAX 1
  python3 tools/re/records.py dump-char poolrad/SAVE/CHRDATA1.SAV

Sizes **[V]**: character 0x11D (285), item 0x3F (63), affect 9.
Field layout for character/item follows coab PoolRadPlayer / Item **[H]**; names and
stats match our bytes (Pascal-style length-prefixed name in the first 16 bytes).
"""
from __future__ import annotations

import glob
import json
import os
import sys

import dax

CHAR_SIZE = 0x11D  # 285; coab PoolRadPlayer.StructSize
ITEM_SIZE = 0x3F   # 63; coab Item.StructSize
AFFECT_SIZE = 9


def _pstring(data: bytes, off: int, maxlen: int) -> str:
    n = data[off]
    if n > maxlen:
        n = maxlen
    return bytes(data[off + 1:off + 1 + n]).decode("ascii", errors="replace")


def _put_pstring(buf: bytearray, off: int, maxlen: int, s: str) -> None:
    # Write length + chars only. Do not wipe the rest of the slot: item name
    # buffers keep leftover bytes past the Pascal length (and bytes 0x2A..0x2D
    # sit between the max name and type at 0x2E).
    raw = s.encode("ascii", errors="replace")[:maxlen]
    buf[off] = len(raw)
    buf[off + 1:off + 1 + len(raw)] = raw


def decode_char(raw: bytes) -> dict:
    if len(raw) != CHAR_SIZE:
        raise ValueError("character record is %d bytes, expected %d" % (len(raw), CHAR_SIZE))
    return {
        "name": _pstring(raw, 0, 15),
        "str": raw[0x10],
        "int": raw[0x11],
        "wis": raw[0x12],
        "dex": raw[0x13],
        "con": raw[0x14],
        "cha": raw[0x15],
        "str00": raw[0x16],
        "thac0": raw[0x2D] if raw[0x2D] < 128 else raw[0x2D] - 256,
        "race": raw[0x2E],
        "class": raw[0x2F],
        "age": int.from_bytes(raw[0x30:0x32], "little"),
        "hp_max": raw[0x32],
        "sex": raw[0x9E],
        "raw_hex": raw.hex(),
    }


def encode_char(rec: dict) -> bytes:
    """Re-encode from decode_char output (preserves unknown bytes via raw_hex)."""
    if "raw_hex" not in rec:
        raise ValueError("encode_char needs raw_hex for unknown fields")
    buf = bytearray.fromhex(rec["raw_hex"])
    if len(buf) != CHAR_SIZE:
        raise ValueError("raw_hex length")
    _put_pstring(buf, 0, 15, rec["name"])
    buf[0x10] = rec["str"] & 0xFF
    buf[0x11] = rec["int"] & 0xFF
    buf[0x12] = rec["wis"] & 0xFF
    buf[0x13] = rec["dex"] & 0xFF
    buf[0x14] = rec["con"] & 0xFF
    buf[0x15] = rec["cha"] & 0xFF
    buf[0x16] = rec["str00"] & 0xFF
    buf[0x2D] = rec["thac0"] & 0xFF
    buf[0x2E] = rec["race"] & 0xFF
    buf[0x2F] = rec["class"] & 0xFF
    buf[0x30:0x32] = int(rec["age"]).to_bytes(2, "little")
    buf[0x32] = rec["hp_max"] & 0xFF
    buf[0x9E] = rec["sex"] & 0xFF
    return bytes(buf)


def decode_item(raw: bytes) -> dict:
    if len(raw) != ITEM_SIZE:
        raise ValueError("item record is %d bytes, expected %d" % (len(raw), ITEM_SIZE))
    return {
        "name": _pstring(raw, 0, 0x2A),
        "type": raw[0x2E],
        "namenum1": raw[0x2F],
        "namenum2": raw[0x30],
        "namenum3": raw[0x31],
        "plus": raw[0x32] if raw[0x32] < 128 else raw[0x32] - 256,
        "plus_save": raw[0x33],
        "readied": raw[0x34] != 0,
        "hidden_names_flag": raw[0x35],
        "cursed": raw[0x36] != 0,
        "weight": int.from_bytes(raw[0x37:0x39], "little"),
        "count": raw[0x39],
        "value": int.from_bytes(raw[0x3A:0x3C], "little"),
        "affect_1": raw[0x3C],
        "affect_2": raw[0x3D],
        "affect_3": raw[0x3E],
        "raw_hex": raw.hex(),
    }


def encode_item(rec: dict) -> bytes:
    if "raw_hex" not in rec:
        raise ValueError("encode_item needs raw_hex")
    buf = bytearray.fromhex(rec["raw_hex"])
    if len(buf) != ITEM_SIZE:
        raise ValueError("raw_hex length")
    _put_pstring(buf, 0, 0x2A, rec["name"])
    buf[0x2E] = rec["type"] & 0xFF
    buf[0x2F] = rec["namenum1"] & 0xFF
    buf[0x30] = rec["namenum2"] & 0xFF
    buf[0x31] = rec["namenum3"] & 0xFF
    buf[0x32] = rec["plus"] & 0xFF
    buf[0x33] = rec["plus_save"] & 0xFF
    buf[0x34] = 1 if rec["readied"] else 0
    buf[0x35] = rec["hidden_names_flag"] & 0xFF
    buf[0x36] = 1 if rec["cursed"] else 0
    buf[0x37:0x39] = int(rec["weight"]).to_bytes(2, "little")
    buf[0x39] = rec["count"] & 0xFF
    buf[0x3A:0x3C] = int(rec["value"]).to_bytes(2, "little")
    buf[0x3C] = rec["affect_1"] & 0xFF
    buf[0x3D] = rec["affect_2"] & 0xFF
    buf[0x3E] = rec["affect_3"] & 0xFF
    return bytes(buf)


def decode_affect(raw: bytes) -> dict:
    if len(raw) != AFFECT_SIZE:
        raise ValueError("affect record is %d bytes, expected %d" % (len(raw), AFFECT_SIZE))
    return {
        "type": raw[0],
        "field_1": raw[1],
        "field_2": raw[2],
        "field_3": raw[3],
        "field_4": raw[4],
        "field_5": raw[5],
        "field_6": raw[6],
        "field_7": raw[7],
        "field_8": raw[8],
        "raw_hex": raw.hex(),
    }


def encode_affect(rec: dict) -> bytes:
    return bytes.fromhex(rec["raw_hex"])


def decode_item_blob(raw: bytes) -> list[dict]:
    if len(raw) % ITEM_SIZE:
        raise ValueError("item blob length %d not multiple of %d" % (len(raw), ITEM_SIZE))
    return [decode_item(raw[i:i + ITEM_SIZE]) for i in range(0, len(raw), ITEM_SIZE)]


def encode_item_blob(items: list[dict]) -> bytes:
    return b"".join(encode_item(it) for it in items)


def decode_affect_blob(raw: bytes) -> list[dict]:
    if len(raw) % AFFECT_SIZE:
        raise ValueError("affect blob length %d not multiple of %d" % (len(raw), AFFECT_SIZE))
    return [decode_affect(raw[i:i + AFFECT_SIZE]) for i in range(0, len(raw), AFFECT_SIZE)]


def encode_affect_blob(affs: list[dict]) -> bytes:
    return b"".join(encode_affect(a) for a in affs)


def verify_tree(root: str) -> int:
    bad = n = 0

    def check(label, raw, kind):
        nonlocal bad, n
        n += 1
        try:
            if kind == "char":
                rec = decode_char(raw)
                if encode_char(rec) != raw:
                    raise ValueError("char round-trip mismatch")
            elif kind == "item":
                items = decode_item_blob(raw)
                if encode_item_blob(items) != raw:
                    raise ValueError("item round-trip mismatch")
            else:
                affs = decode_affect_blob(raw)
                if encode_affect_blob(affs) != raw:
                    raise ValueError("affect round-trip mismatch")
        except ValueError as e:
            bad += 1
            print("%s: %s" % (label, e))

    for path in sorted(glob.glob(os.path.join(root, "MON*CHA.DAX"))):
        for b in dax.read_dax(path):
            check("%s#%d" % (path, b["id"]), dax.unrle(b["data"]), "char")
    for path in sorted(glob.glob(os.path.join(root, "MON*ITM.DAX"))):
        for b in dax.read_dax(path):
            check("%s#%d" % (path, b["id"]), dax.unrle(b["data"]), "item")
    for path in sorted(glob.glob(os.path.join(root, "MON*SPC.DAX"))):
        for b in dax.read_dax(path):
            check("%s#%d" % (path, b["id"]), dax.unrle(b["data"]), "affect")
    for path in sorted(glob.glob(os.path.join(root, "ITEM*.DAX"))):
        # ITEM1.DAX etc; not ITEMS
        if os.path.basename(path).upper() == "ITEMS":
            continue
        for b in dax.read_dax(path):
            check("%s#%d" % (path, b["id"]), dax.unrle(b["data"]), "item")

    save = os.path.join(root, "SAVE")
    if os.path.isdir(save):
        for path in sorted(glob.glob(os.path.join(save, "CHRDAT*.SAV"))):
            check(path, open(path, "rb").read(), "char")
        for path in sorted(glob.glob(os.path.join(save, "CHRDAT*.ITM"))):
            check(path, open(path, "rb").read(), "item")
        for path in sorted(glob.glob(os.path.join(save, "CHRDAT*.SPC"))):
            check(path, open(path, "rb").read(), "affect")

    print("records: %d checked, %s" % (n, "OK" if not bad else "%d problems" % bad))
    return 0 if n and not bad else 1


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("verify", "dump-char", "dump-items", "dump-affects"):
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "verify":
        return verify_tree(argv[2])

    target = argv[2]
    if target.upper().endswith(".DAX"):
        if len(argv) < 4:
            print("dump: need block id"); return 2
        bid = int(argv[3])
        raw = None
        for b in dax.read_dax(target):
            if b["id"] == bid:
                raw = dax.unrle(b["data"]); break
        if raw is None:
            print("block not found"); return 1
    else:
        raw = open(target, "rb").read()

    if cmd == "dump-char":
        print(json.dumps(decode_char(raw), indent=2, sort_keys=True))
    elif cmd == "dump-items":
        print(json.dumps(decode_item_blob(raw), indent=2, sort_keys=True))
    else:
        print(json.dumps(decode_affect_blob(raw), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

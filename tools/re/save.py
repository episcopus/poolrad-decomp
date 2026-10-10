#!/usr/bin/env python3
"""save.py: verify and dump Pool of Radiance SAVE/ directories (whitepaper 4.4).

  python3 tools/re/save.py verify poolrad/SAVE
  python3 tools/re/save.py dump poolrad/SAVE

A save slot is:

  SAVGAMA.DAT              ; 13137 bytes game state **[V]** size
  CHRDAT<slot><n>.SAV      ; 285-byte character (same as MON*CHA)
  CHRDAT<slot><n>.ITM      ; N * 63-byte items (optional)
  CHRDAT<slot><n>.SPC      ; N * 9-byte affects (optional)

Character/item/affect bytes round-trip through tools/re/records.py.
SAVGAMA.DAT is checked for exact size; field map still **[?]**.
"""
from __future__ import annotations

import json
import os
import re
import sys

import records

SAVGAMA_SIZE = 13137
SLOT_RE = re.compile(r"^CHRDAT([A-Z])(\d)\.(SAV|ITM|SPC)$", re.I)


def verify_dir(path: str) -> int:
    bad = 0
    savgama = os.path.join(path, "SAVGAMA.DAT")
    if not os.path.isfile(savgama):
        print("missing SAVGAMA.DAT"); return 1
    sg = open(savgama, "rb").read()
    if len(sg) != SAVGAMA_SIZE:
        print("SAVGAMA.DAT size %d, expected %d" % (len(sg), SAVGAMA_SIZE))
        bad += 1

    chars = items = affects = 0
    for name in sorted(os.listdir(path)):
        m = SLOT_RE.match(name)
        if not m:
            if name.upper() == "SAVGAMA.DAT":
                continue
            print("unexpected save file %s" % name)
            bad += 1
            continue
        full = os.path.join(path, name)
        data = open(full, "rb").read()
        kind = m.group(3).upper()
        try:
            if kind == "SAV":
                rec = records.decode_char(data)
                if records.encode_char(rec) != data:
                    raise ValueError("char round-trip")
                chars += 1
            elif kind == "ITM":
                blob = records.decode_item_blob(data)
                if records.encode_item_blob(blob) != data:
                    raise ValueError("item round-trip")
                items += 1
            else:
                blob = records.decode_affect_blob(data)
                if records.encode_affect_blob(blob) != data:
                    raise ValueError("affect round-trip")
                affects += 1
        except ValueError as e:
            print("%s: %s" % (name, e))
            bad += 1

    print("save: SAVGAMA %d, %d chars, %d item-files, %d affect-files, %s" % (
        len(sg), chars, items, affects, "OK" if not bad else "%d problems" % bad))
    return 0 if not bad and chars else 1


def dump_dir(path: str) -> dict:
    out = {
        "savgama_size": os.path.getsize(os.path.join(path, "SAVGAMA.DAT")),
        "characters": [],
    }
    for name in sorted(os.listdir(path)):
        m = SLOT_RE.match(name)
        if not m or m.group(3).upper() != "SAV":
            continue
        slot, n = m.group(1).upper(), m.group(2)
        base = os.path.join(path, "CHRDAT%s%s" % (slot, n))
        char = records.decode_char(open(base + ".SAV", "rb").read())
        entry = {"slot": slot, "index": int(n), "character": {
            k: char[k] for k in char if k != "raw_hex"
        }}
        itm = base + ".ITM"
        spc = base + ".SPC"
        if os.path.isfile(itm):
            entry["items"] = [
                {k: it[k] for k in it if k != "raw_hex"}
                for it in records.decode_item_blob(open(itm, "rb").read())
            ]
        if os.path.isfile(spc):
            entry["affects"] = [
                {k: a[k] for k in a if k != "raw_hex"}
                for a in records.decode_affect_blob(open(spc, "rb").read())
            ]
        out["characters"].append(entry)
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("verify", "dump"):
        print(__doc__)
        return 2
    cmd, target = argv[1], argv[2]
    if os.path.basename(target.rstrip("/")) != "SAVE" and os.path.isdir(os.path.join(target, "SAVE")):
        target = os.path.join(target, "SAVE")
    if cmd == "verify":
        return verify_dir(target)
    print(json.dumps(dump_dir(target), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

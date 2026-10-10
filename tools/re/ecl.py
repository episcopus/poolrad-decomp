#!/usr/bin/env python3
"""ecl.py: list, verify and dump Pool of Radiance ECL#.DAX scripts (whitepaper section 4.2).

  python3 tools/re/ecl.py verify poolrad/              # every ECL block: size and header
  python3 tools/re/ecl.py list poolrad/ECL1.DAX        # block ids and sizes
  python3 tools/re/ecl.py dump poolrad/ECL1.DAX 18     # header entry points as JSON

LoadEcl (ovl07:0341) allocates a 0x1E00-byte buffer, loads the DAX block, requires
size >= 2, skips the leading u16 (always 5000 in our files), and copies the rest.
The VM then reads five word operands (coab vm_LoadCmdSets / vm_init_ecl) as the
script entry points. Full opcode decode waits on the interpreter lift.
"""
from __future__ import annotations

import glob
import json
import os
import sys

import dax

ECL_HDR_WORD = 5000
ECL_BUF_MAX = 0x1E00  # EclBlock size in coab; GetMem size in ovl07:0341
ENTRY_COUNT = 5


def _load_cmd_sets(buf: bytes, ecl_offset: int, n: int):
    """Mirror coab ovr008.vm_LoadCmdSets for typed operands (read-only)."""
    def at(idx: int) -> int:
        loc = idx & 0xFFFF
        if loc >= len(buf):
            raise ValueError("ECL operand read at %04X past end (%d)" % (loc, len(buf)))
        return buf[loc]

    ops = []
    off = ecl_offset
    for _ in range(n):
        code = at(0x8000 + off + 1)
        low = at(0x8000 + off + 2)
        off = (off + 2) & 0xFFFF
        high = 0
        if code in (1, 2, 3, 0x81):
            off = (off + 1) & 0xFFFF
            high = at(0x8000 + off)
        off = (off + 1) & 0xFFFF
        ops.append({"code": code, "word": low | (high << 8)})
    return ops, off


def decode_ecl(raw: bytes) -> dict:
    if len(raw) < 2:
        raise ValueError("ECL block too short (%d)" % len(raw))
    hdr = int.from_bytes(raw[:2], "little")
    if hdr != ECL_HDR_WORD:
        raise ValueError("ECL header u16 is %d, expected %d" % (hdr, ECL_HDR_WORD))
    body = raw[2:]
    if len(body) > ECL_BUF_MAX:
        raise ValueError("ECL payload %d exceeds buffer %d" % (len(body), ECL_BUF_MAX))
    if not body:
        raise ValueError("ECL payload empty")
    # vm_init_ecl starts at ecl_offset 0x8000 and reads five word literals (code 1).
    ops, next_off = _load_cmd_sets(body, 0x8000, ENTRY_COUNT)
    for i, op in enumerate(ops):
        if op["code"] != 1:
            raise ValueError("entry %d has operand code %d, expected 1" % (i, op["code"]))
    names = [
        "vm_run_1",
        "search_location",
        "pre_camp_check",
        "camp_interrupted",
        "initial_entry",
    ]
    entries = {names[i]: ops[i]["word"] for i in range(ENTRY_COUNT)}
    return {
        "header_u16": hdr,
        "payload_bytes": len(body),
        "buffer_cap": ECL_BUF_MAX,
        "entries": entries,
        "code_start": next_off,
    }


def iter_ecl_files(root: str):
    return sorted(glob.glob(os.path.join(root, "ECL*.DAX")))


def verify_tree(root: str) -> int:
    files = iter_ecl_files(root)
    n = bad = 0
    for path in files:
        try:
            for b in dax.read_dax(path):
                n += 1
                decode_ecl(dax.unrle(b["data"]))
        except ValueError as e:
            bad += 1
            print("%s block %s: %s" % (path, b.get("id", "?"), e))
    print("ecl: %d files, %d blocks, %s" % (len(files), n, "OK" if not bad else "%d problems" % bad))
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
            print(json.dumps(decode_ecl(dax.unrle(b["data"])), indent=2, sort_keys=True))
            return 0
    print("block %d not in %s" % (bid, target))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

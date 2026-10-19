#!/usr/bin/env python3
"""mkimage.py: the game's one container image (step 8.5, decision D13 of the porting guide): everything the game loads, in 256-byte
sectors addressed by logical sector number. Reproducible (the same inputs, the same bytes).

  mkimage.py DATA_DIR GAMEDIR DGROUP.IMG OUT.img

Layout, big endian ("PIM2"; src/engine/img.c and vol.c read it):
  sector 0     "PIM2", u16 nfiles, u16 nent, u32 files_off, u32 ents_off, u32 save_lsn, u16 save_sectors
  files_off    the table of files: nfiles x { name8, u16 first entry, u16 count }, sorted by name
  ents_off     the table of entries: nent x { u8 file, u8 id, u32 byte offset from the start of the image, u16 packed size, u16 raw size }
               grouped by file; a block of a DAX file (packed = its run length coded bytes), an object the engine reads raw
               (BANK/id, CORE/0, DGROUP/0) or, for DGROUP/1 and /2, a run length coded block (tools/mkvm.py)
  data         the blocks, back to back; the raw objects start on a sector boundary so that a whole sector read lands in a block
  save area    save_sectors sectors at save_lsn (the character and game files the game writes; zero at first)"""
import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
import os
sys.path.insert(0, str(HERE))
sys.path.insert(0, os.path.join(os.environ.get("REPO", str(HERE.parent.parent.parent)), "tools/re"))
import mkvolumes  # noqa: E402
from mkgamedisk import flatten  # noqa: E402

SAVE_SECTORS = 256


def name8(n):
    return n.ljust(8).encode("ascii")


def main(data_dir, gamedir, dgroup, out):
    g = Path(gamedir)
    src = mkvolumes.load_sources(data_dir)                         # {NAME: [(id, packed, raw size)]}
    raw_obj = {}                                                   # name -> [(id, bytes, raw size)], stored without a code
    banks = json.loads((g / "banks.json").read_text())["banks"]
    raw_obj["BANK"] = [(b["id"], (g / (b["name"] + ".raw")).read_bytes(), None) for b in sorted(banks, key=lambda b: b["id"])]
    lo, core = flatten(g / "core.bin")
    assert lo == 0x2000
    raw_obj["CORE"] = [(0, core, None)]
    d = Path(dgroup).read_bytes()
    assert d[:4] == b"DGI2"
    hdr = d[4:9]
    pos = 9
    blocks = []
    for _ in range(2):
        pk, rw = struct.unpack(">HH", d[pos:pos + 4])
        blocks.append((d[pos + 4:pos + 4 + pk], rw))
        pos += 4 + pk
    raw_obj["DGROUP"] = [(0, hdr, None)]
    coded = {"DGROUP": [(1, blocks[0][0], blocks[0][1]), (2, blocks[1][0], blocks[1][1])]}
    files = sorted(set(src) | set(raw_obj))
    ents, body_parts = [], []                                      # entries: (fi, id, packed, raw, kind, payload)
    for fi, n in enumerate(files):
        for bid, packed, raw in src.get(n, []):
            ents.append((fi, bid, len(packed), raw, 0, packed))
        for bid, data, _ in raw_obj.get(n, []):
            ents.append((fi, bid, len(data), len(data), 1, data))
        for bid, packed, raw in coded.get(n, []):
            ents.append((fi, bid, len(packed), raw, 0, packed))
    nent = len(ents)
    files_off = 256
    ents_off = -(-(files_off + 12 * len(files)) // 256) * 256
    data_off = -(-(ents_off + 10 * nent) // 256) * 256
    body = bytearray()
    placed = []
    for fi, bid, packed, raw, kind, payload in ents:
        if kind == 1 and len(body) % 256:
            body += bytes(256 - len(body) % 256)
        placed.append(data_off + len(body))
        body += payload
    if len(body) % 256:
        body += bytes(256 - len(body) % 256)
    save_lsn = (data_off + len(body)) // 256
    first = {}
    count = {}
    for i, e in enumerate(ents):
        first.setdefault(e[0], i)
        count[e[0]] = count.get(e[0], 0) + 1
    img = bytearray(data_off)
    img[0:24] = b"PIM2" + struct.pack(">HHLLLH", len(files), nent, files_off, ents_off, save_lsn, SAVE_SECTORS) + bytes(2)
    for fi, n in enumerate(files):
        img[files_off + 12 * fi:files_off + 12 * fi + 12] = name8(n) + struct.pack(">HH", first.get(fi, 0), count.get(fi, 0))
    for i, (e, off) in enumerate(zip(ents, placed)):
        fi, bid, packed, raw, kind, payload = e
        img[ents_off + 10 * i:ents_off + 10 * i + 10] = struct.pack(">BBLHH", fi, bid, off, packed, raw)
    img += body + bytes(SAVE_SECTORS * 256)
    Path(out).write_bytes(bytes(img))
    print("mkimage: %d files, %d entries, %d sectors (%d KB), saves at sector %d" % (len(files), nent, len(img) // 256, len(img) // 1024, save_lsn))


if __name__ == "__main__":
    main(*sys.argv[1:5])

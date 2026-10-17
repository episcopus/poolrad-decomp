#!/usr/bin/env python3
"""mkdecb.py: build a DECB (LOADM) binary from segments.

  mkdecb.py -o out.bin [--base core.bin] [--seg ADDR:file[:pad]]... [--exec ADDR]

--base   an existing DECB file (lwlink output): its data blocks are copied, its exec address
         is the default exec address.
--seg    add a block of the raw file at load address ADDR (hex), zero padded to `pad` bytes.
Blocks are written in order, the exec trailer last. A block holds at most 65535 bytes.
"""
import argparse
import struct


def read_decb(path):
    d = open(path, "rb").read()
    i, blocks, ex = 0, [], None
    while i < len(d):
        t, n, a = struct.unpack(">BHH", d[i:i + 5])
        if t == 0:
            blocks.append((a, d[i + 5:i + 5 + n]))
            i += 5 + n
        elif t == 0xFF:
            ex = a
            break
        else:
            raise SystemExit(f"{path}: bad block type {t:#x} at {i}")
    return blocks, ex


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", required=True)
    ap.add_argument("--base")
    ap.add_argument("--seg", action="append", default=[])
    ap.add_argument("--exec", dest="exec_", type=lambda s: int(s, 16))
    a = ap.parse_args()
    blocks, ex = ([], None)
    if a.base:
        blocks, ex = read_decb(a.base)
    for s in a.seg:
        parts = s.split(":")
        addr, path = int(parts[0], 16), parts[1]
        data = open(path, "rb").read()
        if len(parts) > 2:
            pad = int(parts[2], 0)
            if len(data) > pad:
                raise SystemExit(f"{path}: {len(data)} bytes exceed the {pad} byte slot")
            data += bytes(pad - len(data))
        blocks.append((addr, data))
    if a.exec_ is not None:
        ex = a.exec_
    if ex is None:
        raise SystemExit("mkdecb: no exec address (use --base or --exec)")
    with open(a.o, "wb") as f:
        for addr, data in blocks:
            f.write(struct.pack(">BHH", 0, len(data), addr) + data)
        f.write(struct.pack(">BHH", 0xFF, 0, ex))


if __name__ == "__main__":
    main()

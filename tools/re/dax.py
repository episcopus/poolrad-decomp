#!/usr/bin/env python3
"""dax.py: list, verify and extract Pool of Radiance .DAX archives (whitepaper section 4.1).

  python3 tools/re/dax.py verify poolrad/            # check every .DAX: header, tiling, RLE sizes
  python3 tools/re/dax.py list poolrad/ECL1.DAX      # blocks with sizes
  python3 tools/re/dax.py extract poolrad/ECL1.DAX build/re/dax/ECL1   # raw (decompressed) blocks
"""
import glob, os, struct, sys


def read_dax(path):
    d = open(path, "rb").read()
    hs = struct.unpack("<H", d[:2])[0]
    if hs % 9:
        raise ValueError("header size %d is not a multiple of 9" % hs)
    blocks = []
    for i in range(hs // 9):
        bid, off, raw, packed = struct.unpack("<BIHH", d[2 + 9 * i:11 + 9 * i])
        start = 2 + hs + off
        blocks.append({"id": bid, "offset": off, "raw": raw, "packed": packed, "data": d[start:start + packed]})
    end = max((2 + hs + b["offset"] + b["packed"] for b in blocks), default=2 + hs)
    if end != len(d):
        raise ValueError("blocks end at %d but the file has %d bytes" % (end, len(d)))
    return blocks


def unrle(c):
    out, i = bytearray(), 0
    while i < len(c):
        n = c[i]; i += 1
        if n < 0x80:
            out += c[i:i + n + 1]; i += n + 1
        else:
            out += bytes([c[i]]) * (256 - n); i += 1
    return bytes(out)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("verify", "list", "extract"):
        print(__doc__); return 2
    cmd, target = argv[1], argv[2]
    if cmd == "verify":
        files = sorted(glob.glob(os.path.join(target, "*.DAX")))
        nb = bad = 0
        for f in files:
            try:
                for b in read_dax(f):
                    nb += 1
                    if len(unrle(b["data"])) != b["raw"]:
                        bad += 1; print("size mismatch: %s block %d" % (f, b["id"]))
            except ValueError as e:
                bad += 1; print("%s: %s" % (f, e))
        print("dax: %d files, %d blocks, %s" % (len(files), nb, "OK" if not bad else "%d problems" % bad))
        return 0 if files and not bad else 1
    blocks = read_dax(target)
    if cmd == "list":
        for b in blocks:
            print("block %3d  offset %6d  packed %5d  raw %5d" % (b["id"], b["offset"], b["packed"], b["raw"]))
        return 0
    out = argv[3]
    os.makedirs(out, exist_ok=True)
    for b in blocks:
        open(os.path.join(out, "block%03d.bin" % b["id"]), "wb").write(unrle(b["data"]))
    print("extracted %d blocks to %s" % (len(blocks), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

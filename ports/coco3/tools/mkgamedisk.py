#!/usr/bin/env python3
"""mkgamedisk.py: the program disk of the game on the CoCo (step 8.5e), a DECB-formatted 35-track floppy:

  POOL.BIN      the engine (LOADM, runs in MMU task 1)                     build/game/POOL.BIN
  CORE.BIN      the game's core, raw from logical $2000                    build/game/core.bin (lwlink decb) flattened
  DGROUP.IMG    initial DGROUP (tools/mkvm.py --coco)                      build/gen/vm/DGROUP.IMG
  BANKnn.BIN    the code banks listed in build/game/bootbanks.txt (ids), as many as fit; the rest wait for the disk set

usage: mkgamedisk.py GAMEDIR DGROUP.IMG OUT.dsk  (inside the toolchain: needs decb)"""
import json
import struct
import subprocess
import sys
from pathlib import Path


def flatten(path):
    d = Path(path).read_bytes()
    i, blocks = 0, []
    while i < len(d):
        t, n, a = struct.unpack(">BHH", d[i:i + 5])
        if t == 0:
            blocks.append((a, d[i + 5:i + 5 + n]))
            i += 5 + n
        else:
            break
    lo = min(a for a, _ in blocks)
    img = bytearray(max(a + len(b) for a, b in blocks) - lo)
    for a, b in blocks:
        img[a - lo:a - lo + len(b)] = b
    return lo, bytes(img)


def main(gamedir, dgroup, out):
    """The program disk is just the engine: BASIC's LOADM reads POOL.BIN from it; everything else (core, DGROUP, banks, data, saves)
    is in the one image (tools/mkimage.py) the storage backend serves (porting guide D13)."""
    g = Path(gamedir)
    Path(out).unlink(missing_ok=True)
    subprocess.run(["decb", "dskini", out], check=True)
    copy(out, "POOL.BIN", g / "POOL.BIN")


def copy(disk, name, path, quiet=False):
    r = subprocess.run(["decb", "copy", "-2", "-b", str(path), "%s,%s" % (disk, name)], capture_output=True, text=True)
    if r.returncode:
        if not quiet:
            print("mkgamedisk: %s does not fit: %s" % (name, (r.stdout + r.stderr).strip()[:100]))
        return False
    if not quiet:
        print("mkgamedisk: %-14s %6d bytes" % (name, Path(path).stat().st_size))
    return True


if __name__ == "__main__":
    main(*sys.argv[1:4])

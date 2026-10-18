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
    g = Path(gamedir)
    lo, core = flatten(g / "core.bin")
    assert lo == 0x2000, "the core starts at %04X" % lo
    (g / "CORE.RAW").write_bytes(core)
    banks = json.loads((g / "banks.json").read_text())["banks"]
    by_id = {b["id"]: b["name"] for b in banks}
    # the banks to carry: data/bootbanks.txt (names), then build/game/bootbanks.txt (ids or names: what scripts/bank_probe*.sh found)
    ids = {b["name"]: b["id"] for b in banks}
    want = []
    for bf in (Path(__file__).resolve().parent.parent / "data/bootbanks.txt", g / "bootbanks.txt"):
        if bf.exists():
            for tok in "\n".join(l for l in bf.read_text().split("\n") if not l.startswith("#")).split():
                i = int(tok) if tok.isdigit() else ids[tok]
                if i not in want:
                    want.append(i)
    # development: more banks than the program disk holds go to extra disks, drives 2 and 3 (BANKS.IDX: a byte a bank, its drive)
    disks = [Path(out), Path(out).with_name("bank1.dsk"), Path(out).with_name("bank2.dsk")]
    drives = [0, 2, 3]
    for d in disks:
        d.unlink(missing_ok=True)
        subprocess.run(["decb", "dskini", str(d)], check=True)
    idx = bytearray(64)
    files = [("POOL.BIN", g / "POOL.BIN"), ("CORE.BIN", g / "CORE.RAW"), ("DGROUP.IMG", Path(dgroup))]
    for name, path in files:
        copy(disks[0], name, path)
    (g / "BANKS.IDX").write_bytes(bytes(64))                 # a place holder keeps its granule
    copy(disks[0], "BANKS.IDX", g / "BANKS.IDX", quiet=True)
    cur = 0
    for i in want:
        name, path = "BANK%02d.BIN" % i, g / (by_id[i] + ".raw")
        while True:
            if copy(disks[cur], name, path, quiet=True):
                idx[i] = drives[cur]
                break
            cur += 1
            if cur >= len(disks):
                raise SystemExit("mkgamedisk: the banks do not fit on %d disks" % len(disks))
    (g / "BANKS.IDX").write_bytes(bytes(idx))
    subprocess.run(["decb", "kill", "%s,BANKS.IDX" % disks[0]], check=True, capture_output=True)
    copy(disks[0], "BANKS.IDX", g / "BANKS.IDX", quiet=True)
    print("mkgamedisk: %d banks on %d disks" % (len(want), cur + 1))


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

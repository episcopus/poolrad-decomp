#!/usr/bin/env python3
"""floppycheck.py: what a session did to the disks (step 8.10).

  floppycheck.py IMAGE DISKDIR [DEVIMAGE DEVSAVES]

IMAGE is the image of the floppy set (build/floppy/pool.img), DISKDIR the copy of the disks the run used (MAME wrote the saves into it:
build/run/floppy-S-disks). The data files of the disks are put back together and compared with the image: only the save area may differ.
With DEVIMAGE and DEVSAVES (the .saves file of the same session on the development backend, an image with shared blocks) the save area
the run left must be the one the development run left (the files the game wrote, as the directory of src/game/rtl_file.c lists them).
Exit 1 when something else changed or the save areas differ."""
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import decbfs  # noqa: E402


def disks_image(diskdir, n, counts, il):
    out = bytearray()
    for i in range(n):
        raw = Path(diskdir, "POOL%02d.DSK" % (i + 1)).read_bytes()
        d = decbfs.read_dir(raw)
        first = [e for e in d if e[0].startswith("POOLDSK")][0][4]
        out += decbfs.read_file(raw, first, counts[i], il)
    return bytes(out)


def area_files(area):
    """the files of a save area by the directory: {name: bytes}"""
    files = {}
    for i in range(127):
        e = area[16 + 16 * i:32 + 16 * i]
        if e[0] == 0:
            continue
        start, cap, size = struct.unpack(">HBH", e[11:16])
        files[bytes(e[:11]).decode("latin1").strip()] = bytes(area[start * 256:start * 256 + size])
    return files


def main():
    img = Path(sys.argv[1]).read_bytes()
    nd = img[25]
    counts = [struct.unpack(">H", img[26 + 2 * i:28 + 2 * i])[0] for i in range(nd)]
    save_lsn = struct.unpack(">I", img[16:20])[0]
    save_sectors = struct.unpack(">H", img[20:22])[0]
    got = disks_image(sys.argv[2], nd, counts, img[55] or 1)
    bad = 0
    # a disk's data file is padded to whole granules in the FAT's sense only in the last sector count: the sizes must agree exactly
    if len(got) != len(img):
        print("floppycheck: the disks hold %d sectors, the image %d" % (len(got) // 256, len(img) // 256))
        bad = 1
    n = min(len(got), len(img))
    diff = [s for s in range(n // 256) if got[s * 256:(s + 1) * 256] != img[s * 256:(s + 1) * 256] and not (save_lsn <= s < save_lsn + save_sectors)]
    if diff:
        print("floppycheck: %d sectors outside the save area changed, the first %s" % (len(diff), diff[:8]))
        bad = 1
    area = got[save_lsn * 256:(save_lsn + save_sectors) * 256]
    files = area_files(area)
    print("floppycheck: %d disks, the save area holds %d files: %s" % (nd, len(files), " ".join("%s(%d)" % (k, len(v)) for k, v in sorted(files.items()))))
    if len(sys.argv) >= 5:
        dev = bytearray(Path(sys.argv[3]).read_bytes())
        dsave_lsn = struct.unpack(">I", dev[16:20])[0]
        d = Path(sys.argv[4]).read_bytes()
        rel = d[:8] == b"POVL\0\0\0\1"
        body = d[8:] if rel else d
        for p in range(0, len(body) - 259, 260):
            k = struct.unpack(">I", body[p:p + 4])[0]
            lsn = dsave_lsn + k if rel else k
            dev[lsn * 256:lsn * 256 + 256] = body[p + 4:p + 260]
        want = area_files(dev[dsave_lsn * 256:(dsave_lsn + save_sectors) * 256])
        if want != files:
            bad = 1
            for k in sorted(set(want) | set(files)):
                if want.get(k) != files.get(k):
                    print("floppycheck: %s: development run %s, floppy run %s" % (k, "%d bytes" % len(want[k]) if k in want else "absent", "%d bytes" % len(files[k]) if k in files else "absent"))
        else:
            print("floppycheck: the files the game wrote are the development run's")
    sys.exit(bad)


main()

#!/usr/bin/env python3
"""ide_card.py: put the SuperIDE build (build/ide/POOLIDE.IMG, `make ide`) on a CompactFlash card from a card reader, without touching anything of the card that is in use.

    ide_card.py map DEVICE              read only: which of the 256 HDB-DOS virtual drives hold something, and which run of free drives to give `make ide IDE_DRIVE=`
    ide_card.py check DEVICE            read only: is this the card, and is the place for the game free?
    ide_card.py write DEVICE [FILE]     the same checks, then write FILE (default build/ide/POOLIDE.IMG) and read it back; needs --yes

DEVICE is the card as the computer sees it, whole (macOS /dev/rdiskN after `diskutil unmountDisk /dev/diskN`, Linux /dev/sdX; a file of the size of the card works
too, for a try). The card is a run of 512 byte sectors. HDB-DOS keeps its virtual floppy disks, 630 sectors each, in a run that starts at the HDB-DOS offset of the card
(the SuperIDE sheet says it: $052DDC = 339,420 for the 256 MB card, and 339,420 + 256 * 630 = 500,700 is the number of sectors of the card): disk n starts at sector
offset + n * 630 and keeps each 256 byte sector in the FIRST half of a card sector (HDB-DOS manual, section 4). The game goes to virtual drives that nobody uses:
by default 200 to 205 (`make ide IDE_DRIVE=200`; the file says how many it takes). The first one is a disk that HDB-DOS can read (POOL.BIN), the others are the game's
data, which only the game's own driver reads.

What `check` looks at, and what `write` refuses without --force:
  * the size of the card, against offset + 256 * 630 (a card that is not that size has another HDB-DOS offset: say it with --hdb-offset);
  * a reference drive that the owner uses (default 4): its directory track must look like an RS-DOS disk, which proves that the offset is the right one;
  * every card sector of the drives the game would take: all zeros, all $FF (what DSKINI writes) or what the file already has there; anything else is somebody's data.

Where the game goes is decided once, when it is built: `make ide IDE_DRIVE=n IDE_HDB_OFFSET=m` bakes the card sector the engine reads from into POOL.BIN and writes build/ide/ide.env next to the
card file. This tool reads that file, so it writes where the engine will look; asked for another drive or offset (--drive, --hdb-offset) it refuses, because the game would not find itself. Use
`map` first to see which drives are in use and to pick IDE_DRIVE, build, then `check`, then `write`."""
import argparse
import os
import sys

SEC = 512
DRIVE_SECS = 630


def size_of(fd):
    n = os.lseek(fd, 0, os.SEEK_END)
    if n == 0:
        sys.stderr.write("note: the size of the device is not known (a raw disk of macOS does not tell): the size check is skipped\n")
    return n // SEC


def read(fd, lba, n):
    return os.pread(fd, n * SEC, lba * SEC)


def looks_like_name(b):
    return all(0x20 <= c < 0x7F for c in b)


def reference(fd, off, drive):
    """The directory of virtual drive `drive`: track 17 sector 3 is sector 17 * 18 + 2 of the 35 track disk, in the first half of its card sector."""
    s = read(fd, off + drive * DRIVE_SECS + 17 * 18 + 2, 1)[:256]
    names = []
    for e in range(8):
        ent = s[e * 32:e * 32 + 32]
        if len(ent) < 32 or ent[0] in (0x00, 0xFF):
            continue
        if looks_like_name(ent[:8]) and looks_like_name(ent[8:11]):
            names.append((ent[:8].decode().rstrip() + "/" + ent[8:11].decode()))
    return names


FAT_SEC = 17 * 18 + 1            # track 17 sector 2 of a drive: the allocation table (68 granules, 0xFF = free)
DIR_SECS = range(17 * 18 + 2, 17 * 18 + 11)    # track 17 sectors 3 to 11: the directory (8 entries of 32 bytes a sector)


def uniform(s):
    return s.count(s[0]) == SEC and s[0] in (0x00, 0xFF)


def drive_info(fd, lba):
    """What is on virtual drive at card sector lba: the sectors (numbers within the drive) that are not all $00 or all $FF, and whether it is an empty RS-DOS disk: the
    allocation table says every granule is free and the directory has no file (an entry starts with $FF, never used, or $00, deleted). An empty disk that HDB-DOS has
    formatted is not blank (it has a label sector and some bookkeeping), but there is nothing on it: its files, if there were any, are free space."""
    d = read(fd, lba, DRIVE_SECS)
    if len(d) < DRIVE_SECS * SEC:
        return None
    sec = lambda k: d[k * SEC:(k + 1) * SEC]
    odd = [k for k in range(DRIVE_SECS) if not uniform(sec(k))]
    fat_free = sec(FAT_SEC)[:68] == b"\xff" * 68
    dir_clean = all(sec(k)[e * 32] in (0x00, 0xFF) for k in DIR_SECS for e in range(8))
    return dict(odd=odd, empty=fat_free and dir_clean, data=d)


def drive_state(info, content=None):
    """'blank', 'empty' (a formatted disk with no files), 'ours' (the sectors are the file's) or 'used'"""
    if info is None:
        return "short"
    if content is not None and info["data"] == content:
        return "ours"
    if not info["odd"]:
        return "blank"
    return "empty" if info["empty"] else "used"


def describe(info):
    """the sectors that are not uniform, as track/sector, with the first bytes of the first half"""
    return ", ".join("t%d s%d %s" % (k // 18, k % 18 + 1, info["data"][k * SEC:k * SEC + 8].hex()) for k in info["odd"][:4]) + (" ..." if len(info["odd"]) > 4 else "")


def region_state(fd, lba0, drives, content=None, first=0):
    """'free' (every drive blank, an empty formatted disk, or already what the file has) or the first drive that holds something"""
    seen = set()
    for i in range(drives):
        info = drive_info(fd, lba0 + i * DRIVE_SECS)
        st = drive_state(info, None if content is None else content[i * DRIVE_SECS * SEC:(i + 1) * DRIVE_SECS * SEC])
        seen.add(st)
        if st in ("used", "short"):
            return "drive %d (card sector %d) is %s: %s" % (first + i, lba0 + i * DRIVE_SECS, "in use" if st == "used" else "beyond the card", describe(info) if info else "")
    return "ours" if seen == {"ours"} else "free (%s)" % ", ".join(sorted(seen))


def drive_map(fd, off, ndrives):
    """For every HDB-DOS virtual drive: its state and what is odd on it"""
    out = []
    for dr in range(ndrives):
        info = drive_info(fd, off + dr * DRIVE_SECS)
        out.append((dr, drive_state(info) if info else "short", info, reference(fd, off, dr) if info and info["odd"] and not info["empty"] else []))
    return out


def free_run(m, n, top):
    """The highest run of n drives, all free (blank or empty), that ends below drive `top` (drive 255 is the NitrOS-9 boot disk on the SuperIDE sheet, and the owner adds drives upward from 0)"""
    run = 0
    for dr in range(top - 1, -1, -1):
        run = run + 1 if m[dr][1] in ("blank", "empty") else 0
        if run == n:
            return dr
    return None


def load_env(path):
    env = {}
    if os.path.exists(path):
        for line in open(path):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                env[k] = int(v)
    return env


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["map", "check", "write"])
    ap.add_argument("device")
    ap.add_argument("file", nargs="?", default="build/ide/POOLIDE.IMG")
    ap.add_argument("--hdb-offset", type=int, default=None, help="the card's HDB-DOS offset in sectors (default: the build's, in ide.env next to the file; $052DDC = 339420 is the 256 MB card's)")
    ap.add_argument("--drive", type=int, default=None, help="the first HDB-DOS virtual drive the game takes (default: the build's, in ide.env; `make ide IDE_DRIVE=` sets it)")
    ap.add_argument("--drives", type=int, default=6, help="how many (the file says; default 6)")
    ap.add_argument("--ref-drive", type=int, default=4, help="a drive that the owner uses, to prove the offset (default 4: the HDB-DOS disk of the SuperIDE sheet)")
    ap.add_argument("--yes", action="store_true", help="write: really write")
    ap.add_argument("--force", action="store_true", help="write although a check says no (the data of the drives is lost)")
    a = ap.parse_args(argv)
    env = load_env(os.path.join(os.path.dirname(os.path.abspath(a.file)), "ide.env"))
    for opt, key, default in (("drive", "IDE_DRIVE", 200), ("hdb_offset", "IDE_HDB_OFFSET", 339420)):
        given = getattr(a, opt)
        if given is not None and key in env and given != env[key] and a.cmd != "map":
            sys.exit("%s: the build in %s put the game's place at %s %d, not %d: the engine would not find the game there. Build again with `make ide %s=%d`, or drop the option." % (a.cmd, a.file, key, env[key], given, key, given))
        setattr(a, opt, given if given is not None else env.get(key, default))
    content = None
    if a.cmd == "write" or os.path.exists(a.file):
        if os.path.exists(a.file):
            content = open(a.file, "rb").read()
            assert len(content) % (DRIVE_SECS * SEC) == 0, "%s is not a whole number of drives" % a.file
            a.drives = len(content) // (DRIVE_SECS * SEC)
    if a.cmd == "write" and content is None:
        sys.exit("write: %s is not there (make ide)" % a.file)
    fd = os.open(a.device, os.O_RDONLY)
    if a.cmd == "map":
        total = size_of(fd)
        nd = min(256, (total - a.hdb_offset) // DRIVE_SECS) if total else 256
        m = drive_map(fd, a.hdb_offset, nd)
        sym = {"blank": ".", "empty": "e", "used": "#", "short": "?"}
        print("HDB-DOS offset %d: %d virtual drives. '.' blank (all zeros or all $FF), 'e' a formatted disk with no files (HDB-DOS's label and bookkeeping only), '#' holds files or data:" % (a.hdb_offset, nd))
        for r in range(0, nd, 32):
            print("  %3d  %s" % (r, "".join(sym[x[1]] for x in m[r:r + 32])))
        for dr, st, info, names in m:
            if st == "used":
                print("  drive %3d: %3d of %d sectors in use%s" % (dr, len(info["odd"]), DRIVE_SECS, "; " + ", ".join(names[:6]) if names else ""))
        groups = {}
        for dr, st, info, names in m:
            if st == "empty":
                groups.setdefault(tuple(info["odd"]), []).append(dr)
        for odd, drs in groups.items():
            info = m[drs[0]][2]
            print("  %d empty formatted drives (%s) with only these sectors set: %s" % (len(drs), ", ".join(str(x) for x in drs[:6]) + (" ..." if len(drs) > 6 else ""), describe(info)))
        want = a.drives
        got = free_run(m, want, min(nd, 255))
        if got is None:
            print("no run of %d free drives below drive 255" % want)
        else:
            print("the highest free run of %d drives (below 255) starts at drive %d: `make ide IDE_DRIVE=%d IDE_HDB_OFFSET=%d`, then check and write" % (want, got, got, a.hdb_offset))
        os.close(fd)
        return 0
    lba0 = a.hdb_offset + a.drive * DRIVE_SECS
    secs = a.drives * DRIVE_SECS
    problems = []
    total = size_of(fd)
    if total:
        want = a.hdb_offset + 256 * DRIVE_SECS
        print("card: %d sectors (%d bytes); the HDB-DOS drives end at sector %d%s" % (total, total * SEC, want, "" if total >= want else "  <-- the card is smaller"))
        if total < want:
            problems.append("the card has %d sectors, fewer than offset + 256 drives = %d" % (total, want))
        elif total != want:
            print("  (not exactly: HDB-DOS keeps %d drives of this card; the game's drives %d to %d must be among them)" % ((total - a.hdb_offset) // DRIVE_SECS, a.drive, a.drive + a.drives - 1))
        if lba0 + secs > total:
            problems.append("the game's drives would end past the end of the card")
    names = reference(fd, a.hdb_offset, a.ref_drive)
    print("reference drive %d (at card sector %d): directory %s" % (a.ref_drive, a.hdb_offset + a.ref_drive * DRIVE_SECS, ", ".join(names) if names else "nothing readable"))
    if not names:
        problems.append("virtual drive %d has no directory at the place HDB-DOS keeps it: the offset %d is probably not this card's" % (a.ref_drive, a.hdb_offset))
    st = region_state(fd, lba0, a.drives, content, a.drive)
    print("the game's drives %d to %d (card sectors %d to %d): %s" % (a.drive, a.drive + a.drives - 1, lba0, lba0 + secs - 1, st))
    if not (st == "ours" or st.startswith("free")):
        problems.append("the game's drives are not free: %s" % st)
    os.close(fd)
    if a.cmd == "check":
        print("OK: nothing in the way" if not problems else "NOT OK:\n  " + "\n  ".join(problems))
        return 1 if problems else 0
    if problems and not a.force:
        print("NOT writing:\n  " + "\n  ".join(problems))
        return 1
    if not a.yes:
        print("would write %s (%d sectors) at card sector %d of %s: say --yes" % (a.file, len(content) // SEC, lba0, a.device))
        return 2
    fd = os.open(a.device, os.O_RDWR)
    pos = 0
    step = 128 * SEC
    while pos < len(content):
        n = os.pwrite(fd, content[pos:pos + step], lba0 * SEC + pos)
        assert n == len(content[pos:pos + step]), "short write"
        pos += step
    os.fsync(fd)
    back = b"".join(os.pread(fd, min(step, len(content) - p), lba0 * SEC + p) for p in range(0, len(content), step))
    os.close(fd)
    if back != content:
        print("VERIFY FAILED: what was read back is not what was written")
        return 1
    print("written and read back: %d sectors at card sector %d (virtual drives %d to %d)" % (len(content) // SEC, lba0, a.drive, a.drive + a.drives - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

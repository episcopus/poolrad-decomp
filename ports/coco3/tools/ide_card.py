#!/usr/bin/env python3
"""ide_card.py: put the SuperIDE build (build/ide/POOLIDE.IMG, `make ide`) on a CompactFlash card from a card reader, without touching anything of the card that is in use.

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
  * every card sector of the drives the game would take: all zeros, all $FF (what DSKINI writes) or what the file already has there; anything else is somebody's data."""
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


def region_state(fd, lba0, secs, content=None):
    """'blank' (every sector all $00 or all $FF), 'ours' (the sectors are the file's), or the first sector that is somebody's"""
    ours = True
    blank = True
    chunk = 256
    for i in range(0, secs, chunk):
        n = min(chunk, secs - i)
        d = read(fd, lba0 + i, n)
        if len(d) < n * SEC:
            return "short read at sector %d" % (lba0 + i)
        for k in range(n):
            s = d[k * SEC:(k + 1) * SEC]
            if blank and not (s.count(s[0]) == SEC and s[0] in (0x00, 0xFF)):
                blank = False
                first, first_bytes = lba0 + i + k, s[:8].hex()
            if ours and (content is None or s != content[(i + k) * SEC:(i + k + 1) * SEC]):
                ours = False
            if not blank and not ours:
                return "sector %d is in use (first bytes %s)" % (first, first_bytes)
    return "blank" if blank else "ours"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["check", "write"])
    ap.add_argument("device")
    ap.add_argument("file", nargs="?", default="build/ide/POOLIDE.IMG")
    ap.add_argument("--hdb-offset", type=int, default=339420, help="the card's HDB-DOS offset in sectors (default $052DDC, the 256 MB card)")
    ap.add_argument("--drive", type=int, default=200, help="the first HDB-DOS virtual drive the game takes (default 200; `make ide IDE_DRIVE=` says the same to the build)")
    ap.add_argument("--drives", type=int, default=6, help="how many (the file says; default 6)")
    ap.add_argument("--ref-drive", type=int, default=4, help="a drive that the owner uses, to prove the offset (default 4: the HDB-DOS disk of the SuperIDE sheet)")
    ap.add_argument("--yes", action="store_true", help="write: really write")
    ap.add_argument("--force", action="store_true", help="write although a check says no (the data of the drives is lost)")
    a = ap.parse_args(argv)
    content = None
    if a.cmd == "write" or os.path.exists(a.file):
        if os.path.exists(a.file):
            content = open(a.file, "rb").read()
            assert len(content) % (DRIVE_SECS * SEC) == 0, "%s is not a whole number of drives" % a.file
            a.drives = len(content) // (DRIVE_SECS * SEC)
    if a.cmd == "write" and content is None:
        sys.exit("write: %s is not there (make ide)" % a.file)
    fd = os.open(a.device, os.O_RDONLY)
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
    st = region_state(fd, lba0, secs, content)
    print("the game's drives %d to %d (card sectors %d to %d): %s" % (a.drive, a.drive + a.drives - 1, lba0, lba0 + secs - 1, st))
    if st not in ("blank", "ours"):
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

#!/usr/bin/env python3
"""ide_card.py: put the SuperIDE build (build/ide/POOLIDE.IMG, `make ide`) on a CompactFlash card from a card reader, without touching anything of the card that is in use.

    ide_card.py map DEVICE              read only: which of the 256 HDB-DOS virtual drives hold something, and which run of free drives to give `make ide IDE_DRIVE=`
    ide_card.py check DEVICE            read only: is this the card, and is the place for the game free?
    ide_card.py write DEVICE [FILE]     the same checks, then write FILE (default build/ide/POOLIDE.IMG) and read it back; needs --yes
    ide_card.py saves DEVICE|FILE       read only: the files of the game's save area (on the card, or in a card file) and its free room
    ... write DEVICE --add-slot F       also put saved game F (SAVGAMF.DAT and CHRDATF*.* of --saves-from, default the game folder's SAVE)
                                        into the save area, next to the card's own saves; --replace-slot if the card already has an F
    ide_card.py pull DEVICE|FILE F      read only on the card: copy saved game F (SAVGAMF.DAT and CHRDATF*.*) out of the save area into --to (default the
                                        game folder's SAVE), for the PC or the Tandy 1000; --replace-slot if that folder already has a different F
                                        (its files are moved to build/save-backup/ first)

DEVICE is the card as the computer sees it, whole (macOS /dev/rdiskN after `diskutil unmountDisk /dev/diskN`, Linux /dev/sdX; a file of the size of the card works
too, for a try). The card is a run of 512 byte sectors. HDB-DOS keeps its virtual floppy disks, 630 sectors each, in a run that starts at the HDB-DOS offset of the card
(the SuperIDE sheet says it: $052DDC = 339,420 for the 256 MB card, and 339,420 + 256 * 630 = 500,700 is the number of sectors of the card): disk n starts at sector
offset + n * 630 and keeps each 256 byte sector in the FIRST half of a card sector (HDB-DOS manual, section 4). The game goes to virtual drives that nobody uses:
by default 200 to 205 (`make ide IDE_DRIVE=200`; the file says how many it takes). The first one is a disk that HDB-DOS can read (POOL.BIN), the others are the game's
data, which only the game's own driver reads.

Taking a saved game back to the PC (pull F): the CoCo writes its saves in the PC's byte order (docs/PHASE-8.6.md), so the files of the save area are the files the
PC game reads, unchanged. The slot's files are written under the names the save area has; a folder that already has the same files is left alone, a folder with other
files of that slot is refused unless --replace-slot, which first moves them (all of that slot's files, so no stray CHRDATF8 of an older party is left behind) into
build/save-backup/F-<date and time>/ of the port. Under sudo (a raw disk of macOS needs it) the files are given to the user who ran sudo.

A card that already has a previous build of the game at the place (drive 200 is a disk with POOL/BIN and the next drive starts with the image's "PIM2") is an UPDATE: `write` replaces
the old build without --force, and **keeps the saved games of the card** (the 512 save sectors of the old image are copied into the new one; --fresh-saves takes the build's own
seeded saves instead). Only a run of drives that starts at the old game's boot drive counts as the old game: a drive after a free one that holds something is somebody else's.

Adding a saved game (--add-slot X): the save area is a directory of up to 127 files, each with a room of 256 byte units (src/game/rtl_file.c). The slot's files get rooms
the way the game gives them (60 units for a .DAT, 5 for .ITM, 3 for .SPC, 2 for .SAV, or what the file needs if more), each in the smallest free run, after the card's
saves have been carried over; a slot the card already has is refused (its files would be lost) unless --replace-slot, which first erases the card's files of that slot.

What `check` looks at, and what `write` refuses without --force:
  * the size of the card, against offset + 256 * 630 (a card that is not that size has another HDB-DOS offset: say it with --hdb-offset);
  * a reference drive that the owner uses (default 4): its directory track must look like an RS-DOS disk, which proves that the offset is the right one;
  * every card sector of the drives the game would take: all zeros, all $FF (what DSKINI writes), what the file already has there or a previous build of the game (above); anything else is somebody's data.

Where the game goes is decided once, when it is built: `make ide IDE_DRIVE=n IDE_HDB_OFFSET=m` bakes the card sector the engine reads from into POOL.BIN and writes build/ide/ide.env next to the
card file. This tool reads that file, so it writes where the engine will look; asked for another drive or offset (--drive, --hdb-offset) it refuses, because the game would not find itself. Use
`map` first to see which drives are in use and to pick IDE_DRIVE, build, then `check`, then `write`."""
import argparse
import os
import shutil
import sys
import time

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


def region_state(fd, lba0, drives, content=None, first=0, old=None):
    """'free' (every drive blank, an empty formatted disk, or already what the file has), 'previous build' (a run of drives from the first that is the old game: `old`, the result of
    previous_build) or the first drive that holds something"""
    seen = set()
    run = old is not None                          # still inside the old game's run of drives
    nprev = 0
    for i in range(drives):
        info = drive_info(fd, lba0 + i * DRIVE_SECS)
        st = drive_state(info, None if content is None else content[i * DRIVE_SECS * SEC:(i + 1) * DRIVE_SECS * SEC])
        if st == "used" and run:
            st = "previous"
        elif st in ("blank", "empty"):
            run = False                            # a free drive ends the old game: what follows it that holds something is somebody's
        if st == "previous":
            nprev += 1
        seen.add(st)
        if st in ("used", "short"):
            return "drive %d (card sector %d) is %s: %s" % (first + i, lba0 + i * DRIVE_SECS, "in use" if st == "used" else "beyond the card", describe(info) if info else "")
    if "previous" in seen:
        return "previous build of the game (%d of its drives are replaced)" % nprev
    return "ours" if seen == {"ours"} else "free (%s)" % ", ".join(sorted(seen))


def drive_map(fd, off, ndrives):
    """For every HDB-DOS virtual drive: its state and what is odd on it"""
    out = []
    for dr in range(ndrives):
        info = drive_info(fd, off + dr * DRIVE_SECS)
        out.append((dr, drive_state(info) if info else "short", info, reference(fd, off, dr) if info and info["odd"] and not info["empty"] else []))
    return out


def previous_build(fd, lba0):
    """The header of the game that is on the card at lba0, or None: the first drive is a disk with POOL/BIN in its directory and the next drive's first card sector is the image's
    (its two first sectors: "PIM2", then the counts of the image header). Returns (save_lsn, save_sectors) of that image."""
    if "POOL/BIN" not in reference(fd, lba0, 0):
        return None
    h = read(fd, lba0 + DRIVE_SECS, 1)
    if h[:4] != b"PIM2":
        return None
    return int.from_bytes(h[16:20], "big"), int.from_bytes(h[20:22], "big")


def saves_at(lba_base, save_lsn):
    """The first card sector of the saves of an image whose first sector is at card sector lba_base (src/engine/ide.c: one card sector for each save sector, from base + save_lsn / 2)"""
    return lba_base + save_lsn // 2


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


SAVE_UNITS = 512                                   # the save area: 512 units of 256 bytes (src/game/rtl_file.c)
DIR_ENTRIES = 127
DIR_HEAD = 16


class SaveArea:
    """The save area of a card file (bytes, from its first card sector) whose save unit 0 is at card sector `first`: one unit in the first half of each card sector."""

    def __init__(self, content, first):
        self.b = bytearray(content)
        self.first = first

    def unit(self, u):
        o = (self.first + u) * SEC
        return self.b[o:o + 256]

    def put(self, u, data):
        o = (self.first + u) * SEC
        self.b[o:o + 256] = bytes(data).ljust(256, b"\0")

    def read(self, off, n):
        out = bytearray()
        while n > 0:
            u, r = divmod(off, 256)
            k = min(n, 256 - r)
            out += self.unit(u)[r:r + k]
            off += k
            n -= k
        return bytes(out)

    def write(self, off, data):
        data = bytes(data)
        while data:
            u, r = divmod(off, 256)
            k = min(len(data), 256 - r)
            cur = bytearray(self.unit(u))
            cur[r:r + k] = data[:k]
            self.put(u, cur)
            off += k
            data = data[k:]

    def entries(self):
        """[(index, name 'BASE.EXT', start unit, room in units, size in bytes)] of the live entries"""
        if self.read(0, 4) != b"PSAV":
            return []
        out = []
        for i in range(DIR_ENTRIES):
            e = self.read(DIR_HEAD + 16 * i, 16)
            if e[0] == 0:
                continue
            name = e[:8].decode("latin-1").rstrip() + "." + e[8:11].decode("latin-1").rstrip()
            out.append((i, name, int.from_bytes(e[11:13], "big"), e[13], int.from_bytes(e[14:16], "big")))
        return out

    def file(self, ent):
        return self.read(ent[2] * 256, ent[4])

    def free_units(self):
        used = set(range(8))
        for _i, _n, start, cap, _sz in self.entries():
            used.update(range(start, min(start + cap, SAVE_UNITS)))
        return SAVE_UNITS - len(used)

    def find_room(self, cap):
        """the start of the smallest run of at least cap free units (rtl_file.c find_room), or None"""
        used = [False] * SAVE_UNITS
        for u in range(8):
            used[u] = True
        for _i, _n, start, c, _sz in self.entries():
            for u in range(start, min(start + c, SAVE_UNITS)):
                used[u] = True
        best, bestlen, run, start = None, None, 0, 0
        for u in range(SAVE_UNITS + 1):
            if u < SAVE_UNITS and not used[u]:
                if run == 0:
                    start = u
                run += 1
            else:
                if run >= cap and (bestlen is None or run < bestlen):
                    best, bestlen = start, run
                run = 0
        return best

    def erase(self, index):
        self.write(DIR_HEAD + 16 * index, b"\0")

    def add(self, name, data):
        """a new file with the game's room for its kind (open_write in rtl_file.c), or more if it needs more"""
        base, _, ext = name.upper().partition(".")
        key = (base.ljust(8)[:8] + ext.ljust(3)[:3]).encode("ascii")
        cap = 16
        if key[8:11] == b"DAT":
            cap = 60
        elif key[8:11] == b"TXT":
            cap = 12
        elif key[8:10] == b"IT":
            cap = 5
        elif key[8:10] == b"SP":
            cap = 3
        elif key[8:9] in (b"S", b"C"):
            cap = 2
        cap = max(cap, -(-len(data) // 256))
        if self.read(0, 4) != b"PSAV":
            self.write(0, b"PSAV" + (8).to_bytes(2, "big") + bytes(2))
        free = [i for i in range(DIR_ENTRIES) if self.read(DIR_HEAD + 16 * i, 1) == b"\0"]
        if not free:
            raise SystemExit("save area: no free directory entry for %s" % name)
        start = self.find_room(cap)
        if start is None:
            raise SystemExit("save area: no run of %d free units for %s (%d units free in all)" % (cap, name, self.free_units()))
        self.write(DIR_HEAD + 16 * free[0], key + start.to_bytes(2, "big") + bytes([cap]) + len(data).to_bytes(2, "big"))
        self.write(start * 256, data)
        nxt = int.from_bytes(self.read(4, 2), "big")
        if start + cap > nxt:
            self.write(4, (start + cap).to_bytes(2, "big"))


def slot_files(folder, slot):
    """SAVGAM<slot>.DAT and CHRDAT<slot>*.* of a SAVE folder: [(name, bytes)]"""
    slot = slot.upper()
    out = []
    for f in sorted(os.listdir(folder)):
        u = f.upper()
        if u == "SAVGAM%s.DAT" % slot or (u.startswith("CHRDAT%s" % slot) and len(u.partition(".")[0]) == 8):
            out.append((u, open(os.path.join(folder, f), "rb").read()))
    if not any(n.startswith("SAVGAM") for n, _ in out):
        raise SystemExit("%s has no SAVGAM%s.DAT" % (folder, slot))
    return out


def slot_of(name):
    """the slot letter of a saved game's file (SAVGAMx.DAT, CHRDATxn.*), or None"""
    if name.startswith("SAVGAM") and name.endswith(".DAT") and len(name) == 11:
        return name[6]
    if name.startswith("CHRDAT") and len(name.partition(".")[0]) == 8:
        return name[6]
    return None


def add_slot(area, slot, files, replace):
    """put a saved game's files into the save area; returns lines that say what was done"""
    slot = slot.upper()
    have = [e for e in area.entries() if slot_of(e[1]) == slot]
    lines = []
    if have:
        same = sorted((n, area.file(e)) for e in have for n in [e[1]]) == sorted(files)
        if same:
            return ["saved game %s: already in the save area, the same files" % slot]
        if not replace:
            raise SystemExit("saved game %s is already in the card's save area (%s): say --replace-slot to replace it (those files are lost)" % (
                slot, ", ".join(e[1] for e in have)))
        for e in have:
            area.erase(e[0])
        lines.append("saved game %s: the save area's %d files of it erased (--replace-slot)" % (slot, len(have)))
    for name, data in files:
        area.add(name, data)
    lines.append("saved game %s: %d files added (%d bytes); %d of %d units of the save area free" % (
        slot, len(files), sum(len(d) for _, d in files), area.free_units(), SAVE_UNITS))
    return lines


def give(path):
    """under sudo, give a file or folder this tool made to the user who ran sudo (a raw disk of macOS is read as root)"""
    if hasattr(os, "geteuid") and os.geteuid() == 0 and "SUDO_UID" in os.environ:
        os.chown(path, int(os.environ["SUDO_UID"]), int(os.environ.get("SUDO_GID", os.environ["SUDO_UID"])))


def pull_slot(area, slot, dest, replace, backup_root):
    """copy saved game `slot` out of the save area into the folder dest; returns lines that say what was done"""
    slot = slot.upper()
    files = sorted((e[1], area.file(e)) for e in area.entries() if slot_of(e[1]) == slot)
    if not any(n.startswith("SAVGAM") for n, _ in files):
        have = sorted({slot_of(e[1]) for e in area.entries() if e[1].startswith("SAVGAM")})
        raise SystemExit("the save area has no saved game %s (it has: %s)" % (slot, " ".join(have) or "none"))
    if not os.path.isdir(dest):
        raise SystemExit("%s is not a folder" % dest)
    old = [f for f in sorted(os.listdir(dest)) if slot_of(f.upper()) == slot]
    if sorted((f.upper(), open(os.path.join(dest, f), "rb").read()) for f in old) == files:
        return ["saved game %s: %s already has the same %d files" % (slot, dest, len(files))]
    lines = []
    if old:
        if not replace:
            raise SystemExit("%s already has a saved game %s (%s) that is not the card's: say --replace-slot to replace it (its files are moved to %s first)" % (
                dest, slot, ", ".join(old), backup_root))
        bdir = os.path.join(backup_root, "%s-%s" % (slot, time.strftime("%Y%m%d-%H%M%S")))
        os.makedirs(bdir)
        for d in (backup_root, bdir):
            give(d)
        for f in old:
            shutil.move(os.path.join(dest, f), os.path.join(bdir, f))
        lines.append("saved game %s: the folder's %d files of it moved to %s" % (slot, len(old), bdir))
    for name, data in files:
        p = os.path.join(dest, name)
        with open(p, "wb") as fh:
            fh.write(data)
        give(p)
    lines.append("saved game %s: %d files written to %s (%d bytes): %s" % (slot, len(files), dest, sum(len(d) for _, d in files), " ".join(n for n, _ in files)))
    return lines


def load_area(fd, a):
    """the save area of DEVICE (a card, the game at --drive) or of a card file (build/ide/POOLIDE.IMG); returns (area, what it is)"""
    lba0 = a.hdb_offset + a.drive * DRIVE_SECS
    h = read(fd, DRIVE_SECS, 1)
    if h[:4] == b"PIM2" and size_of(fd) <= 64 * DRIVE_SECS:       # a card file (build/ide/POOLIDE.IMG): the image starts at its second drive
        data = os.pread(fd, size_of(fd) * SEC, 0)
        return SaveArea(data, saves_at(DRIVE_SECS, int.from_bytes(h[16:20], "big"))), "%s: a card file" % a.device
    old = previous_build(fd, lba0)
    if old is None:
        sys.exit("%s: no build of the game at drive %d of %s" % (a.cmd, a.drive, a.device))
    first = saves_at(lba0 + DRIVE_SECS, old[0])
    return SaveArea(os.pread(fd, (first + old[1]) * SEC, 0), first), "%s: the game at drive %d" % (a.device, a.drive)


def list_saves(area):
    ents = area.entries()
    slots = sorted({slot_of(e[1]) for e in ents if slot_of(e[1]) and e[1].startswith("SAVGAM")})
    print("save area: %d files, saved games %s; %d of %d units free" % (len(ents), " ".join(slots) or "none", area.free_units(), SAVE_UNITS))
    for _i, name, start, cap, size in sorted(ents, key=lambda e: e[1]):
        print("  %-12s %6d bytes   units %3d..%3d" % (name, size, start, start + cap - 1))



def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["map", "check", "write", "saves", "pull"])
    ap.add_argument("device")
    ap.add_argument("file", nargs="?", default=None, help="write: the card file (default build/ide/POOLIDE.IMG); pull: the slot letter")
    ap.add_argument("--hdb-offset", type=int, default=None, help="the card's HDB-DOS offset in sectors (default: the build's, in ide.env next to the file; $052DDC = 339420 is the 256 MB card's)")
    ap.add_argument("--drive", type=int, default=None, help="the first HDB-DOS virtual drive the game takes (default: the build's, in ide.env; `make ide IDE_DRIVE=` sets it)")
    ap.add_argument("--drives", type=int, default=6, help="how many (the file says; default 6)")
    ap.add_argument("--ref-drive", type=int, default=4, help="a drive that the owner uses, to prove the offset (default 4: the HDB-DOS disk of the SuperIDE sheet)")
    ap.add_argument("--yes", action="store_true", help="write: really write")
    ap.add_argument("--force", action="store_true", help="write although a check says no (the data of the drives is lost)")
    ap.add_argument("--fresh-saves", action="store_true", help="update: take the build's own saved games and not the ones of the card (they are lost)")
    ap.add_argument("--add-slot", metavar="X", help="write: also put saved game X (a letter) into the save area, from --saves-from")
    ap.add_argument("--saves-from", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "poolrad", "SAVE"),
                    help="the SAVE folder --add-slot takes the files from (default: the game folder's, poolrad/SAVE)")
    ap.add_argument("--replace-slot", action="store_true", help="--add-slot: replace the slot when the card already has it (its files there are lost); "
                    "pull: replace the slot when --to already has a different one (its files are moved to build/save-backup/ first)")
    ap.add_argument("--to", default=None, help="pull: the SAVE folder the slot goes to (default: the game folder's, poolrad/SAVE)")
    ap.add_argument("--backup", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "save-backup"),
                    help="pull --replace-slot: where the folder's old files of the slot go (default the port's build/save-backup)")
    a = ap.parse_args(argv)
    slot = None
    if a.cmd == "pull":
        slot, a.file = a.file, None
        if not slot or len(slot) != 1 or not slot.isalpha():
            ap.error("pull: say which saved game, a letter: ide_card.py pull DEVICE F")
    if a.file is None:
        a.file = "build/ide/POOLIDE.IMG"
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
    if a.cmd in ("saves", "pull"):
        area, what = load_area(fd, a)
        os.close(fd)
        print(what)
        if a.cmd == "saves":
            list_saves(area)
            return 0
        for line in pull_slot(area, slot, os.path.abspath(a.to or a.saves_from), a.replace_slot, os.path.abspath(a.backup)):
            print(line)
        return 0
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
    old = previous_build(fd, lba0)
    st = region_state(fd, lba0, a.drives, content, a.drive, old)
    print("the game's drives %d to %d (card sectors %d to %d): %s" % (a.drive, a.drive + a.drives - 1, lba0, lba0 + secs - 1, st))
    if not (st == "ours" or st.startswith("free") or st.startswith("previous")):
        problems.append("the game's drives are not free: %s" % st)
    carry = None                                   # the saved games of the old build, to be put into the new one
    if st.startswith("previous") and content is not None:
        new_lsn, new_n = int.from_bytes(content[DRIVE_SECS * SEC + 16:DRIVE_SECS * SEC + 20], "big"), int.from_bytes(content[DRIVE_SECS * SEC + 20:DRIVE_SECS * SEC + 22], "big")
        old_lsn, old_n = old
        if a.fresh_saves:
            print("UPDATE: the saved games of the card are replaced by the build's own (--fresh-saves)")
        elif old_n == new_n and old_n > 0 and old_lsn % 2 == 0 and new_lsn % 2 == 0:
            carry = (saves_at(lba0 + DRIVE_SECS, old_lsn), saves_at(DRIVE_SECS, new_lsn), old_n)
            print("UPDATE: the previous build is replaced and the card's %d saved game sectors are kept (--fresh-saves does not)" % old_n)
        else:
            problems.append("the saved games of the old build (%d sectors at image sector %d) do not fit the new image (%d at %d): say --fresh-saves to lose them" % (old_n, old_lsn, new_n, new_lsn))
    os.close(fd)
    if a.cmd == "check":
        print("OK: nothing in the way" if not problems else "NOT OK:\n  " + "\n  ".join(problems))
        return 1 if problems else 0
    if problems and not a.force:
        print("NOT writing:\n  " + "\n  ".join(problems))
        return 1
    if carry:
        src, dst, n = carry                        # dst is in the file (card sectors from its start): the old saves go there
        old_saves = read(fd2 := os.open(a.device, os.O_RDONLY), src, n)
        os.close(fd2)
        content = content[:dst * SEC] + old_saves + content[(dst + n) * SEC:]
    if a.add_slot:
        new_lsn = int.from_bytes(content[DRIVE_SECS * SEC + 16:DRIVE_SECS * SEC + 20], "big")
        area = SaveArea(content, saves_at(DRIVE_SECS, new_lsn))
        for line in add_slot(area, a.add_slot, slot_files(a.saves_from, a.add_slot), a.replace_slot):
            print(line)
        content = bytes(area.b)
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

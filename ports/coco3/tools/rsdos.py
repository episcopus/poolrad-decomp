#!/usr/bin/env python3
"""rsdos.py: write and read RS-DOS (Disk BASIC) disk images: 35 tracks of 18 sectors of 256 bytes, the FAT in track 17
sector 2 (68 granule bytes), the directory in track 17 sectors 3..11 (32 bytes an entry), files in chains of 9-sector
granules (two to a track, track 17 skipped). The writer is deterministic: files in the order given, granules from 0 up,
every unused byte $FF (what `decb dskini` leaves). The reader follows the FAT and the directory the way the CoCo engine's
rsdos.c does, so it is the host half of the round trip."""
import struct

TRACKS, SECTORS, SSIZE = 35, 18, 256
GRANULE = 9 * SSIZE
CAPACITY = 68 * GRANULE                    # 156,672 bytes of file space


def _sector_offset(track, sector):         # sector is 1-based
    return (track * SECTORS + sector - 1) * SSIZE


def _granule_sector0(g):                   # byte offset of the first sector of granule g
    track = g // 2 + (1 if g // 2 >= 17 else 0)
    return _sector_offset(track, 1 if g % 2 == 0 else 10)


def make_image(files):
    """files: list of (name8, ext3, bytes) -> the image bytes. Raises ValueError when it does not fit."""
    img = bytearray(b"\xff" * (TRACKS * SECTORS * SSIZE))
    fat = bytearray(b"\xff" * 68)
    nxt = 0
    ent = []
    for name, ext, data in files:
        n = max(1, -(-len(data) // GRANULE))
        if nxt + n > 68:
            raise ValueError("%s%s does not fit: %d granules needed, %d left" % (name, ext, n, 68 - nxt))
        gs = list(range(nxt, nxt + n))
        nxt += n
        for i, g in enumerate(gs):
            if i + 1 < n:
                fat[g] = gs[i + 1]
            else:
                tail = -(-(len(data) - (n - 1) * GRANULE) // SSIZE) if data else 1
                fat[g] = 0xC0 | max(1, tail)
            chunk = data[i * GRANULE:(i + 1) * GRANULE]
            o = _granule_sector0(g)
            img[o:o + len(chunk)] = chunk
        last = len(data) - (-(-len(data) // SSIZE) - 1) * SSIZE if data else 0
        ent.append((name, ext, gs[0], last if data else 0))
    if len(ent) > 72:
        raise ValueError("too many files")
    img[_sector_offset(17, 2):_sector_offset(17, 2) + 68] = fat
    d = _sector_offset(17, 3)
    for i, (name, ext, first, last) in enumerate(ent):
        e = name.ljust(8).encode("ascii") + ext.ljust(3).encode("ascii") + bytes([2, 0, first]) + struct.pack(">H", last) + bytes(16)
        img[d + 32 * i:d + 32 * i + 32] = e
    return bytes(img)


def read_files(img):
    """-> {(name8, ext3): bytes} following the directory and FAT of the image."""
    fat = img[_sector_offset(17, 2):_sector_offset(17, 2) + 68]
    out = {}
    d = _sector_offset(17, 3)
    for i in range(72):
        e = img[d + 32 * i:d + 32 * i + 32]
        if e[0] == 0xFF:
            break
        if e[0] == 0:
            continue
        name, ext = e[:8].decode("ascii"), e[8:11].decode("ascii")
        g, last = e[13], struct.unpack(">H", e[14:16])[0]
        data = bytearray()
        sectors = 0
        while not fat[g] & 0x80:
            data += img[_granule_sector0(g):_granule_sector0(g) + GRANULE]
            sectors += 9
            g = fat[g]
        used = fat[g] & 0x1F
        data += img[_granule_sector0(g):_granule_sector0(g) + used * SSIZE]
        sectors += used
        size = (sectors - 1) * SSIZE + last
        out[(name, ext)] = bytes(data[:size])
    return out

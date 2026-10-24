#!/usr/bin/env python3
"""decbfs.py: a writer for RS-DOS (Disk BASIC) disk images of 35 tracks, single sided, 18 sectors of 256 bytes (161,280 bytes, the raw
sector image every CoCo emulator takes as a .DSK). It writes what `decb` would, with the placement under our control: the granules of a file
are consecutive (the floppy backend of the engine, src/engine/flop.c, finds sector k of a data file at granule first + k / 9).

  granule g = 9 sectors, two to a track; the directory track 17 is skipped (granules 0..33 are tracks 0..16, 34..67 tracks 18..34)
  FAT       track 17 sector 2: 68 bytes, 0xFF free, a link to the next granule, or 0xC0 + the sectors used in the last granule
  directory track 17 sectors 3..11, 32 byte entries: name 8, extension 3, type, ascii flag, first granule, bytes in the last sector (word)

Library: Disk().add(name, ext, data, type, ascii) -> first granule; Disk().image() -> bytes. Free space: Disk().free_granules."""
import struct

TRACKS, SECS, SSIZE = 35, 18, 256
GRAN = 9
NGRAN = 68


def gran_to_ts(g, k=0):
    """the track and the sector (1..18) of sector k (0..8) of granule g"""
    t = g >> 1
    if t >= 17:
        t += 1
    return t, (1 if g % 2 == 0 else 10) + k


class Disk:
    def __init__(self, fill=0xFF):
        self.img = bytearray([fill]) * (TRACKS * SECS * SSIZE)
        self.fat = bytearray([0xFF]) * 256        # the FAT sector: 68 granules, the rest 0xFF
        self.dir = []                              # (name, ext, type, ascii, first granule, bytes in the last sector)
        self.next_gran = 0

    @property
    def free_granules(self):
        return NGRAN - self.next_gran

    def _put(self, t, s, data):
        o = (t * SECS + (s - 1)) * SSIZE
        self.img[o:o + len(data)] = data

    def add(self, name, ext, data, ftype=1, ascii_flag=0):
        """a file in the next free granules (consecutive); returns its first granule. The last sector is padded with zeros."""
        nsec = max(1, -(-len(data) // SSIZE))
        ng = -(-nsec // GRAN)
        if self.next_gran + ng > NGRAN:
            raise ValueError("decbfs: %s.%s does not fit: %d granules wanted, %d free" % (name, ext, ng, self.free_granules))
        first = self.next_gran
        for i in range(ng):
            g = first + i
            self.fat[g] = (g + 1) if i < ng - 1 else (0xC0 | (nsec - GRAN * (ng - 1)))
        padded = data + bytes(nsec * SSIZE - len(data))
        for k in range(nsec):
            t, s = gran_to_ts(first + k // GRAN, k % GRAN)
            self._put(t, s, padded[k * SSIZE:(k + 1) * SSIZE])
        last = len(data) - (nsec - 1) * SSIZE if data else 0
        self.dir.append((name, ext, ftype, ascii_flag, first, last))
        self.next_gran += ng
        return first

    def image(self):
        for i in range(2, 12):                      # the FAT and directory sectors of track 17 start empty: FAT 0xFF, directory 0xFF
            self._put(17, i, bytes([0xFF]) * 256)
        self._put(17, 2, bytes(self.fat))
        d = bytearray([0xFF]) * (9 * 256)
        for i, (name, ext, ftype, asc, first, last) in enumerate(self.dir):
            e = name.ljust(8).encode("ascii")[:8] + ext.ljust(3).encode("ascii")[:3] + bytes([ftype, asc, first]) + struct.pack(">H", last) + bytes(16)
            d[32 * i:32 * i + 32] = e
        if len(self.dir) > 72:
            raise ValueError("decbfs: too many files")
        for i in range(9):
            self._put(17, 3 + i, bytes(d[256 * i:256 * i + 256]))
        return bytes(self.img)


def read_dir(img):
    """[(name, ext, type, ascii, first granule, last bytes)] of an image (for the checks)"""
    out = []
    for i in range(9 * 8):
        o = (17 * SECS + 2) * SSIZE + 32 * i
        e = img[o:o + 32]
        if e[0] == 0xFF:
            break
        if e[0] == 0:
            continue
        out.append((e[0:8].decode("ascii").rstrip(), e[8:11].decode("ascii").rstrip(), e[11], e[12], e[13], struct.unpack(">H", e[14:16])[0]))
    return out


def read_file(img, first):
    """the sectors of a file by its FAT chain, the last granule's unused sectors cut off (not the last sector's padding)"""
    fat = img[(17 * SECS + 1) * SSIZE:(17 * SECS + 1) * SSIZE + NGRAN]
    out = bytearray()
    g = first
    while True:
        n = fat[g]
        cnt = GRAN if n < 0xC0 else (n & 0x1F)
        for k in range(cnt):
            t, s = gran_to_ts(g, k)
            o = (t * SECS + s - 1) * SSIZE
            out += img[o:o + SSIZE]
        if n >= 0xC0:
            break
        g = n
    return bytes(out)

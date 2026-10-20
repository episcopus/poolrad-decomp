#!/usr/bin/env python3
"""savecheck.py: is the save area of an image plus an overlay in one piece? (step 8.9c)

  savecheck.py IMAGE OVERLAY      the overlay of `make play` (build/play/saves.ovl: "POVL", then records of a save area relative sector
                                  number and 256 bytes) or the .saves file of a headless run (records of an absolute sector number)

The image's save area starts with a directory (src/game/rtl_file.c): "PSAV", the first free 256 byte unit, then 127 entries of 16 bytes (name as 8 + 3
characters, start unit, room in units, size). What is checked: names that are printable and not repeated, the rooms inside the area and not overlapping
each other, the first free unit behind every room. A save area that fails was written by a different layout of the image (the first format of the
overlay kept absolute sector numbers, and a rebuild that moved the save area by two sectors made a directory with copies of itself); exit 1.
"""
import struct
import sys

img = bytearray(open(sys.argv[1], "rb").read())
save_lsn = struct.unpack(">I", img[16:20])[0]
save_sectors = struct.unpack(">H", img[20:22])[0] or 512
d = open(sys.argv[2], "rb").read()
if d[:8] == b"POVL\0\0\0\1":
    rel, body = True, d[8:]
else:
    rel, body = False, d
for p in range(0, len(body) - 259, 260):
    n = struct.unpack(">I", body[p:p + 4])[0]
    lsn = save_lsn + n if rel else n
    if not (save_lsn <= lsn < save_lsn + save_sectors):
        print("savecheck: a record for sector %d, outside the save area %d..%d" % (lsn, save_lsn, save_lsn + save_sectors - 1))
        sys.exit(1)
    img[lsn * 256:lsn * 256 + 256] = body[p + 4:p + 260]
area = img[save_lsn * 256:(save_lsn + save_sectors) * 256]
bad = []
if area[:4] != b"PSAV":
    bad.append("no PSAV header")
nxt = struct.unpack(">H", area[4:6])[0]
names, ext = [], []
for i in range(127):
    e = area[16 + 16 * i:32 + 16 * i]
    if e[0] == 0:
        continue
    nm = bytes(e[:11])
    start, cap, size = struct.unpack(">HBH", e[11:16])
    if not all(32 <= c < 127 for c in nm):
        bad.append("entry %d: name %r is not text" % (i, nm))
    if nm in names:
        bad.append("entry %d: %r twice" % (i, nm))
    names.append(nm)
    if start + cap > save_sectors or size > cap * 256:
        bad.append("entry %d (%s): room %d+%d or size %d outside the area" % (i, nm.decode("latin1").strip(), start, cap, size))
    ext.append((start, start + cap, nm))
    if start + cap > nxt:
        bad.append("entry %d (%s): its room ends at %d, past the first free unit %d" % (i, nm.decode("latin1").strip(), start + cap, nxt))
ext.sort()
for a, b in zip(ext, ext[1:]):
    if b[0] < a[1]:
        bad.append("rooms of %s and %s overlap (%d..%d, %d..)" % (a[2].decode("latin1").strip(), b[2].decode("latin1").strip(), a[0], a[1], b[0]))
if bad:
    print("savecheck: the save area is not in one piece:")
    for b in bad[:12]:
        print("  " + b)
    sys.exit(1)
print("savecheck: %d files, first free unit %d: ok" % (len(names), nxt))

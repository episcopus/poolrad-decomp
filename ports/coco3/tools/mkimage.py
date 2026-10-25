#!/usr/bin/env python3
"""mkimage.py: the game's one container image (step 8.5, decision D13 of the porting guide): everything the game loads, in 256-byte
sectors addressed by logical sector number. Reproducible (the same inputs, the same bytes).

  mkimage.py DATA_DIR GAMEDIR DGROUP.IMG OUT.img

Layout, big endian ("PIM2"; src/engine/img.c and vol.c read it):
  sector 0     "PIM2", u16 nfiles, u16 nent, u32 files_off, u32 ents_off, u32 save_lsn, u16 save_sectors
  files_off    the table of files: nfiles x { name8, u16 first entry, u16 count }, sorted by name
  ents_off     the table of entries: nent x { u8 file, u8 id, u32 byte offset from the start of the image, u16 packed size, u16 raw size }
               grouped by file; a block of a DAX file (packed = its run length coded bytes), an object the engine reads raw
               (BANK/id, CORE/0, DGROUP/0) or, for DGROUP/1 and /2, a run length coded block (tools/mkvm.py)
  data         the blocks, back to back; the raw objects start on a sector boundary so that a whole sector read lands in a block
  save area    save_sectors sectors at save_lsn (the character and game files the game writes; zero at first)"""
import hashlib
import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
import os
sys.path.insert(0, str(HERE))
sys.path.insert(0, os.path.join(os.environ.get("REPO", str(HERE.parent.parent.parent)), "tools/re"))
import dax  # noqa: E402  (tools/re)
import mkvolumes  # noqa: E402
from mkgamedisk import flatten  # noqa: E402
from stripbin import with_storage  # noqa: E402

SAVE_SECTORS = 512


def name8(n):
    return n.ljust(8).encode("ascii")


def seed_saves(data_dir):
    """The save area (src/game/rtl_file.c's directory) holding the shipped SAVE folder: the saved game and the characters of the
    original, as the game finds them. 256 sectors; room for the files the game writes later."""
    area = bytearray(SAVE_SECTORS * 256)
    d = Path(data_dir) / "SAVE"
    nxt = 8                                              # the directory takes the first eight 256 byte units
    ents = []
    for f in sorted(d.iterdir()) if d.exists() else []:
        data = f.read_bytes()
        base, _, ext = f.name.upper().partition(".")
        cap = min(-(-len(data) // 256) + 1, 255)
        ents.append((base.ljust(8)[:8] + ext.ljust(3)[:3], nxt, cap, data))
        area[nxt * 256:nxt * 256 + len(data)] = data
        nxt += cap
    if nxt > SAVE_SECTORS:
        raise SystemExit("mkimage: the shipped saves need %d units, the save area has %d" % (nxt, SAVE_SECTORS))
    if len(ents) > 127:
        raise SystemExit("mkimage: too many saved files")
    area[0:8] = b"PSAV" + struct.pack(">H", nxt) + bytes(2)
    for i, (name, start, cap, data) in enumerate(ents):
        area[16 + 16 * i:32 + 16 * i] = name.encode("ascii") + struct.pack(">HBH", start, min(cap, 255), len(data))
    return bytes(area)


def collect(data_dir, gamedir, dgroup):
    """The entries of the image, not placed yet: (files, ents) with ents = [(file index, id, packed size, raw size, kind, payload)];
    kind 1 is an object the engine reads raw (a sector boundary in front of it), kind 0 a DAX block or a coded block of DGROUP."""
    g = Path(gamedir)
    src = mkvolumes.load_sources(data_dir)                         # {NAME: [(id, packed, raw size)]}
    raw_obj = {}                                                   # name -> [(id, bytes, raw size)], stored without a code
    banks = json.loads((g / "banks.json").read_text())["banks"]
    raw_obj["BANK"] = [(b["id"], (g / (b["name"] + ".raw")).read_bytes(), None) for b in sorted(banks, key=lambda b: b["id"])]
    lo, core = flatten(g / "core.bin")
    assert lo == 0x2000
    raw_obj["CORE"] = [(0, core, None)]
    d = Path(dgroup).read_bytes()
    assert d[:4] == b"DGI2"
    hdr = d[4:9]
    pos = 9
    blocks = []
    for _ in range(2):
        pk, rw = struct.unpack(">HH", d[pos:pos + 4])
        blocks.append((d[pos + 4:pos + 4 + pk], rw))
        pos += 4 + pk
    raw_obj["DGROUP"] = [(0, hdr, None)]
    coded = {"DGROUP": [(1, blocks[0][0], blocks[0][1]), (2, blocks[1][0], blocks[1][1])]}
    files = sorted(set(src) | set(raw_obj))
    ents = []
    for fi, n in enumerate(files):
        for bid, packed, raw in src.get(n, []):
            ents.append((fi, bid, len(packed), raw, 0, packed))
        for bid, data, _ in raw_obj.get(n, []):
            ents.append((fi, bid, len(data), len(data), 1, data))
        for bid, packed, raw in coded.get(n, []):
            ents.append((fi, bid, len(packed), raw, 0, packed))
    return files, ents


def content_key(files, e):
    """What makes two entries the same bytes to the game (the eight tileset files of a family hold identical blocks): the hash of the
    unpacked block and its size; None for what is never shared (the raw objects and DGROUP)."""
    fi, bid, packed, raw, kind, payload = e
    if kind != 0 or files[fi] == "DGROUP":
        return None
    return hashlib.md5(dax.unrle(payload)).hexdigest() + ":" + str(raw)


def pool_bin_sectors(gamedir):
    """The sectors of POOL.BIN on disk 1 (whole granules: 9 sectors each)"""
    n = -(-Path(gamedir, "POOL.BIN").stat().st_size // 256)
    return -(-n // 9) * 9


TRACKS = int(os.environ.get("TRACKS", "35"))                       # tracks of a floppy of the set: 35 (a standard disk), 80 for XRoar and 80 track drives (make floppy-xroar80)
DISK_SECTORS = (TRACKS - 1) * 18                                   # the data sectors of a disk: 612 for 35 tracks (68 granules of 9 sectors)


def build(data_dir, gamedir, dgroup, dedupe=True, layout=None):
    """The image bytes, and the placement of every entry. Without a layout the entries follow each other in the order of `collect`
    and identical blocks are stored once (`dedupe`); with one (tools/mklayout.py: {"disks": [{"keys": [[file, id], ...]}], "save": n})
    every disk is filled in the order of its list and the sectors of the disks follow each other (the floppy medium: the header says
    how many sectors each disk has), an identical block is stored once on a disk but once more on each disk that has another entry of it."""
    files, ents = collect(data_dir, gamedir, dgroup)
    nent = len(ents)
    first, count = {}, {}
    for i, e in enumerate(ents):
        first.setdefault(e[0], i)
        count[e[0]] = count.get(e[0], 0) + 1
    files_off = 256
    ents_off = -(-(files_off + 12 * len(files)) // 256) * 256
    data_off = -(-(ents_off + 10 * nent) // 256) * 256
    keys = [content_key(files, e) for e in ents]
    placed = [0] * nent
    psize = [e[2] for e in ents]                                   # the packed size at the place (a block that shares another's place has that one's)
    saved = 0
    disk_secs = None
    if layout is None:
        body = bytearray()
        shared = {}                                                # content -> (offset, packed size) of its one copy
        for k, e in enumerate(ents):
            fi, bid, packed, raw, kind, payload = e
            if kind == 1 and len(body) % 256:
                body += bytes(256 - len(body) % 256)
            if keys[k] is not None and dedupe and keys[k] in shared:
                placed[k], psize[k] = shared[keys[k]]
                saved += len(payload)
                continue
            if keys[k] is not None:
                shared[keys[k]] = (data_off + len(body), len(payload))
            placed[k] = data_off + len(body)
            body += payload
        if len(body) % 256:
            body += bytes(256 - len(body) % 256)
        save_lsn = (data_off + len(body)) // 256
        out_body = bytes(body)
        saves = seed_saves(data_dir)
    else:
        index_of = {(files[e[0]], e[1]): k for k, e in enumerate(ents)}
        used = set()
        parts, disk_secs = [], []
        save_disk = layout.get("save")
        base = 0                                                   # the first sector of the disk being laid out
        save_lsn = None
        for di, disk in enumerate(layout["disks"]):
            body = bytearray()
            if di == 0:
                body += bytes(data_off)                            # the index is the first thing of disk 1
            if di == save_disk:
                save_lsn = base
                body += seed_saves(data_dir)
            shared = {}
            for key in disk["keys"]:
                k = index_of[(key[0], key[1])]
                assert k not in used, "mkimage: %s/%d is in two places of the layout" % tuple(key)
                used.add(k)
                fi, bid, packed, raw, kind, payload = ents[k]
                if kind == 1 and len(body) % 256:
                    body += bytes(256 - len(body) % 256)
                if keys[k] is not None and dedupe and keys[k] in shared:
                    placed[k], psize[k] = shared[keys[k]]
                    saved += len(payload)
                    continue
                if keys[k] is not None:
                    shared[keys[k]] = (base * 256 + len(body), len(payload))
                placed[k] = base * 256 + len(body)
                body += payload
            if len(body) % 256:
                body += bytes(256 - len(body) % 256)
            cap = DISK_SECTORS - (pool_bin_sectors(gamedir) if di == 0 else 0)
            if len(body) // 256 > cap:
                raise SystemExit("mkimage: disk %d holds %d sectors, a disk has %d" % (di + 1, len(body) // 256, cap))
            parts.append(bytes(body))
            disk_secs.append(len(body) // 256)
            base += len(body) // 256
        missing = [(files[ents[k][0]], ents[k][1]) for k in range(nent) if k not in used]
        if missing:
            raise SystemExit("mkimage: %d entries are in no disk of the layout, the first %s" % (len(missing), missing[:3]))
        out_body = b"".join(parts)
        saves = b""
        if save_lsn is None:
            raise SystemExit("mkimage: the layout has no save disk")
    img = bytearray(data_off)
    img[0:24] = b"PIM2" + struct.pack(">HHLLLH", len(files), nent, files_off, ents_off, save_lsn, SAVE_SECTORS) + bytes(2)
    if disk_secs is not None:                                      # the floppy medium: byte 24 = 1, the number of disks, the sectors of each
        assert len(disk_secs) <= 14
        img[24:26] = bytes([1, len(disk_secs)])
        for i, n in enumerate(disk_secs):
            img[26 + 2 * i:28 + 2 * i] = struct.pack(">H", n)
    for fi, n in enumerate(files):
        img[files_off + 12 * fi:files_off + 12 * fi + 12] = name8(n) + struct.pack(">HH", first.get(fi, 0), count.get(fi, 0))
    for i, (e, off) in enumerate(zip(ents, placed)):
        fi, bid, packed, raw, kind, payload = e
        img[ents_off + 10 * i:ents_off + 10 * i + 10] = struct.pack(">BBLHH", fi, bid, off, psize[i], raw)
    if layout is None:
        img += out_body + saves
    else:
        img = bytearray(img[:data_off]) + out_body[data_off:]
    return bytes(img), dict(files=files, ents=ents, keys=keys, placed=placed, psize=psize, data_off=data_off, save_lsn=save_lsn, saved=saved, disk_secs=disk_secs)


def write_floppies(img, info, gamedir, outdir, interleave=1):
    """The disks of a floppy layout as RS-DOS images (tools/decbfs.py): POOLnn.DSK, each with its slice of the image as POOLDSKn.DAT, the
    first also with POOL.BIN."""
    import decbfs
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    pos = 0
    names = []
    pool = with_storage(Path(gamedir, "POOL.BIN").read_bytes(), "STORAGE: FLOPPY DISKS", "%d TRACKS, %d DISKS" % (TRACKS, len(info["disk_secs"])))
    for i, n in enumerate(info["disk_secs"]):
        d = decbfs.Disk(tracks=TRACKS)
        name = "POOLDSK" + ("%X" % (i + 1) if i + 1 >= 10 else str(i + 1))
        if i == 0 and TRACKS > 35:
            # Disk BASIC knows 68 granules: POOL.BIN goes first, in the granules it can reach, and the data file (which the engine finds by its directory entry, the
            # first) after it, on a track boundary
            d.add("POOL", "BIN", pool, 2, 0)
            d.next_gran += d.next_gran % 2
            d.add(name, "DAT", img[pos * 256:(pos + n) * 256], 1, 0, interleave)
            d.dir.insert(0, d.dir.pop())
        else:
            d.add(name, "DAT", img[pos * 256:(pos + n) * 256], 1, 0, interleave)
            if i == 0:
                d.add("POOL", "BIN", pool, 2, 0)
        p = outdir / ("POOL%02d.DSK" % (i + 1))
        # a disk of more than 40 tracks is a JVC image with a two byte header (18 sectors a track, 1 side): XRoar takes a headerless file of that size for 40 tracks of two sides
        p.write_bytes((b"\x12\x01" if TRACKS > 40 else b"") + d.image())
        names.append(p.name)
        pos += n
    assert pos * 256 == len(img)
    return names


def write_sdc(img, gamedir, out):
    """The single file of the CoCo SDC (step 8.10b): the first 630 sectors are a 35 track RS-DOS disk with POOL.BIN (and POOLSDC.DAT first, the marker the engine
    looks for), so that Disk BASIC boots it from drive 0; the game's image follows, which the engine reads through the SDC's command mode (src/engine/sdc.asm)
    at sector 630 + the image's. The file is a hard disk image to the SDC (above 2,880 sectors): Disk BASIC sees its first 630 sectors only."""
    import decbfs
    d = decbfs.Disk()
    d.add("POOLSDC", "DAT", b"POOL OF RADIANCE: CoCo SDC image, the game's sectors follow the disk.\n", 1, 0)
    d.add("POOL", "BIN", with_storage(Path(gamedir, "POOL.BIN").read_bytes(), "STORAGE: COCO SDC", "ONE IMAGE FILE ON THE CARD"), 2, 0)
    boot = d.image()
    assert len(boot) == 630 * 256
    Path(out).write_bytes(boot + img)


IDE_DRIVE_SECTORS = 630          # an HDB-DOS virtual drive: a 35 track disk, one 256 byte sector in the first half of each card sector


def ide_layout(img):
    """The image as the engine's IDE driver reads it (src/engine/ide.c): the header says where the saves are (always the end of the image); the sectors before
    are kept two to a 512 byte card sector, the saves one to a card sector (the other half zero). The first saves sector must be even: a sector of zeros goes in front
    of the saves when it is not (the saves are last, so nothing else moves), and the header's byte 24 says 3 (the IDE medium; a floppy set's is 1).
    Returns (the image as it will be, the card sectors from the image's sector 0)."""
    img = bytearray(img)
    save_lsn, nsave = struct.unpack(">LH", bytes(img[16:22]))
    assert len(img) % 256 == 0 and save_lsn + nsave == len(img) // 256, "mkimage --ide: the saves are not the last sectors of the image"
    assert nsave % 2 == 0, "mkimage --ide: the saves area has an odd number of sectors"
    if save_lsn % 2:
        img[save_lsn * 256:save_lsn * 256] = bytes(256)
        save_lsn += 1
        img[16:20] = struct.pack(">L", save_lsn)
    img[24] = 3
    secs = len(img) // 256
    card = bytearray()
    for i in range(0, save_lsn, 2):
        card += img[i * 256:(i + 2) * 256]
    for i in range(save_lsn, secs):
        card += img[i * 256:(i + 1) * 256] + bytes(256)
    return bytes(img), bytes(card)


def write_ide(img, pool_bin, out, boot_out):
    """The card's file for the SuperIDE build (docs/PHASE-8.12.md): `out` is a run of 512 byte card sectors that go onto the CompactFlash card at the first sector
    of a run of unused HDB-DOS virtual drives (630 card sectors each, from the HDB-DOS offset of the card): first one drive that is a 35 track disk with POOL.BIN
    (HDB-DOS keeps a 256 byte disk sector in the first half of a card sector, so it is `LOADM"POOL:n":EXEC` from drive n), then the image, the whole drives filled up
    with zeros. `boot_out` is the same disk as a plain 630 sector disk file for anything that is not HDB-DOS (an emulator, an SDC, DriveWire)."""
    import decbfs
    d = decbfs.Disk()
    d.add("POOL", "BIN", Path(pool_bin).read_bytes(), 2, 0)
    boot = d.image()
    assert len(boot) == IDE_DRIVE_SECTORS * 256
    img, card = ide_layout(img)
    Path(boot_out).write_bytes(boot)
    disk = b"".join(boot[i * 256:(i + 1) * 256] + bytes(256) for i in range(IDE_DRIVE_SECTORS))
    body = disk + card
    n = len(body) // 512
    drives = (n + IDE_DRIVE_SECTORS - 1) // IDE_DRIVE_SECTORS
    body += bytes(drives * IDE_DRIVE_SECTORS * 512 - len(body))
    Path(out).write_bytes(body)
    return img, drives


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir")
    ap.add_argument("gamedir")
    ap.add_argument("dgroup")
    ap.add_argument("out")
    ap.add_argument("--nodedupe", action="store_true", help="every entry has its own copy (the traces of tools/mklayout.py need entries that the sector tells apart)")
    ap.add_argument("--layout", help="a layout (tools/mklayout.py): the floppy medium")
    ap.add_argument("--floppies", help="with --layout: write the disks (POOLnn.DSK) into this directory")
    ap.add_argument("--sdc", help="also write the CoCo SDC's single file (a disk with POOL.BIN, then this image; without --layout)")
    ap.add_argument("--ide", help="also write the SuperIDE build's card file (the boot drive of HDB-DOS, then the image: see write_ide; needs --pool-bin and --ide-boot)")
    ap.add_argument("--pool-bin", help="with --ide: the POOL.BIN of the IDE build (make ide)")
    ap.add_argument("--ide-boot", help="with --ide: also write the boot disk alone, as a plain 35 track disk file")
    ap.add_argument("--interleave", type=int, default=1, help="with --floppies: the sector interleave of the data files on the disks (1, 5 or 7: coprime with 18); the engine reads it from the header")
    ap.add_argument("--model", help="write the entries (file, id, sizes, content key, place) as JSON")
    a = ap.parse_args(argv)
    layout = json.loads(Path(a.layout).read_text()) if a.layout else None
    img, info = build(a.data_dir, a.gamedir, a.dgroup, not a.nodedupe, layout)
    if layout is not None and a.interleave != 1:
        img = img[:55] + bytes([a.interleave]) + img[56:]          # the header's byte 31 of the floppy part (flop_setup)
    Path(a.out).write_bytes(img)
    if a.model:
        Path(a.model).write_text(json.dumps(dict(
            files=info["files"], data_off=info["data_off"], save_sectors=SAVE_SECTORS, pool_bin_sectors=pool_bin_sectors(a.gamedir),
            entries=[dict(file=info["files"][e[0]], id=e[1], size=e[2], raw=e[3], kind=e[4], key=k, off=o)
                     for e, k, o in zip(info["ents"], info["keys"], info["placed"])]), indent=0))
    if a.sdc:
        write_sdc(img, a.gamedir, a.sdc)
        print("mkimage: the SDC file %s: %d sectors" % (a.sdc, 630 + len(img) // 256))
    if a.ide:
        _, drives = write_ide(img, a.pool_bin, a.ide, a.ide_boot or a.ide + ".boot.dsk")
        print("mkimage: the IDE card file %s: %d card sectors, %d virtual drives of %d" % (a.ide, drives * IDE_DRIVE_SECTORS, drives, IDE_DRIVE_SECTORS))
    if a.floppies:
        names = write_floppies(img, info, a.gamedir, a.floppies, a.interleave)
        print("mkimage: %d disks in %s: %s" % (len(names), a.floppies, " ".join(names)))
    print("mkimage: %d files, %d entries, %d sectors (%d KB), saves at sector %d; identical blocks stored once: %d bytes saved" %
          (len(info["files"]), len(info["ents"]), len(img) // 256, len(img) // 1024, info["save_lsn"], info["saved"]))


if __name__ == "__main__":
    main(sys.argv[1:])

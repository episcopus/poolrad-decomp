#!/usr/bin/env python3
"""pic.py: decode Pool of Radiance pictures from .DAX blocks (whitepaper 4.2.3).

  python3 tools/re/pic.py verify poolrad/                 # every picture-like block
  python3 tools/re/pic.py list poolrad/PIC1.DAX           # block ids, dims, frames
  python3 tools/re/pic.py dump poolrad/TITLE.DAX 1 out.png
  python3 tools/re/pic.py dump poolrad/PIC1.DAX 1 out/    # directory: one PNG per frame
  python3 tools/re/pic.py dump --cga poolrad/TITLE.DAX 1 out.png   # through the CGA colour map

A dump paints each 4-bit pixel through the EGA default 16-colour palette, as the game's EGA
and Tandy paths draw it (the raw nibble; the game sets no palette register from the picture).
--cga paints it as the CGA path does: the nibble goes through the record's 16-to-4 colour map
and the result through the BIOS mode 4 default colours (black, cyan, magenta, light grey; the
game never selects a CGA palette, so these are the default [I]).

On-disk picture record (coab Classes/DaxFiles/DaxBlock.cs; Load24x24Set reads
height/width/item_count/bpp the same way at ovl32:008C):

  u16 height
  u16 width_cols          ; pixel width = width_cols * 8
  u16 x_pos
  u16 y_pos
  u8  item_count          ; frames or tiles in this record
  u8  palette[8]          ; 16-to-4 CGA colour map as packed nibbles (read only on CGA)
  u8  pixels[item_count * height * width_cols * 4]   ; two 4-bit pixels per byte

PIC/SPRIT/FINAL animations wrap several records:

  u8  num_frames
  repeat num_frames:
    u32 delay             ; tenths of a second (coab)
    <picture record with item_count usually 1>
  For PIC/FINAL, frames after the first are XOR'd against frame 0's pixel bytes.

8X8D1.DAX block 201 is a 1-bit font: 177 glyphs of 8 bytes each (coab seg041).
"""
from __future__ import annotations

import glob
import os
import sys
from pathlib import Path

import dax

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None

# IBM EGA default 16-colour palette.
EGA = [
    (0x00, 0x00, 0x00), (0x00, 0x00, 0xAA), (0x00, 0xAA, 0x00), (0x00, 0xAA, 0xAA),
    (0xAA, 0x00, 0x00), (0xAA, 0x00, 0xAA), (0xAA, 0x55, 0x00), (0xAA, 0xAA, 0xAA),
    (0x55, 0x55, 0x55), (0x55, 0x55, 0xFF), (0x55, 0xFF, 0x55), (0x55, 0xFF, 0xFF),
    (0xFF, 0x55, 0x55), (0xFF, 0x55, 0xFF), (0xFF, 0xFF, 0x55), (0xFF, 0xFF, 0xFF),
]

HDR = 17
FONT_BLOCK_ID = 201
FONT_GLYPHS = 177
FONT_BYTES = FONT_GLYPHS * 8

# Globs that hold picture records (or the one font exception).
PIC_GLOBS = (
    "TITLE.DAX", "FINAL5.DAX",
    "PIC*.DAX", "CPIC*.DAX", "SPRIT*.DAX",
    "HEAD*.DAX", "BODY*.DAX", "CHEAD.DAX", "CBODY.DAX",
    "COMSPR.DAX", "ICON.DAX", "8X8D*.DAX",
)


# CGA mode 4 BIOS default: palette 1, low intensity, black background [I].
CGA = [(0x00, 0x00, 0x00), (0x00, 0xAA, 0xAA), (0xAA, 0x00, 0xAA), (0xAA, 0xAA, 0xAA)]


def _palette_map(pal8: bytes) -> list[int]:
    """8 bytes -> the 16-entry CGA colour map (values 0..3, high nibble first per byte).

    Only the game's CGA path reads it (UnpackPicturePixels, src/RES07.PAS:217..242); in every
    shipped record every entry is 0..3 (whitepaper 4.2.3)."""
    out = []
    for b in pal8:
        out.append((b >> 4) & 0xF)
        out.append(b & 0xF)
    return out


def _ega_rgb(index: int) -> tuple[int, int, int]:
    return EGA[index & 0xF]


def _cga_rgb(index: int, pmap: list[int]) -> tuple[int, int, int]:
    return CGA[pmap[index & 0xF] & 3]


def picture_bytes(height: int, width_cols: int, items: int) -> int:
    return items * height * width_cols * 4


def parse_picture(raw: bytes, off: int = 0) -> tuple[dict, int]:
    """Parse one picture record at off; return (meta, total_size)."""
    if off + HDR > len(raw):
        raise ValueError("picture header truncated at %d" % off)
    height = int.from_bytes(raw[off:off + 2], "little")
    width_cols = int.from_bytes(raw[off + 2:off + 4], "little")
    x_pos = int.from_bytes(raw[off + 4:off + 6], "little")
    y_pos = int.from_bytes(raw[off + 6:off + 8], "little")
    items = raw[off + 8]
    pal = raw[off + 9:off + 17]
    if not (1 <= height <= 400 and 1 <= width_cols <= 80 and 1 <= items <= 200):
        raise ValueError("bad picture dims h=%d w=%d items=%d" % (height, width_cols, items))
    pix = picture_bytes(height, width_cols, items)
    total = HDR + pix
    if off + total > len(raw):
        raise ValueError("picture pixels truncated (need %d at %d, have %d)" % (total, off, len(raw) - off))
    meta = {
        "height": height,
        "width_cols": width_cols,
        "width_px": width_cols * 8,
        "x_pos": x_pos,
        "y_pos": y_pos,
        "items": items,
        "palette": list(pal),
        "pixels": raw[off + HDR:off + total],
    }
    return meta, total


def parse_animation(raw: bytes) -> list[dict]:
    """PIC/SPRIT-style: u8 count, then count * (u32 delay + picture)."""
    if not raw:
        raise ValueError("empty animation")
    n = raw[0]
    if n == 0 or n > 32:
        raise ValueError("bad frame count %d" % n)
    off = 1
    frames = []
    for i in range(n):
        if off + 4 > len(raw):
            raise ValueError("delay truncated at frame %d" % i)
        delay = int.from_bytes(raw[off:off + 4], "little")
        off += 4
        meta, total = parse_picture(raw, off)
        meta["delay"] = delay
        frames.append(meta)
        off += total
    if off != len(raw):
        raise ValueError("animation tail %d of %d" % (off, len(raw)))
    return frames


def xor_pic_frames(frames: list[dict]) -> None:
    """In-place: apply PIC/FINAL delta (frame N ^= frame 0) on pixel bytes."""
    if len(frames) < 2:
        return
    base = frames[0]["pixels"]
    for fr in frames[1:]:
        pix = bytearray(fr["pixels"])
        if len(pix) != len(base):
            raise ValueError("PIC frame size mismatch %d vs %d" % (len(pix), len(base)))
        for i, b in enumerate(base):
            pix[i] ^= b
        fr["pixels"] = bytes(pix)


def decode_pixels(meta: dict, item: int = 0) -> list[list[int]]:
    """Return height x width_px colour indices (0..15) for one item/tile."""
    h, wcols, items = meta["height"], meta["width_cols"], meta["items"]
    if not (0 <= item < items):
        raise ValueError("item %d out of range %d" % (item, items))
    stride = h * wcols * 4
    data = meta["pixels"][item * stride:(item + 1) * stride]
    wpx = wcols * 8
    rows: list[list[int]] = []
    o = 0
    for _y in range(h):
        row = []
        for _ in range(wcols * 4):
            c = data[o]; o += 1
            row.append((c >> 4) & 0xF)
            row.append(c & 0xF)
        if len(row) != wpx:
            raise ValueError("row width")
        rows.append(row)
    return rows


def to_image(meta: dict, item: int = 0, cga: bool = False):
    """The picture as an RGB image: EGA colours of the raw nibbles, or with cga=True the CGA
    colours through the record's colour map."""
    if Image is None:
        raise RuntimeError("Pillow required for PNG output")
    pmap = _palette_map(bytes(meta["palette"]))
    rows = decode_pixels(meta, item)
    img = Image.new("RGB", (meta["width_px"], meta["height"]))
    px = img.load()
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            px[x, y] = _cga_rgb(c, pmap) if cga else _ega_rgb(c)
    return img


def parse_font(raw: bytes) -> dict:
    if len(raw) != FONT_BYTES:
        raise ValueError("font block is %d bytes, expected %d" % (len(raw), FONT_BYTES))
    return {"kind": "font", "glyphs": FONT_GLYPHS, "glyph_bytes": 8, "data": raw}


def font_to_image(font: dict, cols: int = 16):
    if Image is None:
        raise RuntimeError("Pillow required for PNG output")
    glyphs = font["glyphs"]
    rows_n = (glyphs + cols - 1) // cols
    img = Image.new("RGB", (cols * 8, rows_n * 8), (0, 0, 0))
    px = img.load()
    data = font["data"]
    for g in range(glyphs):
        gx, gy = (g % cols) * 8, (g // cols) * 8
        for row in range(8):
            bits = data[g * 8 + row]
            for col in range(8):
                on = (bits >> (7 - col)) & 1
                px[gx + col, gy + row] = (255, 255, 255) if on else (0, 0, 0)
    return img


def decode_block(raw: bytes, name: str = "", block_id: int | None = None) -> dict:
    """Auto-detect picture, animation, or font. Returns a dict with kind and frames/meta."""
    base = os.path.basename(name).upper()
    if block_id == FONT_BLOCK_ID and base.startswith("8X8D"):
        return {"kind": "font", "font": parse_font(raw)}

    # Prefer a single picture when the whole buffer is one record.
    try:
        meta, total = parse_picture(raw, 0)
        if total == len(raw):
            return {"kind": "picture", "frames": [meta]}
    except ValueError:
        pass

    # Animation (PIC, SPRIT, some FINAL).
    try:
        frames = parse_animation(raw)
        if base.startswith("PIC") or base.startswith("FINAL"):
            # Work on copies so verify can re-run; XOR only for decode paths that ask.
            pass
        return {"kind": "animation", "frames": frames, "xor_delta": base.startswith("PIC") or base.startswith("FINAL")}
    except ValueError:
        pass

    raise ValueError("unrecognised picture block (%d bytes)" % len(raw))


def frames_for_png(decoded: dict) -> list[dict]:
    if decoded["kind"] == "font":
        return []
    frames = [dict(f) for f in decoded["frames"]]
    if decoded.get("xor_delta"):
        # deep-ish copy pixels
        for f in frames:
            f["pixels"] = bytes(f["pixels"])
        xor_pic_frames(frames)
    return frames


def iter_pic_files(root: str) -> list[str]:
    seen = set()
    out = []
    for pat in PIC_GLOBS:
        for path in sorted(glob.glob(os.path.join(root, pat))):
            if path not in seen:
                seen.add(path)
                out.append(path)
    return out


def verify_tree(root: str) -> int:
    files = iter_pic_files(root)
    n = bad = 0
    for path in files:
        for b in dax.read_dax(path):
            n += 1
            try:
                decode_block(dax.unrle(b["data"]), path, b["id"])
            except ValueError as e:
                bad += 1
                print("%s block %d: %s" % (path, b["id"], e))
    print("pic: %d files, %d blocks, %s" % (len(files), n, "OK" if not bad else "%d problems" % bad))
    return 0 if files and not bad else 1


def main(argv: list[str]) -> int:
    cga = "--cga" in argv
    argv = [a for a in argv if a != "--cga"]
    if len(argv) < 3 or argv[1] not in ("verify", "list", "dump"):
        print(__doc__)
        return 2
    cmd, target = argv[1], argv[2]
    if cmd == "verify":
        return verify_tree(target)

    blocks = dax.read_dax(target)
    if cmd == "list":
        for b in blocks:
            raw = dax.unrle(b["data"])
            try:
                dec = decode_block(raw, target, b["id"])
            except ValueError as e:
                print("block %3d  ERROR %s" % (b["id"], e))
                continue
            if dec["kind"] == "font":
                print("block %3d  font %d glyphs" % (b["id"], dec["font"]["glyphs"]))
            else:
                fr = dec["frames"]
                f0 = fr[0]
                print("block %3d  %s  %dx%d  frames=%d items0=%d" % (
                    b["id"], dec["kind"], f0["width_px"], f0["height"], len(fr), f0["items"]))
        return 0

    if len(argv) < 5:
        print("dump: need block id and output path"); return 2
    bid, out = int(argv[3]), argv[4]
    for b in blocks:
        if b["id"] != bid:
            continue
        dec = decode_block(dax.unrle(b["data"]), target, bid)
        if dec["kind"] == "font":
            font_to_image(dec["font"]).save(out)
            print("wrote %s" % out)
            return 0
        frames = frames_for_png(dec)
        # Flatten items across frames into PNG(s).
        images = []
        for fi, fr in enumerate(frames):
            for it in range(fr["items"]):
                images.append((fi, it, to_image(fr, it, cga)))
        if len(images) == 1:
            images[0][2].save(out)
            print("wrote %s" % out)
            return 0
        os.makedirs(out, exist_ok=True)
        for fi, it, img in images:
            path = os.path.join(out, "f%02d_i%03d.png" % (fi, it))
            img.save(path)
        print("wrote %d PNGs under %s" % (len(images), out))
        return 0
    print("block %d not in %s" % (bid, target))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

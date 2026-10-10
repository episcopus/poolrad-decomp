"""ega.py: IBM EGA model for the oracle (SPEC 8.2): four 64 KB planes, latches, the sequencer, graphics
controller, CRTC and attribute controller registers, write modes 0 to 3, read modes 0 and 1, the 64
colour EGA palette, and PNG screenshots of the display (graphics modes 0Dh, 0Eh, 0Fh, 10h; text modes).

Not modelled (and not needed by the game as far as the trace shows; raise or ignore loudly if that
changes): CGA/Tandy packed modes (config letters C and T of POOL.CFG), VGA DAC, split screen, panning.
"""
from __future__ import annotations

import hashlib
import struct
import zlib
from pathlib import Path

# default EGA attribute palette registers (BIOS programs these for modes 0Dh/0Eh/10h)
DEFAULT_ATTR = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07,
                0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]


def ega_rgb(v: int) -> tuple[int, int, int]:
    """6-bit EGA colour value (--rgbRGB, bit0=B bit1=G bit2=R secondary bits 3..5) to 8-bit RGB."""
    r = (((v >> 2) & 1) << 1 | ((v >> 5) & 1)) * 85
    g = (((v >> 1) & 1) << 1 | ((v >> 4) & 1)) * 85
    b = ((v & 1) << 1 | ((v >> 3) & 1)) * 85
    return r, g, b


def write_png(path, width: int, height: int, rgb: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


GRAPHICS_MODES = {  # mode: (width, height, bytes_per_line, page_bytes)
    0x0D: (320, 200, 40, 0x2000),
    0x0E: (640, 200, 80, 0x4000),
    0x0F: (640, 350, 80, 0x8000),
    0x10: (640, 350, 80, 0x8000),
}


class EGA:
    def __init__(self, machine):
        self.m = machine
        self.planes = [bytearray(0x10000) for _ in range(4)]
        self.latch = [0, 0, 0, 0]
        self.text_mem = bytearray(0x20000)     # B0000..BFFFF as seen by the CPU in text modes
        self.mode = 0x03
        self.seq = [0] * 5
        self.seq[2] = 0x0F
        self.crtc = [0] * 25
        self.gc = [0] * 9
        self.gc[8] = 0xFF
        self.attr = list(DEFAULT_ATTR) + [0x08, 0, 0x0F, 0, 0]   # 0..15 palette, 16 mode, 17 overscan, 18 plane enable
        self.attr_ff = False                   # 3C0 flip-flop: False = next write is an index
        self.attr_idx = 0
        self.seq_idx = self.gc_idx = self.crtc_idx = 0
        self.misc = 0x23
        self.status_reads = 0
        self.writes = 0                        # statistics for tests / sanity
        self.cursor = [(0, 0)] * 8
        self.cursor_shape = 0x0607
        self.page = 0
        self.dirty = False

    # ------------------------------------------------------------------ CPU aperture (MMIO)
    def _graphics(self) -> bool:
        return self.mode in GRAPHICS_MODES

    def mmio_read(self, uc, offset: int, size: int, _ud) -> int:
        v = 0
        for i in range(size):
            v |= self._read_byte(offset + i) << (8 * i)
        return v

    def mmio_write(self, uc, offset: int, size: int, value: int, _ud) -> None:
        for i in range(size):
            self._write_byte(offset + i, (value >> (8 * i)) & 0xFF)

    def _read_byte(self, off: int) -> int:
        if off >= 0x10000:
            return self.text_mem[off - 0x10000]
        pl, lat = self.planes, self.latch
        a = off
        lat[0], lat[1], lat[2], lat[3] = pl[0][a], pl[1][a], pl[2][a], pl[3][a]
        if self.gc[5] & 0x08:                                  # read mode 1: colour compare
            cmp_, care = self.gc[2] & 0x0F, self.gc[7] & 0x0F
            res = 0xFF
            for p in range(4):
                if care & (1 << p):
                    res &= lat[p] if (cmp_ >> p) & 1 else (~lat[p] & 0xFF)
            return res
        return lat[self.gc[4] & 3]

    def _write_byte(self, off: int, v: int) -> None:
        if off >= 0x10000:
            self.text_mem[off - 0x10000] = v
            self.dirty = True
            return
        self.writes += 1
        gc, lat, pl = self.gc, self.latch, self.planes
        mode = gc[5] & 3
        mask = self.seq[2] & 0x0F
        bm = gc[8]
        func = (gc[3] >> 3) & 3
        rot = gc[3] & 7
        if mode == 1:
            for p in range(4):
                if mask & (1 << p):
                    pl[p][off] = lat[p]
            return
        for p in range(4):
            if not mask & (1 << p):
                continue
            if mode == 0:
                d = ((v >> rot) | (v << (8 - rot))) & 0xFF if rot else v
                if gc[1] & (1 << p):
                    d = 0xFF if gc[0] & (1 << p) else 0x00
            elif mode == 2:
                d = 0xFF if (v >> p) & 1 else 0x00
            else:                                              # mode 3 (VGA): set/reset colour, mask = data AND bit mask
                rd = ((v >> rot) | (v << (8 - rot))) & 0xFF if rot else v
                d = 0xFF if gc[0] & (1 << p) else 0x00
                bmm = bm & rd
                alu = d if func == 0 else (d & lat[p] if func == 1 else (d | lat[p] if func == 2 else d ^ lat[p]))
                pl[p][off] = (alu & bmm) | (lat[p] & ~bmm & 0xFF)
                continue
            if func == 1:
                d &= lat[p]
            elif func == 2:
                d |= lat[p]
            elif func == 3:
                d ^= lat[p]
            pl[p][off] = (d & bm) | (lat[p] & ~bm & 0xFF)
        self.dirty = True

    # ------------------------------------------------------------------ ports
    def port_read(self, port: int, size: int) -> int:
        if port in (0x3DA, 0x3BA):
            self.attr_ff = False
            self.status_reads += 1
            # deterministic retrace: the frame is 1/60 s of virtual time; the last ~10% is vertical
            # retrace. Each poll charges 40 virtual instructions so polling loops terminate quickly.
            m = self.m
            m.extra += 40
            frame = max(1000, m.insn_per_sec // 60)
            ph = m.now() % frame
            vret = ph >= frame - frame // 10
            hret = (ph // 30) & 1
            return (0x08 if vret else 0) | (0x01 if (vret or hret) else 0)
        if port == 0x3C0:
            return self.attr_idx
        if port == 0x3C1:
            return self.attr[self.attr_idx % len(self.attr)] if self.attr_idx < 21 else 0
        if port == 0x3C2:
            return 0x70                                       # EGA switch sense
        if port == 0x3C4:
            return self.seq_idx
        if port == 0x3C5:
            return self.seq[self.seq_idx] if self.seq_idx < 5 else 0
        if port == 0x3CC:
            return self.misc
        if port == 0x3CE:
            return self.gc_idx
        if port == 0x3CF:
            return self.gc[self.gc_idx] if self.gc_idx < 9 else 0
        if port in (0x3D4, 0x3B4):
            return self.crtc_idx
        if port in (0x3D5, 0x3B5):
            return self.crtc[self.crtc_idx] if self.crtc_idx < 25 else 0
        return 0xFF if size == 1 else 0xFFFF

    def port_write(self, port: int, size: int, val: int) -> None:
        if size == 2:                                          # OUT DX,AX writes index then data
            self.port_write(port, 1, val & 0xFF)
            self.port_write(port + 1, 1, (val >> 8) & 0xFF)
            return
        if port == 0x3C0:
            if not self.attr_ff:
                self.attr_idx = val & 0x1F
            else:
                i = self.attr_idx & 0x1F
                if i < 21:
                    self.attr[i] = val & 0xFF
            self.attr_ff = not self.attr_ff
        elif port == 0x3C2:
            self.misc = val & 0xFF
        elif port == 0x3C4:
            self.seq_idx = val & 0x07
        elif port == 0x3C5:
            if self.seq_idx < 5:
                self.seq[self.seq_idx] = val & 0xFF
        elif port == 0x3CE:
            self.gc_idx = val & 0x0F
        elif port == 0x3CF:
            if self.gc_idx < 9:
                self.gc[self.gc_idx] = val & 0xFF
        elif port in (0x3D4, 0x3B4):
            self.crtc_idx = val & 0x1F
        elif port in (0x3D5, 0x3B5):
            if self.crtc_idx < 25:
                self.crtc[self.crtc_idx] = val & 0xFF
                if self.crtc_idx in (0x0C, 0x0D):
                    self.dirty = True
        elif port in (0x3C6, 0x3C7, 0x3C8, 0x3C9, 0x3BA, 0x3DA, 0x3CA, 0x3C3, 0x3D8, 0x3D9, 0x3B8):
            pass                                               # VGA DAC / CGA ports: accepted, not modelled
        else:
            self.m._unhandled_port("out", port, size, val)

    # ------------------------------------------------------------------ BIOS mode setting
    def set_mode(self, mode: int, clear: bool = True) -> None:
        mode &= 0x7F
        self.mode = mode
        if clear:
            for p in self.planes:
                p[:] = bytes(0x10000)
            self.text_mem[:] = b"\x00" * len(self.text_mem)
            if mode in (0, 1, 2, 3):
                for i in range(0x8000 // 2):
                    self.text_mem[0x8000 + 2 * i] = 0x20
                    self.text_mem[0x8000 + 2 * i + 1] = 0x07
        self.seq = [0x03, 0x01, 0x0F, 0x00, 0x06 if mode in GRAPHICS_MODES else 0x03]
        self.gc = [0, 0, 0, 0, 0, 0x00, 0x05 if mode in GRAPHICS_MODES else 0x0D, 0x0F, 0xFF]
        self.crtc = [0] * 25
        self.attr = list(DEFAULT_ATTR) + [0x01 if mode in GRAPHICS_MODES else 0x08, 0, 0x0F, 0, 0]
        self.attr_ff = False
        self.cursor = [(0, 0)] * 8
        self.page = 0
        m = self.m
        info = GRAPHICS_MODES.get(mode)
        cols = {0: 40, 1: 40, 2: 80, 3: 80, 7: 80, 0x0D: 40}.get(mode, 80)
        rows = 25 if mode not in (0x0F, 0x10) else 25
        m.bios.bda_write(0x49, bytes([mode]))
        m.bios.bda_write(0x4A, struct.pack("<H", cols))
        m.bios.bda_write(0x4C, struct.pack("<H", info[3] if info else 0x1000))
        m.bios.bda_write(0x4E, struct.pack("<H", 0))
        m.bios.bda_write(0x63, struct.pack("<H", 0x3D4))
        m.bios.bda_write(0x84, bytes([rows - 1]))
        m.bios.bda_write(0x85, struct.pack("<H", 8 if mode in (0x0D, 0x0E) else 14))
        self.dirty = True

    # ------------------------------------------------------------------ screenshots
    def palette_rgb(self) -> list[tuple[int, int, int]]:
        return [ega_rgb(self.attr[i] & 0x3F) for i in range(16)]

    def display_start(self) -> int:
        return (self.crtc[0x0C] << 8) | self.crtc[0x0D]

    def render(self) -> tuple[int, int, bytes]:
        if self.mode in GRAPHICS_MODES:
            w, h, bpl, _page = GRAPHICS_MODES[self.mode]
            pal = self.palette_rgb()
            start = self.display_start()
            out = bytearray(w * h * 3)
            p0, p1, p2, p3 = self.planes
            o = 0
            for y in range(h):
                base = (start + y * bpl) & 0xFFFF
                for xb in range(bpl):
                    a = (base + xb) & 0xFFFF
                    b0, b1, b2, b3 = p0[a], p1[a], p2[a], p3[a]
                    for bit in range(7, -1, -1):
                        c = ((b0 >> bit) & 1) | (((b1 >> bit) & 1) << 1) | (((b2 >> bit) & 1) << 2) | (((b3 >> bit) & 1) << 3)
                        r, g, b = pal[c]
                        out[o] = r
                        out[o + 1] = g
                        out[o + 2] = b
                        o += 3
            return w, h, bytes(out)
        return self._render_text()

    def _render_text(self) -> tuple[int, int, bytes]:
        cols = 40 if self.mode in (0, 1) else 80
        rows = 25
        cw, ch = 8, 16
        w, h = cols * cw, rows * ch
        out = bytearray(w * h * 3)
        font = _text_font()
        base = 0x8000 + self.m.bios.bda_word(0x4E)
        for r in range(rows):
            for c in range(cols):
                a = base + (r * cols + c) * 2
                code, att = self.text_mem[a % len(self.text_mem)], self.text_mem[(a + 1) % len(self.text_mem)]
                fg, bg = ega_rgb(DEFAULT_ATTR[att & 0x0F]), ega_rgb(DEFAULT_ATTR[(att >> 4) & 0x07])
                glyph = font[code]
                for gy in range(ch):
                    bits = glyph[gy]
                    for gx in range(cw):
                        rgb = fg if (bits >> (7 - gx)) & 1 else bg
                        o = ((r * ch + gy) * w + c * cw + gx) * 3
                        out[o:o + 3] = bytes(rgb)
        return w, h, bytes(out)

    def screenshot(self, path) -> tuple[int, int]:
        w, h, rgb = self.render()
        write_png(path, w, h, rgb)
        return w, h

    def digest_bytes(self) -> bytes:
        h = hashlib.sha256()
        for p in self.planes:
            h.update(p)
        h.update(bytes(self.text_mem))
        h.update(bytes(self.seq + self.gc + self.crtc + self.attr))
        h.update(struct.pack("<H", self.mode))
        return h.digest()

    def planes_digest(self) -> str:
        h = hashlib.sha256()
        for p in self.planes:
            h.update(p)
        return h.hexdigest()


_FONT = None


def _text_font():
    """A placeholder 8x16 text font for debugging screenshots of text modes (the real BIOS font ROM is
    not part of the pinned inputs). Built from Pillow's bitmap font when available."""
    global _FONT
    if _FONT is not None:
        return _FONT
    font = [[0] * 16 for _ in range(256)]
    try:
        from PIL import Image, ImageDraw, ImageFont
        f = ImageFont.load_default()
        for code in range(32, 127):
            im = Image.new("1", (8, 16), 0)
            ImageDraw.Draw(im).text((0, 2), chr(code), font=f, fill=1)
            px = im.load()
            for y in range(16):
                font[code][y] = sum(1 << (7 - x) for x in range(8) if px[x, y])
    except Exception:
        pass
    _FONT = font
    return font

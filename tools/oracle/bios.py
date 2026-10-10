"""bios.py: the BIOS services the game actually calls (SPEC 8.2): INT 10h video, 11h equipment,
12h memory size, 15h system, 16h keyboard, 1Ah time. Anything else raises `Unimplemented` with the
call site, so a gap is found the first time the program reaches it (playbook 25, step 2)."""
from __future__ import annotations

import struct

from .machine import FLAG_ZF, Stop

BDA = 0x400
IDLE_STOP_POLLS = 50          # empty polls with a quiet screen before an exhausted script ends the run


class Bios:
    def __init__(self, machine):
        self.m = machine
        self.cursor = [[0, 0] for _ in range(8)]    # (row, col) per page
        self.blocked_reads = 0
        self.key_reads = 0
        self.peeks = 0
        self.last_key_time = 0
        self.empty_polls = 0               # consecutive empty peeks with no video writes in between
        self._vram_seen = 0
        self.blocked_now = False           # a blocking read is waiting for the script

    # ------------------------------------------------------------------ idle detection (keys.py)
    def note_poll(self, m, got_key: bool) -> None:
        w = m.ega.writes
        if got_key or w != self._vram_seen:
            self.empty_polls = 0
        else:
            self.empty_polls += 1
        self._vram_seen = w

    def note_key_released(self) -> None:
        self.empty_polls = 0
        self.blocked_now = False

    def idle(self, polls: int) -> bool:
        return self.blocked_now or self.empty_polls >= polls

    # ------------------------------------------------------------------ BDA
    def bda_write(self, off: int, data: bytes) -> None:
        self.m.uc.mem_write(BDA + off, data)

    def bda_word(self, off: int) -> int:
        return struct.unpack("<H", self.m.uc.mem_read(BDA + off, 2))[0]

    def bda_byte(self, off: int) -> int:
        return self.m.uc.mem_read(BDA + off, 1)[0]

    def install(self) -> None:
        m = self.m
        w = lambda off, v: self.bda_write(off, struct.pack("<H", v))
        w(0x10, 0x0061)            # equipment: floppy, 80x25 colour (EGA reports 00 in bits 5-4 -> set per mode)
        w(0x13, 640)               # KB of conventional memory
        w(0x1A, 0x1E)              # keyboard buffer head/tail
        w(0x1C, 0x1E)
        w(0x80, 0x1E)
        w(0x82, 0x3E)
        w(0x49, 0x03)
        w(0x4A, 80)
        w(0x63, 0x3D4)
        self.bda_write(0x84, bytes([24]))
        self.bda_write(0x85, struct.pack("<H", 14))
        self.bda_write(0x87, bytes([0x60]))   # EGA active, 256 KB, no clear-memory flag
        self.bda_write(0x88, bytes([0x09]))   # switch settings: EGA colour display
        self.bda_write(0x89, bytes([0x00]))
        for n, fn in ((0x10, self.int10), (0x11, self.int11), (0x12, self.int12), (0x15, self.int15),
                      (0x16, self.int16), (0x1A, self.int1a), (0x13, self.int13), (0x17, self.int17),
                      (0x14, self.int14)):
            m.register_service(n, fn)

    # ------------------------------------------------------------------ INT 11h / 12h / 13h / 14h / 17h
    def int11(self, m):
        m.set("ax", self.bda_word(0x10))

    def int12(self, m):
        m.set("ax", self.bda_word(0x13))

    def int13(self, m):
        ah = m.get("ax") >> 8
        if ah == 0x00:                              # reset: success
            m.set("ax", 0)
            m.ok()
        else:
            m.unimplemented("INT 13h AH=%02X (disk services are not modelled)" % ah)

    def int14(self, m):
        m.unimplemented("INT 14h serial services")

    def int17(self, m):
        m.unimplemented("INT 17h printer services")

    # ------------------------------------------------------------------ INT 10h
    def int10(self, m):
        ax = m.get("ax")
        ah, al = ax >> 8, ax & 0xFF
        ega = m.ega
        if ah == 0x00:
            ega.set_mode(al & 0x7F, clear=not (al & 0x80))
            for c in self.cursor:
                c[0] = c[1] = 0
            m.events.append(("setmode", al & 0x7F))
        elif ah == 0x01:
            ega.cursor_shape = m.get("cx")
            self.bda_write(0x60, struct.pack("<H", m.get("cx")))
        elif ah == 0x02:
            page = (m.get("bx") >> 8) & 7
            self.cursor[page] = [m.get("dx") >> 8, m.get("dx") & 0xFF]
            self.bda_write(0x50 + page * 2, bytes([m.get("dx") & 0xFF, m.get("dx") >> 8]))
        elif ah == 0x03:
            page = (m.get("bx") >> 8) & 7
            r, c = self.cursor[page]
            m.set("dx", (r << 8) | c)
            m.set("cx", ega.cursor_shape)
            m.set("ax", 0)
        elif ah == 0x05:
            ega.page = al & 7
            self.bda_write(0x62, bytes([al & 7]))
        elif ah in (0x06, 0x07):
            self._scroll(m, up=(ah == 0x06))
        elif ah == 0x08:
            r, c = self.cursor[(m.get("bx") >> 8) & 7]
            ch, at = self._text_get(r, c)
            m.set("ax", (at << 8) | ch)
        elif ah in (0x09, 0x0A):
            page = (m.get("bx") >> 8) & 7
            r, c = self.cursor[page]
            attr = m.get("bx") & 0xFF
            for i in range(m.get("cx")):
                self._text_put(r, c + i, al, attr if ah == 0x09 else None)
        elif ah == 0x0B:
            pass                                     # CGA palette select: ignored in EGA modes
        elif ah == 0x0C:
            m.unimplemented("INT 10h AH=0Ch write pixel (not used by the game)")
        elif ah == 0x0D:
            m.unimplemented("INT 10h AH=0Dh read pixel")
        elif ah == 0x0E:
            self.tty(al)
        elif ah == 0x0F:
            m.set("ax", (self.bda_word(0x4A) << 8) | self.bda_byte(0x49))
            m.set("bx", (ega.page << 8) | (m.get("bx") & 0xFF))
        elif ah == 0x10:
            self._palette(m, al)
        elif ah == 0x11:
            self._chargen(m, al)
        elif ah == 0x12:
            self._alt_select(m)
        elif ah == 0x13:
            self._write_string(m, al)
        elif ah == 0x1A:
            m.set("ax", 0x0000)                      # no VGA display combination code: plain EGA
        elif ah == 0x1B:
            m.unimplemented("INT 10h AH=1Bh VGA state")
        elif ah == 0xFE or ah == 0xFF:
            pass                                     # DESQview shadow buffer probes: not present
        else:
            m.unimplemented("INT 10h AH=%02Xh" % ah)

    def _palette(self, m, al):
        ega = m.ega
        bx = m.get("bx")
        if al == 0x00:
            ega.attr[(bx & 0xFF) & 0x0F] = (bx >> 8) & 0x3F
        elif al == 0x01:
            ega.attr[17] = (bx >> 8) & 0x3F
        elif al == 0x02:
            data = m.read(m.get("es"), m.get("dx"), 17)
            ega.attr[0:16] = [b & 0x3F for b in data[:16]]
            ega.attr[17] = data[16]
        elif al == 0x03:
            ega.attr[16] = (ega.attr[16] & ~0x08) | (0x08 if (bx & 0xFF) else 0)
        elif al == 0x07:
            m.set("bx", (bx & 0x00FF) | (ega.attr[bx & 0x0F] << 8))
        elif al == 0x08:
            m.set("bx", (bx & 0x00FF) | (ega.attr[17] << 8))
        elif al == 0x09:
            m.write(m.get("es"), m.get("dx"), bytes(ega.attr[:16] + [ega.attr[17]]))
        elif al in (0x10, 0x12, 0x13, 0x15, 0x17, 0x1A, 0x1B):
            pass                                     # VGA DAC calls on an EGA: no effect
        else:
            m.unimplemented("INT 10h AH=10h AL=%02Xh" % al)

    def _chargen(self, m, al):
        # AL=30h: font info. Return a fake pointer into ROM space and the character height.
        if al == 0x30:
            bh = (m.get("bx") >> 8) & 0xFF
            height = 8 if m.ega.mode in (0x0D, 0x0E) else 14
            m.set("es", 0xC000)
            m.set("bp", 0x0000)
            m.set("cx", height)
            m.set("dx", 24)
        elif al in (0x00, 0x10, 0x01, 0x11, 0x02, 0x12, 0x03, 0x04, 0x14, 0x20, 0x21, 0x22, 0x23, 0x24):
            pass                                     # font loads / rows: no effect on graphics output
        else:
            m.unimplemented("INT 10h AH=11h AL=%02Xh" % al)

    def _alt_select(self, m):
        bl = m.get("bx") & 0xFF
        if bl == 0x10:                               # EGA info: BH=0 colour, BL=3 (256 KB), CH/CL switches
            m.set("bx", 0x0003)
            m.set("cx", 0x0009)
        elif bl in (0x20, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36):
            m.set("ax", (m.get("ax") & 0xFF00) | 0x12)
        else:
            m.unimplemented("INT 10h AH=12h BL=%02Xh" % bl)

    # ------------------------------------------------------------------ text helpers
    def _cols(self) -> int:
        return self.bda_word(0x4A) or 80

    def _addr(self, r: int, c: int) -> int:
        page_size = self.bda_word(0x4C) or 0x1000
        return 0x8000 + self.m.ega.page * page_size + (r * self._cols() + c) * 2

    def _text_get(self, r, c):
        a = self._addr(r, c)
        t = self.m.ega.text_mem
        return t[a], t[a + 1]

    def _text_put(self, r, c, ch, attr):
        a = self._addr(r, c)
        t = self.m.ega.text_mem
        t[a] = ch & 0xFF
        if attr is not None:
            t[a + 1] = attr & 0xFF
        self.m.ega.dirty = True

    def tty(self, ch: int) -> None:
        page = self.m.ega.page
        r, c = self.cursor[page]
        cols = self._cols()
        if ch == 0x0D:
            c = 0
        elif ch == 0x0A:
            r += 1
        elif ch == 0x08:
            c = max(0, c - 1)
        elif ch == 0x07:
            pass
        else:
            self._text_put(r, c, ch, None)
            c += 1
            if c >= cols:
                c, r = 0, r + 1
        if r >= 25:
            self._scroll_region(1, 0x07, 0, 0, 24, cols - 1, up=True)
            r = 24
        self.cursor[page] = [r, c]
        self.bda_write(0x50 + page * 2, bytes([c, r]))

    def _scroll(self, m, up: bool):
        lines, attr = m.get("ax") & 0xFF, m.get("bx") >> 8
        top, left = m.get("cx") >> 8, m.get("cx") & 0xFF
        bot, right = m.get("dx") >> 8, m.get("dx") & 0xFF
        self._scroll_region(lines, attr, top, left, bot, right, up)

    def _scroll_region(self, lines, attr, top, left, bot, right, up):
        height = bot - top + 1
        if lines == 0 or lines >= height:
            for r in range(top, bot + 1):
                for c in range(left, right + 1):
                    self._text_put(r, c, 0x20, attr)
            return
        rows = range(top, bot + 1 - lines) if up else range(bot, top - 1 + lines, -1)
        for r in rows:
            src = r + lines if up else r - lines
            for c in range(left, right + 1):
                ch, at = self._text_get(src, c)
                self._text_put(r, c, ch, at)
        blank = range(bot + 1 - lines, bot + 1) if up else range(top, top + lines)
        for r in blank:
            for c in range(left, right + 1):
                self._text_put(r, c, 0x20, attr)

    def _write_string(self, m, al):
        r, c = m.get("dx") >> 8, m.get("dx") & 0xFF
        attr = m.get("bx") & 0xFF
        data = m.read(m.get("es"), m.get("bp"), m.get("cx"))
        step = 2 if al & 2 else 1
        for i in range(0, len(data), step):
            self._text_put(r, c, data[i], data[i + 1] if step == 2 else attr)
            c += 1
        if al & 1:
            self.cursor[m.ega.page] = [r, c]

    # ------------------------------------------------------------------ INT 15h
    def int15(self, m):
        ah = m.get("ax") >> 8
        if ah in (0x88,):
            m.set("ax", 0)                           # no extended memory
            m.ok()
        elif ah == 0xC0 or ah == 0x4F or ah == 0xC2:
            m.set("ax", (0x86 << 8) | (m.get("ax") & 0xFF))   # function not supported (PC/XT style)
            m.ret_flags(set_mask=1)
        elif ah == 0x86:                             # wait CX:DX microseconds: advance virtual time
            us = (m.get("cx") << 16) | m.get("dx")
            m.extra += us * m.insn_per_sec // 1_000_000
            m.ok()
        else:
            m.unimplemented("INT 15h AH=%02Xh" % ah)

    # ------------------------------------------------------------------ INT 16h keyboard
    def int16(self, m):
        ah = m.get("ax") >> 8
        keys = getattr(m, "keys", None)
        if ah in (0x00, 0x10):
            k = keys.take(m) if keys else None
            if k is None:
                self.blocked_reads += 1
                self.blocked_now = True
                if keys is None or keys.exhausted(m):
                    raise Stop("input-exhausted")
                # block: retry the INT after letting virtual time advance to the next timer tick
                ss, sp = m.get("ss"), m.get("sp")
                m.ww(ss, sp, (m.rw(ss, sp) - 2) & 0xFFFF)
                if not m.irq0_pending:
                    m.extra += max(0, m.next_irq0 - m.now())
                return
            self.key_reads += 1
            m.set("ax", k)
            if getattr(m, "on_key_read", None):
                m.on_key_read(m, k)
        elif ah in (0x01, 0x11):
            k = keys.peek(m) if keys else None
            self.peeks += 1
            self.note_poll(m, k is not None)
            if k is None and keys is not None and keys.exhausted(m) and self.idle(IDLE_STOP_POLLS):
                raise Stop("input-exhausted")        # script done and the game has settled
            if k is None:
                m.ret_flags(set_mask=FLAG_ZF)
            else:
                m.set("ax", k)
                m.ret_flags(clear_mask=FLAG_ZF)
        elif ah in (0x02, 0x12):
            m.set("ax", (m.get("ax") & 0xFF00))      # no shift/ctrl/alt held
        elif ah == 0x03:
            pass
        elif ah == 0x05:
            m.set("ax", m.get("ax") & 0xFF)          # key stuffing: accepted, buffer full not modelled
        else:
            m.unimplemented("INT 16h AH=%02Xh" % ah)

    def kbd_port60(self) -> int:
        return 0

    # ------------------------------------------------------------------ INT 1Ah time
    def int1a(self, m):
        ah = m.get("ax") >> 8
        if ah == 0x00:
            ticks = self._ticks(m)
            m.set("cx", (ticks >> 16) & 0xFFFF)
            m.set("dx", ticks & 0xFFFF)
            m.set("ax", m.get("ax") & 0xFF00)
        elif ah == 0x01:
            self.bda_write(0x6C, struct.pack("<HH", m.get("dx"), m.get("cx")))
        elif ah == 0x02:
            s = m.time_of_day() // 100
            hh, mm, ss = (s // 3600) % 24, (s // 60) % 60, s % 60
            bcd = lambda v: ((v // 10) << 4) | (v % 10)
            m.set("cx", (bcd(hh) << 8) | bcd(mm))
            m.set("dx", (bcd(ss) << 8))
            m.ok()
        elif ah == 0x04:
            m.set("cx", 0x1991)
            m.set("dx", 0x0611)
            m.ok()
        else:
            m.unimplemented("INT 1Ah AH=%02Xh" % ah)

    def _ticks(self, m) -> int:
        lo, hi = struct.unpack("<HH", m.uc.mem_read(BDA + 0x6C, 4))
        return (hi << 16) | lo

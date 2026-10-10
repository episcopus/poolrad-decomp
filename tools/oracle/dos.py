"""dos.py: the INT 21h services the game and the Turbo Pascal runtime call (SPEC 8.2), answered from
the virtual filesystem. DOS 3.30 is reported. Unlisted functions raise `Unimplemented` at the call
site; nothing returns silently (playbook 25 step 2)."""
from __future__ import annotations

import struct

from .machine import ENV_SEG, PSP_SEG, MEM_TOP_SEG, Stop, FLAG_CF
from .vfs import VFile, DevFile

DEFAULT_DATE = (1991, 6, 11)       # fixed virtual date (a Tuesday): the host calendar never leaks in
FILE_DATE = ((1988 - 1980) << 9) | (11 << 5) | 1
FILE_TIME = (12 << 11)
MAX_HANDLES = 20


class Dos:
    def __init__(self, machine, cmdline: bytes = b""):
        self.m = machine
        self.cmdline = cmdline
        self.handles: dict[int, object] = {
            0: DevFile("CON"), 1: DevFile("CON"), 2: DevFile("CON"), 3: DevFile("AUX"), 4: DevFile("PRN")}
        self.dta = (PSP_SEG, 0x80)
        self.psp = PSP_SEG
        self.arena: list[list[int]] = []     # [start_seg, paras, owner]
        self.arena_top = MEM_TOP_SEG
        self.console = bytearray()           # everything written to stdout/stderr (for tests and logs)
        self.reads: list[tuple[str, int, int]] = []   # (path, offset, length) of every file read, in order
        self.find_states: dict[int, list] = {}
        self.find_next_id = 1
        self.break_flag = 0
        self.verify = 0
        self.strategy = 0
        self.last_error = 0

    # ------------------------------------------------------------------ setup
    def install(self) -> None:
        m = self.m
        m.register_service(0x21, self.int21)
        m.register_service(0x20, self.int20)
        m.register_service(0x25, self.int25_26)     # absolute disk read: not modelled
        m.register_service(0x26, self.int25_26)
        m.register_service(0x27, self.int27)
        m.register_service(0x29, self.int29)
        m.register_service(0x2F, self.int2f)

    def make_psp(self, seg: int, exe_path: str) -> None:
        m = self.m
        psp = bytearray(256)
        psp[0:2] = b"\xCD\x20"
        psp[2:4] = struct.pack("<H", MEM_TOP_SEG)
        psp[0x16:0x18] = struct.pack("<H", seg)                   # parent: itself
        psp[0x18:0x18 + MAX_HANDLES] = bytes([0, 1, 2, 3, 4] + [0xFF] * (MAX_HANDLES - 5))
        psp[0x2C:0x2E] = struct.pack("<H", ENV_SEG)
        psp[0x32:0x34] = struct.pack("<H", MAX_HANDLES)
        psp[0x34:0x38] = struct.pack("<HH", 0x18, seg)
        psp[0x50:0x53] = b"\xCD\x21\xCB"
        tail = self.cmdline[:126]
        psp[0x80] = len(tail)
        psp[0x81:0x81 + len(tail)] = tail
        psp[0x81 + len(tail)] = 0x0D
        m.uc.mem_write(seg * 16, bytes(psp))
        env = (b"COMSPEC=C:\\COMMAND.COM\x00PATH=C:\\\x00\x00\x01\x00" + b"C:\\POOLRAD\\START.EXE\x00")
        m.uc.mem_write(ENV_SEG * 16, env)

    def arena_init(self, first_seg: int, top: int) -> None:
        self.arena_top = top
        self.arena = [[ENV_SEG, 0x40, PSP_SEG], [PSP_SEG, top - PSP_SEG, PSP_SEG]]

    # ------------------------------------------------------------------ helpers
    def _path(self, m, seg_reg="ds", off_reg="dx") -> str:
        return m.cstring(m.get(seg_reg), m.get(off_reg), 128).decode("latin-1")

    def _alloc_handle(self, obj) -> int | None:
        for h in range(5, MAX_HANDLES):
            if h not in self.handles:
                self.handles[h] = obj
                return h
        return None

    def _out_char(self, ch: int) -> None:
        self.console.append(ch)
        self.m.bios.tty(ch)

    # ------------------------------------------------------------------ INT 20h / 27h / 29h / 2Fh
    def int20(self, m):
        self._terminate(m, 0)

    def int27(self, m):
        m.unimplemented("INT 27h terminate and stay resident")

    def int25_26(self, m):
        m.unimplemented("INT 25h/26h absolute disk access")

    def int29(self, m):
        self._out_char(m.get("ax") & 0xFF)

    def int2f(self, m):
        ax = m.get("ax")
        if ax in (0x1600, 0x4300, 0x4A01, 0x4A02):   # Windows / XMS / HMA probes: "not installed"
            m.set("ax", ax & 0xFF00 if ax != 0x4300 else 0x0000)
            return
        if (ax >> 8) in (0x11, 0x12, 0x14, 0x15, 0x16, 0x43, 0xB7, 0xAD):  # network redirector, MSCDEX, ...
            m.set("ax", ax & 0xFF00)
            return
        m.unimplemented("INT 2Fh AX=%04X" % ax)

    def _terminate(self, m, code: int) -> None:
        m.exit_code = code
        raise Stop("exit", code)

    # ------------------------------------------------------------------ INT 21h
    def int21(self, m):
        ax = m.get("ax")
        ah, al = ax >> 8, ax & 0xFF
        fn = getattr(self, "f%02X" % ah, None)
        if fn is None:
            m.unimplemented("INT 21h AH=%02Xh" % ah)
            m.err(1)
            return
        fn(m, al)

    # console
    def f01(self, m, al):                         # read char with echo
        k = self._getkey(m)
        if k is None:
            return
        m.set("ax", (m.get("ax") & 0xFF00) | (k & 0xFF))
        self._out_char(k & 0xFF)

    def f02(self, m, al):
        self._out_char(m.get("dx") & 0xFF)

    def f06(self, m, al):
        dl = m.get("dx") & 0xFF
        if dl != 0xFF:
            self._out_char(dl)
            return
        k = m.keys.peek(m) if getattr(m, "keys", None) else None
        if k is None:
            m.ret_flags(set_mask=0x40)
            m.set("ax", m.get("ax") & 0xFF00)
        else:
            m.keys.take(m)
            m.set("ax", (m.get("ax") & 0xFF00) | (k & 0xFF))
            m.ret_flags(clear_mask=0x40)

    def _getkey(self, m):
        keys = getattr(m, "keys", None)
        k = keys.take(m) if keys else None
        if k is None:
            if keys is None or keys.exhausted(m):
                raise Stop("input-exhausted")
            ss, sp = m.get("ss"), m.get("sp")
            m.ww(ss, sp, (m.rw(ss, sp) - 2) & 0xFFFF)
            if not m.irq0_pending:
                m.extra += max(0, m.next_irq0 - m.now())
            return None
        return k

    def f07(self, m, al):
        k = self._getkey(m)
        if k is not None:
            m.set("ax", (m.get("ax") & 0xFF00) | (k & 0xFF))

    f08 = f07

    def f09(self, m, al):
        seg, off = m.get("ds"), m.get("dx")
        for i in range(0xFFFF):
            c = m.rb(seg, off + i)
            if c == 0x24:
                break
            self._out_char(c)

    def f0B(self, m, al):
        k = m.keys.peek(m) if getattr(m, "keys", None) else None
        m.set("ax", (m.get("ax") & 0xFF00) | (0xFF if k is not None else 0x00))

    def f0C(self, m, al):
        m.set("ax", (m.get("ax") & 0xFF) | (al << 8))
        if al in (1, 6, 7, 8):
            getattr(self, "f%02X" % al)(m, al)

    def f0D(self, m, al):
        pass

    # disks
    def f0E(self, m, al):
        m.set("ax", (m.get("ax") & 0xFF00) | 3)          # LASTDRIVE: 3 drives (A, B, C)

    def f19(self, m, al):
        m.set("ax", (m.get("ax") & 0xFF00) | 2)          # current drive C:

    def f1A(self, m, al):
        self.dta = (m.get("ds"), m.get("dx"))

    def f2F(self, m, al):
        m.set("es", self.dta[0])
        m.set("bx", self.dta[1])

    def f1B(self, m, al):                                # default drive allocation info
        m.set("ax", (m.get("ax") & 0xFF00) | 4)
        m.set("cx", 512)
        m.set("dx", 0x2000)
        m.set("ds", 0xF000)
        m.set("bx", 0x0000)

    def f36(self, m, al):                                # free disk space: plenty
        m.set("ax", 4)
        m.set("bx", 0x4000)
        m.set("cx", 512)
        m.set("dx", 0x8000)

    # vectors / system
    def f25(self, m, al):
        m.set_ivt(al, m.get("ds"), m.get("dx"))

    def f35(self, m, al):
        seg, off = m.ivt(al)
        m.set("es", seg)
        m.set("bx", off)

    def f30(self, m, al):
        m.set("ax", 0x1E03)                              # DOS 3.30
        m.set("bx", 0)
        m.set("cx", 0)

    def f33(self, m, al):
        if al == 0:
            m.set("dx", (m.get("dx") & 0xFF00) | self.break_flag)
        elif al == 1:
            self.break_flag = m.get("dx") & 0xFF
        elif al == 5:
            m.set("dx", (m.get("dx") & 0xFF00) | 3)       # boot drive C:
        elif al == 6:
            m.set("bx", 0x1E03)
            m.set("dx", 0x0000)
        else:
            m.unimplemented("INT 21h AH=33h AL=%02X" % al)

    def f2A(self, m, al):
        y, mo, d = DEFAULT_DATE
        days = int(m.seconds()) // 86400
        m.set("cx", y)
        m.set("dx", (mo << 8) | (d + days))
        m.set("ax", (m.get("ax") & 0xFF00) | ((2 + days) % 7))

    def f2C(self, m, al):
        s = m.now() / m.insn_per_sec + 12 * 3600
        sec = int(s)
        m.set("cx", (((sec // 3600) % 24) << 8) | ((sec // 60) % 60))
        m.set("dx", ((sec % 60) << 8) | int((s - sec) * 100))

    def f2E(self, m, al):
        self.verify = al

    f54 = f2E

    def f34(self, m, al):                                 # InDOS flag address
        m.set("es", 0xF000)
        m.set("bx", 0x0010)

    def f38(self, m, al):                                 # country info: US
        if al == 0 and m.get("dx") != 0xFFFF:
            data = bytearray(34)
            data[0:2] = struct.pack("<H", 0)
            data[2:4] = b"$\x00"
            data[7:9] = b",\x00"
            data[9:11] = b".\x00"
            m.write(m.get("ds"), m.get("dx"), bytes(data))
        m.set("bx", 1)
        m.ok()

    # ---- handle based file I/O
    def f3C(self, m, al):                                 # create/truncate
        path = self._path(m)
        f = m.vfs.open(path, True, create=True)
        h = self._alloc_handle(f)
        if h is None:
            return m.err(4)
        m.set("ax", h)
        m.ok()

    f5B = f3C

    def f3D(self, m, al):                                 # open
        path = self._path(m)
        f = m.vfs.open(path, write=(al & 7) != 0)
        if f is None:
            full = m.vfs.resolve(path)
            return m.err(3 if full.rpartition("\\")[0] and full.rpartition("\\")[0] not in m.vfs.dirs else 2)
        h = self._alloc_handle(f)
        if h is None:
            return m.err(4)
        m.set("ax", h)
        m.ok()

    def f3E(self, m, al):
        h = m.get("bx")
        if h not in self.handles:
            return m.err(6)
        if h >= 5:
            del self.handles[h]
        m.ok()

    def f3F(self, m, al):
        h, n = m.get("bx"), m.get("cx")
        f = self.handles.get(h)
        if f is None:
            return m.err(6)
        if f.is_device:
            m.unimplemented("INT 21h AH=3Fh read from device handle %d" % h)
            return m.err(5)
        chunk = bytes(f.data[f.pos:f.pos + n])
        m.write(m.get("ds"), m.get("dx"), chunk)
        self.reads.append((f.path, f.pos, len(chunk)))
        f.pos += len(chunk)
        m.set("ax", len(chunk))
        m.ok()
        if m.tracer:
            m.tracer.on_file(m, "read", f.path, f.pos - len(chunk), len(chunk))

    def f40(self, m, al):
        h, n = m.get("bx"), m.get("cx")
        f = self.handles.get(h)
        if f is None:
            return m.err(6)
        data = m.read(m.get("ds"), m.get("dx"), n)
        if f.is_device:
            for c in data:
                self._out_char(c)
        else:
            if not f.writable:
                return m.err(5)
            if n == 0:                                    # DOS: zero-length write truncates at pos
                del f.data[f.pos:]
            else:
                end = f.pos + n
                if end > len(f.data):
                    f.data.extend(bytes(end - len(f.data)))
                f.data[f.pos:end] = data
                f.pos = end
            if m.tracer:
                m.tracer.on_file(m, "write", f.path, f.pos - n, n)
        m.set("ax", n)
        m.ok()

    def f41(self, m, al):
        if m.vfs.delete(self._path(m)):
            m.ok()
        else:
            m.err(2)

    def f42(self, m, al):
        f = self.handles.get(m.get("bx"))
        if f is None or f.is_device:
            return m.err(6)
        off = (m.get("cx") << 16) | m.get("dx")
        if off & 0x80000000:
            off -= 1 << 32
        base = {0: 0, 1: f.pos, 2: len(f.data)}.get(al)
        if base is None:
            return m.err(1)
        f.pos = max(0, base + off)
        m.set("dx", (f.pos >> 16) & 0xFFFF)
        m.set("ax", f.pos & 0xFFFF)
        m.ok()

    def f43(self, m, al):
        full = m.vfs.resolve(self._path(m))
        if not (m.vfs.exists(full) or m.vfs.isdir(full)):
            return m.err(2)
        if al == 0:
            m.set("cx", 0x10 if m.vfs.isdir(full) else 0x20)
        m.ok()

    def f44(self, m, al):
        h = m.get("bx")
        f = self.handles.get(h)
        if al == 0:                                       # get device information
            if f is None:
                return m.err(6)
            m.set("dx", 0x80D3 if f.is_device else 0x0002)  # char device (stdin+stdout+special) / drive C:
            m.ok()
        elif al == 1:
            m.ok()
        elif al == 6:                                     # input status
            m.set("ax", (m.get("ax") & 0xFF00) | (0xFF if f and (f.is_device or f.pos < len(f.data)) else 0))
            m.ok()
        elif al == 7:
            m.set("ax", (m.get("ax") & 0xFF00) | 0xFF)
            m.ok()
        elif al == 8:                                     # removable? 1 = fixed
            m.set("ax", 1)
            m.ok()
        elif al == 9:                                     # local?
            m.set("dx", 0)
            m.ok()
        else:
            m.unimplemented("INT 21h AH=44h AL=%02X" % al)
            m.err(1)

    def f45(self, m, al):
        f = self.handles.get(m.get("bx"))
        if f is None:
            return m.err(6)
        h = self._alloc_handle(f)
        if h is None:
            return m.err(4)
        m.set("ax", h)
        m.ok()

    def f46(self, m, al):
        f = self.handles.get(m.get("bx"))
        if f is None:
            return m.err(6)
        self.handles[m.get("cx")] = f
        m.ok()

    def f57(self, m, al):
        if al == 0:
            m.set("cx", FILE_TIME)
            m.set("dx", FILE_DATE)
        m.ok()

    def f68(self, m, al):
        m.ok()

    def f67(self, m, al):
        m.ok()

    # ---- directories
    def f3B(self, m, al):
        full = m.vfs.resolve(self._path(m))
        if not m.vfs.isdir(full):
            return m.err(3)
        m.vfs.cwd = full
        m.ok()

    def f47(self, m, al):
        drive = m.get("dx") & 0xFF
        cur = m.vfs.cwd.lstrip("\\").encode() + b"\x00"
        m.write(m.get("ds"), m.get("si"), cur)
        m.set("ax", 0x0100)
        m.ok()

    def f39(self, m, al):
        full = m.vfs.resolve(self._path(m))
        m.vfs.dirs.add(full)
        m.ok()

    def f3A(self, m, al):
        m.vfs.dirs.discard(m.vfs.resolve(self._path(m)))
        m.ok()

    def f56(self, m, al):
        old = m.cstring(m.get("ds"), m.get("dx"), 128).decode("latin-1")
        new = m.cstring(m.get("es"), m.get("di"), 128).decode("latin-1")
        if m.vfs.rename(old, new):
            m.ok()
        else:
            m.err(2)

    def f4E(self, m, al):
        spec = self._path(m)
        res = m.vfs.find(spec)
        if not res:
            return m.err(18)
        fid = self.find_next_id
        self.find_next_id += 1
        self.find_states[fid] = res
        self._find_emit(m, fid, 0)

    def f4F(self, m, al):
        dseg, doff = self.dta
        fid = m.rb(dseg, doff)
        idx = m.rw(dseg, doff + 1)
        if fid not in self.find_states or idx >= len(self.find_states[fid]):
            return m.err(18)
        self._find_emit(m, fid, idx)

    def _find_emit(self, m, fid: int, idx: int) -> None:
        dseg, doff = self.dta
        name, size, attr = self.find_states[fid][idx]
        m.wb(dseg, doff, fid)
        m.ww(dseg, doff + 1, idx + 1)
        m.wb(dseg, doff + 0x15, attr)
        m.ww(dseg, doff + 0x16, FILE_TIME)
        m.ww(dseg, doff + 0x18, FILE_DATE)
        m.write(dseg, doff + 0x1A, struct.pack("<I", size))
        m.write(dseg, doff + 0x1E, name.encode()[:12] + b"\x00" * (13 - min(12, len(name))))
        m.ok()

    # ---- memory
    def f48(self, m, al):
        want = m.get("bx")
        blocks = sorted(self.arena, key=lambda b: b[0])
        cursor = blocks[0][0] if blocks else 0
        gaps = []
        prev_end = 0x1000                               # conventional arena starts above env/PSP block
        for b in blocks:
            if b[0] - prev_end > 0:
                gaps.append((prev_end, b[0] - prev_end))
            prev_end = max(prev_end, b[0] + b[1])
        if self.arena_top - prev_end > 0:
            gaps.append((prev_end, self.arena_top - prev_end))
        for start, size in gaps:
            if size >= want:
                self.arena.append([start, want, self.psp])
                m.set("ax", start)
                return m.ok()
        m.set("bx", max([g[1] for g in gaps] or [0]))
        m.err(8)

    def f49(self, m, al):
        seg = m.get("es")
        for b in self.arena:
            if b[0] == seg:
                self.arena.remove(b)
                return m.ok()
        m.err(9)

    def f4A(self, m, al):
        seg, want = m.get("es"), m.get("bx")
        for b in self.arena:
            if b[0] == seg:
                others = [o for o in self.arena if o is not b and o[0] > seg]
                limit = min([o[0] for o in others] + [self.arena_top])
                if want <= limit - seg:
                    b[1] = want
                    return m.ok()
                m.set("bx", limit - seg)
                return m.err(8)
        m.err(9)

    def f58(self, m, al):
        if al == 0:
            m.set("ax", self.strategy)
        else:
            self.strategy = m.get("bx")
        m.ok()

    # ---- process
    def f4C(self, m, al):
        self._terminate(m, al)

    def f00(self, m, al):
        self._terminate(m, 0)

    def f4D(self, m, al):
        m.set("ax", 0)

    def f50(self, m, al):
        self.psp = m.get("bx")

    f51 = f62 = lambda self, m, al: m.set("bx", self.psp)

    def f4B(self, m, al):
        m.unimplemented("INT 21h AH=4Bh EXEC of %r" % self._path(m))
        m.err(2)

    def f59(self, m, al):
        m.set("ax", self.last_error)
        m.set("bx", 0x0105)
        m.set("cx", 0x0100)

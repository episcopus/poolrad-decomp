"""machine.py: a deterministic, headless 16-bit real-mode PC around Unicorn (SPEC 8.2).

What lives here: memory map, MZ loader, interrupt dispatch (software INTs go through the real IVT so
the program's own handlers, e.g. the Borland overlay manager on INT 3Fh, run as original code),
virtual time and the PIT/PIC timer, port I/O, breakpoints and routine hooks.
DOS and BIOS services (`dos.py`, `bios.py`) and the EGA (`ega.py`) plug into it.

Determinism rules (so that the same key script gives the same trace and digests):
  * time is the executed-instruction counter, never the wall clock;
  * no host randomness, no host date/time, no host environment leaks into the guest;
  * services answer from the pinned inputs and an in-memory write layer only.
"""
from __future__ import annotations

import ctypes
import hashlib
import struct
import sys
from pathlib import Path

from unicorn import (Uc, UcError, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE, UC_HOOK_INSN,
                     UC_PROT_ALL)
from unicorn.x86_const import (UC_X86_REG_AX, UC_X86_REG_BX, UC_X86_REG_CX, UC_X86_REG_DX, UC_X86_REG_SI,
                               UC_X86_REG_DI, UC_X86_REG_BP, UC_X86_REG_SP, UC_X86_REG_CS, UC_X86_REG_DS,
                               UC_X86_REG_ES, UC_X86_REG_SS, UC_X86_REG_IP, UC_X86_REG_EFLAGS,
                               UC_X86_INS_IN, UC_X86_INS_OUT)

ROOT = Path(__file__).resolve().parents[2]

PSP_SEG = 0x0FF0          # same load layout as tools/re/mzutil.py and smoke.py: image at 1000:0000
LOAD_SEG = PSP_SEG + 0x10
ENV_SEG = 0x0F00
MEM_TOP_SEG = 0xA000      # 640 KB of conventional memory

STUB_BASE = 0xF1000       # linear: F000:1000 .. one 4-byte stub per interrupt number (IRET + pad)
STUB_SEG, STUB_OFF0 = 0xF000, 0x1000
ROM_INT8 = (0xF000, 0x2000)       # real x86 code for the default timer interrupt
ROM_IRQ_EOI = (0xF000, 0x2040)    # default handler for IRQ1..7: EOI + IRET
ROM_IRET = (0xF000, 0x0000)       # generic IRET

FLAG_CF, FLAG_ZF, FLAG_IF, FLAG_TF, FLAG_DF = 0x0001, 0x0040, 0x0200, 0x0100, 0x0400
# A timer interrupt that stays pending this long was never delivered: the guest is spinning with
# interrupts off (a blocked read that can never be answered, for instance). Legitimate waits for IF are
# a few hundred instructions; this turns a run that would crawl to max_insns into an error in seconds.
STALL_INSNS = 2_000_000

REG = dict(ax=UC_X86_REG_AX, bx=UC_X86_REG_BX, cx=UC_X86_REG_CX, dx=UC_X86_REG_DX, si=UC_X86_REG_SI,
           di=UC_X86_REG_DI, bp=UC_X86_REG_BP, sp=UC_X86_REG_SP, cs=UC_X86_REG_CS, ds=UC_X86_REG_DS,
           es=UC_X86_REG_ES, ss=UC_X86_REG_SS, ip=UC_X86_REG_IP, flags=UC_X86_REG_EFLAGS)


class OracleError(Exception):
    """Base class: the run cannot continue meaningfully."""


class Unimplemented(OracleError):
    """The program used an emulator feature we do not model. Never returns silently (playbook 25)."""


class GuestCrash(OracleError):
    pass


class Stop(Exception):
    """Raised by hooks to end the run cleanly (script finished, breakpoint, program exit)."""

    def __init__(self, reason: str, code: int = 0):
        super().__init__(reason)
        self.reason, self.code = reason, code


def read_mz(path):
    d = Path(path).read_bytes()
    f = struct.unpack("<14H", d[:28])
    last, pages, nrel, hdrp, minalloc, maxalloc, ss, sp, _ck, ip, cs, reloff = f[1:13]
    size = (pages - 1) * 512 + last if last else pages * 512
    image = bytearray(d[hdrp * 16:size])
    relocs = [struct.unpack_from("<HH", d, reloff + 4 * i) for i in range(nrel)]
    return dict(image=image, relocs=relocs, ss=ss, sp=sp, ip=ip, cs=cs, minalloc=minalloc, maxalloc=maxalloc)


class Machine:
    def __init__(self, exe, game_dir, *, insn_per_sec: int = 1_000_000, strict: bool = True,
                 cmdline: bytes = b""):
        from .vfs import VFS
        from .dos import Dos
        from .bios import Bios
        from .ega import EGA

        self.exe = Path(exe)
        self.strict = strict
        self.insn_per_sec = insn_per_sec
        self.insns = 0                   # executed instructions (exact at chunk boundaries)
        self.extra = 0                   # virtual time charged by port polling (see port 3DA)
        self.exit_code: int | None = None
        self.events = []                 # hooks may append here; trace.py drains it
        self.tracer = None               # set by trace.Tracer
        self.clock_pin: int | None = None   # hundredths of a second since midnight the FIRST time-of-day read returns
        self._tod_offset: int | None = None
        self.tod_log: list[tuple[int, int]] = []   # (virtual time, hundredths returned) for every read
        self.int_counts: dict = {}       # software INTs executed, by number
        self.service_counts: dict = {}   # calls that reached one of our service stubs, by number
        self.overlay_listeners: list = []   # callables(machine) after each read of GAME.OVR (routines.py)
        self.file_listeners: list = []   # callables(machine, op, path, pos, n) after each file read/write

        self.uc = uc = Uc(UC_ARCH_X86, UC_MODE_16)
        # Conventional RAM is a host buffer so the C lift can address it (SPEC 7.3).
        # The Machine keeps the reference: Unicorn does not copy the bytes.
        self.ram = ctypes.create_string_buffer(0xA0000)
        uc.mem_map_ptr(0, 0xA0000, UC_PROT_ALL, ctypes.cast(self.ram, ctypes.c_void_p))
        self.ega = EGA(self)
        uc.mmio_map(0xA0000, 0x20000, self.ega.mmio_read, None, self.ega.mmio_write, None)
        uc.mem_map(0xC0000, 0x40000)                            # ROM area: BIOS stubs live here

        self.vfs = VFS(game_dir)
        self.bios = Bios(self)
        self.dos = Dos(self, cmdline)

        # --- timer / interrupt controller state -------------------------------------
        self.pit_reload = 0x10000          # channel 0 reload (0 means 65536)
        self.pit_latch_lo = True
        self.pit_mode_access = 3
        self.pit2_reload = 0
        self.pit2_lo = True
        self.port61 = 0
        self.irq0_pending = False
        self.irq0_in_service = False
        self.irq0_raised = 0               # timer interrupts raised so far (replay.py records it per read)
        self.irq0_owed: int | None = None  # replay: interrupts to raise, set at reads (None: from the clock)
        self._pending_since = 0
        self.next_irq0 = self._irq0_period()
        self.pic_mask = 0
        self.speaker_log = []              # (time, divisor, on) for sound capture
        self.pit0_log = []                 # (time, reload) every time the timer's reload is written
        self.tandy_log = []                # (time, byte) every write to the Tandy sound chip (port C0h)
        self.port_log_unhandled: dict = {}

        self.services: dict[int, callable] = {}
        self.routine_hooks: dict[int, callable] = {}
        self.breakpoints: dict[int, list] = {}     # linear address -> callbacks (add_breakpoint)
        self.watch_hooks = []

        self._build_rom()
        self._load(exe)
        self._install_hooks()

    # ------------------------------------------------------------------ registers
    def get(self, name: str) -> int:
        v = self.uc.reg_read(REG[name])
        return v & 0xFFFF if name != "flags" else v & 0xFFFF

    def set(self, name: str, v: int) -> None:
        self.uc.reg_write(REG[name], v & 0xFFFF)

    def linear(self, seg: int, off: int) -> int:
        return ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF

    def rb(self, seg, off) -> int:
        return self.uc.mem_read(self.linear(seg, off), 1)[0]

    def rw(self, seg, off) -> int:
        return struct.unpack("<H", self.uc.mem_read(self.linear(seg, off), 2))[0]

    def wb(self, seg, off, v) -> None:
        self.uc.mem_write(self.linear(seg, off), bytes([v & 0xFF]))

    def ww(self, seg, off, v) -> None:
        self.uc.mem_write(self.linear(seg, off), struct.pack("<H", v & 0xFFFF))

    def read(self, seg, off, n) -> bytes:
        return bytes(self.uc.mem_read(self.linear(seg, off), n))

    def write(self, seg, off, data: bytes) -> None:
        self.uc.mem_write(self.linear(seg, off), bytes(data))

    def cstring(self, seg, off, limit=256) -> bytes:
        out = bytearray()
        for i in range(limit):
            b = self.rb(seg, off + i)
            if b == 0:
                break
            out.append(b)
        return bytes(out)

    def now(self) -> int:
        return self.insns + self.extra

    def seconds(self) -> float:
        return self.now() / self.insn_per_sec

    def time_of_day(self) -> int:
        """Time of day the program sees, in hundredths of a second since midnight.

        Virtual: 12:00:00.00 plus the instruction clock. When the session pins the clock (script
        command `clock HH:MM:SS.hh`), the first read returns exactly the pinned value and later reads
        advance from it, so values derived from the first read (`Randomize` seeds) do not depend on how
        many instructions ran before it."""
        t = 12 * 360000 + (self.now() * 100) // self.insn_per_sec
        if self.clock_pin is not None:
            if self._tod_offset is None:
                self._tod_offset = self.clock_pin - t
            t += self._tod_offset
        t %= 8_640_000
        if len(self.tod_log) < 10_000:
            self.tod_log.append((self.now(), t))
        return t

    # ------------------------------------------------------------------ stack and flags
    def push(self, v: int) -> None:
        sp = (self.get("sp") - 2) & 0xFFFF
        self.ww(self.get("ss"), sp, v)
        self.set("sp", sp)

    def pop(self) -> int:
        sp = self.get("sp")
        v = self.rw(self.get("ss"), sp)
        self.set("sp", sp + 2)
        return v

    def ret_flags(self, set_mask: int = 0, clear_mask: int = 0) -> None:
        """Modify the FLAGS word an INT handler will IRET with (our services return CF/ZF this way)."""
        ss, sp = self.get("ss"), self.get("sp")
        f = self.rw(ss, sp + 4)
        self.ww(ss, sp + 4, (f | set_mask) & ~clear_mask)

    def ok(self) -> None:
        self.ret_flags(clear_mask=FLAG_CF)

    def err(self, code: int) -> None:
        self.set("ax", code)
        self.ret_flags(set_mask=FLAG_CF)

    def far_return(self, pop_bytes: int = 0) -> None:
        """Perform a Pascal far return from a hooked routine (RETF n)."""
        ip, cs = self.pop(), self.pop()
        self.set("cs", cs)
        self.set("ip", ip)
        self.set("sp", self.get("sp") + pop_bytes)

    def ivt(self, n: int) -> tuple[int, int]:
        off, seg = struct.unpack("<HH", self.uc.mem_read(n * 4, 4))
        return seg, off

    def set_ivt(self, n: int, seg: int, off: int) -> None:
        self.uc.mem_write(n * 4, struct.pack("<HH", off & 0xFFFF, seg & 0xFFFF))

    def deliver_interrupt(self, n: int, clear_if: bool = True) -> None:
        """What the CPU does on INT n / IRQ: push FLAGS, CS, IP; clear IF/TF; load the vector."""
        self.push(self.get("flags"))
        self.push(self.get("cs"))
        self.push(self.get("ip"))
        fl = self.get("flags") & ~(FLAG_TF | (FLAG_IF if clear_if else 0))
        self.uc.reg_write(UC_X86_REG_EFLAGS, fl)
        seg, off = self.ivt(n)
        self.set("cs", seg)
        self.set("ip", off)

    # ------------------------------------------------------------------ loading
    def _build_rom(self) -> None:
        uc = self.uc
        uc.mem_write(0xF0000, b"\xCF")                           # generic IRET at F000:0000
        for n in range(256):                                      # one stub per interrupt: IRET + pad
            uc.mem_write(STUB_BASE + n * 4, b"\xCF\x90\x90\x90")
        # default INT 8: inc BIOS tick count, chain INT 1Ch, EOI.
        int8 = bytes([
            0x50, 0x1E,                                           # push ax; push ds
            0xB8, 0x40, 0x00, 0x8E, 0xD8,                         # mov ax,40h; mov ds,ax
            0xFF, 0x06, 0x6C, 0x00,                               # inc word [6Ch]
            0x75, 0x04,                                           # jnz +4
            0xFF, 0x06, 0x6E, 0x00,                               # inc word [6Eh]
            0xCD, 0x1C,                                           # int 1Ch
            0xB0, 0x20, 0xE6, 0x20,                               # mov al,20h; out 20h,al
            0x1F, 0x58, 0xCF,                                     # pop ds; pop ax; iret
        ])
        uc.mem_write(self.linear(*ROM_INT8), int8)
        eoi = bytes([0x50, 0xB0, 0x20, 0xE6, 0x20, 0x58, 0xCF])  # push ax; mov al,20h; out 20h,al; pop ax; iret
        uc.mem_write(self.linear(*ROM_IRQ_EOI), eoi)
        # IVT: everything -> generic IRET, services -> their stub, IRQs -> real code
        for n in range(256):
            self.set_ivt(n, *ROM_IRET)
        for n in range(0x08, 0x10):
            self.set_ivt(n, *ROM_IRQ_EOI)
        self.set_ivt(0x08, *ROM_INT8)
        for n in range(0x70, 0x78):
            self.set_ivt(n, *ROM_IRQ_EOI)
        # services register themselves (bios.py, dos.py) and point their vector at the stub
        self.bios.install()
        self.dos.install()

    def register_service(self, n: int, fn) -> None:
        self.services[n] = fn
        self.set_ivt(n, STUB_SEG, STUB_OFF0 + n * 4)

    def _load(self, exe) -> None:
        mz = read_mz(exe)
        img = mz["image"]
        for off, seg in mz["relocs"]:
            p = seg * 16 + off
            img[p:p + 2] = struct.pack("<H", (struct.unpack("<H", img[p:p + 2])[0] + LOAD_SEG) & 0xFFFF)
        self.image_len = len(img)
        self.uc.mem_write(LOAD_SEG * 16, bytes(img))
        self.dos.make_psp(PSP_SEG, str(self.exe))
        self.dos.arena_init(PSP_SEG - 1, MEM_TOP_SEG)
        for r, v in (("cs", mz["cs"] + LOAD_SEG), ("ip", mz["ip"]), ("ss", mz["ss"] + LOAD_SEG),
                     ("sp", mz["sp"]), ("ds", PSP_SEG), ("es", PSP_SEG)):
            self.set(r, v)
        self.uc.reg_write(UC_X86_REG_EFLAGS, 0x0202)             # IF=1 (DOS enters programs with interrupts on)
        self.entry = (mz["cs"] + LOAD_SEG, mz["ip"])

    def _install_hooks(self) -> None:
        uc = self.uc
        uc.hook_add(UC_HOOK_INTR, self._on_intr)
        uc.hook_add(UC_HOOK_CODE, self._on_stub, begin=STUB_BASE, end=STUB_BASE + 256 * 4 - 1)
        uc.hook_add(UC_HOOK_INSN, self._port_in, None, 1, 0, UC_X86_INS_IN)
        uc.hook_add(UC_HOOK_INSN, self._port_out, None, 1, 0, UC_X86_INS_OUT)

    # ------------------------------------------------------------------ interrupts
    def _on_intr(self, uc, n, _ud) -> None:
        # Software INT n and CPU exceptions both end up here. Unicorn does not dispatch through the IVT
        # itself, so we do what the CPU does: push the frame and jump to the vector. Service vectors point
        # at our stubs (run in `_on_stub`); vectors the program installed run as original code.
        self.int_counts[n] = self.int_counts.get(n, 0) + 1
        if self.tracer:
            self.tracer.on_int(self, n)
        self.deliver_interrupt(n)

    def _on_stub(self, uc, addr, size, _ud) -> None:
        n = (addr - STUB_BASE) // 4
        self.service_counts[n] = self.service_counts.get(n, 0) + 1
        fn = self.services.get(n)
        if fn is None:
            self.unimplemented("INT %02Xh has no service (vector points at its stub)" % n)
            return
        fn(self)

    def unimplemented(self, what: str) -> None:
        msg = "UNIMPLEMENTED at %04X:%04X (load-relative %04X:%04X): %s | AX=%04X BX=%04X CX=%04X DX=%04X" % (
            self.get("cs"), self.get("ip"), (self.get("cs") - LOAD_SEG) & 0xFFFF, self.get("ip"), what,
            self.get("ax"), self.get("bx"), self.get("cx"), self.get("dx"))
        print(msg, file=sys.stderr)
        if self.strict:
            raise Unimplemented(msg)

    # ------------------------------------------------------------------ port I/O
    def _port_in(self, uc, port, size, _ud) -> int:
        v = self.port_read(port, size)
        if self.tracer:
            self.tracer.on_port(self, "in", port, size, v)
        return v

    def _port_out(self, uc, port, size, val, _ud) -> None:
        if self.tracer:
            self.tracer.on_port(self, "out", port, size, val)
        self.port_write(port, size, val)

    def port_read(self, port: int, size: int) -> int:
        if 0x3B0 <= port <= 0x3DF:
            return self.ega.port_read(port, size)
        if port == 0x40:
            return (self.now() // 3) & 0xFF            # free-running counter low byte; deterministic
        if port == 0x42:
            return (self.now() // 5) & 0xFF
        if port == 0x60:
            return self.bios.kbd_port60()
        if port == 0x61:
            return self.port61
        if port == 0x21:
            return self.pic_mask
        if port in (0x20, 0xA0):
            return 0
        if port == 0x201:
            return 0xFF                                # no joystick
        return self._unhandled_port("in", port, size, 0xFF if size == 1 else 0xFFFF)

    def port_write(self, port: int, size: int, val: int) -> None:
        if 0x3B0 <= port <= 0x3DF:
            self.ega.port_write(port, size, val)
        elif port == 0x20:
            if val & 0xE0 == 0x20:                     # EOI
                self.irq0_in_service = False
        elif port == 0x21:
            self.pic_mask = val & 0xFF
        elif port == 0x43:
            ch = (val >> 6) & 3
            if ch == 0:
                self.pit_mode_access = (val >> 4) & 3
                self.pit_latch_lo = True
            elif ch == 2:
                self.pit2_lo = True
        elif port == 0x40:
            self._pit0_write(val)
        elif port == 0x42:
            if self.pit2_lo:
                self.pit2_reload = (self.pit2_reload & 0xFF00) | (val & 0xFF)
            else:
                self.pit2_reload = (self.pit2_reload & 0x00FF) | ((val & 0xFF) << 8)
                self.speaker_log.append((self.now(), self.pit2_reload, bool(self.port61 & 3 == 3)))
            self.pit2_lo = not self.pit2_lo
        elif port == 0x61:
            self.port61 = val & 0xFF
            self.speaker_log.append((self.now(), self.pit2_reload, (val & 3) == 3))
        elif port == 0xC0:
            self.tandy_log.append((self.now(), val & 0xFF))   # Tandy/PCjr SN76489 sound chip
        elif port in (0x22, 0x23, 0x80, 0xA0, 0xA1, 0x3F2, 0x201, 0x378, 0x379, 0x37A):
            pass
        else:
            self._unhandled_port("out", port, size, val)

    def _unhandled_port(self, d: str, port: int, size: int, default: int) -> int:
        key = (d, port)
        self.port_log_unhandled[key] = self.port_log_unhandled.get(key, 0) + 1
        if self.port_log_unhandled[key] == 1:
            print("note: unmodelled port %s %04Xh (size %d) at %04X:%04X" % (
                d, port, size, self.get("cs"), self.get("ip")), file=sys.stderr)
        return default

    def _pit0_write(self, val: int) -> None:
        acc = self.pit_mode_access
        if acc == 1:
            self.pit_reload = val & 0xFF or 0x100
        elif acc == 2:
            self.pit_reload = ((val & 0xFF) << 8) or 0x10000
        else:
            if self.pit_latch_lo:
                self._pit_lo = val & 0xFF
            else:
                self.pit_reload = ((val & 0xFF) << 8 | self._pit_lo) or 0x10000
                self.pit0_log.append((self.now(), self.pit_reload))
                self.next_irq0 = self.now() + self._irq0_period()
            self.pit_latch_lo = not self.pit_latch_lo

    def _irq0_period(self) -> int:
        return max(1, (self.pit_reload * self.insn_per_sec) // 1_193_182)

    # ------------------------------------------------------------------ running
    def add_breakpoint(self, seg: int, off: int, fn) -> None:
        """fn(machine) is called when execution reaches seg:off (runtime segment). Hooks run in the order
        they were added, so a breakpoint added before a replacement at the same address (protection.py's
        wheel solver on Random's entry) still sees the caller's stack."""
        lin = self.linear(seg, off)
        self.breakpoints.setdefault(lin, []).append(fn)
        self.uc.hook_add(UC_HOOK_CODE, lambda uc, a, s, ud: fn(self), begin=lin, end=lin)

    def notify_file(self, op: str, path: str, pos: int, n: int) -> None:
        if op == "read" and path.upper().endswith("GAME.OVR"):
            for cb in self.overlay_listeners:        # overlay routines may have moved (routines.py)
                cb(self)
        for cb in self.file_listeners:
            cb(self, op, path, pos, n)

    def hook_routine(self, seg: int, off: int, fn, ret_bytes: int = 0, far: bool = True):
        """Replace a routine (hybrid execution, SPEC 8.4). `fn(machine)` runs when execution reaches
        seg:off. If it returns anything but False the routine is considered done and the machine
        performs the return (`retf ret_bytes`, or `ret` when far is False); if it returns False the
        original code runs, so a hook can handle only the cases it implements. Returns the hook handle
        (pass to `unhook`). `routines.replace` does this by routine id, overlay routines included.

        Virtual time is instructions and a replacement executes none, so a hooked run on the clock
        drifts from the original (timer ticks, polls). Session replays (replay.py) answer every read of
        the outside world from the original's recording instead, so the drift has nothing to act on."""
        return self.hook_linear(self.linear(seg, off), fn, ret_bytes=ret_bytes, far=far)

    def hook_linear(self, addr: int, fn, ret_bytes: int = 0, far: bool = True):
        """`hook_routine` at a linear address."""
        def trampoline(uc, a, s, ud):
            if fn(self) is False:
                return
            if far:
                self.far_return(ret_bytes)
            else:
                self.set("ip", self.pop())
                self.set("sp", self.get("sp") + ret_bytes)
        return self.uc.hook_add(UC_HOOK_CODE, trampoline, begin=addr, end=addr)

    def unhook(self, handle) -> None:
        self.uc.hook_del(handle)

    def _raise_irq0(self) -> None:
        self.irq0_pending = True
        self.irq0_raised += 1
        self._pending_since = self.insns

    def _try_deliver_irq0(self) -> None:
        if not self.irq0_pending or self.irq0_in_service or (self.pic_mask & 1):
            return
        if not (self.get("flags") & FLAG_IF):
            return
        self.irq0_pending = False
        self.irq0_in_service = True
        self.deliver_interrupt(0x08)

    def run(self, max_insns: int = 50_000_000, on_chunk=None) -> str:
        """Run until the program exits, a hook raises Stop, or max_insns more instructions executed.
        Returns the stop reason."""
        uc = self.uc
        limit = self.insns + max_insns
        try:
            while True:
                if self.exit_code is not None:
                    return "exit"
                now = self.now()
                if self.irq0_owed is None:
                    if self.irq0_pending is False and now >= self.next_irq0:
                        self._raise_irq0()
                        self.next_irq0 += self._irq0_period()
                elif self.irq0_pending is False and self.irq0_owed > 0:
                    self.irq0_owed -= 1                  # replay: raised as the recording's reads say
                    self._raise_irq0()
                self._try_deliver_irq0()
                if self.irq0_pending and self.insns - self._pending_since > STALL_INSNS:
                    raise OracleError("stalled: a timer interrupt has been pending for %d instructions with "
                                      "interrupts off, at %04X:%04X (a read that can never be answered?)" % (
                                          self.insns - self._pending_since, self.get("cs"), self.get("ip")))
                if self.irq0_pending:
                    chunk = 100                      # waiting for IF; look again soon
                elif self.irq0_owed is not None:
                    chunk = 50_000                   # replay: no clock event to stop at
                else:
                    chunk = max(1, self.next_irq0 - now)
                chunk = min(chunk, 50_000, limit - self.insns)
                if chunk <= 0:
                    return "max-insns"
                start = self.linear(self.get("cs"), self.get("ip"))
                uc.emu_start(start, 0xFFFFFFFF, count=chunk)
                self.insns += chunk
                # HLT leaves emu_start early; jump to the next timer event instead of spinning
                # (in a replay the interrupts come from the recorded reads, so a halt simply resumes)
                if self.irq0_owed is None and uc.mem_read(self.linear(self.get("cs"), (self.get("ip") - 1)), 1) == b"\xF4":
                    self.insns = max(self.insns, self.next_irq0 - self.extra)
                keys = getattr(self, "keys", None)
                if keys is not None:
                    keys.service(self)
                if on_chunk:
                    on_chunk(self)
        except Stop as s:
            return s.reason
        except UcError as e:
            raise GuestCrash(self.crash_report(str(e))) from e

    def crash_report(self, why: str) -> str:
        lines = ["guest fault: %s" % why,
                 "  CS:IP=%04X:%04X (load-relative %04X:%04X)  SS:SP=%04X:%04X  DS=%04X ES=%04X" % (
                     self.get("cs"), self.get("ip"), (self.get("cs") - LOAD_SEG) & 0xFFFF, self.get("ip"),
                     self.get("ss"), self.get("sp"), self.get("ds"), self.get("es")),
                 "  AX=%04X BX=%04X CX=%04X DX=%04X SI=%04X DI=%04X BP=%04X FLAGS=%04X insns=%d" % (
                     self.get("ax"), self.get("bx"), self.get("cx"), self.get("dx"), self.get("si"),
                     self.get("di"), self.get("bp"), self.get("flags"), self.insns)]
        return "\n".join(lines)

    # ------------------------------------------------------------------ state digests
    def state_digest(self, include_video: bool = True, registers: bool = True) -> str:
        """sha256 over registers, conventional memory and (optionally) the EGA planes and registers.
        Later narrowed by re/state.toml into the canonical state (SPEC 8.5)."""
        h = hashlib.sha256()
        if registers:
            h.update(struct.pack("<12H", *[self.get(r) for r in
                     ("ax", "bx", "cx", "dx", "si", "di", "bp", "sp", "cs", "ds", "es", "ss")]))
        h.update(bytes(self.uc.mem_read(0x500, 0xA0000 - 0x500)))
        if include_video:
            h.update(self.ega.digest_bytes())
        return h.hexdigest()

#!/usr/bin/env python3
"""hybrid.py: run the C lift inside the oracle (SPEC 8.4).

Loads build/host/libpoolrad_hybrid (dylib or so) with ctypes and provides one
replacement per lifted routine with the same stack layout the original reads:

  System_Move      sp+4 count, sp+6 dst_off, sp+8 dst_seg, sp+10 src_off,
                   sp+12 src_seg (10 param bytes, retf 10)
  System_FillChar  sp+4 value word, sp+6 count, sp+8 dst_off, sp+10 dst_seg
                   (8 param bytes, retf 8)
  System_Random    sp+4 range (2 param bytes, retf 2); RandSeed is G, which
                   sits at guest DS:0000 when the guest RAM is bound

A session binds the guest's conventional RAM (Machine.ram, mapped with
mem_map_ptr), so the C stores are guest stores. Isolated fuzz keeps its own
scratch buffer. A copy that would touch video MMIO (linear >= 0xA0000) is
declined and the original runs. Move's direction flag is applied here: the
original leaves DF set whenever the source offset is below the destination
offset (std at 0AF8:169E, no cld before retf), including a count of 0.
FillChar always cld's. No time is charged for C: session replays answer the
game's reads of the outside world from the original's recording (replay.py).
"""
from __future__ import annotations

import ctypes
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle.machine import FLAG_DF  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MEM_SIZE = 0x100000
VIDEO_LO = 0xA0000
DGROUP_LINEAR = 0x1C7C0          # LOAD_SEG 0x1000 + DGROUP 0x0C7C, shifted
GUEST_RAM = 0xA0000


def move_leaves_df_set(src_off: int, dst_off: int) -> bool:
    """0AF8:1685 takes the std path when si < di, and does not cld before retf."""
    return (src_off & 0xFFFF) < (dst_off & 0xFFFF)


def range_leaves_ram(seg: int, off: int, count: int, limit: int = VIDEO_LO) -> bool:
    """True when any byte of a rep-string range is outside conventional RAM.

    Offsets wrap at 64 KB inside the segment, the way rep movsb wraps SI/DI.
    A range that would cross into video MMIO is declined so the original runs.
    """
    if count <= 0:
        return False
    off &= 0xFFFF
    seg &= 0xFFFF
    if off + count <= 0x10000:
        start = ((seg << 4) + off) & 0xFFFFF
        end = start + count
        if start >= limit or end > 0x100000:
            return True
        return end > limit
    head = 0x10000 - off
    return (range_leaves_ram(seg, off, head, limit)
            or range_leaves_ram(seg, 0, count - head, limit))

PARAMS = {
    "0AF8:1685": {"name": "System_Move", "ret_bytes": 10, "far": True},
    "0AF8:16A8": {"name": "System_FillChar", "ret_bytes": 8, "far": True},
    "0AF8:11C0": {"name": "System_Random", "ret_bytes": 2, "far": True},
}


def lib_path() -> Path:
    for name in ("libpoolrad_hybrid.dylib", "libpoolrad_hybrid.so"):
        p = ROOT / "build/host" / name
        if p.exists():
            return p
    raise FileNotFoundError("hybrid library not built (run `make hybrid`)")


class HybridLib:
    """The C lift. Fuzz uses the scratch mirror; a session rebinds to guest RAM."""

    def __init__(self, path: Path | None = None):
        self.lib = ctypes.CDLL(str(path or lib_path()))
        lib = self.lib
        lib.pool_hybrid_bind.argtypes = [ctypes.c_char_p, ctypes.c_uint32]
        lib.pool_hybrid_bind.restype = None
        lib.pool_hybrid_set_dgroup.argtypes = [ctypes.c_uint32]
        lib.pool_hybrid_set_dgroup.restype = None
        lib.pool_g_ptr.argtypes = []
        lib.pool_g_ptr.restype = ctypes.c_void_p
        lib.hybrid_System_Move.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint16]
        lib.hybrid_System_Move.restype = None
        lib.hybrid_System_FillChar.argtypes = [ctypes.c_uint32, ctypes.c_uint16, ctypes.c_uint8]
        lib.hybrid_System_FillChar.restype = None
        lib.hybrid_System_Random.argtypes = [ctypes.c_uint16]
        lib.hybrid_System_Random.restype = ctypes.c_uint16
        lib.hybrid_rtl_randomize.argtypes = [ctypes.c_uint8, ctypes.c_uint8, ctypes.c_uint8, ctypes.c_uint8]
        lib.hybrid_rtl_randomize.restype = None
        self.mirror = ctypes.create_string_buffer(MEM_SIZE)
        self._guest_ram = None
        lib.pool_hybrid_set_dgroup(DGROUP_LINEAR)
        lib.pool_hybrid_bind(self.mirror, MEM_SIZE)
        self._stubs = None
        # RandSeed is at offset 0x4428 of G, and G is at DGROUP_LINEAR in the buffer.
        self.g_base = lib.pool_g_ptr()
        self.seed_off = 0x4428

    def bind_guest(self, m) -> None:
        """Point FP() and G at this machine's conventional RAM."""
        from oracle.state import dgroup_seg
        if self._guest_ram is m.ram:
            return
        self.lib.pool_hybrid_set_dgroup((dgroup_seg() << 4) & 0xFFFFF)
        self.lib.pool_hybrid_bind(m.ram, GUEST_RAM)
        self.g_base = self.lib.pool_g_ptr()
        self._guest_ram = m.ram

    def _set_df(self, m, on: bool) -> None:
        fl = m.get("flags")
        m.set("flags", (fl | FLAG_DF) if on else (fl & ~FLAG_DF))

    def _lin(self, seg: int, off: int) -> int:
        return ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF

    def _get(self, addr: int, n: int) -> bytes:
        return bytes(self.mirror[addr:addr + n])

    def _put(self, addr: int, data: bytes) -> None:
        self.mirror[addr:addr + len(data)] = data

    # ------------------------------------------------------------- replacements
    def c_move(self, m) -> bool | None:
        self.bind_guest(m)
        ss, sp = m.get("ss"), m.get("sp")
        count = m.rw(ss, sp + 4)
        dst_off, dst_seg = m.rw(ss, sp + 6), m.rw(ss, sp + 8)
        src_off, src_seg = m.rw(ss, sp + 10), m.rw(ss, sp + 12)
        if (range_leaves_ram(src_seg, src_off, count)
                or range_leaves_ram(dst_seg, dst_off, count)):
            return False
        self.lib.hybrid_System_Move((src_seg << 16) | src_off, (dst_seg << 16) | dst_off, count)
        self._set_df(m, move_leaves_df_set(src_off, dst_off))
        return None

    def c_fill(self, m) -> bool | None:
        self.bind_guest(m)
        ss, sp = m.get("ss"), m.get("sp")
        value = m.rw(ss, sp + 4) & 0xFF
        count = m.rw(ss, sp + 6)
        dst_off, dst_seg = m.rw(ss, sp + 8), m.rw(ss, sp + 10)
        if range_leaves_ram(dst_seg, dst_off, count):
            return False
        self.lib.hybrid_System_FillChar((dst_seg << 16) | dst_off, count, value)
        self._set_df(m, False)
        return None

    def c_random(self, m) -> bool | None:
        from oracle.state import dgroup_seg
        self.bind_guest(m)
        ss, sp = m.get("ss"), m.get("sp")
        ds = dgroup_seg()
        rng = m.rw(ss, sp + 4)
        result = self.lib.hybrid_System_Random(rng)
        new_seed = self._get_seed()
        m.set("ax", result)
        # The guest seed must advance exactly as the original's step would
        # (game code reads RandSeed directly). This write trips the oracle's
        # seed_write hook once; seed_writes are diagnostics, not goldens.
        m.write(ds, 0x4428, new_seed.to_bytes(4, "little"))
        # The oracle logs randomness at the step's ret (rng.py): kind=range
        # with the caller resolved from the FAR return address of the
        # enclosing Random frame (e.g. ovl01:0721), not from inside Random.
        # The C replacement never executes the step, so it logs the entry.
        from oracle.rng import RandomCall
        from oracle.trace import locate, overlay_stubs
        if self._stubs is None:
            self._stubs = overlay_stubs()
        far_ip, far_cs = m.rw(ss, sp), m.rw(ss, sp + 2)
        caller = locate(m, m.linear(far_cs, far_ip), self._stubs)
        m.random_log.append(RandomCall(len(m.random_log), m.now(), "range", caller, rng, new_seed,
                                       (new_seed >> 16) % rng if rng else 0))
        assert result == ((new_seed >> 16) % rng if rng else 0)
        return None

    def _put_seed(self, seed: int) -> None:
        ctypes.c_uint32.from_address(self.g_base + self.seed_off).value = seed & 0xFFFFFFFF

    def _get_seed(self) -> int:
        return ctypes.c_uint32.from_address(self.g_base + self.seed_off).value


def install(prepare_map=None):
    """Prepare callback for run_session: replace the spike routines with C
    (routines.replace; every routine when prepare_map is None, else those in it)."""
    from oracle import routines as _routines
    hyb = HybridLib()
    fns = {"0AF8:1685": hyb.c_move, "0AF8:16A8": hyb.c_fill, "0AF8:11C0": hyb.c_random}

    def prepare(m):
        for rid, fn in fns.items():
            if prepare_map is None or rid in prepare_map:
                p = PARAMS[rid]
                _routines.replace(m, rid, fn, ret_bytes=p["ret_bytes"], far=p["far"])

    prepare.hybrid = hyb
    return prepare

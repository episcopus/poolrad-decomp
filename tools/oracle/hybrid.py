#!/usr/bin/env python3
"""hybrid.py: run the C lift inside the oracle (SPEC 8.4).

Loads build/host/libpoolrad_hybrid (dylib or so) with ctypes, binds a 1 MB
mirror buffer, and provides one replacement per lifted routine with the same
stack layout the original reads:

  System_Move      sp+4 count, sp+6 dst_off, sp+8 dst_seg, sp+10 src_off,
                   sp+12 src_seg (10 param bytes, retf 10)
  System_FillChar  sp+4 value word, sp+6 count, sp+8 dst_off, sp+10 dst_seg
                   (8 param bytes, retf 8)
  System_Random    sp+4 range (2 param bytes, retf 2); seed in G mirrors
                   guest DS:4428 around the call

Video destinations (>= 0xA0000) are declined to the original code, as in the
Python reference (tests/unit/test_exact_time.py). Virtual time comes from
timing.replace with a recorded CostTable, so the run keeps original time.
"""
from __future__ import annotations

import ctypes
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

ROOT = Path(__file__).resolve().parents[2]
MEM_SIZE = 0x100000
VIDEO_LO = 0xA0000

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
    """The C lift with a mirror buffer the C memory macros index."""

    def __init__(self, path: Path | None = None):
        self.lib = ctypes.CDLL(str(path or lib_path()))
        lib = self.lib
        lib.pool_hybrid_bind.argtypes = [ctypes.c_char_p, ctypes.c_uint32]
        lib.pool_hybrid_bind.restype = None
        lib.pool_g_ptr.argtypes = []
        lib.pool_g_ptr.restype = ctypes.c_void_p
        lib.hybrid_System_Move.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint16]
        lib.hybrid_System_Move.restype = None
        lib.hybrid_System_FillChar.argtypes = [ctypes.c_uint32, ctypes.c_uint16, ctypes.c_uint8]
        lib.hybrid_System_FillChar.restype = None
        lib.hybrid_System_Random.argtypes = [ctypes.c_uint16]
        lib.hybrid_System_Random.restype = ctypes.c_uint16
        self.mirror = ctypes.create_string_buffer(MEM_SIZE)
        lib.pool_hybrid_bind(self.mirror, MEM_SIZE)
        self._stubs = None
        # RandSeed is at offset 0x4428 of the DGROUP mirror struct.
        self.g_base = lib.pool_g_ptr()
        self.seed_off = 0x4428

    def _lin(self, seg: int, off: int) -> int:
        return ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF

    def _get(self, addr: int, n: int) -> bytes:
        return bytes(self.mirror[addr:addr + n])

    def _put(self, addr: int, data: bytes) -> None:
        self.mirror[addr:addr + len(data)] = data

    # ------------------------------------------------------------- replacements
    def c_move(self, m) -> bool | None:
        ss, sp = m.get("ss"), m.get("sp")
        count = m.rw(ss, sp + 4)
        dst_off, dst_seg = m.rw(ss, sp + 6), m.rw(ss, sp + 8)
        src_off, src_seg = m.rw(ss, sp + 10), m.rw(ss, sp + 12)
        s, d = self._lin(src_seg, src_off), self._lin(dst_seg, dst_off)
        if d + count >= VIDEO_LO or s + count > MEM_SIZE or d + count > MEM_SIZE:
            return False
        self._put(s, m.read(src_seg, src_off, count))
        self.lib.hybrid_System_Move((src_seg << 16) | src_off, (dst_seg << 16) | dst_off, count)
        m.write(dst_seg, dst_off, self._get(d, count))
        return None

    def c_fill(self, m) -> bool | None:
        ss, sp = m.get("ss"), m.get("sp")
        value = m.rw(ss, sp + 4) & 0xFF
        count = m.rw(ss, sp + 6)
        dst_off, dst_seg = m.rw(ss, sp + 8), m.rw(ss, sp + 10)
        d = self._lin(dst_seg, dst_off)
        if d + count >= VIDEO_LO or d + count > MEM_SIZE:
            return False
        self.lib.hybrid_System_FillChar((dst_seg << 16) | dst_off, count, value)
        m.write(dst_seg, dst_off, self._get(d, count))
        return None

    def c_random(self, m) -> bool | None:
        from oracle.state import dgroup_seg
        ss, sp = m.get("ss"), m.get("sp")
        ds = dgroup_seg()
        rng = m.rw(ss, sp + 4)
        seed = m.read(ds, 0x4428, 4)
        self._put_seed(int.from_bytes(seed, "little"))
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


def install(prepare_map: dict | None = None):
    """Prepare callback for run_session: replace the spike routines with C.

    Uses plain hook costs (1 instruction each); for exact-time runs pass a
    CostTable via sessions.py instead.
    """
    from oracle import timing as _timing
    hyb = HybridLib()
    fns = {"0AF8:1685": hyb.c_move, "0AF8:16A8": hyb.c_fill, "0AF8:11C0": hyb.c_random}

    def prepare(m):
        for rid, fn in fns.items():
            if prepare_map is None or rid in prepare_map:
                p = PARAMS[rid]
                m.hook_routine(int(rid.split(":")[0], 16), int(rid.split(":")[1], 16),
                               fn, ret_bytes=p["ret_bytes"], far=p["far"], cost=1)

    prepare.hybrid = hyb
    return prepare

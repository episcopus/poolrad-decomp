"""rng.py: a log of every call to Turbo Pascal's pseudo-random generator (SPEC 8.3, 8.5).

The generator is `System` code, byte-matched to TP 6.0 (whitepaper 2.2, `0AF8:120F`):

    seed' = seed * 08088405h + 1           (32 bits, RandSeed at DS:4428, low word first)
    Random(range)  = hi16(seed') mod range  (0 when range is 0; this is TP 6, not TP 7's multiply-shift)
    Random (real)  = hi16(seed') scaled to [0,1) by `0AF8:11D6`

`Randomize` (`0AF8:1247`) is `INT 21h AH=2Ch` followed by RandSeed := DX:CX. There is no other source of
entropy, so the sequence of `(kind, range, result)` below is, with the seed, a complete description of
every random decision the game made. Two runs that disagree anywhere disagree there first.

The log is taken at the one place every consumer passes through (the generator step), so it also sees
callers we have not identified. Direct writes to RandSeed by game code are logged separately.
"""
from __future__ import annotations

import hashlib
from collections import namedtuple

from unicorn import UC_HOOK_MEM_WRITE

from .machine import LOAD_SEG

STEP_RET = (0x0AF8 + LOAD_SEG, 0x1244)     # the `ret` of the generator step; RandSeed already updated (original)
NEAR_RET_RANGE = 0x11C3                    # step called from Random(range)
NEAR_RET_REAL = 0x11D9                     # step called from Random (real)
RANDSEED = 0x4428
STEP_BODY = range(0x120F, 0x1245)          # writes from here are the generator itself

RandomCall = namedtuple("RandomCall", "index time kind caller range seed result")
SeedWrite = namedtuple("SeedWrite", "time where value")


def install_random_log(m) -> None:
    from . import layout
    from .trace import locate, overlay_stubs
    lay = layout.current()
    step_ret = (lay.system_para + LOAD_SEG, STEP_RET[1])    # System code is the same in every build
    randseed = lay.randseed
    ds_seg = lay.dgroup_para + LOAD_SEG
    m.random_log = []
    m.seed_writes = []
    stubs = overlay_stubs()

    def on_step(mach):
        seed = (mach.rw(ds_seg, randseed + 2) << 16) | mach.rw(ds_seg, randseed)
        ss, sp = mach.get("ss"), mach.get("sp")
        near, ip, cs = mach.rw(ss, sp), mach.rw(ss, sp + 2), mach.rw(ss, sp + 4)
        if near == NEAR_RET_RANGE:
            kind, rng = "range", mach.rw(ss, sp + 6)
            result = (seed >> 16) % rng if rng else 0
        elif near == NEAR_RET_REAL:
            kind, rng, result = "real", None, seed >> 16
        else:
            kind, rng, result = "step", None, seed >> 16
        caller = locate(mach, mach.linear(cs, ip), stubs)
        mach.random_log.append(RandomCall(len(mach.random_log), mach.now(), kind, caller, rng, seed, result))

    def on_seed_write(uc, access, addr, size, value, _ud):
        ip = m.get("ip")
        if m.get("cs") == step_ret[0] and ip in STEP_BODY:
            return
        where = locate(m, m.linear(m.get("cs"), ip), stubs)
        m.seed_writes.append(SeedWrite(m.now(), where, value))

    m.add_breakpoint(step_ret[0], step_ret[1], on_step)
    lo = ds_seg * 16 + randseed
    m.uc.hook_add(UC_HOOK_MEM_WRITE, on_seed_write, begin=lo, end=lo + 3)


def sequence_digest(log) -> str:
    """Digest of what the game decided, not when: (kind, caller, range, result) per call. Time is left
    out on purpose so a hybrid run with different timing can be compared with the original."""
    h = hashlib.sha256()
    for c in log:
        h.update(("%s %s %s %s\n" % (c.kind, c.caller, c.range, c.result)).encode())
    return h.hexdigest()


def format_log(log) -> str:
    return "".join("%6d %10d %-5s %-14s range=%-5s seed=%08X result=%d\n" % (
        c.index, c.time, c.kind, c.caller, c.range, c.seed, c.result) for c in log)

"""protection.py: lets a key script pass the game's copy protection (the code wheel, whitepaper 5.12).

The check lives in ovl02 (`ovl02:00FD`): up to three times it asks a question chosen with
`Random(13)`, then compares the typed word with a Pascal string in DGROUP at `DS:r*21+2` using
`System_StrCompare` (0AF8:0C10). The harness watches that `Random(13)` call (System_Random,
0AF8:11C0, called from the ovl02 stub's load segment) and records the answer from the game's own
table, so the `wheel` script command can type the right word whatever the virtual-time seed gave.

Nothing in the original code path is altered: the program still runs its own prompt and comparison.
"""
from __future__ import annotations

from .machine import LOAD_SEG

RANDOM = (0x0AF8 + LOAD_SEG, 0x11C0)      # System_Random(range: Word): Word (original)
OVL02_STUB = 0x001C + LOAD_SEG            # overlay 2 stub segment (appendix A); LoadSeg at +10h (original)
RECORD = 21


def install_wheel_solver(m) -> None:
    from . import layout
    lay = layout.current()
    random = (lay.system_para + LOAD_SEG, RANDOM[1])
    ovl02_stub = (lay.stubs["ovl02"] + LOAD_SEG) if lay.stubs else OVL02_STUB
    table = lay.wheel_table
    m.wheel_answer = None
    m.wheel_log = []
    seen_returns: set[tuple[int, int]] = set()

    def on_return(mach):
        ax = mach.get("ax")
        if ax >= 13:
            return
        n = mach.rb(mach.get("ds"), table + ax * RECORD + 2)
        word = mach.read(mach.get("ds"), table + ax * RECORD + 3, n).decode("ascii")
        mach.wheel_answer = word
        mach.wheel_log.append((mach.now(), ax, word))

    def on_random(mach):
        ss, sp = mach.get("ss"), mach.get("sp")
        ip, cs, arg = mach.rw(ss, sp), mach.rw(ss, sp + 2), mach.rw(ss, sp + 4)
        if arg != 13 or cs != mach.rw(ovl02_stub, 0x10):
            return
        if (cs, ip) not in seen_returns:
            seen_returns.add((cs, ip))
            mach.add_breakpoint(cs, ip, on_return)

    m.add_breakpoint(random[0], random[1], on_random)

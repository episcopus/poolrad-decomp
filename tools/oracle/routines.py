#!/usr/bin/env python3
"""routines.py: routines of re/symbols.toml at their runtime addresses (SPEC 8.4).

Resident code stays where the loader put it; overlay code moves, so an overlay routine's address is
read from its stub's load segment again after every read of GAME.OVR (`Machine.overlay_listeners`).

  replace(m, id, fn, ret_bytes=, far=)   run `fn` instead of the routine (hybrid execution; the C lift
                                         in the C translation, branch track-c-hybrid). Time is not charged: session
                                         replays answer the game's reads of the outside world from a
                                         recording (replay.py), so no clock depends on the instructions
                                         a routine executes.
  Profiler(m, ids)                       instructions each call of the routines executed in its own code
                                         (an analysis aid for tools/re/timing_scan.py; a Python hook on
                                         every instruction, about 2.5 million per second)
"""
from __future__ import annotations

from array import array

from oracle.machine import LOAD_SEG  # noqa: E402
from oracle.trace import OVL_LOADSEG_OFF, load_symbols, overlay_stubs  # noqa: E402

RET_OPCODES = (0xC2, 0xC3, 0xCA, 0xCB)


class Routine:
    """A routine of re/symbols.toml: unit, offset in the unit's segment and size."""
    __slots__ = ("id", "name", "unit", "seg", "off", "size")

    def __init__(self, r: dict):
        self.id, self.name, self.unit = r["id"], r.get("name", r["id"]), r["unit"]
        seg, off = r["addr"].split(":")
        self.off, self.size = int(off, 16), int(r["size"])
        self.seg = int(seg, 16) if self.unit.startswith("res") else None


def find_routines(ids) -> list[Routine]:
    """Routine ids or names of re/symbols.toml, or `Routine` objects (tests build their own)."""
    routines, _units = load_symbols()
    by_id = {r["id"]: r for r in routines}
    by_name = {r.get("name"): r for r in routines}
    out = []
    for i in ids:
        if isinstance(i, Routine):
            out.append(i)
            continue
        r = by_id.get(i) or by_name.get(i)
        if r is None:
            raise KeyError("no routine %r in re/symbols.toml" % i)
        out.append(Routine(r))
    return out


class Binder:
    """Keeps the runtime linear address of each routine current and tells its users when it moves."""

    def __init__(self, m):
        self.m = m
        self.routines: list[Routine] = []
        self.stubs = overlay_stubs()
        self.listeners = []                        # callables([(routine, linear address or None)])
        m.overlay_listeners.append(lambda _m: self.rebind())

    def address(self, r: Routine) -> int | None:
        if r.seg is not None:
            return ((r.seg + LOAD_SEG) << 4) + r.off
        stub = self.stubs.get(r.unit)
        seg = self.m.rw(stub, OVL_LOADSEG_OFF) if stub else 0
        return ((seg << 4) + r.off) if seg else None

    def rebind(self) -> None:
        bound = [(r, self.address(r)) for r in self.routines]
        for cb in self.listeners:
            cb(bound)


def binder_of(m) -> Binder:
    b = getattr(m, "_binder", None)
    if b is None:
        b = m._binder = Binder(m)
    return b


def replace(m, routine_id, fn, *, ret_bytes: int = 0, far: bool = True) -> Routine:
    """Replace one routine: `fn(machine)` runs at its entry and applies its effect, then the machine
    returns to the caller (`retf ret_bytes`, or `ret` when far is False); `fn` may return False to leave
    the call to the original code. An overlay routine is hooked wherever its unit is loaded."""
    (r,) = find_routines([routine_id])
    b = binder_of(m)
    handle = [None, None]                          # (hook handle, linear address)

    def on_move(bound):
        for rr, a in bound:
            if rr is not r or a == handle[1]:
                continue
            if handle[0] is not None:
                m.unhook(handle[0])
            handle[0] = m.hook_linear(a, fn, ret_bytes=ret_bytes, far=far) if a is not None else None
            handle[1] = a
    b.routines.append(r)
    b.listeners.append(on_move)
    b.rebind()
    return r


class Profiler:
    """Observes a run and records, per call of each routine, the instructions executed in the routine's
    own code (every address inside it, up to and including the return). Callees and interrupt handlers
    count for themselves; a call entered by a jump into the middle is not a call."""

    def __init__(self, m, routine_ids):
        from unicorn import UC_HOOK_CODE
        self.m = m
        self.routines = find_routines(routine_ids)
        self.rows: dict[str, list[int]] = {r.id: [] for r in self.routines}
        self._index = {r.id: i + 1 for i, r in enumerate(self.routines)}     # 0 means "not ours"
        self._stacks = [None] + [[] for _ in self.routines]                  # open frames per routine
        self._owner = array("H", bytes(2 * 0xA0000))
        self._entry: dict[int, int] = {}
        self._is_ret: dict[int, bool] = {}
        b = binder_of(m)
        b.routines.extend(self.routines)
        b.listeners.append(self._rebind)
        b.rebind()
        m.uc.hook_add(UC_HOOK_CODE, self._observe)

    def _rebind(self, bound) -> None:
        self._owner = array("H", bytes(2 * 0xA0000))
        self._entry.clear()
        self._is_ret.clear()
        for r, a in bound:
            idx = self._index.get(r.id)
            if idx is None or a is None:
                continue
            self._owner[a:a + r.size] = array("H", [idx]) * r.size
            self._entry[a] = idx

    def _observe(self, uc, addr, size, _ud) -> None:
        if addr >= 0xA0000:
            return
        idx = self._owner[addr]
        if not idx:
            return
        st = self._stacks[idx]
        if self._entry.get(addr) == idx:
            st.append(0)
        if not st:
            return
        st[-1] += 1
        ret = self._is_ret.get(addr)
        if ret is None:
            ret = self._is_ret[addr] = uc.mem_read(addr, 1)[0] in RET_OPCODES
        if ret:
            self.rows[self.routines[idx - 1].id].append(st.pop())

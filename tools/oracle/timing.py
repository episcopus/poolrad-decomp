#!/usr/bin/env python3
"""timing.py: exact time for hybrid runs (SPEC 8.4, whitepaper appendix C).

Virtual time is the executed-instruction count, and a routine replaced by C or Python executes none of
the instructions the original did, so a plain hybrid run places timer ticks (and everything derived from
them) at other program points than the original. This module fixes that without masks:

  record   run the original once and note, for every call of the chosen routines, the exact time it was
           entered and how many instructions it executed in its own code (callees and interrupt
           handlers are not part of it: they run for real in the hybrid run too);
  replace  in a hybrid run, install the replacement and charge those instructions at the call, in the
           chunk structure the original had (a timer tick inside the routine is delivered at the
           routine's entry, at its original time, and the routine then resumes).

Needs `Machine(exact=True)` (`run.build_machine(..., exact=True)`). The first call of a replaced routine
is checked against the recording: if the time is not the recorded one the run has diverged and
OracleError says which call.

Limits **[V]** (tests/unit/test_exact_time.py, whitepaper appendix C):
  * the replacement's effect is applied at the routine's entry, so an interrupt handler that runs while
    the original was in the middle of the routine sees the finished routine; routines whose state a timer
    handler reads or writes need the C code to say so (not needed for System_Move);
  * the interrupt frame is pushed at the routine's entry stack depth, not at the depth the original had
    mid-routine, so bytes below SP (dead stack) differ from the original;
  * a script checkpoint (`shot`, `digest`) that falls inside a replaced routine sees its finished state.

  .venv/bin/python tools/oracle/timing.py record --session NAME --routine ID [--routine ID ...] --out FILE
  .venv/bin/python tools/oracle/timing.py info FILE
"""
from __future__ import annotations

import argparse
import json
import sys
from array import array
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle.machine import LOAD_SEG, ROOT, OracleError  # noqa: E402
from oracle.trace import OVL_LOADSEG_OFF, load_symbols, overlay_stubs  # noqa: E402

RET_OPCODES = (0xC2, 0xC3, 0xCA, 0xCB)
FORMAT = 1
STUB_LO, STUB_HI = 0xF1000, 0xF1000 + 256 * 4


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
    """Keeps the runtime linear address of each routine current: resident code is fixed, overlay code
    moves, so addresses are resolved again after every read of GAME.OVR."""

    def __init__(self, m):
        if not m.exact:
            raise OracleError("exact time needs Machine(exact=True) (run.build_machine(..., exact=True))")
        self.m = m
        self.items: list[tuple[Routine, object]] = []     # (routine, payload)
        self.stubs = overlay_stubs()
        self.rebind_cbs = []
        m.overlay_listeners.append(self.rebind)

    def add(self, routine: Routine, payload, rebind: bool = True) -> None:
        self.items.append((routine, payload))
        if rebind:
            self.rebind(self.m)

    def address(self, r: Routine) -> int | None:
        if r.seg is not None:
            return ((r.seg + LOAD_SEG) << 4) + r.off
        stub = self.stubs.get(r.unit)
        seg = self.m.rw(stub, OVL_LOADSEG_OFF) if stub else 0
        return ((seg << 4) + r.off) if seg else None

    def rebind(self, m) -> None:
        m._repl_at.clear()
        bound = []
        for r, payload in self.items:
            a = self.address(r)
            if a is not None:
                bound.append((r, payload, a))
        for cb in self.rebind_cbs:
            cb(bound)
        for r, payload, a in bound:
            if isinstance(payload, Replacement):
                m._repl_at[a] = payload


def binder_of(m) -> Binder:
    b = getattr(m, "_binder", None)
    if b is None:
        b = m._binder = Binder(m)
    return b


class Replacement:
    """What the machine needs to dispatch a replaced routine (machine._dispatch)."""
    __slots__ = ("name", "fn", "ret_bytes", "far", "cost", "rows", "calls", "windows")

    def __init__(self, name, fn, ret_bytes, far, cost, rows):
        self.name, self.fn, self.ret_bytes, self.far, self.cost, self.rows = name, fn, ret_bytes, far, cost, rows
        self.calls = 0
        self.windows: dict[int, list] = {}


def replace(m, routine_id, fn, *, ret_bytes: int = 0, far: bool = True, table: "CostTable | None" = None,
            cost=0) -> Replacement:
    """Replace one routine (hybrid execution). `fn(machine)` is called once at the routine's entry and
    applies its effect; it may return False to leave the call to the original code. With `table` the time
    is the recorded one, else `1 + cost` instructions (an int or callable(machine))."""
    (r,) = find_routines([routine_id])
    rows = None
    if table is not None:
        if r.id not in table.rows:
            raise KeyError("%s has no recorded costs in this table" % r.id)
        rows = table.rows[r.id]
    rep = Replacement(r.id, fn, ret_bytes, far, cost, rows)
    binder_of(m).add(r, rep)
    return rep


class CostTable:
    def __init__(self, rows: dict[str, list], meta: dict | None = None):
        self.rows = rows                 # routine id -> [[time at entry, instructions in own code, extra], ...]
        self.meta = meta or {}

    def save(self, path) -> None:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_text(json.dumps({"format": FORMAT, "meta": self.meta, "routines": self.rows},
                                         separators=(",", ":")) + "\n")

    @classmethod
    def load(cls, path) -> "CostTable":
        d = json.loads(Path(path).read_text())
        if d.get("format") != FORMAT:
            raise ValueError("%s: unknown cost table format %r" % (path, d.get("format")))
        return cls(d["routines"], d.get("meta"))


class CostRecorder:
    """Observes an original run and records, per call of each routine: the exact time of its first
    instruction, the instructions executed in the routine's own code (every address inside it, up to
    and including the return), and the time charged by services called from it (`extra`: port polls,
    INT 15h waits)."""

    def __init__(self, m, routine_ids):
        self.m = m
        self.routines = find_routines(routine_ids)
        self.rows: dict[str, list] = {r.id: [] for r in self.routines}
        self.unattributed_extra = 0
        self._index = {r.id: i + 1 for i, r in enumerate(self.routines)}     # 0 means "not ours"
        self._stacks = [None] + [[] for _ in self.routines]                  # open frames per routine
        self._owner = array("H", bytes(2 * 0xA0000))
        self._entry: dict[int, int] = {}
        self._is_ret: dict[int, bool] = {}
        self._last_extra = m.extra
        self._prev = 0
        b = binder_of(m)
        b.rebind_cbs.append(self._rebind)
        for r in self.routines:
            b.add(r, None, rebind=False)
        b.rebind(m)
        m._observer = self._observe

    def _rebind(self, bound) -> None:
        self._owner = array("H", bytes(2 * 0xA0000))
        self._entry.clear()
        self._is_ret.clear()
        for r, _payload, a in bound:
            idx = self._index.get(r.id)
            if idx is None:
                continue
            self._owner[a:a + r.size] = array("H", [idx]) * r.size
            self._entry[a] = idx

    def _observe(self, m, addr: int) -> None:
        d = m.extra - self._last_extra
        if d:
            self._last_extra = m.extra
            st = self._stacks[self._prev] if self._prev else None
            if st:
                st[-1][2] += d
            else:
                self.unattributed_extra += d
        if addr >= 0xA0000:
            if not (STUB_LO <= addr < STUB_HI):      # service stubs continue the caller's attribution
                self._prev = 0
            return
        idx = self._owner[addr]
        self._prev = idx
        if not idx:
            return
        st = self._stacks[idx]
        if self._entry.get(addr) == idx:
            st.append([m.exact_now(), 0, 0])
        if not st:
            return                                    # entered by a jump into the middle: not a call
        st[-1][1] += 1
        ret = self._is_ret.get(addr)
        if ret is None:
            ret = self._is_ret[addr] = m.uc.mem_read(addr, 1)[0] in RET_OPCODES
        if ret:
            t, n, e = st.pop()
            self.rows[self.routines[idx - 1].id].append([t, n, e])

    def table(self, meta: dict | None = None) -> CostTable:
        return CostTable({k: [list(r) for r in v] for k, v in self.rows.items()}, meta)


def record(script_text: str, routine_ids, *, max_insns: int = 400_000_000, out=None) -> CostTable:
    """Run a session on the original code (exact mode) and return the cost table of the routines."""
    from oracle.run import run_session
    holder = {}

    def prepare(m):
        holder["rec"] = CostRecorder(m, routine_ids)

    s = run_session(script_text, max_insns=max_insns, quiet=True, exact=True, prepare=prepare)
    rec = holder["rec"]
    open_frames = {r.id: len(rec._stacks[i + 1]) for i, r in enumerate(rec.routines) if rec._stacks[i + 1]}
    table = rec.table({"instructions": s["insns"], "stop_reason": s["reason"],
                       "open_frames_at_end": open_frames, "unattributed_extra": rec.unattributed_extra})
    if out:
        table.save(out)
    return table


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("record", help="record routine costs from the original in the oracle")
    r.add_argument("--session", required=True, help="tests/sessions/NAME.keys")
    r.add_argument("--routine", action="append", required=True, help="routine id or name (re/symbols.toml)")
    r.add_argument("--out", required=True)
    i = sub.add_parser("info", help="summarise a cost table")
    i.add_argument("file")
    a = ap.parse_args(argv)
    if a.cmd == "record":
        text = (ROOT / "tests/sessions" / (a.session + ".keys")).read_text()
        t = record(text, a.routine, out=a.out)
        for k, rows in t.rows.items():
            print("%s: %d calls, %d instructions in own code, %d extra" % (
                k, len(rows), sum(x[1] for x in rows), sum(x[2] for x in rows)))
        print("wrote", a.out)
        return 0
    t = CostTable.load(a.file)
    for k, rows in t.rows.items():
        print("%s: %d calls, %d instructions, %d extra" % (k, len(rows), sum(x[1] for x in rows), sum(x[2] for x in rows)))
    print(t.meta)
    return 0


if __name__ == "__main__":
    sys.exit(main())

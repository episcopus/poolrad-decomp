#!/usr/bin/env python3
"""prof.py: where a session's time goes on the target machine, an 8088 at 7.16 MHz (Tandy 1000 EX).

  .venv/bin/python ports/dos/tools/prof.py [--build game|ref] [--session NAME ...] [--jobs N]
  .venv/bin/python ports/dos/tools/prof.py --report [--build game] [--session NAME] [--top 40]
  .venv/bin/python ports/dos/tools/prof.py --diff ref game [--session NAME]

Plays the session the way func.py does (Tandy video and sound, the program's clock) and charges every executed
basic block an estimated 8088 cost. The 8088 has an 8-bit bus and a 4-byte prefetch queue: nearly every
instruction waits for its bytes, so an instruction costs about the larger of its 8086 execution time (plus 4
clocks for every word it moves over the bus, which the 8088 moves a byte at a time) and 4 clocks for each byte of
the instruction and of the data it reads or writes. A REP string instruction is charged per repetition. The
model is not exact (no wait states, no queue state, branches taken half the time); it is meant to rank routines
and to show how much a change saves, never to predict a frame rate to the millisecond.

Recorded per session (build/prof/<build>/<session>.pkl):
  per routine    cycles spent in the routine itself and the number of times it was entered
  per action     cycles between two key reads (what a key press costs until the game asks for the next key),
                 and the cycles of the waits inside (keyboard polls, Delay, the time of day waits), which are
                 the game doing nothing on purpose and are kept apart
Routine names are the link map's (the port's own build), so a patched routine is found under its name.
"""
from __future__ import annotations

import argparse
import bisect
import pickle
import sys
import time
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import func  # noqa: E402

PORT = func.PORT
OUT = PORT / "build/prof"
MHZ = 7.16

# waits: Crt's Delay is a counted loop calibrated against the clock, the game waiting on purpose
WAIT_ROUTINES = {"CRT.Crt_Delay", "CRT.Crt_DelayTick"}
WAIT_SPAN = 20_000         # a stretch between two polls or clock reads shorter than this, with no video write, waits
RUNTIME = {"SYSTEM": "0AF8", "CRT": "0A40", "DOS": "0A32", "OVERLAY": "0AA2"}   # library units: names from re/symbols.toml

# --------------------------------------------------------------------------------------------- cost model
# 8086 execution clocks by instruction form (Intel 8086 manual, Table 2-21); EA adds its own below
ALU = {"add", "adc", "sub", "sbb", "and", "or", "xor", "cmp", "test"}
SHIFTS = {"shl", "sal", "shr", "sar", "rol", "ror", "rcl", "rcr"}
JCC = {"jo", "jno", "jb", "jae", "je", "jne", "jbe", "ja", "js", "jns", "jp", "jnp", "jl", "jge", "jle", "jg",
       "jcxz"}
STRING = {  # per repetition under REP (8086), single execution, bytes moved per execution
    "movsb": (17, 18, 2), "movsw": (17, 18, 4), "stosb": (10, 11, 1), "stosw": (10, 11, 2),
    "lodsb": (13, 12, 1), "lodsw": (13, 12, 2), "cmpsb": (22, 22, 2), "cmpsw": (22, 22, 4),
    "scasb": (15, 15, 1), "scasw": (15, 15, 2),
}


def ea_clocks(op) -> int:
    m = op.mem
    base, index, disp = m.base != 0, m.index != 0, m.disp != 0
    if not base and not index:
        return 6
    c = 5 if (base != index) else 7
    return c + (4 if disp else 0)


def insn_cost(insn) -> int:
    from capstone import x86
    mn = insn.mnemonic
    rep = insn.prefix[0] in (0xF3, 0xF2)
    if mn.startswith("rep"):
        rep = True
        mn = mn.split()[-1]
    if mn in STRING:
        per_rep, single, nbytes = STRING[mn]
        words = nbytes // 2 if mn.endswith("w") else 0
        return (per_rep if rep else single) + 4 * words      # 8088: a word is two bus cycles
    ops = insn.operands
    mem = [o for o in ops if o.type == x86.X86_OP_MEM]
    size = max((o.size for o in ops), default=1)
    word = size >= 2
    ea = ea_clocks(mem[0]) if mem and mn != "lea" else 0
    if mn == "lea":
        ea = ea_clocks(mem[0]) if mem else 0
    nm = len(mem)
    if mn == "mov":
        if nm:
            base = 10 if ops[0].type == x86.X86_OP_MEM else 8
            if ops[0].type == x86.X86_OP_MEM and ops[1].type == x86.X86_OP_IMM:
                base = 10
        elif any(o.type == x86.X86_OP_REG and o.reg in (x86.X86_REG_DS, x86.X86_REG_ES, x86.X86_REG_SS) for o in ops):
            base = 2
        else:
            base = 4 if ops[1].type == x86.X86_OP_IMM else 2
    elif mn in ALU:
        if nm:
            base = 16 if (ops[0].type == x86.X86_OP_MEM and mn not in ("cmp", "test")) else 9
            if ops[0].type == x86.X86_OP_MEM and ops[-1].type == x86.X86_OP_IMM:
                base = 17 if mn not in ("cmp", "test") else 10
        else:
            base = 4 if ops[-1].type == x86.X86_OP_IMM else 3
    elif mn in ("inc", "dec", "neg", "not"):
        base = 15 if nm else (2 if word else 3)
    elif mn in SHIFTS:
        cl = len(ops) > 1 and ops[1].type == x86.X86_OP_REG
        base = (20 if nm else 8) + (8 if cl else 0) if cl else (15 if nm else 2)
    elif mn in ("push", "pop"):
        base = (16 if mn == "push" else 17) if nm else (11 if mn == "push" else 8)
        word = True
    elif mn in ("pushf", "popf"):
        base, word = 10, True
    elif mn == "call":
        far = insn.size >= 5 or (nm and ops[0].size == 4)
        base = (28 if far else 19) + (8 if nm else 0)
        word = True
    elif mn in ("ret", "retf"):
        base = 18 if mn == "retf" else 8
        word = True
    elif mn == "iret":
        base = 24
    elif mn == "int":
        base = 51
    elif mn in ("jmp", "ljmp"):
        base = 15 if not nm else 18
    elif mn in JCC:
        base = 10                                               # taken 16, not taken 4: half and half
    elif mn in ("loop", "loope", "loopne"):
        base = 11
    elif mn in ("mul", "imul"):
        base = (133 if word else 77) + (6 if nm else 0)
    elif mn in ("div", "idiv"):
        base = (162 if word else 90) + (6 if nm else 0)
    elif mn in ("les", "lds"):
        base, word = 16, True
    elif mn in ("xchg",):
        base = 17 if nm else 4
    elif mn in ("in", "out"):
        base = 10
    elif mn in ("cbw", "cwd", "clc", "stc", "cld", "std", "cli", "sti", "nop", "cmc", "lahf", "sahf", "xlatb"):
        base = 2 if mn != "cwd" else 5
        if mn == "xlatb":
            base = 11
    else:
        base = 8
    # bus: every memory operand moves its bytes; the 8088 moves one byte per 4-clock bus cycle
    membytes = 0
    for o in mem:
        n = o.size if o.size else (2 if word else 1)
        rw = (1 if o.access & 1 else 0) + (1 if o.access & 2 else 0)
        membytes += n * max(1, rw)
    if mn in ("push", "pop", "call", "ret", "retf", "pushf", "popf"):
        membytes += 2 if mn != "call" or insn.size < 5 else 4
    if mn == "retf" or mn == "iret":
        membytes += 2 if mn == "retf" else 4
    eu = base + ea + (4 * (membytes // 2) if word else 0)
    bus = 4 * (insn.size + membytes)
    return max(eu, bus)


class Costs:
    """Cost and routine of each basic block, cached by address; the overlay buffer's cache is dropped whenever
    an overlay is read in (other code at the same addresses)."""

    def __init__(self, m, pubs: dict, segs: dict):
        from capstone import Cs, CS_ARCH_X86, CS_MODE_16
        from oracle.machine import LOAD_SEG
        self.m = m
        self.md = Cs(CS_ARCH_X86, CS_MODE_16)
        self.md.detail = True
        self.load = LOAD_SEG * 16
        self.resident = {}                    # linear -> (routine, cycles)
        self.overlay = {}
        # code segments: (start linear, end linear, unit) for resident units; overlay stubs by unit
        by_para = {}
        self.ranges = []
        self.stubs = {}
        for name, (start, size, cls) in segs.items():
            by_para[start >> 4] = name
            if cls != "CODE":
                continue
            if name.startswith("OVL"):
                self.stubs[name] = LOAD_SEG + (start >> 4)
            else:
                self.ranges.append((self.load + start, self.load + start + size, name))
        self.ranges.sort()
        self.starts = [r[0] for r in self.ranges]
        self.publics = defaultdict(list)       # unit -> sorted [(offset, name)]
        for name, (para, off) in pubs.items():
            unit = by_para.get(para)
            if unit:
                self.publics[unit].append((off, name))
        for v in self.publics.values():
            v.sort()
        import tomllib
        reg = tomllib.loads((func.ROOT / "re/symbols.toml").read_text())["routine"]
        for unit, seg in RUNTIME.items():
            self.publics[unit] = sorted((int(r["addr"][5:], 16), r["name"]) for r in reg if r["addr"].startswith(seg + ":"))
        self.pub_offs = {u: [o for o, _n in v] for u, v in self.publics.items()}
        m.overlay_listeners.append(lambda _m: self.overlay.clear())

    def routine(self, linear: int) -> tuple[str, bool]:
        """(UNIT.ROUTINE or UNIT+offset, in an overlay?)"""
        m = self.m
        for unit, stub in self.stubs.items():
            loadseg = m.rw(stub, 0x10)
            if loadseg and loadseg * 16 <= linear < loadseg * 16 + m.rw(stub, 0x08):
                return self._name(unit, linear - loadseg * 16), True
        i = bisect.bisect_right(self.starts, linear) - 1
        if i >= 0 and linear < self.ranges[i][1]:
            unit = self.ranges[i][2]
            return self._name(unit, linear - self.ranges[i][0]), False
        return "?%05X" % (linear - self.load), False

    def _name(self, unit: str, off: int) -> str:
        offs = self.pub_offs.get(unit)
        if offs:
            j = bisect.bisect_right(offs, off) - 1
            if j >= 0:
                return "%s.%s" % (unit, self.publics[unit][j][1])
        return "%s+%04X" % (unit, off)

    def block(self, addr: int, size: int) -> tuple[str, int]:
        hit = self.resident.get(addr) or self.overlay.get(addr)
        if hit is not None and hit[2] == size:
            return hit[0], hit[1]
        name, in_ovl = self.routine(addr)
        code = bytes(self.m.uc.mem_read(addr, size))
        cyc = 0
        for insn in self.md.disasm(code, addr & 0xFFFF):
            cyc += insn_cost(insn)
        (self.overlay if in_ovl else self.resident)[addr] = (name, cyc, size)
        return name, cyc


def profile(build: str, session: str) -> dict:
    from unicorn import UC_HOOK_BLOCK
    from oracle.machine import Stop
    m, script, pubs, segs, _ds = func.setup(build, session)
    costs = Costs(m, pubs, segs)
    per = defaultdict(lambda: [0, 0])          # routine -> [cycles of work, cycles of waiting]
    state = {"cyc": 0, "wait": 0, "writes": 0}
    cur = defaultdict(int)                     # cycles per routine since the last poll or clock read
    span = [0]
    act = defaultdict(int)                     # cycles of work per routine in the current action
    actions = []                               # (label, cycles of work, cycles of waiting)
    mark = {"cyc": 0, "wait": 0, "label": "start"}

    def on_block(uc, addr, size, _ud):
        name, cyc = costs.block(addr, size)
        state["cyc"] += cyc
        if name in WAIT_ROUTINES:
            state["wait"] += cyc
            per[name][1] += cyc
            return
        cur[name] += cyc
        span[0] += cyc

    def settle():
        """A poll or a clock read: the stretch since the last one was waiting if it was short and drew nothing."""
        w = m.ega.writes
        waited = span[0] < WAIT_SPAN and w == state["writes"]
        state["writes"] = w
        for name, cyc in cur.items():
            per[name][1 if waited else 0] += cyc
            if not waited:
                act[name] += cyc
        if waited:
            state["wait"] += span[0]
        cur.clear()
        span[0] = 0

    m.uc.hook_add(UC_HOOK_BLOCK, on_block)
    m.wait_listeners.append(settle)

    def close(label):
        settle()
        work = state["cyc"] - mark["cyc"] - (state["wait"] - mark["wait"])
        top = dict(sorted(act.items(), key=lambda kv: -kv[1])[:40])
        actions.append((mark["label"], work, state["wait"] - mark["wait"], top))
        act.clear()
        mark.update(cyc=state["cyc"], wait=state["wait"], label=label)

    def on_key(mach, k):
        close("key %d %s" % (mach.bios.key_reads, keyname(k)))
    m.on_key_read = on_key

    def on_op(op, mach):
        kind, arg = op
        if kind == "quit":
            raise Stop("quit")
    script.on_op = on_op
    t0 = time.time()
    try:
        reason = m.run(3_000_000_000)
    except Exception as e:
        reason = "error %s" % e
    close("end")
    res = {"build": build, "session": session, "reason": reason, "cycles": state["cyc"], "wait": state["wait"],
           "routines": {k: tuple(v) for k, v in per.items()}, "actions": actions, "seconds": time.time() - t0,
           "insns": m.insns}
    out = OUT / build / (session + ".pkl")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(pickle.dumps(res))
    return res


def keyname(k: int) -> str:
    from oracle.keys import NAMED
    for n, v in NAMED.items():
        if v == k:
            return n
    c = k & 0xFF
    return repr(chr(c)) if 32 <= c < 127 else "%04X" % k


def load(build: str, session: str) -> dict:
    return pickle.loads((OUT / build / (session + ".pkl")).read_bytes())


def secs(cyc: int) -> float:
    return cyc / (MHZ * 1e6)


def report(build: str, sessions: list[str], top: int) -> None:
    tot = defaultdict(int)
    work_all = 0
    for s in sessions:
        r = load(build, s)
        work = r["cycles"] - r["wait"]
        work_all += work
        print("%-18s work %8.1f s  wait %8.1f s  (8088 at %.2f MHz)" % (s, secs(work), secs(r["wait"]), MHZ))
        for name, (cyc, _w) in r["routines"].items():
            tot[name] += cyc
    print("\nroutines by work, all sessions above (%.1f s of work):" % secs(work_all))
    for name, cyc in sorted(tot.items(), key=lambda kv: -kv[1])[:top]:
        print("  %6.2f %%  %8.1f s  %s" % (100 * cyc / work_all, secs(cyc), name))


def actions(build: str, session: str, top: int, detail: int = 0, in_order: bool = False) -> None:
    r = load(build, session)
    print("%s: the %d costliest actions (work until the game reads the next key)" % (session, top))
    for label, work, wait, routines in r["actions"][:top] if in_order else sorted(r["actions"], key=lambda a: -a[1])[:top]:
        print("  %7.2f s work  %7.2f s wait  after %s" % (secs(work), secs(wait), label))
        if detail:
            for name, cyc in list(routines.items())[:detail]:
                print("        %6.2f s  %s" % (secs(cyc), name))


def diff(a: str, b: str, sessions: list[str]) -> None:
    for s in sessions:
        ra, rb = load(a, s), load(b, s)
        wa, wb = ra["cycles"] - ra["wait"], rb["cycles"] - rb["wait"]
        print("%-18s work %8.1f s -> %8.1f s  (%+.1f %%)" % (s, secs(wa), secs(wb), 100 * (wb - wa) / max(1, wa)))


def _job(args):
    build, session = args
    r = profile(build, session)
    return session, r["seconds"], r["cycles"], r["wait"]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--build", default="game", choices=sorted(func.BUILDS))
    ap.add_argument("--session", action="append")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--actions", action="store_true")
    ap.add_argument("--diff", nargs=2, metavar=("A", "B"))
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--detail", type=int, default=0, help="--actions: the N costliest routines of each action")
    ap.add_argument("--in-order", action="store_true", help="--actions: in the session's order, not by cost")
    a = ap.parse_args(argv)
    sessions = a.session or func.suite()
    if a.report:
        report(a.build, sessions, a.top)
        return 0
    if a.actions:
        for s in sessions:
            actions(a.build, s, a.top, a.detail, a.in_order)
        return 0
    if a.diff:
        diff(a.diff[0], a.diff[1], sessions)
        return 0
    with ProcessPoolExecutor(max_workers=a.jobs) as ex:
        for s, t, cyc, wait in ex.map(_job, [(a.build, s) for s in sessions]):
            print("  %-18s %6.0f s host; work %7.1f s, wait %7.1f s on the 8088" % (s, t, secs(cyc - wait), secs(wait)),
                  flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

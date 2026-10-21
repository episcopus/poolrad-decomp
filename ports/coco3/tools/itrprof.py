#!/usr/bin/env python3
"""itrprof.py: an exact profile with call stacks from an instruction trace (step 8.9d).

Input: build/run/itrace.txt made by MB_ITRACE=t with MB_ITRACE_ACT='tracelog "%02X %02X %02X %04X|",b@909,b@80,b@<eng_idx>,w@90A' (the task, the code bank, the
engine call in progress and the keyboard poll counter before every instruction; build/run/itr.sh in the profiling worktree does it), one line per instruction:
    TT BB EE PPPP|ADDR: MNEMONIC OPERAND
Every instruction is given its cycles (the 6809's table, indexed modes by the common cost), the address is turned into a routine by the maps of the build (the
engine's pool.map in task 1, core.map in task 0 below $8000, the bank's own map above), and the calls (BSR, LBSR, JSR) and returns (RTS, PULS .. PC) keep a stack
of routines, so a routine has an EXCLUSIVE time (its own instructions) and an INCLUSIVE time (itself and what it called). The far call trampolines and the
engine call are calls like any other. A return that does not go where the top call came from pops to the frame it does go to.
Usage: itrprof.py [--from-poll] [--top N] [--tree ROUTINE] [--skip-idle]
  --skip-idle   leave out the instructions executed while the game waits for a key (the poll counter changes in them)"""
import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prof_pc  # noqa: E402

B = prof_pc.B
TRACE = os.path.join(prof_pc.ROOT, "build", "run", "itrace.txt")

INH = {"NOP": 2, "ABX": 3, "DAA": 2, "SEX": 2, "MUL": 11, "RTS": 5, "RTI": 6, "SWI": 19, "SYNC": 4, "TFR": 6, "EXG": 8, "CWAI": 20}
RMW = {"NEG", "COM", "LSR", "ROR", "ASR", "ASL", "LSL", "ROL", "DEC", "INC", "TST", "CLR"}
WIDE_LD = {"LDD", "LDX", "LDY", "LDU", "LDS", "STD", "STX", "STY", "STU", "STS", "CMPX", "CMPY", "CMPU", "CMPS", "CMPD", "ADDD", "SUBD"}


def cycles(mn, op):
    if mn in INH:
        return INH[mn]
    if mn.endswith(("A", "B")) and mn[:-1] in RMW and not op:
        return 2
    if mn in ("PSHS", "PSHU", "PULS", "PULU"):
        n = sum(2 if r in ("D", "X", "Y", "U", "S", "PC") else 1 for r in re.split(r"[ ,]+", op.strip()) if r)
        return 5 + n
    if mn.startswith("B") and mn not in ("BITA", "BITB", "BSR"):
        return 3
    if mn.startswith("LB") and mn != "LBSR":
        return 5
    if mn == "BSR":
        return 7
    if mn == "LBSR":
        return 9
    if mn in ("ANDCC", "ORCC"):
        return 3
    if mn.startswith("LEA"):
        return 5 if "," in op else 4
    imm, direct, indexed = op.startswith("#"), op.startswith("<"), "," in op
    wide = mn in WIDE_LD or mn in ("LDD", "STD")
    if mn in ("JSR", "JMP"):
        base = 7 if mn == "JSR" else 3
        return base + (1 if not indexed and not direct else 0) + (1 if indexed and mn == "JSR" else 0)
    if mn in RMW:
        return 6 if direct else 6 + (1 if not indexed else 0) + (0 if not indexed else 0)
    if imm:
        return 4 if mn in ("LDY", "LDS", "CMPD", "CMPY", "CMPS", "CMPU", "CMPX") and wide and mn not in ("CMPX", "CMPU") else (3 if wide else 2)
    if indexed:
        return 6 if wide else 5
    if direct:
        return 5 if wide else 4
    return 6 if wide else 5


def load_maps(a):
    meta = json.load(open(os.path.join(B, "banks.json")))
    bank_name = {b["id"]: b["name"] for b in meta["banks"]}
    maps = {}

    def bank_map(bid):
        if bid not in maps:
            maps[bid] = prof_pc.load_map(os.path.join(B, bank_name.get(bid, "none") + ".map"))
        return maps[bid]
    eng, core = prof_pc.load_map(os.path.join(B, "pool.map")), prof_pc.load_map(os.path.join(B, "core.map"))
    return meta, bank_name, bank_map, eng, core


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trace", default=TRACE)
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--skip-idle", action="store_true")
    ap.add_argument("--busy", action="store_true", help="only the longest stretch in which the poll counter does not change (the game working on a key, not waiting for one)")
    ap.add_argument("--tree", help="print the callees of this routine (inclusive cycles) instead of the tables")
    ap.add_argument("--depth", type=int, default=3)
    a = ap.parse_args()
    meta, bank_name, bank_map, eng, core = load_maps(a)
    api = meta["engine_api"]
    seg = (0, 1 << 60)
    if a.busy:
        best, start, cyc, lp, n = (0, 0, 0), 0, 0, None, 0
        pre = re.compile(r"([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{4})\|([0-9A-F]{4}): (\w+)\s*(.*)$")
        for line in open(a.trace, errors="replace"):
            m = pre.match(line)
            if not m:
                continue
            pl = int(m.group(4), 16)
            if lp is not None and pl != lp:
                if cyc > best[0]:
                    best = (cyc, start, n)
                start, cyc = n, 0
            lp = pl
            cyc += cycles(m.group(6), m.group(7).strip())
            n += 1
        seg = (best[1], best[2])
        print("busy stretch: instructions %d..%d, %d cycles = %.2f s at 1.79 MHz" % (seg[0], seg[1], best[0], best[0] / 1790000.0))
    excl, incl, calls = collections.Counter(), collections.Counter(), collections.Counter()
    edge = collections.Counter()                 # (caller, callee) -> inclusive cycles
    stack = []                                   # [name, call pc, entry] per frame
    pending = None                               # a call just executed: (call pc, caller name)
    total = 0
    last_polls = None
    skipped = 0
    pat = re.compile(r"([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{4})\|([0-9A-F]{4}): (\w+)\s*(.*)$")
    ret_check = None
    idx = -1
    for line in open(a.trace, errors="replace"):
        m = pat.match(line)
        if not m:
            continue
        idx += 1
        if idx < seg[0] or idx >= seg[1]:
            continue
        task, bank, ei, polls, pc = int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16), int(m.group(5), 16)
        mn, op = m.group(6), m.group(7).strip()
        waiting = last_polls is not None and polls != last_polls
        last_polls = polls
        if task == 1:
            name = "engine:" + prof_pc.lookup(eng, pc)
        elif pc >= 0x8000:
            name = bank_name.get(bank, "bank%d" % bank) + ":" + prof_pc.lookup(bank_map(bank), pc)
        elif pc < 0x2000:
            name = "shared:" + prof_pc.lookup(eng, pc)
        else:
            name = "core:" + prof_pc.lookup(core, pc)
        c = cycles(mn, op)
        # the stack: a call made by the previous instruction enters its callee here
        if pending is not None:
            stack.append([name, pending, pc])
            calls[name] += 1
            pending = None
        elif ret_check is not None:
            # a return: pop to the frame whose call site this address follows
            k = len(stack) - 1
            while k >= 0 and not (stack[k][1] < pc <= stack[k][1] + 5):
                k -= 1
            if k >= 0:
                del stack[k:]
            ret_check = None
        if waiting and a.skip_idle:
            skipped += c
            if mn in ("JSR", "BSR", "LBSR"):
                pending = pc
            elif mn == "RTS" or (mn == "PULS" and "PC" in op):
                ret_check = True
            continue
        total += c
        excl[name] += c
        seen = set()
        for fr in stack:
            if fr[0] not in seen:
                incl[fr[0]] += c
                seen.add(fr[0])
        if name not in seen:
            incl[name] += c
        for k in range(1, len(stack)):
            edge[(stack[k - 1][0], stack[k][0])] += c
        if mn in ("JSR", "BSR", "LBSR"):
            pending = pc
        elif mn == "RTS" or (mn == "PULS" and "PC" in op):
            ret_check = True
    print("total %.2f s (%d cycles at 1.79 MHz; idle left out: %.2f s)" % (total / 1790000.0, total, skipped / 1790000.0))
    if a.tree:
        print_tree(a.tree, edge, incl, total, a.depth)
        return
    print("\nEXCLUSIVE: the routine's own instructions")
    for n, c in excl.most_common(a.top):
        print("%7.3f s %5.1f%%  %s" % (c / 1790000.0, 100.0 * c / total, n))
    print("\nINCLUSIVE: with what it called")
    for n, c in incl.most_common(a.top):
        print("%7.3f s %5.1f%%  %6d calls  %s" % (c / 1790000.0, 100.0 * c / total, calls[n], n))


def print_tree(root, edge, incl, total, depth):
    kids = collections.defaultdict(list)
    for (p, c), n in edge.items():
        kids[p].append((n, c))
    names = [n for n in incl if n.endswith(":" + root) or n == root]
    if not names:
        sys.exit("no routine %s" % root)

    def show(n, ind, d):
        for c, k in sorted(kids.get(n, []), reverse=True)[:8]:
            print("%s%7.3f s %5.1f%%  %s" % ("  " * ind, c / 1790000.0, 100.0 * c / total, k))
            if d > 1:
                show(k, ind + 1, d - 1)
    for n in names:
        print("%7.3f s  %s" % (incl[n] / 1790000.0, n))
        show(n, 1, depth)


if __name__ == "__main__":
    main()

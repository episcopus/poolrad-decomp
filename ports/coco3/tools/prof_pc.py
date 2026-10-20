#!/usr/bin/env python3
"""prof_pc.py: where the emulated 6809 spends its time (step 8.9).

Input: the output of a run made with MB_PCLOG=t0-t1 (lua/watch.lua prints "pc t=.. pc=.. s=.. task=.. bank=.." at every
video frame, so one sample is 1/60 s of emulated time). Each sample is turned into a routine by the link maps of the build:
  task 1 (the engine)                 -> build/game/pool.map
  task 0, pc < $8000 (core, shared)   -> build/game/core.map, then pool.map for the shared code in slot 0
  task 0, pc >= $8000 (a code bank)   -> build/game/<bank>.map, the bank being the id the far call trampoline keeps in FC_CURBANK
Usage: prof_pc.py RUN.out [--from T] [--to T] [--top N] [--unit]
Samples are statistical (one per frame): a routine with fewer than about 50 samples is noise.
"""
import argparse
import bisect
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
B = os.path.join(ROOT, "build", "game")


def load_map(path):
    """(sorted addresses, names) of the function-like symbols of a link map; static functions lose their prefix."""
    syms = {}
    if not os.path.exists(path):
        return [], []
    for line in open(path, errors="replace"):
        m = re.match(r"Symbol: (\S+) \(.*\) = ([0-9A-F]+)$", line.strip())
        if not m:
            continue
        name, addr = m.group(1), int(m.group(2), 16)
        if name.startswith(".static.function."):
            name = name[len(".static.function."):]
        elif name.startswith("_") and not name.startswith("__") and not name.startswith("\x02"):
            name = name[1:]
        elif re.match(r"^[A-Za-z]", name) and not re.match(r"^[LD]\d+$", name) and name not in ("DIV16",):
            pass                       # an assembler label: keep (kernels, irq code)
        else:
            continue
        if name.startswith(("\x02", ".global", "funcsize_")):
            continue
        syms.setdefault(addr, name)
    addrs = sorted(syms)
    return addrs, [syms[a] for a in addrs]


def lookup(table, pc):
    addrs, names = table
    i = bisect.bisect_right(addrs, pc) - 1
    return names[i] if i >= 0 else "?%04X" % pc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--to", dest="t1", type=float, default=1e9)
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--all", action="store_true", help="count the frames in which the game polled the keyboard too (waiting)")
    ap.add_argument("--api", action="store_true", help="engine samples by the engine call in progress (what the game asked for) instead of the engine routine")
    ap.add_argument("--unit", action="store_true", help="aggregate per unit (bank, engine, core) instead of per routine")
    a = ap.parse_args()

    banks = json.load(open(os.path.join(B, "banks.json")))["banks"]
    bank_name = {b["id"]: b["name"] for b in banks}
    api = json.load(open(os.path.join(B, "banks.json")))["engine_api"]
    maps = {}

    def bank_map(bid):
        if bid not in maps:
            maps[bid] = load_map(os.path.join(B, bank_name.get(bid, "none") + ".map"))
        return maps[bid]

    eng, core = load_map(os.path.join(B, "pool.map")), load_map(os.path.join(B, "core.map"))
    counts, total, idle, last_polls = {}, 0, 0, None
    for line in open(a.run, errors="replace"):
        m = re.match(r"pc t=([\d.]+) pc=([0-9A-F]+) s=([0-9A-F]+) task=(\d+) bank=(\d+) polls=(\d+) eng=(\d+)", line)
        if not m:
            continue
        t, pc, task, bank, polls = float(m.group(1)), int(m.group(2), 16), int(m.group(4)), int(m.group(5)), int(m.group(6))
        eng_idx = int(m.group(7))
        waiting = last_polls is not None and polls != last_polls      # the game read the keyboard during this frame: it waits for a key or a time
        last_polls = polls
        if t < a.t0 or t > a.t1:
            continue
        if waiting:
            idle += 1
            if not a.all:
                continue
        if task == 1:
            unit, fn = "engine", lookup(eng, pc)
            if a.api:
                fn = "bankload" if eng_idx == 0 else api[eng_idx - 1] if eng_idx <= len(api) else "call%d" % eng_idx     # entry 0 of the table is the bank loader
        elif pc >= 0x8000:
            unit, fn = bank_name.get(bank, "bank%d" % bank), lookup(bank_map(bank), pc)
        elif pc < 0x2000:
            unit, fn = "shared", lookup(eng, pc)
        else:
            unit, fn = "core", lookup(core, pc)
        key = unit if a.unit else (unit, fn)
        counts[key] = counts.get(key, 0) + 1
        total += 1
    if not total:
        sys.exit("no samples")
    print("%d busy samples = %.1f s of emulated time (%d frames more with the game polling the keyboard%s)" % (total, total / 60.0, idle, ", counted" if a.all else ", left out"))
    for key, n in sorted(counts.items(), key=lambda kv: -kv[1])[:a.top]:
        label = key if a.unit else "%-8s %s" % key
        print("%6d %5.1f%%  %s" % (n, 100.0 * n / total, label))


if __name__ == "__main__":
    main()

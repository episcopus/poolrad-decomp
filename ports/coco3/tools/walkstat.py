#!/usr/bin/env python3
"""walkstat.py: what one key costs, key by key (step 8.9d, walking in the 3D view).

Input: a run made with MB_PCLOG (lua/watch.lua prints "pc t=.. polls=.." once per video frame and "session: T s: keys N" when it presses a key).
For every key press the busy frames (the game did not poll the keyboard) up to the next press are counted and attributed to units and routines by the
maps of the build, like tools/prof_pc.py. Usage: walkstat.py RUN.out [--from T] [--top N] [--api]
Prints one line per key (time, key code, busy seconds), then the totals by unit and by routine over the keys of the selection."""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prof_pc  # noqa: E402

B = prof_pc.B
NAMES = {129: "UP", 131: "LEFT", 132: "RIGHT", 130: "DOWN", 65: "A", 76: "L"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--top", type=int, default=30)
    ap.add_argument("--api", action="store_true")
    ap.add_argument("--key", help="only the presses of this key code")
    ap.add_argument("--caller", action="store_true", help="a sample in the core is labelled with the code bank that was running (the caller, usually)")
    a = ap.parse_args()
    meta = json.load(open(os.path.join(B, "banks.json")))
    bank_name = {b["id"]: b["name"] for b in meta["banks"]}
    api = meta["engine_api"]
    maps = {}

    def bank_map(bid):
        if bid not in maps:
            maps[bid] = prof_pc.load_map(os.path.join(B, bank_name.get(bid, "none") + ".map"))
        return maps[bid]
    eng, core = prof_pc.load_map(os.path.join(B, "pool.map")), prof_pc.load_map(os.path.join(B, "core.map"))
    presses, frames = [], []
    last = None
    for line in open(a.run, errors="replace"):
        m = re.match(r"session: ([\d.]+) s: keys (\d+)", line)
        if m:
            presses.append((float(m.group(1)), int(m.group(2))))
            continue
        m = re.match(r"pc t=([\d.]+) pc=([0-9A-F]+) s=([0-9A-F]+) task=(\d+) bank=(\d+) polls=(\d+) eng=(\d+)", line)
        if not m:
            continue
        t, pc, task, bank, polls, ei = float(m.group(1)), int(m.group(2), 16), int(m.group(4)), int(m.group(5)), int(m.group(6)), int(m.group(7))
        waiting = last is not None and polls != last
        last = polls
        if task == 1:
            unit, fn = "engine", prof_pc.lookup(eng, pc)
            if a.api:
                fn = "bankload" if ei == 0 else api[ei - 1] if ei <= len(api) else "call%d" % ei
        elif pc >= 0x8000:
            unit, fn = bank_name.get(bank, "bank%d" % bank), prof_pc.lookup(bank_map(bank), pc)
        elif pc < 0x2000:
            unit, fn = "shared", prof_pc.lookup(eng, pc)
        else:
            unit, fn = "core", prof_pc.lookup(core, pc)
            if a.caller:
                fn += " <- " + bank_name.get(bank, "bank%d" % bank)
        frames.append((t, waiting, unit, fn))
    units, fns, total, nkeys = {}, {}, 0, 0
    print("%8s %-6s %7s %s" % ("t", "key", "busy s", "(frames from the press to the next one)"))
    for k, (t, code) in enumerate(presses):
        if t < a.t0 or (a.key and str(code) != a.key):
            continue
        end = presses[k + 1][0] if k + 1 < len(presses) else t + 30
        busy = [(u, f) for (ft, w, u, f) in frames if t <= ft < end and not w]
        print("%8.1f %-6s %7.2f" % (t, NAMES.get(code, code), len(busy) / 60.0))
        nkeys += 1
        for u, f in busy:
            units[u] = units.get(u, 0) + 1
            fns[(u, f)] = fns.get((u, f), 0) + 1
            total += 1
    if not total:
        sys.exit("no samples")
    print("\n%d presses, %.1f busy s, %.2f s a press" % (nkeys, total / 60.0, total / 60.0 / nkeys))
    for u, n in sorted(units.items(), key=lambda kv: -kv[1])[:12]:
        print("%7.2f s %5.1f%%  %s" % (n / 60.0 / nkeys, 100.0 * n / total, u))
    print()
    for (u, f), n in sorted(fns.items(), key=lambda kv: -kv[1])[:a.top]:
        print("%7.3f s %5.1f%%  %-18s %s" % (n / 60.0 / nkeys, 100.0 * n / total, u, f))


if __name__ == "__main__":
    main()

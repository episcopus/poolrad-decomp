#!/usr/bin/env python3
"""timeline.py RUN.out [--win S] [--from T] [--to T] [--top N]: the busy time of a run in windows of S seconds, with the routines that took most of each (step 8.9e, combat).
Input: a run made with MB_PCLOG. Busy = frames in which the game did not poll the keyboard; the routine of a sample as in tools/prof_pc.py (engine samples by the engine call in progress)."""
import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prof_pc  # noqa: E402

B = prof_pc.B


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--win", type=float, default=10.0)
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--to", dest="t1", type=float, default=1e9)
    ap.add_argument("--top", type=int, default=3)
    ap.add_argument("--min", type=float, default=0.5, help="windows with less busy seconds are not printed")
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
    wins = collections.OrderedDict()
    last = None
    for line in open(a.run, errors="replace"):
        m = re.match(r"pc t=([\d.]+) pc=([0-9A-F]+) s=([0-9A-F]+) task=(\d+) bank=(\d+) polls=(\d+) eng=(\d+)", line)
        if not m:
            continue
        t, pc, task, bank, polls, ei = float(m.group(1)), int(m.group(2), 16), int(m.group(4)), int(m.group(5)), int(m.group(6)), int(m.group(7))
        waiting = last is not None and polls != last
        last = polls
        if waiting or t < a.t0 or t > a.t1:
            continue
        if task == 1:
            name = "engine:" + ("bankload" if ei == 0 else api[ei - 1] if ei <= len(api) else "call%d" % ei)
        elif pc >= 0x8000:
            name = bank_name.get(bank, "bank%d" % bank) + ":" + prof_pc.lookup(bank_map(bank), pc)
        elif pc < 0x2000:
            name = "shared:" + prof_pc.lookup(eng, pc)
        else:
            name = "core:" + prof_pc.lookup(core, pc) + " <- " + bank_name.get(bank, "?")
        w = int(t // a.win)
        wins.setdefault(w, collections.Counter())[name] += 1
    for w, c in wins.items():
        n = sum(c.values())
        if n / 60.0 < a.min:
            continue
        print("%7.0f s  busy %5.1f s   %s" % (w * a.win, n / 60.0, "; ".join("%s %.1f" % (k, v / 60.0) for k, v in c.most_common(a.top))))


if __name__ == "__main__":
    main()

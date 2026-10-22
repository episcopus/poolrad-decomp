#!/usr/bin/env python3
"""scrollstat.py RUN.out [--name ScrollViewTo]: the busy stretches of a run (frames between two keyboard polls) that contain a sample in the named game routine
(step 8.9g, scrolling the combat map): start time, length in seconds and the routines that took most of it. Input: a run made with MB_PCLOG."""
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
    ap.add_argument("--name", default="ScrollViewTo")
    ap.add_argument("--top", type=int, default=6)
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
    stretch, hit, last, t0 = [], False, None, 0.0

    def flush():
        nonlocal stretch, hit
        if hit:
            c = collections.Counter(n for _, n in stretch)
            print("%8.1f  %5.2f s  %s" % (stretch[0][0], len(stretch) / 60.0, "; ".join("%s %.2f" % (n, k / 60.0) for n, k in c.most_common(a.top))))
        stretch, hit = [], False
    for line in open(a.run, errors="replace"):
        m = re.match(r"pc t=([\d.]+) pc=([0-9A-F]+) s=([0-9A-F]+) task=(\d+) bank=(\d+) polls=(\d+) eng=(\d+)", line)
        if not m:
            continue
        t, pc, task, bank, polls, ei = float(m.group(1)), int(m.group(2), 16), int(m.group(4)), int(m.group(5)), int(m.group(6)), int(m.group(7))
        waiting = last is not None and polls != last
        last = polls
        if waiting:
            flush()
            continue
        if task == 1:
            name = "engine:" + ("bankload" if ei == 0 else api[ei - 1] if ei <= len(api) else "call%d" % ei)
        elif pc >= 0x8000:
            fn = prof_pc.lookup(bank_map(bank), pc)
            name = fn
            if fn == a.name:
                hit = True
        elif pc < 0x2000:
            name = "shared"
        else:
            name = "core:" + prof_pc.lookup(core, pc)
        stretch.append((t, name))
    flush()


if __name__ == "__main__":
    main()

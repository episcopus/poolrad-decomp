#!/usr/bin/env python3
"""iobudget.py: what the sessions ask of the storage, as a number to keep small (step 8.11).

Input: the logs of runs made with MB_SECLOG=1 (`make io-budget` makes them: build/run/io-<session>.out, one line `sec cmd=1 lsn= count= t=` per request), the image
they ran on (build/game/pool.img, "PIM2") and tests/sessions/*.keys. Output, per session: the kilobytes read, by kind (code banks, pictures and other data, the core, the
saves), the number of bank loads, the worst 30 seconds of code traffic, and the seconds the reading would take on each medium (what the player waits for):

    floppy through DSKCON    4 KB/s    measured in XRoar and MAME (PHASE-8.10 section 8)
    floppy, a track a turn  22 KB/s    [E] 18 sectors in one revolution
    DriveWire              11 KB/s    [E] research 03
    SDC command mode      100 KB/s    [E] research 03

The original DOS game, the same combat session on the oracle: 56 overlay loads, 384 KB; a fight needs 4 of them (docs/PHASE-8.11.md). The budget file data/io_budget.json
holds the numbers a session may not exceed (`--write` ratchets them down to what the last run did, plus 3 %); `--check` exits 1 when one is exceeded.
Usage: iobudget.py [--check] [--write] [--window 30]"""
import argparse
import bisect
import collections
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from seclog import load_index  # noqa: E402

PORT = os.path.dirname(HERE)
MEDIA = [("floppy", 4.0), ("track", 22.0), ("DriveWire", 11.0), ("SDC", 100.0)]
SKIP = ("create-elf-mage",)


def kinds_of(image):
    files, ents, save_lsn, _ = load_index(image)
    order = sorted(ents)
    starts = [e[0] for e in order]

    def kind(lsn):
        if lsn >= save_lsn:
            return "save"
        off = lsn * 256
        if off < (starts[0] if starts else 0):
            return "index"
        e = order[bisect.bisect_right(starts, off) - 1]
        name = files[e[3]][0]
        return "bank" if name == "BANK" else "core" if name in ("CORE", "DGROUP") else "data"
    return kind


def session_numbers(path, kind, window):
    kb = collections.Counter()
    loads = 0
    bins = collections.defaultdict(float)       # window number -> KB of code banks
    last_bank_lsn = None
    for line in open(path, errors="replace"):
        m = re.match(r"sec cmd=1 lsn=(\d+) count=(\d+) at=\w+ t=([\d.]+)", line)
        if not m:
            continue
        lsn, cnt, t = int(m.group(1)), int(m.group(2)), float(m.group(3))
        k = kind(lsn)
        kb[k] += cnt / 4.0
        if k == "bank":
            if lsn != last_bank_lsn:
                loads += 1                       # (a bank is read in runs of 32 sectors: a run that continues the last is the same load)
            bins[int(t // window)] += cnt / 4.0
            last_bank_lsn = lsn + cnt
        else:
            last_bank_lsn = None
    return kb, loads, (max(bins.values()) if bins else 0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 when a session reads more than data/io_budget.json allows")
    ap.add_argument("--write", action="store_true", help="write the budget from this run (3 percent above what each session read)")
    ap.add_argument("--window", type=float, default=30.0, help="seconds of the traffic peak")
    ap.add_argument("--image", default=os.path.join(PORT, "build/game/pool.img"))
    ap.add_argument("--budget", default=os.path.join(PORT, "data/io_budget.json"))
    ap.add_argument("--runs", default=os.path.join(PORT, "build/run/io-%s.out"))
    a = ap.parse_args()
    kind = kinds_of(a.image)
    sessions = [os.path.basename(p)[:-5] for p in sorted(glob.glob(os.path.join(PORT, "../../tests/sessions/*.keys")))]
    sessions = [s for s in sessions if s not in SKIP and os.path.exists(a.runs % s)]
    if not sessions:
        sys.exit("iobudget: no runs in %s: make io-budget" % (a.runs % "<session>"))
    budget = json.load(open(a.budget)) if os.path.exists(a.budget) else {}
    print("%-17s %6s %6s %6s %5s | %5s | %s | %s" % ("session", "code", "data", "total", "loads", "peak", "seconds of reading: " + "  ".join("%s" % m for m, _ in MEDIA), "budget"))
    print("%-17s %6s %6s %6s %5s | %5s |" % ("", "KB", "KB", "KB", "", "KB/%gs" % a.window))
    new, bad = {}, 0
    tot = collections.Counter()
    loads_all = 0
    for s in sessions:
        kb, loads, peak = session_numbers(a.runs % s, kind, a.window)
        read = sum(kb.values())
        secs = "  ".join("%7.0f" % (read / r) for _, r in MEDIA)
        code, data = kb["bank"], kb["data"] + kb["core"] + kb["save"] + kb["index"]
        b = budget.get(s)
        flag = ""
        if b and (code > b["code_kb"] or peak > b["peak_kb"]):
            flag, bad = "OVER (code %.0f > %.0f, peak %.0f > %.0f)" % (code, b["code_kb"], peak, b["peak_kb"]), bad + 1
        print("%-17s %6.0f %6.0f %6.0f %5d | %5.0f | %s | %s" % (s, code, data, read, loads, peak, secs, flag or ("%.0f KB" % b["code_kb"] if b else "-")))
        new[s] = {"code_kb": round(code * 1.03 + 1), "peak_kb": round(peak * 1.03 + 1)}
        tot["code"] += code
        tot["read"] += read
        tot["peak"] = max(tot["peak"], peak)
        loads_all += loads
    n = len(sessions)
    print("%-17s %6.0f %6.0f %6.0f %5d | %5.0f | %s" % ("average of %d" % n, tot["code"] / n, (tot["read"] - tot["code"]) / n, tot["read"] / n, loads_all / n, tot["peak"],
                                                       "  ".join("%7.0f" % (tot["read"] / n / r) for _, r in MEDIA)))
    print("the original DOS game, the same combat session: 384 KB of overlays in 56 loads, 33 KB in the fight")
    if a.write:
        json.dump(new, open(a.budget, "w"), indent=1, sort_keys=True)
        print("budget written to", a.budget)
    if a.check and bad:
        print("iobudget: %d sessions over their budget" % bad)
        sys.exit(1)


if __name__ == "__main__":
    main()

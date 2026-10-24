#!/usr/bin/env python3
"""profwatch.py: watches the runs of tools/routine_profile.py and says when one looks stuck (step 8.11).

Each run writes build/profile/<session>.progress every 2 million instructions: "done expected stack tracer-stack". Every INTERVAL seconds this
prints one line per running session (percent, rate, time left) and a line starting with STALL when

  * a session made no progress for STALL seconds,
  * its rate fell below a third of the best it had (the quadratic slowdown of a tracer whose stack leaks looks like this), or
  * a stack is over 2,000 frames deep.

It ends when no run is left. Usage: profwatch.py [interval 60] [stall 300]"""
import os
import subprocess
import sys
import time
from pathlib import Path

PROF = Path(__file__).resolve().parent.parent / "build" / "profile"


def running():
    out = subprocess.run(["pgrep", "-fl", "tools/routine_profile.py"], capture_output=True, text=True).stdout
    return {l.split()[-1] for l in out.splitlines() if "xargs" not in l and not l.endswith("routine_profile.py")}


def main():
    interval = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    stall = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    hist = {}                                  # session -> [(time, insns)]
    best = {}
    warned = set()
    while True:
        live = running()
        if not live:
            print("no run left")
            return 0
        now = time.time()
        for s in sorted(live):
            f = PROF / (s + ".progress")
            try:
                done, exp, depth, tdepth = (int(x) for x in f.read_text().split())
            except (OSError, ValueError):
                print("%-18s no progress file yet" % s)
                continue
            h = hist.setdefault(s, [])
            h.append((now, done))
            h[:] = h[-12:]
            rate = (h[-1][1] - h[0][1]) / max(1.0, h[-1][0] - h[0][0]) if len(h) > 1 else 0
            best[s] = max(best.get(s, 0), rate)
            left = (exp - done) / rate / 60 if rate and exp else float("nan")
            print("%-18s %5.1f%%  %6.0f k insn/s  %5.0f min left  stack %d/%d" % (s, 100.0 * done / exp if exp else 0, rate / 1000, left, depth, tdepth), flush=True)
            if len(h) > 1 and now - max(t for t, d in h if d != h[-1][1] or t == h[0][0]) >= stall and h[-1][1] == h[0][1] and now - h[0][0] >= stall:
                msg = "no progress for %d s" % (now - h[0][0])
            elif len(h) > 6 and best[s] and rate < best[s] / 3:
                msg = "rate fell to %.0f k insn/s from %.0f" % (rate / 1000, best[s] / 1000)
            elif depth > 2000 or tdepth > 2000:
                msg = "stack %d/%d frames deep" % (depth, tdepth)
            else:
                continue
            if (s, msg[:8]) not in warned:
                warned.add((s, msg[:8]))
                print("STALL %s: %s" % (s, msg), flush=True)
        time.sleep(interval)


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""explore_prune.py: drop the keys of a script that do not matter for the lines it reaches (after explore_climb.py).

  .venv/bin/python tools/c/explore_prune.py IN.keys OUT.keys [--from-line N] [--units ovl06,ovl21]

Plays the script on the explorer with coverage, then tries to remove each `press`/`key` (and its `wait`) after line N (default: the last
`wait 300`, that is after the saved game is loaded), keeping the removal when the lines the script reaches that the committed sessions
do not reach stay the same (or all but --slack of them)."""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import explore_climb as C  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--from-line", type=int)
    ap.add_argument("--slack", type=int, default=0)
    ap.add_argument("--maxpolls", type=int, default=30000000)
    a = ap.parse_args()
    C.ensure_baseline()
    base = C.lines_of(os.path.join(C.OUT, "x-base.profdata"), os.path.join(C.COV, "poolrad_replay"))
    lines = [l for l in open(a.inp).read().split("\n") if l.strip() and not l.startswith("quit")]
    start = a.from_line if a.from_line is not None else max(i for i, l in enumerate(lines) if l.startswith("wait 300")) + 1
    head, body = lines[:start], lines[start:]
    units, cur = [], []
    for l in body:
        if l.startswith(("press ", "key ")):
            if cur:
                units.append(cur)
            cur = [l]
        else:
            cur.append(l)
    if cur:
        units.append(cur)

    def new(us):
        text = "\n".join(head + [l for u in us for l in u]) + "\n"
        return C.play(text, "p", a.maxpolls) - base

    goal = new(units)
    print("start: %d keys, %d new lines" % (len(units), len(goal)), flush=True)
    i = 0
    while i < len(units):
        trial = units[:i] + units[i + 1:]
        got = new(trial)
        if len(goal - got) <= a.slack:
            units = trial
            print("dropped %s" % units[i - 0 if False else min(i, len(units) - 1)][0] if False else "dropped key %d" % i, flush=True)
        else:
            i += 1
    open(a.out, "w").write("\n".join(head + [l for u in units for l in u]) + "\n")
    print("%d keys left, %d new lines -> %s" % (len(units), len(new(units)), a.out))


if __name__ == "__main__":
    main()

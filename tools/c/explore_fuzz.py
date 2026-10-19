#!/usr/bin/env python3
"""explore_fuzz.py: random walks on the C translation, to find where things are before a session is recorded on the original.

  .venv/bin/python tools/c/explore_fuzz.py --watch ShopMain,VisitTemple [--walks 200] [--steps 300] [--seed 1] [--prefix FILE]

Each walk is a key script: the shared prefix (default: load the shipped saved game A), then random moves (forward most of the time,
turns, and now and then Enter, Esc, Y, N, a letter) played by build/cmake-trace/poolrad_explore (a build with -DPOOLRAD_TRACE=ON). The
routines named in --watch are reported with the party's cell and facing and the number of the script line that was running.
The scripts that reached something are kept in build/explore/fz/ (hit-<routine>-<n>.keys), cut after the line that did it.
Not a test: it proves nothing about the game, it only finds the way. Sessions are recorded on the original (playbook 40)."""
import argparse
import os
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
EXE = os.path.join(ROOT, "build/cmake-trace/poolrad_explore")
PREFIX = "clock 12:00:16.58\nwheel\nwait 20\nkey L\nwait 20\nkey A\nwait 300\n"


def walk(seed, steps, prefix, watch):
    rnd = random.Random(seed)
    lines = prefix.rstrip("\n").split("\n") if prefix else []
    for _ in range(steps):
        r = rnd.random()
        if r < 0.62:
            k = "UP"
        elif r < 0.72:
            k = "LEFT"
        elif r < 0.82:
            k = "RIGHT"
        elif r < 0.88:
            k = "ENTER"
        elif r < 0.92:
            k = "ESC"
        else:
            k = rnd.choice(["Y", "N", "E", "A", "S", "L", "T", "SPACE", "1"])
        lines.append("press " + k)
        lines.append("wait 2")
    lines.append("quit")
    return "\n".join(lines) + "\n"


def run(seed, args, prefix):
    text = walk(seed, args.steps, prefix, args.watch)
    path = os.path.join(ROOT, "build/explore/fz/w%d.keys" % seed)
    with open(path, "w") as f:
        f.write(text)
    env = dict(os.environ, EXPLORE_WATCH=args.watch)
    try:
        p = subprocess.run([EXE, "--data", os.path.join(ROOT, "poolrad"), "--save", os.path.join(ROOT, "build/explore/fz/save%d" % seed),
                            "--script", path, "--out", os.path.join(ROOT, "build/explore/fz/o%d" % seed), "--max-polls", "12000000"],
                           capture_output=True, text=True, env=env, timeout=90)
    except subprocess.TimeoutExpired:
        return seed, ["TIMEOUT"], text
    hits = re.findall(r"^HIT (\w+) col (-?\d+) row (-?\d+) facing (\d+) op (\d+)", p.stderr, re.M)
    return seed, hits, text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", required=True)
    ap.add_argument("--walks", type=int, default=100)
    ap.add_argument("--steps", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--prefix")
    ap.add_argument("--jobs", type=int, default=8)
    args = ap.parse_args()
    prefix = open(args.prefix).read() if args.prefix else PREFIX
    first = {}
    with ThreadPoolExecutor(args.jobs) as ex:
        for seed, hits, text in ex.map(lambda s: run(s, args, prefix), range(args.seed, args.seed + args.walks)):
            for h in hits:
                if h == "TIMEOUT":
                    continue
                name, col, row, fac, op = h
                if name not in first:
                    first[name] = (seed, col, row, fac, int(op))
                    ops = [l for l in text.split("\n") if l.strip() and not l.startswith("clock")]
                    out = os.path.join(ROOT, "build/explore/fz/hit-%s.keys" % name)
                    # the script is cut at the op that was running: ops count wait and key lines as separate ops
                    cut = text.split("\n")
                    kept, n = [], 0
                    for l in cut:
                        c = l.split("#")[0].strip().split(" ")[0]
                        kept.append(l)
                        if c in ("key", "press", "wait", "shot", "wheel", "text", "state"):
                            n += 1
                        if n > int(op) + 2:
                            break
                    open(out, "w").write("\n".join(kept) + "\nquit\n")
                    print("%-22s first by walk %d at cell %s,%s facing %s (op %s) -> %s" % (name, seed, col, row, fac, op, os.path.relpath(out, ROOT)))
    for w in args.watch.split(","):
        if w not in first:
            print("%-22s not reached" % w)


if __name__ == "__main__":
    main()

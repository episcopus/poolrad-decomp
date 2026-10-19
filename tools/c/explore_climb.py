#!/usr/bin/env python3
"""explore_climb.py: find key sequences that reach lines of the game no committed session reaches (hill climbing on coverage).

  .venv/bin/python tools/c/explore_climb.py BASE.keys OUT.keys [--units ovl06,ovl21] [--rounds 40] [--cands 24] [--keys ENTER,ESC,...]

BASE.keys is a script that ends where the search starts (a shop door, the camp menu, a fight). Each round appends 1 to 3 random keys (`press`
and a short `wait`, so the key goes in whatever the game is doing) to the best script so far, plays the candidates on the explorer built with
coverage (build/cmake-cov) and keeps the one that reaches the most lines not in the baseline (build/coverage/x-base.profdata, from
`make coverage` and explore_cov.py's merge): lines of --units count in full, the others a tenth. Stops after a few rounds without gain.
The result is a script to read, shorten and record on the original (playbook 40); it is not a test of anything."""
import argparse
import glob
import os
import random
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
COV = os.path.join(ROOT, "build/cmake-cov")
OUT = os.path.join(ROOT, "build/coverage")
ALPHA = ["ENTER", "ESC", "SPACE", "UP", "DOWN", "LEFT", "RIGHT", "HOME", "END", "PGUP", "PGDN"] + list("ABCDEFGHIJKLMNOPQRSTUVWXYZ") + list("0123456789")


def tool(n):
    return subprocess.check_output(["xcrun", "--find", n], text=True).strip()


LLVM_COV, LLVM_PROF = tool("llvm-cov"), tool("llvm-profdata")
SRC = sorted(glob.glob(os.path.join(ROOT, "c/game/*.c")))


def lines_of(profdata, exe):
    r = subprocess.run([LLVM_COV, "export", exe, "-instr-profile=" + profdata, "-format=lcov"] + SRC, capture_output=True, text=True, check=True)
    cur, got = None, set()
    for ln in r.stdout.split("\n"):
        if ln.startswith("SF:"):
            cur = os.path.basename(ln[3:])[:-2]
        elif ln.startswith("DA:") and cur:
            n, c = ln[3:].split(",")[:2]
            if int(c) > 0:
                got.add((cur, int(n)))
    return got


def ensure_baseline():
    """x-base.profdata: the committed sessions' profiles merged (make coverage wrote them for the build in build/cmake-cov); redone every
    time, because a profile does not fit a binary built after it."""
    profs = [p for p in glob.glob(os.path.join(OUT, "*.profdata")) if not os.path.basename(p).startswith(("all", "x-", "c-"))]
    subprocess.run([LLVM_PROF, "merge", "-sparse"] + profs + ["-o", os.path.join(OUT, "x-base.profdata")], check=True)


def play(text, tag, maxpolls):
    k = os.path.join(ROOT, "build/explore/climb-%s.keys" % tag)
    open(k, "w").write(text)
    raw = os.path.join(OUT, "c-%s.profraw" % tag)
    if os.path.exists(raw):
        os.unlink(raw)
    subprocess.run([os.path.join(COV, "poolrad_explore"), "--data", os.path.join(ROOT, "poolrad"), "--save", os.path.join(ROOT, "build/explore/climb-save-%s" % tag),
                    "--script", k, "--out", os.path.join(ROOT, "build/explore/climb-%s" % tag), "--max-polls", str(maxpolls)],
                   capture_output=True, text=True, env=dict(os.environ, LLVM_PROFILE_FILE=raw), timeout=240)
    prof = os.path.join(OUT, "c-%s.profdata" % tag)
    subprocess.run([LLVM_PROF, "merge", "-sparse", raw, "-o", prof], check=True, capture_output=True)
    return lines_of(prof, os.path.join(COV, "poolrad_explore"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("out")
    ap.add_argument("--units", default="")
    ap.add_argument("--rounds", type=int, default=40)
    ap.add_argument("--cands", type=int, default=24)
    ap.add_argument("--keys")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--maxpolls", type=int, default=30000000)
    ap.add_argument("--patience", type=int, default=6)
    a = ap.parse_args()
    alpha = a.keys.split(",") if a.keys else ALPHA
    want = set(a.units.split(",")) if a.units else set()
    rnd = random.Random(a.seed)
    ensure_baseline()
    base = lines_of(os.path.join(OUT, "x-base.profdata"), os.path.join(COV, "poolrad_replay"))
    text = open(a.base).read().rstrip("\n") + "\n"

    def score(lines):
        new = lines - base
        return sum(1.0 if (not want or u in want) else 0.1 for u, _ in new), len(new)

    best = score(play(text, "base", a.maxpolls))
    print("base: score %.1f, %d new lines" % best, flush=True)
    stale = 0
    for rnd_i in range(a.rounds):
        cands = []
        for i in range(a.cands):
            add = "".join("press %s\nwait 2\n" % rnd.choice(alpha) for _ in range(rnd.choice((1, 1, 2, 3))))
            cands.append(text + add)
        with ThreadPoolExecutor(8) as ex:
            res = list(ex.map(lambda ic: (score(play(ic[1], "c%d" % ic[0], a.maxpolls)), ic[1]), enumerate(cands)))
        res.sort(key=lambda x: (-x[0][0], len(x[1])))
        (sc, n), t = res[0]
        if sc > best[0] + 0.5:
            best, text, stale = (sc, n), t, 0
            print("round %d: score %.1f (%d new lines), +%s" % (rnd_i, sc, n, "/".join(l.split()[1] for l in t.split("\n")[len(text.split("\n")) - 1:] if l.startswith("press")) or "?"), flush=True)
            open(a.out, "w").write(text)
        else:
            stale += 1
            if stale >= a.patience:
                break
    open(a.out, "w").write(text)
    print("final: score %.1f, %d new lines -> %s" % (best[0], best[1], a.out))


if __name__ == "__main__":
    main()

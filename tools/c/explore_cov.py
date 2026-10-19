#!/usr/bin/env python3
"""explore_cov.py: what a candidate session would add to the coverage, before it is recorded.

  .venv/bin/python tools/c/explore_cov.py script.keys [more.keys ...]

Plays each script on the explorer built with coverage (build/cmake-cov, `make coverage` builds it), merges the profiles of the committed
sessions (build/coverage/*.profdata, from `make coverage`) and says, per script, how many lines of the game it reaches that the committed
sessions do not, and in which units."""
import glob
import os
import subprocess
import sys
from collections import Counter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
COV = os.path.join(ROOT, "build/cmake-cov")
OUT = os.path.join(ROOT, "build/coverage")


def tool(n):
    return subprocess.check_output(["xcrun", "--find", n], text=True).strip()


def lines(profdata, exe):
    r = subprocess.run([tool("llvm-cov"), "export", exe, "-instr-profile=" + profdata, "-format=lcov"] + sorted(glob.glob(os.path.join(ROOT, "c/game/*.c"))),
                       capture_output=True, text=True, check=True)
    cur, got = None, set()
    for ln in r.stdout.split("\n"):
        if ln.startswith("SF:"):
            cur = os.path.basename(ln[3:])
        elif ln.startswith("DA:") and cur:
            n, c = ln[3:].split(",")[:2]
            if int(c) > 0:
                got.add((cur, int(n)))
    return got


def main():
    exe = os.path.join(COV, "poolrad_explore")
    base_profs = [p for p in glob.glob(os.path.join(OUT, "*.profdata")) if not os.path.basename(p).startswith(("all", "x-", "c-"))]
    subprocess.run([tool("llvm-profdata"), "merge", "-sparse"] + base_profs + ["-o", os.path.join(OUT, "x-base.profdata")], check=True)
    # the baseline lines are measured against the replay binary of the same build
    base = lines(os.path.join(OUT, "x-base.profdata"), os.path.join(COV, "poolrad_replay"))
    for script in sys.argv[1:]:
        n = os.path.basename(script)[:-5]
        raw = os.path.join(OUT, "x-%s.profraw" % n)
        subprocess.run([exe, "--data", os.path.join(ROOT, "poolrad"), "--save", os.path.join(ROOT, "build/explore/covsave"), "--script", script, "--out",
                        os.path.join(ROOT, "build/explore/cov-" + n), "--max-polls", os.environ.get("MAXPOLLS", "40000000")],
                       capture_output=True, text=True, env=dict(os.environ, LLVM_PROFILE_FILE=raw))
        prof = os.path.join(OUT, "x-%s.profdata" % n)
        subprocess.run([tool("llvm-profdata"), "merge", "-sparse", raw, "-o", prof], check=True)
        got = lines(prof, exe)
        new = got - base
        by = Counter(u for u, _ in new)
        print("%s: %d lines reached, %d of them new; %s" % (n, len(got), len(new), ", ".join("%s %d" % (u, c) for u, c in by.most_common(8))))


if __name__ == "__main__":
    main()

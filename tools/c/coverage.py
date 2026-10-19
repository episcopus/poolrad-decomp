#!/usr/bin/env python3
"""coverage.py: how much of the game the recorded sessions run (`make coverage`).

  .venv/bin/python tools/c/coverage.py [--write] [--sessions a,b] [--uncovered]

Builds the C translation with clang's source coverage (build/cmake-cov), replays every recording in build/c/replay/ on it (each
replay has to end with the original's own checks passing), merges the profiles and reports, per unit of the translated game
(c/game/*.c): routines, lines, branches; per session: the lines only that session reaches; and the routines nobody reaches.
The translation is the Pascal of the original line for line (tools/c/pas2c.py), so a line the sessions never run is a line of the game
no golden says anything about: neither the C translation nor the ports built from it (CoCo 3, step 8.x) are proven there.

--write puts the report in tests/sessions/COVERAGE.md and the machine readable numbers in tests/sessions/coverage.json (committed:
the numbers are the baseline a new session is measured against; `make coverage` prints the change against them).
Needs the recordings (`make c-golden` once, they are written by it) and clang's llvm-cov and llvm-profdata."""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
BUILD = os.path.join(ROOT, "build/cmake-cov")
OUT = os.path.join(ROOT, "build/coverage")
JSON = os.path.join(ROOT, "tests/sessions/coverage.json")
MD = os.path.join(ROOT, "tests/sessions/COVERAGE.md")


def tool(name):
    p = shutil.which(name)
    if p:
        return p
    try:
        return subprocess.check_output(["xcrun", "--find", name], text=True).strip()
    except Exception:
        raise SystemExit("coverage: %s not found (clang's llvm tools)" % name)


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise SystemExit("coverage: %s failed:\n%s%s" % (" ".join(cmd[:3]), r.stdout[-2000:], r.stderr[-2000:]))
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--sessions")
    ap.add_argument("--uncovered", action="store_true")
    a = ap.parse_args()
    # Debug: the optimised build with counters crashes on macOS (a counter write into the text segment); -O0 is also what makes the numbers exact
    run(["cmake", "-S", ROOT, "-B", BUILD, "-DPOOLRAD_COVERAGE=ON", "-DCMAKE_BUILD_TYPE=Debug"])
    run(["cmake", "--build", BUILD, "-j", "--target", "poolrad_replay"])
    exe = os.path.join(BUILD, "poolrad_replay")
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    rpls = sorted(glob.glob(os.path.join(ROOT, "build/c/replay/*.rpl")))
    if a.sessions:
        want = set(a.sessions.split(","))
        rpls = [r for r in rpls if os.path.basename(r)[:-4] in want]
    if not rpls:
        raise SystemExit("coverage: no recordings in build/c/replay (make c-golden)")
    names = []
    for r in rpls:
        n = os.path.basename(r)[:-4]
        names.append(n)
        env = dict(os.environ, LLVM_PROFILE_FILE=os.path.join(OUT, n + ".profraw"))
        p = subprocess.run([exe, "--data", os.path.join(ROOT, "poolrad"), "--save", os.path.join(OUT, "save-" + n), r], capture_output=True, text=True, env=env)
        if "ok:" not in p.stdout + p.stderr:
            raise SystemExit("coverage: the replay of %s failed:\n%s%s" % (n, p.stdout[-800:], p.stderr[-800:]))
        run([tool("llvm-profdata"), "merge", "-sparse", os.path.join(OUT, n + ".profraw"), "-o", os.path.join(OUT, n + ".profdata")])
    run([tool("llvm-profdata"), "merge", "-sparse"] + [os.path.join(OUT, n + ".profdata") for n in names] + ["-o", os.path.join(OUT, "all.profdata")])
    src = sorted(glob.glob(os.path.join(ROOT, "c/game/*.c")))

    def export(profdata):
        r = run([tool("llvm-cov"), "export", exe, "-instr-profile=" + profdata] + src)
        return json.loads(r.stdout)["data"][0]

    full = export(os.path.join(OUT, "all.profdata"))
    units = {}
    for f in full["files"]:
        u = os.path.basename(f["filename"])[:-2]
        s = f["summary"]
        units[u] = {"lines": [s["lines"]["covered"], s["lines"]["count"]], "branches": [s["branches"]["covered"], s["branches"]["count"]],
                    "functions": [0, 0]}
    fnames = {}
    for fn in full["functions"]:
        u = os.path.basename(fn["filenames"][0])[:-2]
        if u not in units:
            continue
        name = fn["name"].split(":")[-1]
        fnames[(u, name)] = fn["count"] > 0
        units[u]["functions"][1] += 1
        units[u]["functions"][0] += fn["count"] > 0
    # the lines each session reaches alone
    lines_by = {}
    for n in names:
        cov = set()
        r = run([tool("llvm-cov"), "export", exe, "-instr-profile=" + os.path.join(OUT, n + ".profdata"), "-format=lcov"] + src)
        cur = None
        for ln in r.stdout.split("\n"):
            if ln.startswith("SF:"):
                cur = os.path.basename(ln[3:])
            elif ln.startswith("DA:") and cur:
                num, cnt = ln[3:].split(",")[:2]
                if int(cnt) > 0:
                    cov.add((cur, int(num)))
        lines_by[n] = cov
    allc = set().union(*lines_by.values())
    tot = [sum(u["lines"][0] for u in units.values()), sum(u["lines"][1] for u in units.values())]
    totb = [sum(u["branches"][0] for u in units.values()), sum(u["branches"][1] for u in units.values())]
    totf = [sum(u["functions"][0] for u in units.values()), sum(u["functions"][1] for u in units.values())]
    only = {n: len(lines_by[n] - set().union(*(lines_by[m] for m in names if m != n))) for n in names}
    rep = {"sessions": names, "total": {"lines": tot, "branches": totb, "functions": totf}, "units": units,
           "only": only, "uncovered_functions": sorted("%s:%s" % k for k, v in fnames.items() if not v)}
    old = json.load(open(JSON)) if os.path.exists(JSON) else None

    def pct(c):
        return "%5.1f%%" % (100.0 * c[0] / c[1]) if c[1] else "   n/a"
    out = []
    out.append("Coverage of the C translation of the game (c/game, the Pascal of the original line for line) by the recorded sessions: %s" % ", ".join(names))
    out.append("")
    out.append("| unit | routines | lines | branches |")
    out.append("|---|---|---|---|")
    for u in sorted(units):
        x = units[u]
        out.append("| %s | %d of %d | %s (%d of %d) | %s |" % (u, x["functions"][0], x["functions"][1], pct(x["lines"]), x["lines"][0], x["lines"][1], pct(x["branches"])))
    out.append("| **all** | %d of %d | **%s** (%d of %d) | %s |" % (totf[0], totf[1], pct(tot), tot[0], tot[1], pct(totb)))
    out.append("")
    out.append("Lines only one session reaches: " + ", ".join("%s %d" % (n, only[n]) for n in names))
    if old:
        out.append("")
        out.append("Against the committed baseline: lines %s -> %s, routines %d -> %d of %d" % (pct(old["total"]["lines"]), pct(tot), old["total"]["functions"][0], totf[0], totf[1]))
    text = "\n".join(out)
    print(text)
    if a.uncovered:
        print("\nRoutines no session runs:")
        print("\n".join(rep["uncovered_functions"]))
    if a.write:
        json.dump(rep, open(JSON, "w"), indent=1, sort_keys=True)
        open(MD, "w").write("# Session coverage (generated by `make coverage WRITE=1`, do not edit)\n\n" + text + "\n\nRoutines no session runs: see `uncovered_functions` in coverage.json.\n")
        print("\nwritten %s and %s" % (os.path.relpath(MD, ROOT), os.path.relpath(JSON, ROOT)))


if __name__ == "__main__":
    main()

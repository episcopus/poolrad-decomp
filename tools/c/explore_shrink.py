#!/usr/bin/env python3
"""explore_shrink.py: cut a script found by explore_fuzz.py down to the keys that matter (delta debugging).

  .venv/bin/python tools/c/explore_shrink.py build/explore/fz/hit-ShopMain.keys ShopMain build/explore/shop.keys

Keeps the lines before the first `key` (the prefix) and removes keys, with the `wait` after each, in ever smaller chunks while the named
routine is still entered. Every try is a run of poolrad_explore (about a second)."""
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
EXE = os.path.join(ROOT, "build/cmake-trace/poolrad_explore")


def hits(lines, name):
    try:
        return _hits(lines, name)
    except subprocess.TimeoutExpired:
        return False


def _hits(lines, name):
    path = os.path.join(ROOT, "build/explore/shrink.keys")
    open(path, "w").write("\n".join(lines) + "\n")
    p = subprocess.run([EXE, "--data", os.path.join(ROOT, "poolrad"), "--save", os.path.join(ROOT, "build/explore/shrink-save"), "--script", path,
                        "--out", os.path.join(ROOT, "build/explore/shrink"), "--max-polls", "40000000"], capture_output=True, text=True,
                       env=dict(os.environ, EXPLORE_WATCH=name), timeout=120)
    return re.search(r"^HIT %s " % name, p.stderr, re.M) is not None


def main():
    src, name, dst = sys.argv[1:4]
    lines = [l.rstrip("\n") for l in open(src) if l.strip()]
    first = next(i for i, l in enumerate(lines) if l.startswith("key"))
    prefix, body = lines[:first], lines[first:]
    # units: a key and the waits after it
    units, cur = [], []
    for l in body:
        if l.startswith("key") or l.startswith("press"):
            if cur:
                units.append(cur)
            cur = [l]
        elif l.startswith("quit"):
            continue
        else:
            cur.append(l)
    if cur:
        units.append(cur)
    assert hits(prefix + [l for u in units for l in u] + ["quit"], name), "the script does not reach %s" % name
    n = max(1, len(units) // 2)
    while n >= 1:
        i = 0
        while i < len(units):
            trial = units[:i] + units[i + n:]
            if hits(prefix + [l for u in trial for l in u] + ["quit"], name):
                units = trial
            else:
                i += n
        n //= 2
    out = prefix + [l for u in units for l in u] + ["quit"]
    open(dst, "w").write("\n".join(out) + "\n")
    print("%s: %d keys left of %d" % (dst, len(units), len(body) // 2))


if __name__ == "__main__":
    main()

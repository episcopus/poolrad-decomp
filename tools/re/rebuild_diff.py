#!/usr/bin/env python3
"""rebuild_diff.py: say where the rebuilt program differs from the original, byte by byte (playbook 50).

  .venv/bin/python tools/re/rebuild_diff.py [--limit N]
  make rebuild-diff

`make rebuild` (tools/match/rebuild.py) reports which segments differ. This tool opens each differing
segment of build/rebuild (run `make rebuild` first) and prints the bytes that differ apart from relocation
words, with a few bytes of context, grouped into runs, plus what the typical causes look like:

  a word that is a DS offset on one side and another on the other   the data layout (`make dgroup`)
  a far call `9A off seg` whose offset differs                       the order of an overlay unit's interface
                                                                     (`make stub-order`) or the link order
  a whole run that is code on one side only                          a unit linked in another place
  differences at the end of the unit only                            padding, or an external object

It reads the link map for our segments and `build/re/overlays.json` for the original's overlays.
"""
from __future__ import annotations

import argparse
import json
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))
sys.path.insert(0, str(ROOT / "tools/re"))

import match  # noqa: E402
import tp_toolchain as tp  # noqa: E402

OUT = ROOT / "build/rebuild"
LIBRARY = {"res00": "SYSTEM", "res01": "CRT", "res13": "DOS", "res14": "OVERLAY"}


def runs_of(idx: list[int]) -> list[list[int]]:
    runs: list[list[int]] = []
    for i in idx:
        if runs and i == runs[-1][1] + 1:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    return runs


def show(label: str, a: bytes, b: bytes, hidden: set[int], limit: int) -> int:
    n = min(len(a), len(b))
    diff = [i for i in range(n) if a[i] != b[i] and i not in hidden]
    pad_ok = len(a) <= len(b) and not any(b[len(a):]) and len(b) - len(a) < 16
    if not diff and (len(a) == len(b) or pad_ok):
        return 0
    print("%s: ours %d bytes, original %d; %d differing bytes" % (label, len(a), len(b), len(diff)))
    if len(a) != len(b) and not pad_ok:
        print("   lengths differ by %d" % (len(b) - len(a)))
    for lo, hi in runs_of(diff)[:limit]:
        c0, c1 = max(0, lo - 4), min(n, hi + 5)
        print("   %04X..%04X  ours %s | original %s" % (lo, hi, a[c0:c1].hex(" "), b[c0:c1].hex(" ")))
    return len(diff)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--limit", type=int, default=6, help="runs shown per segment")
    a = ap.parse_args(argv)
    exe, mapf = tp.ci(OUT, "POOL.EXE"), tp.ci(OUT, "POOL.MAP")
    if exe is None or mapf is None:
        print("no rebuild in build/rebuild: `make rebuild` first")
        return 1
    orig = match.Original()
    img, rel = tp.read_mz(exe)
    segs, _pubs = tp.read_map(mapf)
    units = tomllib.loads((ROOT / "re/units.toml").read_text())
    total = 0
    for u in [{"id": "main"}] + units["resident"]:
        uid = u["id"]
        name = match.PROGRAM if uid == "main" else LIBRARY.get(uid, uid.upper())
        o_bytes, o_seg = orig.segment(uid)
        if name not in segs:
            print("%s: not in the link map" % uid)
            total += 1
            continue
        start, length, _cls = segs[name]
        ours = img[start:start + length]
        o_start = o_seg * 16
        hidden = {r - start + k for r in rel if start <= r < start + length for k in (0, 1)} | \
                 {r - o_start + k for r in orig.relocs if o_start <= r < o_start + len(o_bytes) for k in (0, 1)}
        total += show(uid, ours, o_bytes, hidden, a.limit)
    ours_json = OUT / "overlays/overlays.json"
    if ours_json.exists():
        ours_ovl = {o["overlay"]: o for o in json.loads(ours_json.read_text())["overlays"]}
        for o in json.loads((ROOT / "build/re/overlays.json").read_text())["overlays"]:
            uid = "ovl%02d" % o["overlay"]
            mine = ours_ovl.get(o["overlay"])
            if mine is None:
                print("%s: not in the rebuilt overlay file" % uid)
                total += 1
                continue
            ours = (OUT / "overlays" / (uid + ".bin")).read_bytes()
            theirs = (ROOT / "build/re/overlays" / (uid + ".bin")).read_bytes()
            hidden = {f + k for f in set(mine.get("fixups", [])) | set(o.get("fixups", [])) for k in (0, 1)}
            total += show(uid, ours, theirs, hidden, a.limit)
            ea = [e["code_offset"] for e in mine["entries"]]
            eb = [e["code_offset"] for e in o["entries"]]
            if ea != eb:
                print("%s: stub entries in another order (`make stub-order`)" % uid)
                total += 1
    print("rebuild_diff: %s" % ("no differences" if not total else "%d differing bytes or segments" % total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())

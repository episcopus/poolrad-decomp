#!/usr/bin/env python3
"""bisect_state.py: the first read of a session after which the C translation's state differs from the original's
(DGROUP, heap and video), ignoring the runtime's own bookkeeping.

  .venv/bin/python tools/c/bisect_state.py SESSION [--lo N] [--hi N]
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/c"))
import snap_oracle as so  # noqa: E402

# DGROUP names that are the runtime's own bookkeeping (file handles, the overlay manager, procedure ids)
NOISE_PREFIX = ("Ovr", "HeapError", "FreeList", "FreeZero", "Cfg", "Regs", "Input", "Output", "DirectVideo", "TextAttr",
                "LoaderFile", "SpellHandlers", "AffectHandlers", "SpellTargetPicker", "?", "SaveInt", "PrefixSeg")


def differs(session: str, n: int, workdir: Path) -> dict:
    a, b = str(workdir / "oo"), str(workdir / "cc")
    so.take(session, n, a)
    rpl = ROOT / "build/c/replay" / (session + ".rpl")
    subprocess.run([str(ROOT / "build/cmake/poolrad_replay"), "--data", str(ROOT / "poolrad"), "--save", str(workdir / "save"),
                    "--dump", b, "--snap", str(n), str(rpl)], capture_output=True)
    table = so.names()
    da, db = Path(a + "-snap.dgroup").read_bytes(), Path(b + "-snap.dgroup").read_bytes()
    names = set()
    import export_replay as ex
    ranges = ex.STATIC_MASKS + ex.file_masks()
    for i in range(0x10000):
        if da[i] != db[i] and not any(lo <= i < hi for lo, hi in ranges):
            names.add(so.name_of(i, table).split("+")[0])
    ha, hb = Path(a + "-snap.heap").read_bytes(), Path(b + "-snap.heap").read_bytes()
    heap = sum(1 for x, y in zip(ha, hb) if x != y) + abs(len(ha) - len(hb))
    pa, pb = Path(a + "-snap.planes").read_bytes(), Path(b + "-snap.planes").read_bytes()
    planes = sum(1 for x, y in zip(pa, pb) if x != y)
    return {"names": sorted(names), "heap": heap, "planes": planes}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("session")
    ap.add_argument("--lo", type=int, default=1)
    ap.add_argument("--hi", type=int, default=100000)
    ap.add_argument("--work", default=str(ROOT / "build/c/bisect"))
    a = ap.parse_args(argv)
    w = Path(a.work)
    w.mkdir(parents=True, exist_ok=True)
    lo, hi = a.lo, a.hi
    r0 = differs(a.session, lo, w)
    if r0["names"] or r0["heap"] or r0["planes"]:
        print("already different at read %d: %s heap=%d planes=%d" % (lo, r0["names"][:12], r0["heap"], r0["planes"]))
        return 1
    r = differs(a.session, hi, w)
    if not (r["names"] or r["heap"] or r["planes"]):
        print("no difference at read %d" % hi)
        return 0
    while hi - lo > 1:
        mid = (lo + hi) // 2
        r = differs(a.session, mid, w)
        bad = bool(r["names"] or r["heap"] or r["planes"])
        print("read %d: %s" % (mid, "differs %s heap=%d planes=%d" % (r["names"][:6], r["heap"], r["planes"]) if bad else "same"))
        if bad:
            hi = mid
        else:
            lo = mid
    r = differs(a.session, hi, w)
    print("first difference after read %d: DGROUP %s, heap bytes %d, plane bytes %d" % (hi, r["names"], r["heap"], r["planes"]))
    return 1


if __name__ == "__main__":
    sys.exit(main())

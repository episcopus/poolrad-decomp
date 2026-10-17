#!/usr/bin/env python3
"""snap_oracle.py: DGROUP, heap and video planes of the original at a given read of the outside world, for
comparison with the C translation's `poolrad_replay --snap N --dump PREFIX` (same numbering of reads).

  .venv/bin/python tools/c/snap_oracle.py SESSION N PREFIX
  .venv/bin/python tools/c/snap_oracle.py --diff PREFIX_ORACLE PREFIX_C      names the differing globals
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/c"))

STACK = (0x8760, 0xC760)     # the stack segment inside DGROUP's 64 KB (SS 24F2, 4000h bytes)


def take(session: str, n: int, prefix: str) -> int:
    from oracle import golden, state
    from oracle.run import run_session
    import export_replay as ex
    from oracle import replay

    holder = {}

    class Snap(ex.OrderedRecorder):
        def note(self, kind, value):
            super().note(kind, value)
            if self.streams.total == n:
                m = self.m
                ds = state.dgroup_seg()
                Path(prefix + "-snap.dgroup").write_bytes(bytes(m.read(ds, 0, 0x10000)))
                lo, hi = state.heap_bytes(m, ds), None
                Path(prefix + "-snap.heap").write_bytes(lo)
                Path(prefix + "-snap.planes").write_bytes(b"".join(bytes(p) for p in m.ega.planes))
                from oracle.machine import Stop
                raise Stop("snapshot")

    def prepare(m):
        holder["rec"] = Snap(m)

    text = (golden.SESSIONS / (session + ".keys")).read_text()
    run_session(text, max_insns=golden.MAX_INSNS, quiet=True, prepare=prepare, insn_per_sec=golden.INSN_PER_SEC)
    return 0


def names() -> list[tuple[int, int, str]]:
    out = []
    for line in (ROOT / "c/game/globals.txt").read_text().split("\n"):
        if line.strip():
            o, sz, nm = line.split()[:3]
            out.append((int(o, 16), int(sz), nm))
    return sorted(out)


def name_of(off: int, table) -> str:
    best = None
    for o, sz, nm in table:
        if o <= off < o + max(sz, 1):
            if best is None or o >= best[0]:
                best = (o, sz, nm)
    return "%s+%d" % (best[2], off - best[0]) if best else "?"


def diff(a: str, b: str, limit: int = 40) -> int:
    table = names()
    da, db = Path(a + "-snap.dgroup").read_bytes(), Path(b + "-snap.dgroup").read_bytes()
    import export_replay as ex
    ranges = ex.STATIC_MASKS + ex.file_masks()
    bad = [i for i in range(0x10000) if da[i] != db[i] and not any(lo <= i < hi for lo, hi in ranges)]
    print("DGROUP: %d bytes differ" % len(bad))
    groups: dict[str, list[int]] = {}
    for i in bad:
        groups.setdefault(name_of(i, table).split("+")[0], []).append(i)
    for nm, offs in sorted(groups.items(), key=lambda kv: kv[1][0])[:limit]:
        o = offs[0]
        print("  %-32s %d bytes, first at %04X: original %02X, C %02X" % (nm, len(offs), o, da[o], db[o]))
    ha, hb = Path(a + "-snap.heap").read_bytes(), Path(b + "-snap.heap").read_bytes()
    print("heap: %d vs %d bytes, %d bytes differ" % (len(ha), len(hb), sum(1 for x, y in zip(ha, hb) if x != y)))
    pa, pb = Path(a + "-snap.planes").read_bytes(), Path(b + "-snap.planes").read_bytes()
    pd = [i for i in range(len(pa)) if pa[i] != pb[i]]
    print("planes: %d bytes differ%s" % (len(pd), (", first at plane %d offset %04X" % (pd[0] // 65536, pd[0] % 65536)) if pd else ""))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("c", nargs="?")
    ap.add_argument("--diff", action="store_true")
    a = ap.parse_args(argv)
    if a.diff:
        return diff(a.a, a.b)
    return take(a.a, int(a.b), a.c)


if __name__ == "__main__":
    sys.exit(main())

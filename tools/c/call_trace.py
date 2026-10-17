#!/usr/bin/env python3
"""call_trace.py: the routines the original and the C translation call between two reads of the outside world, side by
side, to find the first routine that behaves differently.

  .venv/bin/python tools/c/call_trace.py SESSION LO HI

Needs the C build with call tracing: cmake -S . -B build/cmake-trace -DPOOLRAD_TRACE=ON && cmake --build build/cmake-trace
(poolrad_replay there prints `call NAME` for each translated routine). The oracle side uses tools/oracle/trace.py.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/c"))


def oracle_calls(session: str, lo: int, hi: int) -> list[str]:
    from oracle import golden, trace
    from oracle.machine import Stop
    from oracle.run import run_session
    import export_replay as ex

    out: list[str] = []
    holder = {}

    class R(ex.OrderedRecorder):
        def note(self, kind, value):
            super().note(kind, value)
            n = self.streams.total
            holder["tr"].active = lo <= n < hi
            if n >= hi:
                raise Stop("enough")

    def prepare(m):
        tr = trace.Tracer(m, calls=True, out=None)
        tr.active = False
        orig_emit = tr.emit

        def emit(line):
            if tr.active and line.lstrip().startswith("call "):
                name = line.strip().split("(")[0].split(" ", 1)[1]
                if not name.startswith(("Overlay_", "System_", "Crt_", "Dos_")):    # the runtime is not translated
                    out.append("%s %s" % (name, ex.masked_digest(holder["m"], holder["rec"].ranges)[:16]))
        tr.emit = emit
        holder["tr"] = tr
        holder["m"] = m
        holder["rec"] = R(m)

    text = (golden.SESSIONS / (session + ".keys")).read_text()
    run_session(text, max_insns=golden.MAX_INSNS, quiet=True, prepare=prepare, insn_per_sec=golden.INSN_PER_SEC)
    return out


def oracle_snap(session: str, lo: int, hi: int, k: int, prefix: str) -> None:
    """DGROUP, heap and planes of the original on entry to the k-th traced routine of the window."""
    from oracle import golden, state, trace
    from oracle.machine import Stop
    from oracle.run import run_session
    import export_replay as ex

    holder = {"n": 0}

    class R(ex.OrderedRecorder):
        def note(self, kind, value):
            super().note(kind, value)
            n = self.streams.total
            holder["tr"].active = lo <= n < hi
            if n >= hi:
                raise Stop("enough")

    def prepare(m):
        tr = trace.Tracer(m, calls=True, out=None)
        tr.active = False

        def emit(line):
            if tr.active and line.lstrip().startswith("call "):
                name = line.strip().split("(")[0].split(" ", 1)[1]
                if name.startswith(("Overlay_", "System_", "Crt_", "Dos_")):
                    return
                if holder["n"] == k:
                    ds = state.dgroup_seg()
                    Path(prefix + "-snap.dgroup").write_bytes(bytes(m.read(ds, 0, 0x10000)))
                    Path(prefix + "-snap.heap").write_bytes(state.heap_bytes(m, ds))
                    Path(prefix + "-snap.planes").write_bytes(b"".join(bytes(p) for p in m.ega.planes))
                    raise Stop("snapshot")
                holder["n"] += 1
        tr.emit = emit
        holder["tr"] = tr
        R(m)

    text = (golden.SESSIONS / (session + ".keys")).read_text()
    run_session(text, max_insns=golden.MAX_INSNS, quiet=True, prepare=prepare, insn_per_sec=golden.INSN_PER_SEC)


def c_calls(session: str, lo: int, hi: int) -> list[str]:
    exe = ROOT / "build/cmake-trace/poolrad_replay"
    p = subprocess.run([str(exe), "--data", str(ROOT / "poolrad"), "--save", str(ROOT / "build/c/save-trace"),
                        "--trace-calls", str(lo), str(hi), str(ROOT / "build/c/replay" / (session + ".rpl"))],
                       capture_output=True, text=True)
    return [l.split(" ", 1)[1] for l in p.stdout.splitlines() if l.startswith("call ")]


def split(c):
    n, _, d = c.partition(" ")
    return n, d


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("session")
    ap.add_argument("lo", type=int)
    ap.add_argument("hi", type=int)
    ap.add_argument("--states", action="store_true", help="compare the sequence of state digests, not the names of the calls")
    ap.add_argument("--snap", nargs=3, metavar=("K_ORACLE", "K_C", "PREFIX"),
                    help="write snapshots at the K-th call of each side (PREFIX-o and PREFIX-c) to diff with snap_oracle --diff")
    a = ap.parse_args(argv)
    if a.snap:
        ko, kc, pre = int(a.snap[0]), int(a.snap[1]), a.snap[2]
        oracle_snap(a.session, a.lo, a.hi, ko, pre + "-o")
        subprocess.run([str(ROOT / "build/cmake-trace/poolrad_replay"), "--data", str(ROOT / "poolrad"), "--save",
                        str(ROOT / "build/c/save-trace"), "--trace-calls", str(a.lo), str(a.hi), "--snap-call", str(kc),
                        "--dump", pre + "-c", str(ROOT / "build/c/replay" / (a.session + ".rpl"))], capture_output=True)
        return 0
    o, c = oracle_calls(a.session, a.lo, a.hi), c_calls(a.session, a.lo, a.hi)
    print("oracle: %d calls, C: %d calls" % (len(o), len(c)))
    if a.states:
        # the state changes only: nested routines are not in the original's trace, so compare what the calls changed
        def changes(lst):
            out, last = [], None
            for x in lst:
                n, d = split(x)
                if d != last:
                    out.append((n, d))
                    last = d
            return out
        co, cc = changes(o), changes(c)
        for i, (x, y) in enumerate(zip(co, cc)):
            if x[1] != y[1]:
                print("state sequences differ at change %d: original %s on entry to %s, C %s on entry to %s" % (i, x[1], x[0], y[1], y[0]))
                print("before:", [v[0] for v in co[max(0, i - 4):i]])
                return 1
        print("same state changes (%d, %d)" % (len(co), len(cc)))
        return 0
    for i, (x, y) in enumerate(zip(o, c)):
        if split(x)[0] != split(y)[0]:
            print("first difference at call %d: original %s, C %s" % (i, x, y))
            print("context:", [split(v)[0] for v in o[max(0, i - 5):i + 3]], "|", [split(v)[0] for v in c[max(0, i - 5):i + 3]])
            return 1
        if split(x)[1] != split(y)[1]:
            print("same call %d (%s) but the state on entry differs: original %s, C %s" % (i, split(x)[0], split(x)[1], split(y)[1]))
            print("previous calls:", [split(v)[0] for v in o[max(0, i - 6):i]])
            return 1
    if len(o) != len(c):
        print("same up to call %d; then the original %s, C %s" % (min(len(o), len(c)), o[len(c):len(c) + 3], c[len(o):len(o) + 3]))
        return 1
    print("same calls")
    return 0


if __name__ == "__main__":
    sys.exit(main())

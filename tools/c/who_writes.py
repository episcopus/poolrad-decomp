#!/usr/bin/env python3
"""who_writes.py: which routine of the original writes a given address (to find what the C translation does
differently). Runs a session to the Nth read of the outside world and lists the first writers.

  .venv/bin/python tools/c/who_writes.py SESSION LINEAR LENGTH [--reads N] [--max 10]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/c"))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("session")
    ap.add_argument("linear", type=lambda x: int(x, 0))
    ap.add_argument("length", type=int)
    ap.add_argument("--reads", type=int, default=0)
    ap.add_argument("--max", type=int, default=10)
    ap.add_argument("--exclude", action="append", default=[], help="a writer to skip (e.g. 0AF8:16B7, System FillChar)")
    ap.add_argument("--nonzero", action="store_true", help="only writes of a value other than zero")
    a = ap.parse_args(argv)
    from unicorn import UC_HOOK_MEM_WRITE
    from oracle import golden, trace
    from oracle.machine import Stop
    from oracle.run import run_session
    import export_replay as ex

    found = []

    class R(ex.OrderedRecorder):
        def note(self, kind, value):
            super().note(kind, value)
            if a.reads and self.streams.total >= a.reads:
                raise Stop("enough")

    def prepare(m):
        R(m)
        stubs = trace.overlay_stubs()

        def cb(uc, access, address, size, value, _ud):
            if len(found) < a.max and (value or not a.nonzero):
                pc = (m.get("cs") << 4) + m.get("ip")
                where = trace.locate(m, pc, stubs)
                if where not in a.exclude:
                    found.append((address, size, value, where))
        m.uc.hook_add(UC_HOOK_MEM_WRITE, cb, begin=a.linear, end=a.linear + a.length - 1)

    text = (golden.SESSIONS / (a.session + ".keys")).read_text()
    run_session(text, max_insns=golden.MAX_INSNS, quiet=True, prepare=prepare, insn_per_sec=golden.INSN_PER_SEC)
    for addr, size, val, where in found:
        print("write %05X size %d value %X by %s" % (addr, size, val, where))
    return 0


if __name__ == "__main__":
    sys.exit(main())

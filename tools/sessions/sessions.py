#!/usr/bin/env python3
"""sessions.py: replay goldens with C routines inside the oracle (SPEC 8.5).

  .venv/bin/python tools/sessions/sessions.py [--session NAME] [--routine ID]
  make sessions [SESSION=name]   (default: boot-title and create-character)

Each golden carries the recording of its run's reads of the outside world
(tools/oracle/replay.py, Exhume's method; `make golden` writes it and
`make golden CHECK=1` verifies it against the original). This tool runs the
game with the lifted routines replaced by the C hybrid library
(tools/oracle/hybrid.py), answers every read from the recording, and compares
at the same reads: no-stack canonical state (DGROUP, heap, video), all memory
outside the stack, screen, Random count, timer interrupts; at the end also the
Random sequence and the files written. No time is charged for C: time only
matters where the game reads it, and those reads are replayed.

Exit 0 when every session matches, 1 with the first difference otherwise.
P3 spike: System_Move, System_FillChar, System_Random. Later units add their
ids to SPIKE_ROUTINES (or pass --routine) without changing the mechanism.
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle import golden, replay, routines  # noqa: E402
from oracle.hybrid import HybridLib, PARAMS  # noqa: E402
from oracle.run import EXE  # noqa: E402

SPIKE_ROUTINES = ["0AF8:1685", "0AF8:16A8", "0AF8:11C0"]


def run_replay(name: str, routine_ids: list[str]) -> int:
    d = golden.GOLDEN / name
    g = json.loads((d / "golden.json").read_text())
    if g.get("format") != golden.FORMAT:
        print("[%s] FAIL: golden format %r, tools write %d: re-record it (make golden)" % (
            name, g.get("format"), golden.FORMAT))
        return 1
    if (g["script_sha256"] != golden.sha256_file(golden.SESSIONS / (name + ".keys"))
            or g["exe_sha256"] != golden.sha256_file(EXE)):
        print("[%s] FAIL: the script or the executable changed since the golden was recorded" % name)
        return 1
    rec = replay.Recording.load(d / golden.RECORDING)
    hyb = HybridLib()
    fns = {"0AF8:1685": hyb.c_move, "0AF8:16A8": hyb.c_fill, "0AF8:11C0": hyb.c_random}
    calls = collections.Counter()

    def prepare(m):
        for rid in routine_ids:
            p = PARAMS[rid]

            def fn(mm, rid=rid, f=fns[rid]):
                r = f(mm)
                if r is not False:
                    calls[rid] += 1
                return r
            routines.replace(m, rid, fn, ret_bytes=p["ret_bytes"], far=p["far"])

    t = time.time()
    got, player = replay.replay(rec, prepare)
    diff = replay.difference(rec, got, player)
    counts = ", ".join("%s %d" % (PARAMS[r]["name"], calls[r]) for r in routine_ids)
    if diff:
        print("[%s] FAIL (C calls: %s): %s" % (name, counts, diff))
        return 1
    missing = [r for r in routine_ids if not calls[r]]
    if missing:
        print("[%s] FAIL: C never ran for %s" % (name, missing))
        return 1
    print("[%s] ok (%.1fs): C routines reproduce the recording at all %d reads and %d checkpoints (C calls: %s)"
          % (name, time.time() - t, rec.streams.total, sum(len(v) for v in rec.checkpoints.values()), counts))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--session", action="append", default=None)
    ap.add_argument("--routine", action="append", default=None)
    a = ap.parse_args(argv)
    rc = 0
    for n in a.session or ["boot-title", "create-character"]:
        if not (golden.SESSIONS / (n + ".keys")).exists():
            print("no such session: %s" % n)
            rc = 1
            continue
        rc |= run_replay(n, a.routine or SPIKE_ROUTINES)
    return rc


if __name__ == "__main__":
    sys.exit(main())

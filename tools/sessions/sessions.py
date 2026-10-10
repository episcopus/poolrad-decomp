#!/usr/bin/env python3
"""sessions.py: replay goldens with C routines inside the oracle (SPEC 8.5).

  .venv/bin/python tools/sessions/sessions.py [--session NAME]
  make sessions [SESSION=name]   (default: boot-title)

For each session: record the per-call costs of the lifted routines on the
original (timing.py, exact time), then run again with those routines replaced
by the C hybrid library (tools/oracle/hybrid.py) and compare the hybrid view
(time, screens, no-stack state, Random sequence) against the committed golden.
Exit 0 when every session matches, 1 with the first difference otherwise.

P3 spike: System_Move, System_FillChar, System_Random. Later units add their
ids to SPIKE_ROUTINES (or pass --routine) without changing the mechanism.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle import golden, timing  # noqa: E402
from oracle.hybrid import HybridLib, PARAMS  # noqa: E402
from oracle.run import run_session  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPIKE_ROUTINES = ["0AF8:1685", "0AF8:16A8", "0AF8:11C0"]
# 0AF8:11C0 (Random) inlines its step callee 0AF8:120F, which therefore never
# runs in a hybrid run. timing.py charges a routine's own code only (callees
# "run for real"), so the step's instructions would go missing from hybrid
# time. The merge below charges each 11C0 call with its own code plus the
# step instructions nested inside it. Sound here because every call site of
# the step lies inside the 11C0 block (0x11C0, 0x11D6, 0x11F3) and Random does
# not recurse. P4 routines that inline callees need the same treatment.
STEP_CHILD = "0AF8:120F"


def record_merged(text: str, routine_ids: list[str]) -> timing.CostTable:
    """Record costs; the Random step callee is merged into its caller (above)."""
    from oracle.run import run_session
    holder = {}
    want = list(routine_ids)
    if "0AF8:11C0" in want and STEP_CHILD not in want:
        want = want + [STEP_CHILD]

    def prepare(m):
        holder["rec"] = timing.CostRecorder(m, want)

    run_session(text, max_insns=golden.MAX_INSNS, quiet=True, exact=True, prepare=prepare)
    rec = holder["rec"]
    if "0AF8:11C0" in routine_ids:
        parents = rec.rows["0AF8:11C0"]
        children = rec.rows[STEP_CHILD]
        merged = [[t, n, e] for t, n, e in parents]
        used = [0] * len(parents)
        for ct, cn, ce in children:
            i = None
            for k, (pt, _pn, _pe) in enumerate(parents):
                if pt <= ct:
                    i = k
            if i is None:
                raise RuntimeError("step call at %d precedes every 0AF8:11C0 call" % ct)
            merged[i][1] += cn
            merged[i][2] += ce
            used[i] += 1
        if len(children) != len(parents) or any(u != 1 for u in used):
            raise RuntimeError("each 0AF8:11C0 call must inline exactly one step call "
                               "(%d parents, %d steps)" % (len(parents), len(children)))
        rec.rows["0AF8:11C0"] = merged
        del rec.rows[STEP_CHILD]
    return timing.CostTable({k: rec.rows[k] for k in routine_ids},
                            {"merged_child": STEP_CHILD})


def run_hybrid(name: str, routine_ids: list[str]) -> int:
    text = (golden.SESSIONS / (name + ".keys")).read_text()
    print("[%s] recording costs on the original ..." % name, flush=True)
    table = record_merged(text, routine_ids)
    for rid, rows in table.rows.items():
        print("[%s] %s: %d calls" % (name, rid, len(rows)), flush=True)
    hyb = HybridLib()
    fns = {"0AF8:1685": hyb.c_move, "0AF8:16A8": hyb.c_fill, "0AF8:11C0": hyb.c_random}

    def prepare(m):
        for rid in routine_ids:
            p = PARAMS[rid]
            timing.replace(m, rid, fns[rid], ret_bytes=p["ret_bytes"], far=p["far"], table=table)

    print("[%s] hybrid run with C routines ..." % name, flush=True)
    s = run_session(text, max_insns=golden.MAX_INSNS, quiet=True, exact=True, prepare=prepare)
    got = golden.hybrid_view(golden.summarise(s))
    g = golden.json.loads((golden.GOLDEN / name / "golden.json").read_text())
    want = golden.hybrid_view({k: g[k] for k in golden.summarise(s)})
    diff = golden.hybrid_difference(want, got)
    if diff:
        print("[%s] FAIL: hybrid run differs from golden: %s" % (name, diff))
        return 1
    for note in golden.hybrid_spinner_notes(want, got):
        print("[%s] note: %s" % (name, note))
    print("[%s] ok: C routines reproduce the golden (%d checkpoints, %d key reads)" % (
        name, len(got["checkpoints"]), got["key_reads"]))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--session", action="append", default=None)
    ap.add_argument("--routine", action="append", default=None)
    a = ap.parse_args(argv)
    rc = 0
    routines = a.routine or SPIKE_ROUTINES
    sessions = a.session or ["boot-title"]
    for n in sessions:
        if not (golden.SESSIONS / (n + ".keys")).exists():
            print("no such session: %s" % n)
            rc = 1
            continue
        rc |= run_hybrid(n, routines)
    return rc


if __name__ == "__main__":
    sys.exit(main())

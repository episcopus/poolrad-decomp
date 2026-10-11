#!/usr/bin/env python3
"""golden.py: record or verify session goldens (SPEC 8.5, playbook 40, `make golden`).

  .venv/bin/python tools/oracle/golden.py [--session NAME ...] [--check] [--out-root DIR]

Recording runs each session script twice on the original code in the oracle. The two runs must be
identical in every digest (stop reason, instruction count, checkpoints, per-key-read digests, random
sequence, final state); otherwise nothing is written and the first difference is reported.
A golden lives in `tests/sessions/golden/<name>/`:

  golden.json   verdict data: script hash, input hash, settings, checkpoints, summary digests
  reads.txt     one full state digest (16 hex) per keyboard read, in order
  reads_nostack.txt  the same without the stack segment (the form a hybrid run can match)
  <label>.png   our own screenshot at each named `shot` (to be looked at by a person: playbook 40 step 3)
  replay.json.gz  the run's reads of the outside world and its checkpoints (tools/oracle/replay.py):
                what a build of ours (rebuild, C translation) is replayed against

`--check` re-runs each session once and compares against the committed golden (screen and state
digests, not PNG bytes, which depend on the zlib build) and its recording. Goldens hold digests, our own
screenshots and recordings of our own runs; never copies of game files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle import replay  # noqa: E402
from oracle.machine import ROOT  # noqa: E402
from oracle.run import EXE  # noqa: E402

SESSIONS = ROOT / "tests/sessions"
GOLDEN = SESSIONS / "golden"
FORMAT = 3                        # 3: heap in the canonical state (re/state.toml), recording saved
RECORDING = "replay.json.gz"
MAX_INSNS = 400_000_000
INSN_PER_SEC = 1_000_000          # run_session default; recorded so a changed clock model is visible


def sha256_file(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def summarise(s: dict) -> dict:
    """The comparable verdict data of one run (no host-dependent values, no screenshots bytes)."""
    reads = s["read_digests"]
    reads_nostack = s["read_nostack_digests"]
    return {
        "stop_reason": s["reason"],
        "instructions": s["insns"],
        "virtual_seconds": s["virtual_seconds"],
        "video_mode": s["mode"],
        "key_reads": s["key_reads"],
        "reads_sha256": hashlib.sha256("\n".join(reads).encode()).hexdigest(),
        "reads_nostack_sha256": hashlib.sha256("\n".join(reads_nostack).encode()).hexdigest(),
        "state_digest": s["state_digest"],
        "canonical_digest": s["canonical_digest"],
        "canonical_nostack_digest": s["canonical_nostack_digest"],
        "random_calls": s["random_calls"],
        "random_digest": s["random_digest"],
        "files_opened": s["files_opened"],
        "checkpoints": [{k: c[k] for k in ("label", "time", "screen", "canonical", "canonical_nostack", "digest",
                                           "random_calls")} for c in s["checkpoints"]],
    }


def first_difference(a: dict, b: dict, a_reads: list[str] = (), b_reads: list[str] = ()) -> str | None:
    for k in a:
        if k == "checkpoints":
            for i, (x, y) in enumerate(zip(a[k], b[k])):
                if x != y:
                    return "checkpoint %d (%s): %s" % (i, x["label"], {f: (x[f], y[f]) for f in x if x[f] != y[f]})
            if len(a[k]) != len(b[k]):
                return "checkpoint count %d != %d" % (len(a[k]), len(b[k]))
        elif a[k] != b[k]:
            if k == "reads_sha256":
                for i, (x, y) in enumerate(zip(a_reads, b_reads)):
                    if x != y:
                        return "key read %d: state digest %s != %s" % (i, x, y)
            return "%s: %r != %r" % (k, a[k], b[k])
    return None


def run_once(name: str, out_dir: Path | None = None):
    """One run of the original with its script; returns (summary, replay.Recording)."""
    text = (SESSIONS / (name + ".keys")).read_text()
    return replay.record(text, max_insns=MAX_INSNS, out_dir=out_dir, insn_per_sec=INSN_PER_SEC)


def record(name: str, out_root: Path) -> int:
    print("[%s] run 1 ..." % name, flush=True)
    a, rec_a = run_once(name, out_root / name)
    print("[%s] run 2 ..." % name, flush=True)
    b, rec_b = run_once(name)
    sa, sb = summarise(a), summarise(b)
    if a["reason"] not in ("input-exhausted", "quit"):
        print("[%s] FAIL: unexpected stop %s %s" % (name, a["reason"], a["error"] or ""), file=sys.stderr)
        return 1
    diff = first_difference(sa, sb, a["read_digests"], b["read_digests"])
    if not diff and rec_a.digest() != rec_b.digest():
        diff = "the recordings of the outside world differ"
    if diff:
        print("[%s] FAIL: the two runs differ: %s" % (name, diff), file=sys.stderr)
        return 1
    d = out_root / name
    shots = sorted((d / "shots").glob("*.png")) if (d / "shots").exists() else []
    # keep only our named screenshots, flat next to the digests
    for p in shots:
        p.replace(d / p.name)
    for leftover in ("shots", "console.txt", "summary.json", "final.png"):
        t = d / leftover
        if t.is_dir():
            t.rmdir()
        elif t.exists():
            t.unlink()
    (d / "reads.txt").write_text("\n".join(a["read_digests"]) + "\n")
    (d / "reads_nostack.txt").write_text("\n".join(a["read_nostack_digests"]) + "\n")
    rec_a.save(d / RECORDING)
    keep = {"golden.json", "reads.txt", "reads_nostack.txt", RECORDING} | {c["label"] + ".png" for c in sa["checkpoints"]}
    for stale in d.iterdir():
        if stale.name not in keep:
            stale.unlink()                     # leftovers of an older format or of removed checkpoints
    gold = {
        "format": FORMAT,
        "session": name,
        "script_sha256": sha256_file(SESSIONS / (name + ".keys")),
        "exe": "poolrad/start-unpack.exe",
        "exe_sha256": sha256_file(EXE),
        "insn_per_sec": INSN_PER_SEC,
        "recorded_runs": 2,
        **sa,
    }
    (d / "golden.json").write_text(json.dumps(gold, indent=1) + "\n")
    print("[%s] golden written: %d checkpoints, %d key reads, %d instructions, %d Random calls; recording: %s" % (
        name, len(sa["checkpoints"]), sa["key_reads"], sa["instructions"], sa["random_calls"],
        replay.describe(rec_a)))
    return 0


def check(name: str, out_root: Path) -> int:
    gp = out_root / name / "golden.json"
    if not gp.exists():
        print("[%s] FAIL: no golden at %s" % (name, gp), file=sys.stderr)
        return 1
    gold = json.loads(gp.read_text())
    if gold.get("format") != FORMAT:
        print("[%s] FAIL: golden format %r, tool writes %d; re-record it" % (name, gold.get("format"), FORMAT), file=sys.stderr)
        return 1
    if gold["script_sha256"] != sha256_file(SESSIONS / (name + ".keys")):
        print("[%s] FAIL: the script changed since the golden was recorded; re-record it" % name, file=sys.stderr)
        return 1
    if gold["exe_sha256"] != sha256_file(EXE):
        print("[%s] FAIL: the pinned executable differs from the one the golden was recorded on" % name, file=sys.stderr)
        return 1
    r, rec = run_once(name)
    got = summarise(r)
    want = {k: gold[k] for k in got}
    want_reads = (out_root / name / "reads.txt").read_text().split()
    diff = first_difference(want, got, want_reads, r["read_digests"])
    if not diff:
        try:
            if replay.Recording.load(out_root / name / RECORDING).digest() != rec.digest():
                diff = "the recording of the outside world (%s) differs" % RECORDING
        except (OSError, ValueError) as e:
            diff = "recording: %s" % e
    if diff:
        print("[%s] FAIL: differs from golden: %s" % (name, diff), file=sys.stderr)
        return 1
    print("[%s] ok: matches golden (%d checkpoints, %d key reads)" % (name, len(got["checkpoints"]), got["key_reads"]))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--session", action="append", help="session name (tests/sessions/NAME.keys); default: all")
    ap.add_argument("--check", action="store_true", help="verify committed goldens instead of recording")
    ap.add_argument("--out-root", default=str(GOLDEN))
    a = ap.parse_args(argv)
    names = a.session or sorted(p.stem for p in SESSIONS.glob("*.keys"))
    if not names:
        print("no sessions in %s" % SESSIONS, file=sys.stderr)
        return 1
    root = Path(a.out_root)
    rc = 0
    for n in names:
        if not (SESSIONS / (n + ".keys")).exists():
            print("no such session: %s" % n, file=sys.stderr)
            rc = 1
            continue
        rc |= (check if a.check else record)(n, root)
    return rc


if __name__ == "__main__":
    sys.exit(main())

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

`--rebuilt` (with `--check`) runs the program `make rebuild` linked (build/rebuild/POOL.EXE and POOL.OVR,
Phase 5, playbook 50) against the goldens recorded on the original. Two tiers, both reported:

  behaviour  what the program did in the outside world and on the screen: stop reason, instructions,
             virtual time, video mode, key reads, Random calls and their sequence, files opened, every
             checkpoint's screen and time, the recording's streams of reads of the outside world and the
             files written. This is the gate: equal means the rebuilt game played the session identically.
  state      the DGROUP, heap and memory digests. Equal only when the rebuild's data layout is the
             original's (`make rebuild` identical); until then reported, not failed (`--strict-state`).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle import layout, replay  # noqa: E402
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


BEHAVIOUR = ("stop_reason", "instructions", "virtual_seconds", "video_mode", "key_reads", "random_calls",
             "random_digest", "files_opened")
CHECKPOINT_BEHAVIOUR = ("label", "time", "screen", "random_calls")
STATE = ("state_digest", "canonical_digest", "canonical_nostack_digest", "reads_sha256", "reads_nostack_sha256")
RECORDING_FINAL = ("reason", "random_calls", "random_digest", "files_opened", "mode", "written_files")


def _short(v, n: int = 120) -> str:
    t = repr(v)
    return t if len(t) <= n else t[:n] + "... (%d chars)" % len(t)


def behaviour_differences(want: dict, got: dict, want_rec: "replay.Recording", rec: "replay.Recording") -> list[str]:
    """Every difference in what the program did (not in where it keeps it), most basic first."""
    out = []
    for k in BEHAVIOUR:
        if want[k] != got[k]:
            if isinstance(want[k], list):
                i = next((i for i, (a, b) in enumerate(zip(want[k], got[k])) if a != b), min(len(want[k]), len(got[k])))
                out.append("%s: %d != %d entries, first difference at %d (%s != %s)" % (
                    k, len(want[k]), len(got[k]), i, _short(want[k][i:i + 1]), _short(got[k][i:i + 1])))
            else:
                out.append("%s: %s != %s" % (k, _short(want[k]), _short(got[k])))
    wc, gc = want["checkpoints"], got["checkpoints"]
    if len(wc) != len(gc):
        out.append("checkpoint count %d != %d" % (len(wc), len(gc)))
    for i, (x, y) in enumerate(zip(wc, gc)):
        for k in CHECKPOINT_BEHAVIOUR:
            if x[k] != y[k]:
                out.append("checkpoint %d (%s) %s: %s != %s" % (i, x["label"], k, _short(x[k], 24), _short(y[k], 24)))
    def plain(v):                       # a recording from disk holds lists, a fresh run tuples
        return json.loads(json.dumps(v))
    for kind in sorted(set(want_rec.streams.runs) | set(rec.streams.runs)):
        if plain(want_rec.streams.runs.get(kind)) != plain(rec.streams.runs.get(kind)):
            out.append("reads of the outside world differ in stream %r" % kind)
    for k in RECORDING_FINAL:
        if plain(want_rec.final.get(k)) != plain(rec.final.get(k)):
            out.append("recording final %s differs" % k)
    return out


def state_difference(gold: dict, got: dict) -> str | None:
    for k in STATE:
        if gold[k] != got[k]:
            return k
    return None


def check_rebuilt(name: str, out_root: Path, strict_state: bool) -> int:
    gp = out_root / name / "golden.json"
    if not gp.exists():
        print("[%s] FAIL: no golden at %s" % (name, gp), file=sys.stderr)
        return 1
    gold = json.loads(gp.read_text())
    if gold.get("format") != FORMAT or gold["script_sha256"] != sha256_file(SESSIONS / (name + ".keys")):
        print("[%s] FAIL: stale golden (format or script changed); re-record it on the original" % name,
              file=sys.stderr)
        return 1
    if gold["exe_sha256"] != sha256_file(EXE):
        print("[%s] FAIL: the pinned executable differs from the one the golden was recorded on" % name,
              file=sys.stderr)
        return 1
    want_rec = replay.Recording.load(out_root / name / RECORDING)
    r, rec = run_once(name)
    got = summarise(r)
    if r["reason"] == "guest-fault" or r["reason"] == "unimplemented":
        print("[%s] FAIL: the rebuilt program stopped: %s %s after %d instructions" % (
            name, r["reason"], r["error"] or "", r["insns"]), file=sys.stderr)
        return 1
    why = behaviour_differences({k: gold[k] for k in got}, got, want_rec, rec)
    if why:
        print("[%s] FAIL: the rebuilt program played differently (%d differences):" % (name, len(why)),
              file=sys.stderr)
        for w in why[:12]:
            print("    " + w, file=sys.stderr)
        return 1
    sd = state_difference(gold, got)
    if sd and strict_state:
        print("[%s] FAIL: behaviour equal, state differs (%s)" % (name, sd), file=sys.stderr)
        return 1
    print("[%s] ok (rebuilt): behaviour equal (%d checkpoints, %d key reads, %d instructions); state %s" % (
        name, len(got["checkpoints"]), got["key_reads"], got["instructions"],
        "equal" if not sd else "differs (%s; the data layout is not the original's yet)" % sd))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--session", action="append", help="session name (tests/sessions/NAME.keys); default: all")
    ap.add_argument("--check", action="store_true", help="verify committed goldens instead of recording")
    ap.add_argument("--out-root", default=str(GOLDEN))
    ap.add_argument("--rebuilt", action="store_true",
                    help="with --check: run build/rebuild/POOL.EXE and compare behaviour (and state) with the goldens")
    ap.add_argument("--strict-state", action="store_true", help="with --rebuilt: a state difference fails too")
    a = ap.parse_args(argv)
    if a.rebuilt and not a.check:
        print("--rebuilt only checks; goldens are recorded on the original", file=sys.stderr)
        return 1
    if a.rebuilt:
        layout.use(layout.rebuilt())
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
        if a.rebuilt:
            rc |= check_rebuilt(n, root, a.strict_state)
        else:
            rc |= (check if a.check else record)(n, root)
    return rc


if __name__ == "__main__":
    sys.exit(main())

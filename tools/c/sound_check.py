#!/usr/bin/env python3
"""sound_check.py: compare the C sound driver's hardware trace with the oracle's golden.

  .venv/bin/python tools/c/sound_check.py [--probe build/cmake/sound_probe]

Builds nothing: it runs the probe binary (c/tests/sound_probe.c, built by the CMake target sound_probe) and compares
the SEQUENCE of events (kind, a, b) with tests/sessions/golden/sound-driver. Times differ (the oracle counts
instructions, the probe counts timer ticks), so the digest compared is `sound_sequence_digest`, the one over the
events in order without times.

The oracle sorts events of equal time by kind (P = PIT channel 0 reload, then S = speaker, then T = Tandy byte), and
its clock only advances per instruction chunk, so the events of a timer tick and of the calls right after it share
a time. The probe prints after its events the virtual time each event belongs to (see the probe's header); this
script applies the same stable sort (time, kind) before comparing, which gives the oracle's order.

Exit 0 when the sequences are identical, 1 otherwise (the first differing event is reported).
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOLDEN = ROOT / "tests/sessions/golden/sound-driver"
KIND_ORDER = "PST"


def parse_probe(text: str) -> list[tuple[str, int, int]]:
    lines = text.splitlines()
    cut = lines.index("--")
    events = []
    for line in lines[:cut]:
        kind, a, b = line.split()
        events.append((kind, int(a), int(b)))
    marks = [tuple(int(x) for x in line.split()) for line in lines[cut + 1:]]   # (first event index, vtime)
    times = [0] * len(events)
    for i, (start, vtime) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(events)
        for k in range(start, end):
            times[k] = vtime
    order = sorted(range(len(events)), key=lambda k: (times[k], KIND_ORDER.index(events[k][0])))
    return [events[k] for k in order]


def digest(events: list[tuple[str, int, int]]) -> str:
    """oracle/sound.py digest(ev, with_time=False)."""
    h = hashlib.sha256()
    for kind, a, b in events:
        h.update((" %s %d %d\n" % (kind, a, b)).encode())
    return h.hexdigest()


def load_golden() -> list[tuple[str, int, int]]:
    out = []
    for line in gzip.decompress((GOLDEN / "sound.txt.gz").read_bytes()).decode().splitlines():
        _t, kind, a, b = line.split()
        out.append((kind, int(a), int(b)))
    return out


def kinds(events) -> dict[str, int]:
    return {k: sum(1 for e in events if e[0] == k) for k in KIND_ORDER}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--probe", default=str(ROOT / "build/cmake/sound_probe"))
    args = ap.parse_args(argv)
    probe = Path(args.probe)
    if not probe.exists():
        print("sound-check: FAIL: %s not built (cmake --build build/cmake --target sound_probe)" % probe)
        return 1
    run = subprocess.run([str(probe)], capture_output=True, text=True, check=True)
    got = parse_probe(run.stdout)
    gold_info = json.loads((GOLDEN / "golden.json").read_text())
    if digest(got) == gold_info["sound_sequence_digest"]:
        print("sound-check: ok: %d events, sequence identical to the oracle's (P=%d S=%d T=%d)" % (
            (len(got),) + tuple(kinds(got)[k] for k in KIND_ORDER)))
        return 0
    want = load_golden()
    k = kinds(got)
    print("sound-check: FAIL: %d events (P=%d S=%d T=%d), golden %d (P=%d S=%d T=%d)" % (
        (len(got), k["P"], k["S"], k["T"], len(want)) + tuple(kinds(want)[x] for x in KIND_ORDER)))
    for i, (g, w) in enumerate(zip(got, want)):
        if g != w:
            print("first difference at event %d: C %r, golden %r" % (i, g, w))
            for j in range(max(0, i - 3), min(len(want), i + 4)):
                print("  %5d  golden %-18r C %r" % (j, want[j], got[j] if j < len(got) else None))
            return 1
    print("one trace is a prefix of the other (lengths %d, %d)" % (len(got), len(want)))
    return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""check.py: the DOS port's driver plays what the listening page played (README.md).

  .venv/bin/python ports/dos/sound/capture.py                                   the original (capture.json)
  .venv/bin/python ports/dos/sound/capture.py --build ports/dos/build/link --out port.json
  python3 ports/dos/sound/check.py

For every tune 1..20, the port's writes to port C0h against the expectation:
  - a designed tune (picks.json): the script's bytes in order, frame f written on the timer tick 2f after the
    first (the player runs every second tick), then only the chip quiet (attenuation 15 on the four channels);
  - every other tune: the original's writes with the noise fix (build.noise_fixed: an unchanged noise control
    dropped), byte for byte and tick for tick: what the page's "Noise fixed" lane rendered.
Exit status 0 when every tune matches.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import build  # noqa: E402
import port  # noqa: E402

QUIET = {0x9F, 0xBF, 0xDF, 0xFF}
TICK = 1 / build.TICK


def ticks(log):
    """(tick index from the first write, byte)."""
    t0 = log[0][0]
    return [(int(round((t - t0) / TICK)), b) for t, b in log]


def main() -> int:
    orig = json.loads((build.OUT / "capture.json").read_text())["tunes"]
    got = json.loads((build.OUT / "port.json").read_text())["tunes"]
    scripts = {s - 1: data for s, data in port.designed().items()}
    bad = 0
    for tune in range(1, 21):
        p = [tuple(e) for e in got[str(tune)]["tandy"]]
        if tune in scripts:
            want = port.decode(scripts[tune])
            have = ticks(p)
            body, tail = have[:len(want)], have[len(want):]
            ok_bytes = [b for f, b in body] == [b for f, b in want]
            ok_time = all(t == 2 * f for (t, _), (f, _) in zip(body, want))
            ok_tail = all(b in QUIET for t, b in tail)
            ok = ok_bytes and ok_time and ok_tail
            what = "designed (sound %d): %d script writes %s, frames on every second tick %s, then quiet %s" % (
                tune + 1, len(want), "same" if ok_bytes else "DIFFER", "yes" if ok_time else "NO",
                "yes" if ok_tail else "NO")
        else:
            want = build.noise_fixed([tuple(e) for e in orig[str(tune)]["tandy"]])
            same = [b for t, b in p] == [b for t, b in want]
            close = same and all(abs(a[0] - b[0]) < TICK / 4 for a, b in zip(p, want))
            dropped = len(orig[str(tune)]["tandy"]) - len(want)
            ok = close
            what = "original, noise fixed: %d writes (%d noise writes dropped) %s" % (
                len(want), dropped, "same, same ticks" if close else ("same bytes, ticks differ" if same else "DIFFER"))
        bad += not ok
        print("tune %2d %s %s" % (tune, "ok  " if ok else "FAIL", what))
    print("check: %s" % ("every tune plays as the page did" if not bad else "%d tunes differ" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

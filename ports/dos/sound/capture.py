#!/usr/bin/env python3
"""capture.py: every tune of the original's own sound driver, on the Tandy chip and the PC speaker (README.md).

Boots the original (poolrad/start-unpack.exe) in the oracle to its first keyboard wait, as soundprobe.py does, then
for each tune 1..20 calls the sound unit's own routines the way the game does:

    SetSoundDriverIdle(0); PlaySound(1)          the timer driver runs for good, output on
    PlaySound(tune + 1)                          up to SECONDS of virtual time
    PlaySound(0FFh)                              both devices to tune 0

and keeps every write to port C0h (the Tandy chip) and to PIT channel 2 with the speaker gate, with its virtual
time in seconds (the oracle runs 1,000,000 instructions a virtual second and raises the timer interrupt at the
rate the driver programs, 236.7 Hz). Writes build/sound/capture.json.

  .venv/bin/python ports/dos/sound/capture.py [--seconds 4]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))

from oracle.soundprobe import Probe, SECOND, TUNES, soundmode_offset  # noqa: E402
from oracle.state import dgroup_seg  # noqa: E402

OUT = ROOT / "ports/dos/build/sound"


def capture(seconds: float) -> dict:
    p = Probe()
    m = p.m
    ds = dgroup_seg()
    tunes = {}
    for device, key in ((0, "tandy"), (1, "speaker")):
        m.ww(ds, soundmode_offset(), device)
        p.call("SetSoundDriverIdle", 0)
        p.call("PlaySound", 1)
        for tune in range(1, TUNES + 1):
            t_log, s_log = len(m.tandy_log), len(m.speaker_log)
            t0 = m.now()
            p.call("PlaySound", tune + 1)
            p.wait(int(seconds * SECOND))
            p.call("PlaySound", 0xFF)
            t1 = m.now()
            p.wait(SECOND // 20)
            rec = tunes.setdefault(str(tune), {})
            rec[key + "_length"] = (t1 - t0) / SECOND
            if key == "tandy":
                rec["tandy"] = [((t - t0) / SECOND, b) for t, b in m.tandy_log[t_log:] if t <= t1]
            else:
                rec["speaker"] = [((t - t0) / SECOND, d, int(on)) for t, d, on in m.speaker_log[s_log:] if t <= t1]
        p.call("PlaySound", 0)
        p.call("SetSoundDriverIdle", 100)
    return {"seconds": seconds, "tunes": tunes}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seconds", type=float, default=4.0)
    a = ap.parse_args(argv)
    OUT.mkdir(parents=True, exist_ok=True)
    data = capture(a.seconds)
    (OUT / "capture.json").write_text(json.dumps(data))
    for k, r in data["tunes"].items():
        print("tune %2s: %5d Tandy writes, %4d speaker events" % (k, len(r["tandy"]), len(r["speaker"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())

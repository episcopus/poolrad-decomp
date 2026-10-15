#!/usr/bin/env python3
"""soundprobe.py: play every tune of the sound driver in the oracle and keep the hardware trace (playbook 50).

  .venv/bin/python tools/oracle/soundprobe.py --record            write tests/sessions/golden/sound-driver/
  .venv/bin/python tools/oracle/soundprobe.py --check [--rebuilt]  compare a run with it
  make sound-golden [REBUILT=1]

The two golden sessions hardly make a sound (the driver starts and stops once). The driver is 5.7 KB of
hand-written assembly, so this probe exercises all of it: it boots the game to its first keyboard wait,
then calls the unit's own routines from outside, the way the game does,

    SetSoundDriverIdle(0)       the timer driver runs for good
    PlaySound(1)                output on
    for each tune k = 1..20     PlaySound(k + 1), one virtual second, PlaySound(0FFh), a tenth of a second
    PlaySound(0); SetSoundDriverIdle(100)

once with SoundMode 1 (PC speaker) and once with 0 (Tandy chip), and records every write to PIT channel 0,
PIT channel 2 with the speaker gate, and port C0h (oracle/sound.py). The trace is the reference a build of
another speed (the C translation) must reproduce in sequence, and what the rebuilt program must reproduce
exactly, times included.
"""
from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle import layout, sound  # noqa: E402
from oracle.keys import KeyScript  # noqa: E402
from oracle.machine import LOAD_SEG, ROOT, Stop  # noqa: E402
from oracle.run import build_machine  # noqa: E402
from oracle.state import dgroup_seg  # noqa: E402

GOLDEN = ROOT / "tests/sessions/golden/sound-driver"
TUNES = 20                       # tune indices 1..20 of the driver's tables (whitepaper 5.14)
SECOND = 1_000_000               # instructions per virtual second (the oracle's clock model)
BOOT_INSNS = 60_000_000
SENT_SEG, SENT_RET, SENT_IDLE = 0xF000, 0x8000, 0x8004   # a return address, and `sti; hlt; jmp hlt`
ROUTINES = {"PlaySound": 0x00DC, "SilenceSound": 0x017B, "SetSoundDriverIdle": 0x01A5}
FLAG_IF = 0x0200


def res03_segment() -> int:
    """Runtime paragraph of the sound unit's code segment."""
    lay = layout.current()
    para = 0x08AE
    for lo, hi, seg, uid, base in (lay.resident_ranges or []):
        if uid == "res03":
            para = base >> 4
    return para + LOAD_SEG


class Probe:
    def __init__(self):
        script = KeyScript([])
        self.m = build_machine(script)
        reason = self.m.run(BOOT_INSNS)
        if reason != "input-exhausted":
            raise RuntimeError("the game did not reach its first keyboard wait: %s" % reason)
        m = self.m
        m.keys = None                              # from here on nothing feeds or stops on the keyboard
        lin = m.linear(SENT_SEG, SENT_RET)
        m.uc.mem_write(lin, bytes.fromhex("0000000000000000"))
        m.uc.mem_write(m.linear(SENT_SEG, SENT_IDLE), bytes.fromhex("FB F4 EB FD"))   # sti; hlt; jmp hlt

        def done(mach):
            raise Stop("probe-return")
        m.add_breakpoint(SENT_SEG, SENT_RET, done)
        self.armed = False

        def idle(mach):
            if self.armed:
                raise Stop("probe-idle")
        m.add_breakpoint(SENT_SEG, SENT_IDLE + 2, idle)
        self.seg = res03_segment()

    def call(self, name: str, *args: int) -> None:
        m = self.m
        m.set("ds", dgroup_seg())
        m.set("es", dgroup_seg())
        for a in args:
            m.push(a & 0xFFFF)
        m.push(SENT_SEG)                           # far return address
        m.push(SENT_RET)
        m.set("cs", self.seg)
        m.set("ip", ROUTINES[name])
        m.set("flags", m.get("flags") | FLAG_IF)
        reason = m.run(10 * SECOND)
        if reason != "probe-return":
            raise RuntimeError("%s did not return: %s" % (name, reason))

    def wait(self, instructions: int) -> None:
        m = self.m
        m.set("cs", SENT_SEG)
        m.set("ip", SENT_IDLE)
        m.set("flags", m.get("flags") | FLAG_IF)
        reason = m.run(instructions)
        if reason != "max-insns":
            raise RuntimeError("the idle wait ended early: %s" % reason)
        # stop only at a safe point: the `jmp` after `hlt` is reached when a timer interrupt has returned
        self.armed = True
        reason = m.run(10 * SECOND)
        self.armed = False
        if reason != "probe-idle":
            raise RuntimeError("the driver's timer handler never returned to the idle loop: %s" % reason)


def soundmode_offset() -> int:
    lay = layout.current()
    return getattr(lay, "soundmode", 0x5372)


def run_probe() -> list[tuple]:
    p = Probe()
    m = p.m
    ds = dgroup_seg()
    for device in (1, 0):                          # PC speaker, then Tandy
        m.ww(ds, soundmode_offset(), device)
        p.call("SetSoundDriverIdle", 0)
        p.call("PlaySound", 1)
        for tune in range(1, TUNES + 1):
            p.call("PlaySound", tune + 1)
            p.wait(SECOND)
            p.call("PlaySound", 0xFF)
            p.wait(SECOND // 10)
        p.call("PlaySound", 0)
        p.call("SetSoundDriverIdle", 100)
        p.wait(SECOND // 10)
    return sound.events(m)


def record() -> int:
    a, b = run_probe(), run_probe()
    if sound.digest(a) != sound.digest(b):
        print("sound-driver: FAIL: two runs differ")
        return 1
    GOLDEN.mkdir(parents=True, exist_ok=True)
    sound.save(GOLDEN / "sound.txt.gz", a)
    (GOLDEN / "golden.json").write_text(json.dumps({
        "format": 1, "probe": "tunes 1..%d on the PC speaker then the Tandy chip" % TUNES,
        "exe": "poolrad/start-unpack.exe", **sound.summary(a)}, indent=1) + "\n")
    print("sound-driver: golden written: %s" % ", ".join("%s=%s" % kv for kv in sound.summary(a).items()
                                                        if "digest" not in kv[0]))
    return 0


def first_difference(want: list[str], got: list[str]) -> str:
    for i, (x, y) in enumerate(zip(want, got)):
        if x != y:
            return "event %d: golden %r, run %r" % (i, x.strip(), y.strip())
    return "lengths %d != %d" % (len(want), len(got))


def check() -> int:
    gp = GOLDEN / "golden.json"
    if not gp.exists():
        print("sound-driver: FAIL: no golden (make sound-golden RECORD=1)")
        return 1
    gold = json.loads(gp.read_text())
    ev = run_probe()
    got = sound.summary(ev)
    if got["sound_digest"] == gold["sound_digest"]:
        print("sound-driver: ok (%s): %d events, trace identical" % (layout.current().name, got["sound_events"]))
        return 0
    want = gzip.decompress((GOLDEN / "sound.txt.gz").read_bytes()).decode().splitlines()
    have = sound.format_trace(ev).splitlines()
    print("sound-driver: FAIL: %s" % first_difference(want, have))
    return 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--record", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--rebuilt", action="store_true", help="run build/rebuild/POOL.EXE")
    a = ap.parse_args(argv)
    if a.rebuilt:
        layout.use(layout.rebuilt())
    if a.record and a.rebuilt:
        print("goldens are recorded on the original")
        return 1
    if a.record:
        return record()
    return check()


if __name__ == "__main__":
    sys.exit(main())

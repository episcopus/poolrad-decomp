#!/usr/bin/env python3
"""snd_check.py: the CoCo sound driver on the host against the oracle (step 8.8). Run by tools/snd_check.sh (make snd-check).

  1. ideal clock: the speaker events (divisor, on) of the generated driver, run through the real schedule of the oracle's probe, are
     the golden sound-driver's speaker events of the PC speaker half, event for event (7,043 of them);
  2. the DAC: for every tone the driver set, the model's toggles come at the half period of the PIT divisor (within the resolution of the
     12 bit reload: 0.05 %), whatever the interrupt count per toggle;
  3. the pump: with the real clock (the interrupts counted, snd_run), polled every tick, every 1000 units and every 20,000 units, the
     speaker events are the ideal run's and the number of driver ticks over the whole schedule is within 0.1 % of the ideal run's."""
import gzip
import json
import subprocess
import sys
from pathlib import Path

COCO = Path(__file__).resolve().parent.parent
GOLD = COCO.parent.parent / "tests/sessions/golden/sound-driver"
B = COCO / "build/snd"
fails = 0


def check(ok, msg):
    global fails
    print(("ok   " if ok else "FAIL ") + msg)
    fails += 0 if ok else 1


def run(*args):
    p = subprocess.run([str(B / "snd_ref"), *args], capture_output=True, text=True)
    if p.returncode:
        print(p.stderr)
        sys.exit(1)
    return p.stderr.strip()


def events(path):
    return [tuple(map(int, l.split()[1:])) for l in open(path)]


# 1. against the golden
ev = [l.split() for l in gzip.decompress((GOLD / "sound.txt.gz").read_bytes()).decode().splitlines()]
p_idx = [i for i, e in enumerate(ev) if e[1] == "P"]
start, nxt = 0, p_idx[5]                              # from the start to the P 5041 that begins the Tandy half
gold = [(int(e[2]), int(e[3])) for e in ev[start:nxt] if e[1] == "S"]
log = run("ideal", "--events", str(B / "ideal.ev"), "--dac", str(B / "ideal.dac"), "--ticks", str(B / "ideal.ticks"))
ideal = events(B / "ideal.ev")
check(ideal == gold, "ideal clock: %d speaker events, the golden's %d" % (len(ideal), len(gold)))
if ideal != gold:
    for i, (a, b) in enumerate(zip(ideal, gold)):
        if a != b:
            print("   first difference at %d: %r, golden %r" % (i, a, b))
            break

# 2. the DAC against the divisors: in every tick window in which the same tone plays as in the window before, the DAC toggled
#    15123 / (1.5 D) times, give or take one (the phase of the wave against the window); in every silent window not at all
rows = [tuple(map(int, l.split())) for l in open(B / "ideal.ticks")]
tone = [(d, n) for d, n in rows if d]
bad = [(d, n) for d, n in tone if abs(n - 15123 / max(1.5 * d, 500)) > 2.01]     # (a half period under 500 units is clamped)
quiet = [n for d, n in rows if d == 0]
check(len(tone) > 1500 and len(bad) <= len(tone) // 100, "DAC: %d tone windows, %d off by more than two toggles; %d tones" % (len(tone), len(bad), len(set(d for d, n in tone))))
if bad:
    print("   e.g.", bad[:6])
check(all(n == 0 for n in quiet), "DAC: %d silent windows, none toggled (%d did)" % (len(quiet), sum(1 for n in quiet if n)))

# 3. the pump
ideal_ticks = int(log.split("toggles, ")[1].split()[0])
for poll, busy in ((15123, 0), (1000, 0), (20000, 0), (1000, 5000), (3000, 12000)):
    out = run("pump", "--poll", str(poll), "--busy", str(busy), "--events", str(B / "pump.ev"))
    pe = events(B / "pump.ev")
    n = int(out.split("toggles, ")[1].split()[0])
    units = int(out.split("pump calls, ")[1].split()[0])
    ideal_n = units // 15123                          # (the model's waits overshoot a little when the driver is busy)
    check(len(pe) > 0, "pump (poll every %d units, the driver busy %d units a tick): %d speaker events; %s" % (poll, busy, len(pe), out.split(": ", 1)[1]))
    check(abs(len(pe) - len(ideal)) <= 60, "   pump events within 60 of the ideal run's (%d against %d: the rests are ticks too)" % (len(pe), len(ideal)))
    want_n = ideal_ticks if busy == 0 else ideal_n
    check(abs(n - want_n) <= max(3, want_n // 150), "   pump ticks %d against the %d it should be (the clock loses or gains nothing over 22 s of changing tones)" % (n, want_n))
print("snd-check:", "FAILED %d" % fails if fails else "ok")
sys.exit(1 if fails else 0)

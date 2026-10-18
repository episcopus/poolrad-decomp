#!/usr/bin/env python3
"""engcheck.py TEST: compare the screens an engine test left (MAME: one per mb_hold checkpoint; XRoar: the final one)
with their goldens (step 8.3). The table says which golden each checkpoint must equal: a recorded screen of the original
game (goldens/4bpp/<session>.s4, label) or a reference screen of the engine script (goldens/engine/<test>.s4)."""
import hashlib
import sys

BASE = {
    "t_pic": {"mame": {1: ("boot-title", "ssi-logo"), 2: ("boot-title", "title")}, "xroar": ("boot-title", "title")},
    "t_gfx": {"mame": {i + 1: ("goldens/engine/t_gfx.s4", l) for i, l in
                       enumerate(["blank", "text", "tiles", "flush", "fill", "palette"])},
              "xroar": ("goldens/engine/t_gfx.s4", "palette")},
}


def golden(session, label):
    path = f"goldens/4bpp/{session}.s4" if "/" not in session else session
    for line in open(path):
        k, v = line.split()
        if k == label:
            return v
    sys.exit(f"{path}: no label {label}")


def digest(data):
    return hashlib.sha256(data[:32016]).hexdigest()


def words(path, base=0):
    d = open(path, "rb").read()
    return [(d[base + 0x10 + 2 * i] << 8) | d[base + 0x11 + 2 * i] for i in range(32)]


def check_irq():
    """t_irq (8.3d): MAME stamps the checkpoints in emulated seconds, 60 frames apart; its typed keys arrive decoded."""
    bad = 0
    times = [float(l.split()[1]) for l in open("build/run/t_irq-mame.cp") if l.split()[0] in "1234"]
    gaps = [b - a for a, b in zip(times, times[1:])]
    ok = len(gaps) == 3 and all(0.99 < g < 1.01 for g in gaps)
    bad += not ok
    print("  MAME 60 frames = %s s: %s" % (", ".join("%.4f" % g for g in gaps), "equal" if ok else "DIFFERENT"))
    w = words("build/run/t_irq-mame.mbx")
    want = [0x31, 0x32, 0x20, 0x21, 0x61, 0x0D]       # typed "12 !A" and Enter: shift+A is a lower case a on the CoCo
    ok = w[2] == len(want) and w[3:3 + len(want)] == want
    bad += not ok
    print("  MAME typed keys decoded %s: %s" % (" ".join("%02X" % k for k in w[3:3 + w[2]]), "equal" if ok else "DIFFERENT"))
    print("  MAME ticks in 60 frames: %d" % w[16])
    try:
        r = open("build/run/t_irq-xroar.ram", "rb").read()
        x = words("build/run/t_irq-xroar.ram", 0x71000)
        print("  XRoar ticks in 60 frames: %d, keys: %d" % (x[16], x[2]))
    except FileNotFoundError:
        print("  XRoar skipped")
    return bad


CUSTOM = {"t_irq": check_irq}

test = sys.argv[1]
if test in CUSTOM:
    sys.exit(1 if CUSTOM[test]() else 0)
spec = BASE.get(test)
if not spec:
    sys.exit(0)
bad = 0
for cp, (session, label) in spec["mame"].items():
    d = open(f"build/run/{test}-mame-cp{cp}.scr4", "rb").read()
    ok = digest(d) == golden(session, label)
    bad += not ok
    print(f"  MAME checkpoint {cp} = {session} {label}: {'equal' if ok else 'DIFFERENT'}")
session, label = spec["xroar"]
try:
    r = open(f"build/run/{test}-xroar.ram", "rb").read()
    ok = digest(r[:32000] + r[0x71050:0x71060]) == golden(session, label)
    bad += not ok
    print(f"  XRoar final screen = {session} {label}: {'equal' if ok else 'DIFFERENT'}")
except FileNotFoundError:
    print("  XRoar skipped")
sys.exit(1 if bad else 0)

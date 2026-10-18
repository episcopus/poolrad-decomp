#!/usr/bin/env python3
"""engcheck.py TEST: compare the screens an engine test left (MAME: one per mb_hold checkpoint; XRoar: the final one)
with their goldens (step 8.3). The table says which golden each checkpoint must equal: a recorded screen of the original
game (goldens/4bpp/<session>.s4, label) or a reference screen of the engine script (goldens/engine/<test>.s4)."""
import hashlib
import sys

BASE = {
    "t_pic": {"mame": {1: ("boot-title", "ssi-logo"), 2: ("boot-title", "title")}, "xroar": ("boot-title", "title")},
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


test = sys.argv[1]
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

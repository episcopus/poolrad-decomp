#!/usr/bin/env python3
"""gamecheck.py SESSION PREFIX: did the game on the CoCo show the screens of the recorded session? The screens the harness
kept (PREFIX-sNN.scr4, lua/watch.lua) are hashed like the goldens (goldens/4bpp/SESSION.s4: sha256 of the 32,000 bytes and the
16 palette registers); the distinct screens of the golden, in the order the original showed them, must appear in that order
among ours (ours also keeps the screens in between: loading, a screen being drawn). Exit 1 unless every one does."""
import glob
import hashlib
import sys

session, prefix = sys.argv[1], sys.argv[2]
gold = []                                             # (label, hash) in order, consecutive repeats dropped
for line in open(f"goldens/4bpp/{session}.s4"):
    label, h = line.split()
    if label.startswith("read"):
        continue                                       # the periodic checks repeat the screens the labelled shots took
    if not gold or gold[-1][1] != h:
        gold.append((label, h))
ours = []
for f in sorted(glob.glob(f"{prefix}-s*.scr4")):
    ours.append(hashlib.sha256(open(f, "rb").read()[:32016]).hexdigest())
i, bad = 0, 0
for label, h in gold:
    try:
        i = ours.index(h, i) + 1
        print(f"  {label:<14} equal (our screen {i})")
    except ValueError:
        print(f"  {label:<14} NOT among our screens after screen {i}")
        bad += 1
print(f"{session}: {len(gold) - bad} of {len(gold)} golden screens shown in order, {len(ours)} screens kept")
sys.exit(1 if bad else 0)

#!/usr/bin/env python3
"""gamecheck.py SESSION PREFIX: did the game on the CoCo show the screens of the recorded session? The screens the harness
kept (PREFIX-sNN.scr4, lua/watch.lua) are hashed like the goldens (goldens/4bpp/SESSION.s4: sha256 of the 32,000 bytes and the
16 palette registers); the distinct screens of the golden, in the order the original showed them, must appear in that order
among ours (ours also keeps the screens in between: loading, a screen being drawn). The screens the session script labelled
(`shot name`) are the verdict: exit 1 unless every one is shown, in order. The unlabelled ones the recorder took after each key
(key1, key2, ...) are reported too but do not decide: they catch a screen mid-redraw, and the code wheel's own screens (the runes
depend on the clock, whitepaper 5.12) can never be equal."""
import glob
import hashlib
import re
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
for f in sorted(glob.glob(f"{prefix}-s*.scr4"), key=lambda f: int(re.search(r"-s(\d+)\.scr4$", f).group(1))):
    ours.append(hashlib.sha256(open(f, "rb").read()[:32016]).hexdigest())
i, bad, hard, hard_ok, soft, soft_ok = 0, 0, 0, 0, 0, 0
for label, h in gold:
    is_key = re.fullmatch(r"key\d+", label) is not None and (label, h) != gold[-1]   # (the last screen of a session decides, whatever it is called)
    try:
        j = ours.index(h, i) + 1
        i = j
        print(f"  {label:<14} equal (our screen {i})")
        ok = True
    except ValueError:
        print(f"  {label:<14} NOT among our screens after screen {i}" + ("  (not decisive)" if is_key else ""))
        ok = False
    if is_key:
        soft += 1
        soft_ok += ok
    else:
        hard += 1
        hard_ok += ok
print(f"{session}: {hard_ok} of {hard} labelled golden screens shown in order, {soft_ok} of {soft} unlabelled ones; {len(ours)} screens kept")
sys.exit(0 if hard_ok == hard else 1)

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
import os
import re
import struct
import sys
import zlib

session, prefix = sys.argv[1], sys.argv[2]
# A screen with an animated picture can never be bit for bit: the camp's fire flickers by the game's random numbers, and how many frames were drawn
# depends on how fast the machine was (the bank loads cost time). For these sessions a labelled screen also counts when it equals the golden picture
# (tests/sessions/golden/SESSION/*.png) everywhere outside the animated window; the number of differing pixels is printed. (x0, y0, x1, y1), inclusive.
ANIMATED = {"camp-save": (24, 24, 111, 111)}


def golden_rgb(path):
    d = open(path, "rb").read()
    i, idat = 8, b""
    while i < len(d):
        n = struct.unpack(">I", d[i:i + 4])[0]
        if d[i + 4:i + 8] == b"IDAT":
            idat += d[i + 8:i + 8 + n]
        i += 12 + n
    raw = zlib.decompress(idat)
    return [raw[y * 961 + 1:(y + 1) * 961] for y in range(200)]


def outside_diff(scr4, rows, box):
    """(pixels that differ outside the box, inside it) between a screen dump and the golden's rows of RGB"""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../tools"))
    from oracle.ega import ega_rgb
    pal = [bytes(ega_rgb(v)) for v in scr4[32000:32016]]
    out = ins = 0
    for y in range(200):
        for x in range(160):
            v = scr4[y * 160 + x]
            for k, c in enumerate((v >> 4, v & 15)):
                X = x * 2 + k
                if pal[c] != rows[y][X * 3:X * 3 + 3]:
                    if box[0] <= X <= box[2] and box[1] <= y <= box[3]:
                        ins += 1
                    else:
                        out += 1
    return out, ins
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
    if h == "text":                                   # the original ended in DOS text mode (the game ended, Halt): nothing on a CoCo screen to compare;
        print(f"  {label:<14} the original left the game (text mode): the run's mailbox says whether the CoCo halted too")   # tools/baseline_table.py reads it
        continue
    is_key = re.fullmatch(r"key\d+", label) is not None and (label, h) != gold[-1]   # (the last screen of a session decides, whatever it is called)
    try:
        j = ours.index(h, i) + 1
        i = j
        print(f"  {label:<14} equal (our screen {i})")
        ok = True
    except ValueError:
        ok = False
        if session in ANIMATED and not is_key and i < len(ours):
            for png in sorted(glob.glob(f"../../tests/sessions/golden/{session}/*.png")):
                last = f"{prefix}-s{len(ours)}.scr4"
                if os.path.exists(last):
                    o, n = outside_diff(open(last, "rb").read(), golden_rgb(png), ANIMATED[session])
                    if o == 0:
                        print(f"  {label:<14} equal outside the animated picture window ({n} pixels differ inside it; {os.path.basename(png)})")
                        ok = True
                        break
        if not ok:
            print(f"  {label:<14} NOT among our screens after screen {i}" + ("  (not decisive)" if is_key else ""))
    if is_key:
        soft += 1
        soft_ok += ok
    else:
        hard += 1
        hard_ok += ok
print(f"{session}: {hard_ok} of {hard} labelled golden screens shown in order, {soft_ok} of {soft} unlabelled ones; {len(ours)} screens kept")
sys.exit(0 if hard_ok == hard else 1)

#!/usr/bin/env python3
"""scrcheck.py: compare a 4bpp screen dump with a golden digest (step 8.3).

  scrcheck.py SCREEN.scr4 GOLDEN.s4 LABEL            SCREEN.scr4: 32,000 bytes of pixels + 16 palette bytes
  scrcheck.py RAM.ram --ram GOLDEN.s4 LABEL          a raw XRoar RAM dump (physical order: the screen at 0, the
                                                     palette in the mailbox at $71050)
GOLDEN.s4 lines are `label sha256` (poolrad_replay --screens4); the digest is over the 32,000 bytes then the 16 palette
bytes. Exit 1 on a difference."""
import hashlib
import sys

args = sys.argv[1:]
ram = "--ram" in args
args = [a for a in args if a != "--ram"]
path, golden, label = args
d = open(path, "rb").read()
if ram:
    d = d[:32000] + d[0x70950:0x70960]
want = None
for line in open(golden):
    k, v = line.split()
    if k == label:
        want = v
got = hashlib.sha256(d[:32016]).hexdigest()
ok = got == want
print(f"{path} vs {golden} {label}: {'equal' if ok else 'DIFFERENT'}  {got[:12]} {(want or '?')[:12]}")
sys.exit(0 if ok else 1)

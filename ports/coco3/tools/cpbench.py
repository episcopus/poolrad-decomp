#!/usr/bin/env python3
"""cpbench.py FILE.cp: far-call cost from the checkpoint timestamps of the banked demo.
Checkpoint 2 to 3 is 1000 far calls, 3 to 4 is 1000 resident calls of the same shape;
the difference per call is the cost of the stub plus __farcall. 1.789773 MHz (SAM fast)."""
import sys

CALLS = 1000
HZ = 1789772.7
t = {}
for line in open(sys.argv[1]):
    c, s = line.split()
    t[int(c)] = float(s)
if not all(k in t for k in (2, 3, 4)):
    sys.exit("cpbench: checkpoints 2, 3 and 4 not all seen: " + str(sorted(t)))
far = (t[3] - t[2]) / CALLS * HZ
near = (t[4] - t[3]) / CALLS * HZ
print(f"far call loop      {far:7.0f} cycles per iteration")
print(f"resident call loop {near:7.0f} cycles per iteration")
print(f"far-call overhead  {far - near:7.0f} cycles (about {(far - near) / HZ * 1e6:.0f} us)")

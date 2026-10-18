#!/usr/bin/env python3
"""placement_check.py DIR: static checks of a placement build's generated C (step 8.2).

A banked block is reachable through one of two data windows, so a statement may use at most two different banked
pointers (a third would evict a window the statement still needs). Counts the statements that use FPB, those that use
two, and fails when one uses more than two.
"""
import glob
import re
import sys

total = pairs = bad = 0
for f in sorted(glob.glob(sys.argv[1] + "/ovl*.c") + glob.glob(sys.argv[1] + "/res*.c")):
    for i, line in enumerate(open(f), 1):
        args = set(re.findall(r"FPB\([^,]*,\s*([A-Za-z_][\w\[\]\.\->\*\(\)]*?)\)", line))
        if args:
            total += 1
        if len(args) == 2:
            pairs += 1
        elif len(args) > 2:
            bad += 1
            print(f"{f}:{i}: {len(args)} different banked pointers in one statement")
print(f"statements using banked data: {total}; with two different banked pointers: {pairs}; with more than two: {bad}")
sys.exit(1 if bad else 0)

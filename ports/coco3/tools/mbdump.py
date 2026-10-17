#!/usr/bin/env python3
"""mbdump.py: print or check a mailbox dump written by lua/mailbox.lua or xroar.

  mbdump.py FILE.mbx [PROBE.c] [--check]    FILE.mbx: 80 bytes from logical $0100
  mbdump.py FILE.ram --ram [PROBE.c]        a raw XRoar RAM dump (physical order; the
                                            mailbox is at $70100 = block $38 offset $100)

With a probe source, lines of its header comment `r<i> <text> | std=<n>` label the results.
--check: exit 1 unless the program finished (status 1) with no failed check.
"""
import re
import sys

MAILBOX_PHYS = 0x70100


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    d = open(args[0], "rb").read()
    if "--ram" in flags:
        d = d[MAILBOX_PHYS:MAILBOX_PHYS + 0x50]
    if d[:4] != b"PRAD":
        sys.exit(f"{args[0]}: no mailbox magic (the program never started)")
    status, fails = d[5], (d[6] << 8) | d[7]
    labels = {}
    if len(args) > 1:
        for line in open(args[1]):
            m = re.match(r"\s*\*?\s*r(\d+)\s+(.*?)\s*\|\s*std=(\d+)", line)
            if m:
                labels[int(m.group(1))] = (m.group(2), int(m.group(3)))
    names = {0: "running", 1: "pass", 2: "fail"}
    if labels:   # a probe: a failed check is a difference from standard C, not an error
        print(f"finished: {status != 0}, results that differ from standard C and Turbo Pascal: {fails}")
    else:
        print(f"status {status} ({names.get(status, '?')}), checkpoint {d[4]}, failed checks {fails}")
    for i in range(32):
        w = (d[0x10 + 2 * i] << 8) | d[0x11 + 2 * i]
        if i in labels:
            text, std = labels[i]
            print(f"  r{i:<2} {w:5d} ${w:04X}  {'= std' if w == std else f'!= std {std}':<10} {text}")
        elif w or i < 12:
            print(f"  r{i:<2} {w:5d} ${w:04X}")
    if "--check" in flags and not (status == 1 and fails == 0):
        sys.exit(1)


if __name__ == "__main__":
    main()

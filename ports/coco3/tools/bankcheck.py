#!/usr/bin/env python3
"""bankcheck.py BANK.map: a code bank holds code and constants only (research 04, rule 10).
Fails when the bank has writable data (rwdata, bss), global initialisers (initgl), or does not
fit the 16 KB window ($8000..$BFFF)."""
import re
import sys

bad = []
end = 0
for line in open(sys.argv[1], encoding="latin-1"):
    m = re.match(r"^Section: (\S+) \((.*)\) load at ([0-9A-Fa-f]+), length ([0-9A-Fa-f]+)", line)
    if not m:
        continue
    name, obj, load, length = m.group(1), m.group(2), int(m.group(3), 16), int(m.group(4), 16)
    if name in ("rwdata", "bss", "initgl") and length:
        bad.append(f"{obj}: section {name} has {length} bytes")
    if load >= 0x8000:
        end = max(end, load + length)
if end > 0xC000:
    bad.append(f"the bank ends at ${end:04X}, past the window ($BFFF)")
if bad:
    sys.exit(f"{sys.argv[1]}: " + "; ".join(bad))

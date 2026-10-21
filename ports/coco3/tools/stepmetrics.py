#!/usr/bin/env python3
"""stepmetrics.py [LABEL]: the numbers a step of 8.9c is judged by, from the last build (build/game) and the last `make perf-all` (build/run/prof-*.out):
bank bytes (code and rodata in the banks), the core's and the engine's ends, the image size, and over the sessions (camp-magic left out, its camp
screen animates for the whole limit): bank loads, busy seconds of emulated time, kilobytes read from the image and the number of storage requests."""
import glob
import json
import os
import re
import subprocess
import sys

B = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build")
label = sys.argv[1] if len(sys.argv) > 1 else ""
banks = json.load(open(B + "/game/banks.json"))["banks"]
bank_bytes = sum(b["size"] for b in banks)
core = re.search(r"Section: .*\n", "")
def end(mapfile):
    e = 0
    for m in re.finditer(r"Section: (\S+) \((.*?)\) load at ([0-9A-F]+), length ([0-9A-F]+)", open(mapfile).read()):
        e = max(e, int(m.group(3), 16) + int(m.group(4), 16))
    return e
img = os.path.getsize(B + "/game/pool.img")
busy = loadcpu = loads = reqs = kb = 0
SESSIONS = [os.path.basename(f)[:-5] for f in sorted(glob.glob(B + "/../../../tests/sessions/*.keys"))]
for s in SESSIONS:
    f = B + "/run/game-%s.out" % s
    if s in ("create-elf-mage", "camp-magic") or not os.path.exists(f):
        continue
    last = None
    t = open(f, errors="replace").read()
    for m in re.finditer(r"pc t=[\d.]+ pc=\S+ s=\S+ task=(\d+) bank=\d+ polls=(\d+) eng=(\d+)", t):
        p = int(m.group(2))
        if last is not None and p == last:
            busy += 1
            if m.group(1) == "1" and m.group(3) == "0":      # the engine's bank loader (engine call 0)
                loadcpu += 1
        last = p
    m = re.search(r" r9 +(\d+)", t)
    loads += int(m.group(1)) if m else 0
    out = subprocess.run([sys.executable, "-I", os.path.dirname(os.path.abspath(__file__)) + "/seclog.py", f, B + "/game/pool.img"], capture_output=True, text=True).stdout
    m = re.search(r"^total\s+(\d+)\s+\d+\s+(\d+)", out, re.M)
    if m:
        reqs += int(m.group(1))
        kb += int(m.group(2))
print("%-28s banks %7d B  core ends $%04X  engine ends $%04X  image %8d B | sessions: loads %5d  busy %6.0f s (%5.0f s of it loading banks)  read %6d KB  requests %6d" % (
    label, bank_bytes, end(B + "/game/core.map"), end(B + "/game/pool.map"), img, loads, busy / 60.0, loadcpu / 60.0, kb, reqs))

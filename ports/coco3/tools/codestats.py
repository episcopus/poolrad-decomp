#!/usr/bin/env python3
"""codestats.py: what the 6809 code of the banks is made of (step 8.9b). A linear sweep of every bank's code section (build/game/<bank>.raw at
$8000, the section limits from its link map) with tools/dis6809.py, then:
  * bytes by mnemonic, and by call target (the core's routines named from core.map: the data window accessors vm_ptr/vm_bp/vm_pkp, the compiler's
    helpers, the far stubs of other banks, calls inside the bank);
  * the most frequent instruction sequences of 2 to 4 instructions, by the bytes they occupy (what a subroutine or a better code generator would save);
  * the frame code (LEAS, PSHS/PULS of U and the like) of the routines.
Usage: codestats.py [--seq N] [--bank NAME]"""
import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dis6809  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
B = os.path.join(ROOT, "build", "game")


def core_symbols():
    syms = {}
    for line in open(os.path.join(B, "core.map"), errors="replace"):
        m = re.match(r"Symbol: (\S+) \(.*\) = ([0-9A-F]+)$", line.strip())
        if m and not m.group(1).startswith(("\x02", "\\02", ".global", "funcsize_", "funcend_")):
            syms.setdefault(int(m.group(2), 16), m.group(1).lstrip("_"))
    return syms


def sections(bank):
    out = {}
    for m in re.finditer(r"Section: (\S+) \(\S+\) load at ([0-9A-F]+), length ([0-9A-F]+)", open(os.path.join(B, bank + ".map")).read()):
        out.setdefault(m.group(1), []).append((int(m.group(2), 16), int(m.group(3), 16)))
    return out


def core_ranges():
    """[(lo, hi, label)] of the core's code by object: the far stubs are one object (farstubs.o)"""
    out = []
    for m in re.finditer(r"Section: code \((\S+)\) load at ([0-9A-F]+), length ([0-9A-F]+)", open(os.path.join(B, "core.map")).read()):
        out.append((int(m.group(2), 16), int(m.group(2), 16) + int(m.group(3), 16), os.path.basename(m.group(1))))
    return out


RANGES = core_ranges()


def classify_target(addr, core, bank_lo, bank_hi):
    if bank_lo <= addr < bank_hi:
        return "inside the bank"
    n = core.get(addr)
    for lo, hi, obj in RANGES:
        if lo <= addr < hi:
            if obj == "farstubs.o":
                return "FAR STUB (a routine of another bank)"
            if obj.startswith("engine_stubs"):
                return "ENGINE CALL stub"
            return n or ("core " + obj)
    return n or "core ?%04X" % addr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seq", type=int, default=25)
    ap.add_argument("--bank")
    a = ap.parse_args()
    core = core_symbols()
    banks = json.load(open(os.path.join(B, "banks.json")))["banks"]
    mn_bytes, mn_n = collections.Counter(), collections.Counter()
    call_bytes, call_n = collections.Counter(), collections.Counter()
    seqs = collections.Counter()
    seqn = collections.Counter()
    total = 0
    for b in banks:
        if a.bank and b["name"] != a.bank:
            continue
        raw = open(os.path.join(B, b["name"] + ".raw"), "rb").read()
        sec = sections(b["name"])
        for base, ln in sec.get("code", []):
            d = raw[base - 0x8000:base - 0x8000 + ln] + b"\0\0\0\0"
            i, ins = 0, []
            while i < ln:
                s, j = dis6809.dis(d, base, i)
                ins.append((s, j - i))
                i = j
            total += ln
            for s, n in ins:
                m = s.split()[0]
                mn_bytes[m] += n
                mn_n[m] += 1
                mm = re.match(r"(JSR|LBSR|BSR|LBRA) \$([0-9A-F]{4})", s)
                if mm and m in ("JSR", "LBSR", "BSR"):
                    tgt = int(mm.group(2), 16)
                    k = classify_target(tgt, core, 0x8000, 0xC000)
                    call_bytes[k] += n
                    call_n[k] += 1
                elif m == "JSR":
                    call_bytes["jsr indexed or direct"] += n
                    call_n["jsr indexed or direct"] += 1
            # sequences of instructions with their operands generalised (addresses and offsets become X)
            gen = [(re.sub(r"\$[0-9A-F]+|#\$[0-9A-F]+|-?\d+(?=,)", "N", s), n) for s, n in ins]
            for L in (2, 3, 4):
                for k in range(len(gen) - L + 1):
                    key = " ; ".join(g[0] for g in gen[k:k + L])
                    seqs[key] += sum(g[1] for g in gen[k:k + L])
                    seqn[key] += 1
    print("code bytes swept: %d" % total)
    print("\nbytes by mnemonic (top 25):")
    for m, n in mn_bytes.most_common(25):
        print("%8d %5.1f%%  %-7s %7d instr" % (n, 100.0 * n / total, m, mn_n[m]))
    print("\ncalls (JSR/LBSR/BSR) by target (top 35): bytes, count")
    ct = sum(call_bytes.values())
    print("calls total %d bytes (%.1f%% of code)" % (ct, 100.0 * ct / total))
    for k, n in call_bytes.most_common(35):
        print("%8d  %6d calls  %s" % (n, call_n[k], k))
    print("\nrepeated sequences (by bytes they occupy, 2 to 4 instructions, operands generalised), top %d:" % a.seq)
    shown = 0
    for k, n in seqs.most_common(400):
        if seqn[k] < 20:
            continue
        print("%8d bytes %6d times  %s" % (n, seqn[k], k))
        shown += 1
        if shown >= a.seq:
            break


if __name__ == "__main__":
    main()

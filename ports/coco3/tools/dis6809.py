#!/usr/bin/env python3
"""dis6809.py: a small 6809 disassembler (for reading Disk BASIC's ROM). usage: dis6809.py file load_addr [start [end]]"""
import sys

# mnemonic, mode: i immediate8, I immediate16, d direct, x indexed, e extended, r rel8, R rel16, h inherent, p pshs-list, q pshu, t tfr
P0 = {}
def add(base, names, modes):
    for i, n in enumerate(names):
        for j, m in enumerate(modes):
            P0[base + j * 0x10 + i] = (n, m)
# 00-0F direct
for op, n in {0x00:"NEG",0x03:"COM",0x04:"LSR",0x06:"ROR",0x07:"ASR",0x08:"ASL",0x09:"ROL",0x0A:"DEC",0x0C:"INC",0x0D:"TST",0x0E:"JMP",0x0F:"CLR"}.items():
    P0[op] = (n, "d"); P0[op + 0x60] = (n, "x"); P0[op + 0x70] = (n, "e")
for op, n in {0x12:"NOP",0x13:"SYNC",0x19:"DAA",0x1D:"SEX",0x39:"RTS",0x3A:"ABX",0x3B:"RTI",0x3D:"MUL",0x3F:"SWI"}.items():
    P0[op] = (n, "h")
P0[0x16] = ("LBRA", "R"); P0[0x17] = ("LBSR", "R"); P0[0x1A] = ("ORCC", "i"); P0[0x1C] = ("ANDCC", "i"); P0[0x1E] = ("EXG", "t"); P0[0x1F] = ("TFR", "t"); P0[0x3C] = ("CWAI", "i")
for op, n in enumerate(["BRA","BRN","BHI","BLS","BHS","BLO","BNE","BEQ","BVC","BVS","BPL","BMI","BGE","BLT","BGT","BLE"]):
    P0[0x20 + op] = (n, "r")
P0[0x30] = ("LEAX", "x"); P0[0x31] = ("LEAY", "x"); P0[0x32] = ("LEAS", "x"); P0[0x33] = ("LEAU", "x")
P0[0x34] = ("PSHS", "p"); P0[0x35] = ("PULS", "p"); P0[0x36] = ("PSHU", "q"); P0[0x37] = ("PULU", "q")
for op, n in {0x40:"NEGA",0x43:"COMA",0x44:"LSRA",0x46:"RORA",0x47:"ASRA",0x48:"ASLA",0x49:"ROLA",0x4A:"DECA",0x4C:"INCA",0x4D:"TSTA",0x4F:"CLRA",
              0x50:"NEGB",0x53:"COMB",0x54:"LSRB",0x56:"RORB",0x57:"ASRB",0x58:"ASLB",0x59:"ROLB",0x5A:"DECB",0x5C:"INCB",0x5D:"TSTB",0x5F:"CLRB"}.items():
    P0[op] = (n, "h")
A = ["SUB","CMP","SBC","SUBD","AND","BIT","LD","","EOR","ADC","OR","ADD"]
for base, regs in ((0x80, "A"), (0xC0, "B")):
    for k, n in enumerate(["SUB","CMP","SBC",None,"AND","BIT","LD","ST","EOR","ADC","OR","ADD"]):
        if n is None: continue
        for j, m in enumerate("idxe"):
            if n == "ST" and m == "i": continue
            P0[base + j * 0x10 + k] = (n + regs, m)
for j, m in enumerate("idxe"):
    P0[0x83 + j * 0x10] = ("SUBD" if True else "", "I" if m == "i" else m)
    P0[0xC3 + j * 0x10] = ("ADDD", "I" if m == "i" else m)
    P0[0x8C + j * 0x10] = ("CMPX", "I" if m == "i" else m)
    P0[0x8E + j * 0x10] = ("LDX", "I" if m == "i" else m)
    P0[0xCC + j * 0x10] = ("LDD", "I" if m == "i" else m)
    P0[0xCE + j * 0x10] = ("LDU", "I" if m == "i" else m)
    if m != "i":
        P0[0x8F + j * 0x10] = ("STX", m); P0[0xCD + j * 0x10] = ("STD", m); P0[0xCF + j * 0x10] = ("STU", m)
P0[0x8D] = ("BSR", "r")
for j, m in enumerate("dxe"):
    P0[0x9D + j * 0x10] = ("JSR", m)
P1 = {0x3F: ("SWI2","h"), 0x83: ("CMPD","I"), 0x8C: ("CMPY","I"), 0x8E: ("LDY","I"), 0xCE: ("LDS","I")}
for j, m in enumerate("dxe"):
    P1[0x93 + j * 0x10] = ("CMPD", m); P1[0x9C + j * 0x10] = ("CMPY", m); P1[0x9E + j * 0x10] = ("LDY", m)
    P1[0x9F + j * 0x10] = ("STY", m); P1[0xDE + j * 0x10] = ("LDS", m); P1[0xDF + j * 0x10] = ("STS", m)
for op, n in enumerate(["BRN","BHI","BLS","BHS","BLO","BNE","BEQ","BVC","BVS","BPL","BMI","BGE","BLT","BGT","BLE"]):
    P1[0x21 + op] = ("L" + n, "R")
P2 = {0x3F: ("SWI3","h"), 0x83: ("CMPU","I"), 0x8C: ("CMPS","I")}
for j, m in enumerate("dxe"):
    P2[0x93 + j * 0x10] = ("CMPU", m); P2[0x9C + j * 0x10] = ("CMPS", m)
REG = ["D","X","Y","U","S","PC","?","?","A","B","CC","DP","?","?","?","?"]
IDX = ["X","Y","U","S"]


def idx(d, i):
    pb = d[i]; i += 1
    r = IDX[(pb >> 5) & 3]
    if not pb & 0x80:
        o = pb & 0x1F
        if o & 0x10: o -= 32
        return "%d,%s" % (o, r), i
    ind = pb & 0x10
    m = pb & 0x0F
    s = None
    if m == 0: s = ",%s+" % r
    elif m == 1: s = ",%s++" % r
    elif m == 2: s = ",-%s" % r
    elif m == 3: s = ",--%s" % r
    elif m == 4: s = ",%s" % r
    elif m == 5: s = "B,%s" % r
    elif m == 6: s = "A,%s" % r
    elif m == 8:
        o = d[i]; i += 1
        s = "%d,%s" % (o - 256 if o > 127 else o, r)
    elif m == 9:
        o = (d[i] << 8) | d[i + 1]; i += 2
        s = "%d,%s" % (o - 65536 if o > 32767 else o, r)
    elif m == 11: s = "D,%s" % r
    elif m == 12:
        o = d[i]; i += 1
        s = "%d,PC" % (o - 256 if o > 127 else o)
    elif m == 13:
        o = (d[i] << 8) | d[i + 1]; i += 2
        s = "%d,PC" % (o - 65536 if o > 32767 else o)
    elif m == 15:
        o = (d[i] << 8) | d[i + 1]; i += 2
        s = "$%04X" % o
    else: s = "?idx%02X" % pb
    return ("[%s]" % s if ind else s), i


def dis(d, base, i):
    a0 = i
    op = d[i]; i += 1
    tab = P0
    if op == 0x10: tab = P1; op = d[i]; i += 1
    elif op == 0x11: tab = P2; op = d[i]; i += 1
    e = tab.get(op)
    if not e:
        return "FCB $%02X" % op, i
    n, m = e
    if m == "h": return n, i
    if m == "i": return "%s #$%02X" % (n, d[i]), i + 1
    if m == "I": return "%s #$%04X" % (n, (d[i] << 8) | d[i + 1]), i + 2
    if m == "d": return "%s <$%02X" % (n, d[i]), i + 1
    if m == "e": return "%s $%04X" % (n, (d[i] << 8) | d[i + 1]), i + 2
    if m == "x":
        s, i = idx(d, i)
        return "%s %s" % (n, s), i
    if m == "r":
        o = d[i]; i += 1
        o = o - 256 if o > 127 else o
        return "%s $%04X" % (n, base + i + o), i
    if m == "R":
        o = (d[i] << 8) | d[i + 1]; i += 2
        o = o - 65536 if o > 32767 else o
        return "%s $%04X" % (n, (base + i + o) & 0xFFFF), i
    if m == "t":
        b = d[i]; return "%s %s,%s" % (n, REG[b >> 4], REG[b & 15]), i + 1
    if m in "pq":
        b = d[i]; i += 1
        names = ["CC","A","B","DP","X","Y","U" if m == "p" else "S","PC"]
        return "%s %s" % (n, ",".join(x for k, x in enumerate(names) if b & (1 << k))), i
    return n, i


def main():
    path, load = sys.argv[1], int(sys.argv[2], 16)
    d = open(path, "rb").read()
    start = int(sys.argv[3], 16) - load if len(sys.argv) > 3 else 0
    end = int(sys.argv[4], 16) - load if len(sys.argv) > 4 else len(d)
    i = start
    while i < end:
        s, j = dis(d + b"\0\0\0\0", load, i)
        print("%04X  %-16s %s" % (load + i, " ".join("%02X" % x for x in d[i:j]), s))
        i = j


if __name__ == "__main__":
    main()

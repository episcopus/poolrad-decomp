#!/usr/bin/env python3
"""ECL disassembler for Pool of Radiance, written from the decompiled OVL03/OVL07 interpreter.
Code base is 0x9900; block body (after the 2-byte 5000 header) maps to 0x9900+offset."""
import sys, os, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "re"))
import dax  # noqa: E402

BASE = 0x9900
FIXED = {0: 0, 1: 1, 2: 1, 3: 2, 4: 3, 5: 3, 6: 3, 7: 3, 8: 2, 9: 2, 10: 1, 11: 3, 12: 3, 13: 0, 14: 1,
         15: 2, 16: 2, 17: 1, 18: 1, 19: 0, 20: 4, 21: 'list3', 22: 0, 23: 0, 24: 0, 25: 0, 26: 0, 27: 0,
         28: 0, 29: 1, 30: 6, 31: 0, 32: 1, 33: 3, 34: 2, 35: 4, 36: 0, 37: 'case', 38: 'case', 39: 8,
         40: 3, 41: 14, 42: 3, 43: 'menu', 44: 6, 45: 1, 46: 5, 47: 3, 48: 3, 49: 0, 50: 1, 51: 0, 52: 1,
         53: 3, 54: 2, 55: 3, 56: 1, 57: 1, 58: 0, 59: 3, 60: 1, 61: 0}
NAMES = {0: 'END', 1: 'GOTO', 2: 'GOSUB', 3: 'CMP', 4: 'ADD', 5: 'SUB', 6: 'DIV', 7: 'MUL', 8: 'RAND', 9: 'STORE',
         10: 'SELCHAR', 11: 'ADDMON', 12: 'SHOWENC', 13: 'APPROACH', 14: 'CLOSEUP', 15: 'INNUM', 16: 'INSTR',
         17: 'PRINT', 18: 'PRINTCLR', 19: 'RETURN', 20: 'CMP2', 21: 'LISTMENU', 22: 'IF=', 23: 'IF!=', 24: 'IF<',
         25: 'IF>', 26: 'IF<=', 27: 'IF>=', 28: 'CLEARMON', 29: 'PARTYVAL', 30: 'SCANPARTY', 32: 'NEWECL',
         33: 'LOADGFX', 34: 'RANGERCHK', 35: 'SURPRISE', 36: 'COMBAT', 37: 'ONGOTO', 38: 'ONGOSUB', 39: 'LOOT',
         40: 'ROB', 41: 'ENCACTION', 42: 'GETTABLE', 43: 'MENU', 44: 'ATTITUDE', 45: 'ENGINE', 46: 'DAMAGE',
         47: 'AND', 48: 'OR', 49: 'REDRAW', 50: 'CMPITEM', 51: 'NEWLINE', 52: 'PASSTIME', 53: 'SETTABLE',
         54: 'ADDNPC', 55: 'LOADGFX2', 56: 'SCREEN', 57: 'PICKMEMBER', 58: 'PAUSE', 59: 'FINDSPELL', 60: 'GLYPH',
         61: 'CLEARPIC'}


def sixbit(code):
    return chr(code) if code > 0x1F else chr(code + 0x40)


def unpack(data):
    out = []
    phase = 1
    cur = prev = 0
    i = 0
    n = len(data)
    count = 0
    while count < n:
        if phase < 4:
            prev = cur
            cur = data[i]
            i += 1
            count += 1
        if phase == 1:
            c = cur >> 2
        elif phase == 2:
            c = (((prev << 6) + (cur >> 2)) & 0xFF) >> 2
        elif phase == 3:
            c = (((prev << 4) & 0xFF) + (cur >> 4) & 0xFF) >> 2
        else:
            c = cur & 0x3F
        phase = phase + 1 if phase < 4 else 1
        if c:
            out.append(sixbit(c))
    if phase == 4:
        c = cur & 0x3F
        if c:
            out.append(sixbit(c))
    return ''.join(out)


class Op:
    __slots__ = ('type', 'val', 'text', 'raw')

    def __repr__(self):
        t = self.type
        if t == 0:
            return str(self.val)
        if t == 2:
            return '#%d' % self.val if self.val < 0x4900 else '#%04X' % self.val
        if t in (1, 3):
            return '[%04X]' % self.val
        if t == 0x80:
            return repr(self.text)
        if t == 0x81:
            return 'str[%04X]' % self.val
        return '?%02X:%d' % (t, self.val)


def read_ops(body, pc, n):
    """pc = address of the opcode; returns ops and next pc, mirroring DecodeOperands"""
    ops = []
    p = pc - BASE
    for _ in range(n):
        o = Op()
        o.type = body[p + 1]
        o.val = body[p + 2]
        o.text = None
        p += 2
        if o.type in (1, 2, 3, 0x81):
            p += 1
            o.val |= body[p] << 8
        elif o.type == 0x80:
            ln = o.val
            o.text = unpack(body[p + 1:p + 1 + ln]) if ln else ''
            p += ln
        ops.append(o)
    return ops, BASE + p + 1


def disasm_cmd(body, pc):
    opc = body[pc - BASE]
    spec = FIXED.get(opc, 0)
    if spec == 'list3':
        ops, nxt = read_ops(body, pc, 3)
        cnt = ops[2].val
        more, nxt = read_ops(body, nxt - 1, cnt)  # Dec(EclPC) then decode
        ops += more
    elif spec == 'menu':
        ops, nxt = read_ops(body, pc, 2)
        cnt = ops[1].val
        more, nxt = read_ops(body, nxt - 1, cnt)
        ops += more
    elif spec == 'case':
        ops, nxt = read_ops(body, pc, 2)
        cnt = ops[1].val
        more, nxt = read_ops(body, nxt - 1, cnt)
        ops += more
    else:
        ops, nxt = read_ops(body, pc, spec)
    return opc, ops, nxt


def load(name, block):
    """script body of block `block` of poolrad/<name>.DAX (e.g. load('ECL4', 21)); address = 0x9900 + offset"""
    for b in dax.read_dax(str(ROOT / "poolrad" / (name + ".DAX"))):
        if b["id"] == block:
            raw = dax.unrle(b["data"])
            assert struct.unpack('<H', raw[:2])[0] == 5000
            return raw[2:]
    raise KeyError("%s block %d" % (name, block))


def entries(body):
    ents = []
    pc = BASE
    for _ in range(5):
        ops, pc = read_ops(body, pc, 1)
        ents.append(ops[0].val)
    return ents


def linear(body, start, end=None):
    """linear sweep disassembly from the first command after the header"""
    pc = start
    end = end or BASE + len(body)
    out = []
    while pc < end and pc - BASE < len(body):
        try:
            opc, ops, nxt = disasm_cmd(body, pc)
        except IndexError:
            break
        out.append((pc, opc, ops))
        pc = nxt
    return out


def fmt(pc, opc, ops):
    return '%04X %-9s %s' % (pc, NAMES.get(opc, 'OP%d' % opc), ', '.join(repr(o) for o in ops))


if __name__ == '__main__':
    # python3 tools/maps/ecldis.py ECL4 21
    body = load(sys.argv[1], int(sys.argv[2]))
    e = entries(body)
    print('entries step=%04X search=%04X precamp=%04X campint=%04X init=%04X' % tuple(e))
    for pc, opc, ops in linear(body, BASE + 20):
        print(fmt(pc, opc, ops))

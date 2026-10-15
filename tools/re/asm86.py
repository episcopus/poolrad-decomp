#!/usr/bin/env python3
"""asm86.py: a small 8086 assembler that writes OMF object files for Turbo Pascal's `{$L}` (playbook 50).

  .venv/bin/python tools/re/asm86.py SOURCE.ASM [-o OUT.OBJ] [--binary OUT.BIN] [--map] [--listing]

The sound driver of res03 was assembled with TASM and linked into the unit with `{$L}`. No DOS assembler
runs here, and the rebuild must not depend on one, so this tool assembles the project's own source of the
driver (`src/RES03.ASM`) into the same kind of object: one 16-bit code segment named CODE, public names,
and fixups, so the Turbo Pascal linker places the code after the unit's own and resolves the addresses.

It is not a general assembler. It knows the 8086 instructions the driver uses and nothing else, and it
chooses encodings the way TASM did (checked: the driver assembles to the original's bytes):

  reg,reg and reg,mem ALU/MOV forms put the destination in the reg field (`mov bp,sp` is 8B EC);
  AX/AL with an immediate use the accumulator forms (`and ax,7Fh` is 25 7F 00);
  other registers and memory take the sign-extended imm8 form (83) when a constant fits;
  AX/AL with a direct address use A0..A3; a backward jump is short when it fits, a forward `jmp` is near
  unless written `jmp short`; conditional jumps and `loop` are always short.

Syntax (case-insensitive, `;` comments):

  PUBLIC  name, name              names the linker (and `external` declarations in Pascal) can see
  name    EQU  expression         an assembly-time constant (no fixup)
  label:                          an offset in the code segment (every use gets an offset fixup)
  CODESEG                         the paragraph of the code segment itself (a segment-base fixup)
  db 1, 'text', 0Dh, 48 dup (0)  dw expr, ...
  mov     ax, word ptr es:[bx+Table+2]    byte ptr / word ptr, segment overrides, [reg+reg+expr]
  numbers: 12, 0Ch, 0x0C, 'a'; operators + - * ( )

Output: the object file; with --binary the assembled bytes as they stand before linking (every label
reference holds the label's offset in the file, segment references hold 0: the form a C build embeds, with
--map giving the offsets); with --map the label offsets; with --listing the bytes of every line.
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path


class AsmError(Exception):
    pass


R16 = {"ax": 0, "cx": 1, "dx": 2, "bx": 3, "sp": 4, "bp": 5, "si": 6, "di": 7}
R8 = {"al": 0, "cl": 1, "dl": 2, "bl": 3, "ah": 4, "ch": 5, "dh": 6, "bh": 7}
SEG = {"es": 0, "cs": 1, "ss": 2, "ds": 3}
SEG_PREFIX = {"es": 0x26, "cs": 0x2E, "ss": 0x36, "ds": 0x3E}
ALU = {"add": 0, "or": 1, "adc": 2, "sbb": 3, "and": 4, "sub": 5, "xor": 6, "cmp": 7}
SHIFT = {"rol": 0, "ror": 1, "rcl": 2, "rcr": 3, "shl": 4, "sal": 4, "shr": 5, "sar": 7}
UNARY = {"not": 2, "neg": 3, "mul": 4, "imul": 5, "div": 6, "idiv": 7}
JCC = {"jo": 0, "jno": 1, "jb": 2, "jc": 2, "jnae": 2, "jae": 3, "jnb": 3, "jnc": 3, "je": 4, "jz": 4,
       "jne": 5, "jnz": 5, "jbe": 6, "jna": 6, "ja": 7, "jnbe": 7, "js": 8, "jns": 9, "jp": 10, "jnp": 11,
       "jl": 12, "jnge": 12, "jge": 13, "jnl": 13, "jle": 14, "jng": 14, "jg": 15, "jnle": 15}
SIMPLE = {"nop": 0x90, "ret": 0xC3, "retf": 0xCB, "iret": 0xCF, "cli": 0xFA, "sti": 0xFB, "cld": 0xFC,
          "std": 0xFD, "cbw": 0x98, "cwd": 0x99, "movsb": 0xA4, "movsw": 0xA5, "stosb": 0xAA, "stosw": 0xAB,
          "lodsb": 0xAC, "lodsw": 0xAD, "xlat": 0xD7, "pushf": 0x9C, "popf": 0x9D, "clc": 0xF8, "stc": 0xF9}


class Value:
    """A constant plus at most one label (offset) or the segment of the code segment."""
    __slots__ = ("const", "label", "seg")

    def __init__(self, const=0, label=None, seg=False):
        self.const, self.label, self.seg = const, label, seg

    @property
    def relocatable(self) -> bool:
        return self.label is not None or self.seg


class Operand:
    __slots__ = ("kind", "reg", "size", "value", "base", "index", "segp", "text", "explicit")

    def __init__(self, kind, text=""):
        self.kind, self.text = kind, text      # "r8" "r16" "sreg" "mem" "imm"
        self.reg = self.size = self.value = self.base = self.index = self.segp = None
        self.explicit = False


class Fixup:
    def __init__(self, offset, kind, label=None, disp=0):
        self.offset, self.kind, self.label, self.disp = offset, kind, label, disp   # kind: "off" | "seg"


# --- expressions -----------------------------------------------------------------------------------------
TOK = re.compile(r"\s*(0x[0-9a-fA-F]+|[0-9][0-9a-fA-F]*[hH]|[0-9]+|'(?:[^']|'')'|[A-Za-z_@$?][\w@$?]*|[-+*()])")


def tokenize(s: str) -> list[str]:
    out, pos = [], 0
    while pos < len(s):
        if s[pos].isspace():
            pos += 1
            continue
        m = TOK.match(s, pos)
        if not m or m.start() != pos and not s[pos:m.start()].isspace():
            raise AsmError("cannot read %r" % s[pos:pos + 12])
        out.append(m.group(1))
        pos = m.end()
    return out


def number(t: str) -> int | None:
    if re.fullmatch(r"0x[0-9a-fA-F]+", t):
        return int(t, 16)
    if re.fullmatch(r"[0-9][0-9a-fA-F]*[hH]", t):
        return int(t[:-1], 16)
    if t.isdigit():
        return int(t)
    if len(t) == 3 and t[0] == "'" and t[2] == "'":
        return ord(t[1])
    return None


class Expr:
    """Evaluates `a + b - 3` style expressions against the symbol tables; at most one label may appear
    with a plus sign (an address plus a constant), CODESEG alone is the segment."""

    def __init__(self, equs: dict, labels: dict | None):
        self.equs, self.labels = equs, labels

    def value(self, toks: list[str]) -> Value:
        self.t, self.i = toks, 0
        v = self._sum()
        if self.i != len(toks):
            raise AsmError("junk after expression: %r" % toks[self.i:])
        return v

    def _sum(self) -> Value:
        v = self._prod()
        while self.i < len(self.t) and self.t[self.i] in "+-":
            op = self.t[self.i]
            self.i += 1
            w = self._prod()
            if w.relocatable:
                if op == "-" or v.relocatable:
                    raise AsmError("unsupported relocatable arithmetic")
                v = Value(v.const + w.const, w.label, w.seg)
            else:
                v = Value(v.const + (w.const if op == "+" else -w.const), v.label, v.seg)
        return v

    def _prod(self) -> Value:
        v = self._atom()
        while self.i < len(self.t) and self.t[self.i] == "*":
            self.i += 1
            w = self._atom()
            if v.relocatable or w.relocatable:
                raise AsmError("cannot multiply an address")
            v = Value(v.const * w.const)
        return v

    def _atom(self) -> Value:
        if self.i >= len(self.t):
            raise AsmError("expression ends early")
        t = self.t[self.i]
        self.i += 1
        if t == "-":
            v = self._atom()
            if v.relocatable:
                raise AsmError("cannot negate an address")
            return Value(-v.const)
        if t == "(":
            v = self._sum()
            if self.i >= len(self.t) or self.t[self.i] != ")":
                raise AsmError("missing )")
            self.i += 1
            return v
        n = number(t)
        if n is not None:
            return Value(n)
        key = t.lower()
        if key == "codeseg":
            return Value(seg=True)
        if key in self.equs:
            return Value(self.equs[key])
        if self.labels is None:                      # pass 1: sizes only
            return Value(0, label=t)
        if key in self.labels:
            return Value(0, label=key)
        raise AsmError("undefined symbol %s" % t)


# --- the assembler ---------------------------------------------------------------------------------------
class Assembler:
    def __init__(self):
        self.equs: dict[str, int] = {}
        self.labels: dict[str, int] = {}
        self.names: dict[str, str] = {}              # lowercase -> as written
        self.publics: list[str] = []
        self.code = bytearray()
        self.fixups: list[Fixup] = []
        self.listing: list[tuple[int, bytes, str]] = []

    # parsing -------------------------------------------------------------------------------------------
    def operand(self, text: str, labels) -> Operand:
        s = text.strip()
        low = s.lower()
        if low in R16:
            o = Operand("r16", s)
            o.reg, o.size = R16[low], 2
            return o
        if low in R8:
            o = Operand("r8", s)
            o.reg, o.size = R8[low], 1
            return o
        if low in SEG:
            o = Operand("sreg", s)
            o.reg = SEG[low]
            return o
        size, explicit = None, False
        m = re.match(r"(byte|word|dword)\s+ptr\s+(.*)$", s, re.I)
        if m:
            size, explicit, s = {"byte": 1, "word": 2, "dword": 4}[m.group(1).lower()], True, m.group(2).strip()
        segp = None
        m = re.match(r"(es|cs|ss|ds)\s*:\s*(.*)$", s, re.I)
        if m:
            segp, s = m.group(1).lower(), m.group(2).strip()
        if s.startswith("["):
            if not s.endswith("]"):
                raise AsmError("bad memory operand %r" % text)
            o = Operand("mem", text)
            o.size, o.segp, o.explicit = size, segp, explicit
            regs, rest = [], []
            body = s[1:-1]
            for part in re.split(r"(?=[+-])", body):
                p = part.strip()
                if not p:
                    continue
                sign = "+"
                if p[0] in "+-":
                    sign, p = p[0], p[1:].strip()
                if p.lower() in ("bx", "bp", "si", "di"):
                    if sign == "-":
                        raise AsmError("cannot subtract a register")
                    regs.append(p.lower())
                else:
                    rest.append(sign + p)
            o.value = self.expr(" ".join(rest).lstrip("+").strip() or "0", labels)
            if rest and rest[0].startswith("-"):
                o.value = self.expr(" ".join(rest).strip(), labels)
            o.base = [r for r in regs if r in ("bx", "bp")]
            o.index = [r for r in regs if r in ("si", "di")]
            if len(o.base) > 1 or len(o.index) > 1:
                raise AsmError("bad address %r" % text)
            return o
        o = Operand("imm", text)
        o.value = self.expr(s, labels)
        o.size, o.explicit = size, explicit
        return o

    def expr(self, s: str, labels) -> Value:
        return Expr(self.equs, labels).value(tokenize(s))

    # emission ------------------------------------------------------------------------------------------
    def emit_modrm(self, reg: int, rm: Operand, out: bytearray, fix: list) -> None:
        """ModR/M, SIB-less 16-bit addressing; fixups are (offset within `out`, kind, value)."""
        if rm.kind in ("r8", "r16"):
            out.append(0xC0 | reg << 3 | rm.reg)
            return
        v = rm.value
        base, index = rm.base, rm.index
        combos = {("bx", "si"): 0, ("bx", "di"): 1, ("bp", "si"): 2, ("bp", "di"): 3, (None, "si"): 4,
                  (None, "di"): 5, ("bp", None): 6, ("bx", None): 7}
        b = base[0] if base else None
        i = index[0] if index else None
        if b is None and i is None:                 # direct address
            out.append(reg << 3 | 6)
            fix.append((len(out), v))
            out += b"\0\0"
            return
        code = combos.get((b, i))
        if code is None:
            raise AsmError("unsupported address mode %r" % rm.text)
        if v.relocatable:
            out.append(0x80 | reg << 3 | code)
            fix.append((len(out), v))
            out += b"\0\0"
        elif v.const == 0 and code != 6:
            out.append(reg << 3 | code)
        elif -128 <= v.const <= 127:
            out.append(0x40 | reg << 3 | code)
            out.append(v.const & 0xFF)
        else:
            out.append(0x80 | reg << 3 | code)
            out += struct.pack("<H", v.const & 0xFFFF)

    def put(self, buf: bytearray, fixes: list, line: str) -> None:
        pos = len(self.code)
        for off, v in fixes:
            if not v.relocatable:                    # a plain constant address
                buf[off:off + 2] = struct.pack("<H", v.const & 0xFFFF)
            elif v.seg:
                self.fixups.append(Fixup(pos + off, "seg"))
            else:
                # the field holds the label's offset in the object; the linker adds the segment's
                # placement through the fixup
                if self.labels and v.label.lower() in self.labels:
                    val = self.labels[v.label.lower()] + v.const
                    buf[off:off + 2] = struct.pack("<H", val & 0xFFFF)
                self.fixups.append(Fixup(pos + off, "off", v.label, v.const))
        self.code += buf
        self.listing.append((pos, bytes(buf), line))

    def seg_prefix(self, o: Operand, buf: bytearray) -> None:
        if o.kind == "mem" and o.segp:
            buf.append(SEG_PREFIX[o.segp])

    def imm_bytes(self, v: Value, size: int, buf: bytearray, fixes: list) -> None:
        if v.relocatable and size == 2:
            fixes.append((len(buf), v))
            buf += b"\0\0"
        elif v.relocatable:
            raise AsmError("an address does not fit a byte")
        elif size == 1:
            if not -128 <= v.const <= 255:
                raise AsmError("%d does not fit a byte" % v.const)
            buf.append(v.const & 0xFF)
        else:
            buf += struct.pack("<H", v.const & 0xFFFF)

    def assemble_instruction(self, mnem: str, ops: list[Operand], pc: int, pass2: bool, raw: str):
        """Returns (bytes, fixes) for one instruction at offset `pc`."""
        buf, fixes = bytearray(), []
        m = mnem.lower()
        n = len(ops)
        if m in SIMPLE and n == 0:
            return bytearray([SIMPLE[m]]), fixes
        if m == "mov":
            return self.enc_mov(ops)
        if m in ALU:
            return self.enc_alu(ALU[m], ops)
        if m in ("inc", "dec"):
            o = ops[0]
            ext = 0 if m == "inc" else 1
            if o.kind == "r16":
                return bytearray([0x40 + 8 * ext + o.reg]), fixes
            self.seg_prefix(o, buf)
            wide = o.kind == "r16" or (o.size == 2)
            if o.kind == "mem" and o.size is None:
                raise AsmError("operand size needed: %s" % raw)
            buf.append(0xFF if wide else 0xFE)
            self.emit_modrm(ext, o, buf, fixes)
            return buf, fixes
        if m in ("push", "pop"):
            o = ops[0]
            if o.kind == "r16":
                return bytearray([(0x50 if m == "push" else 0x58) + o.reg]), fixes
            if o.kind == "sreg":
                return bytearray([(0x06 if m == "push" else 0x07) + 8 * o.reg]), fixes
            raise AsmError("unsupported %s operand: %s" % (m, raw))
        if m in UNARY:
            o = ops[0]
            self.seg_prefix(o, buf)
            wide = o.kind == "r16" or o.size == 2
            if o.kind == "mem" and o.size is None:
                raise AsmError("operand size needed: %s" % raw)
            buf.append(0xF7 if wide else 0xF6)
            self.emit_modrm(UNARY[m], o, buf, fixes)
            return buf, fixes
        if m in SHIFT:
            o, c = ops
            self.seg_prefix(o, buf)
            wide = o.kind == "r16" or o.size == 2
            if c.kind == "r8" and c.reg == 1:
                buf.append(0xD3 if wide else 0xD2)
            elif c.kind == "imm" and not c.value.relocatable and c.value.const == 1:
                buf.append(0xD1 if wide else 0xD0)
            else:
                raise AsmError("shift count must be 1 or cl: %s" % raw)
            self.emit_modrm(SHIFT[m], o, buf, fixes)
            return buf, fixes
        if m == "int":
            return bytearray([0xCD, ops[0].value.const & 0xFF]), fixes
        if m in ("in", "out"):
            a, b = ops
            if m == "in":
                port, acc = b, a
            else:
                port, acc = a, b
            if acc.kind != "r8" and acc.kind != "r16" or acc.reg != 0:
                raise AsmError("in/out use al or ax: %s" % raw)
            if port.kind == "imm":
                op = (0xE4 if m == "in" else 0xE6) + (1 if acc.kind == "r16" else 0)
                return bytearray([op, port.value.const & 0xFF]), fixes
            if port.kind == "r16" and port.reg == 2:
                op = (0xEC if m == "in" else 0xEE) + (1 if acc.kind == "r16" else 0)
                return bytearray([op]), fixes
            raise AsmError("bad port: %s" % raw)
        if m == "retf" and n == 1:
            return bytearray([0xCA]) + struct.pack("<H", ops[0].value.const), fixes
        if m == "ret" and n == 1:
            return bytearray([0xC2]) + struct.pack("<H", ops[0].value.const), fixes
        if m == "xchg":
            a, b = ops
            if a.kind == "r16" and b.kind == "r16" and 0 in (a.reg, b.reg):
                return bytearray([0x90 + (b.reg if a.reg == 0 else a.reg)]), fixes
            raise AsmError("unsupported xchg: %s" % raw)
        if m == "lea":
            a, b = ops
            buf.append(0x8D)
            self.emit_modrm(a.reg, b, buf, fixes)
            return buf, fixes
        raise AsmError("unknown instruction: %s" % raw)

    def enc_mov(self, ops):
        buf, fixes = bytearray(), []
        d, s = ops
        if d.kind == "sreg" or s.kind == "sreg":
            if d.kind == "sreg":
                buf.append(0x8E)
                self.seg_prefix(s, buf) if False else None
                pre = bytearray()
                self.seg_prefix(s, pre)
                buf = pre + buf
                self.emit_modrm(d.reg, s, buf, fixes)
            else:
                pre = bytearray()
                self.seg_prefix(d, pre)
                buf = pre + bytearray([0x8C])
                self.emit_modrm(s.reg, d, buf, fixes)
            return buf, fixes
        wide = (d.kind == "r16") or (s.kind == "r16") or (d.size == 2) or (s.size == 2) or \
               (d.kind == "mem" and s.kind == "imm" and d.size == 2)
        if d.kind in ("r8", "r16") and s.kind == "imm":
            if d.kind == "r16":
                buf.append(0xB8 + d.reg)
                self.imm_bytes(s.value, 2, buf, fixes)
            else:
                buf.append(0xB0 + d.reg)
                self.imm_bytes(s.value, 1, buf, fixes)
            return buf, fixes
        if d.kind in ("r8", "r16") and s.kind in ("r8", "r16"):
            if d.kind != s.kind:
                raise AsmError("register sizes differ")
            buf.append(0x8B if d.kind == "r16" else 0x8A)
            self.emit_modrm(d.reg, s, buf, fixes)
            return buf, fixes
        if d.kind in ("r8", "r16") and s.kind == "mem":
            self.seg_prefix(s, buf)
            direct = not s.base and not s.index
            if d.reg == 0 and direct:
                buf.append(0xA1 if d.kind == "r16" else 0xA0)
                fixes.append((len(buf), s.value))
                buf += b"\0\0"
                return buf, fixes
            buf.append(0x8B if d.kind == "r16" else 0x8A)
            self.emit_modrm(d.reg, s, buf, fixes)
            return buf, fixes
        if d.kind == "mem" and s.kind in ("r8", "r16"):
            self.seg_prefix(d, buf)
            direct = not d.base and not d.index
            if s.reg == 0 and direct:
                buf.append(0xA3 if s.kind == "r16" else 0xA2)
                fixes.append((len(buf), d.value))
                buf += b"\0\0"
                return buf, fixes
            buf.append(0x89 if s.kind == "r16" else 0x88)
            self.emit_modrm(s.reg, d, buf, fixes)
            return buf, fixes
        if d.kind == "mem" and s.kind == "imm":
            if d.size is None:
                raise AsmError("operand size needed for mov to memory")
            self.seg_prefix(d, buf)
            buf.append(0xC7 if d.size == 2 else 0xC6)
            self.emit_modrm(0, d, buf, fixes)
            # displacement fixups come before the immediate: recorded by emit_modrm already
            self.imm_bytes(s.value, d.size, buf, fixes)
            return buf, fixes
        raise AsmError("unsupported mov operands")

    def enc_alu(self, code: int, ops):
        buf, fixes = bytearray(), []
        d, s = ops
        if s.kind == "imm":
            v = s.value
            if d.kind in ("r8", "r16", "mem"):
                wide = d.kind == "r16" or (d.kind == "mem" and d.size == 2)
                if d.kind == "mem" and d.size is None:
                    raise AsmError("operand size needed")
                if d.kind in ("r8", "r16") and d.reg == 0:     # accumulator forms
                    buf.append(code * 8 + (5 if wide else 4))
                    self.imm_bytes(v, 2 if wide else 1, buf, fixes)
                    return buf, fixes
                self.seg_prefix(d, buf)
                if not wide:
                    buf.append(0x80)
                    self.emit_modrm(code, d, buf, fixes)
                    self.imm_bytes(v, 1, buf, fixes)
                elif not v.relocatable and -128 <= v.const <= 127:
                    buf.append(0x83)
                    self.emit_modrm(code, d, buf, fixes)
                    buf.append(v.const & 0xFF)
                else:
                    buf.append(0x81)
                    self.emit_modrm(code, d, buf, fixes)
                    self.imm_bytes(v, 2, buf, fixes)
                return buf, fixes
        if d.kind in ("r8", "r16") and s.kind in ("r8", "r16", "mem"):
            self.seg_prefix(s, buf)
            wide = d.kind == "r16"
            buf.append(code * 8 + (3 if wide else 2))
            self.emit_modrm(d.reg, s, buf, fixes)
            return buf, fixes
        if d.kind == "mem" and s.kind in ("r8", "r16"):
            self.seg_prefix(d, buf)
            buf.append(code * 8 + (1 if s.kind == "r16" else 0))
            self.emit_modrm(s.reg, d, buf, fixes)
            return buf, fixes
        raise AsmError("unsupported operands")

    # driver ---------------------------------------------------------------------------------------------
    def run(self, text: str) -> None:
        lines = []
        for n, raw in enumerate(text.splitlines(), 1):
            s = raw.split(";", 1)[0] if "'" not in raw else self.strip_comment(raw)
            lines.append((n, raw, s.strip()))
        for pass2 in (False, True):
            self.code = bytearray()
            self.fixups = []
            self.listing = []
            if pass2:
                self.labels = dict(self.labels)
            for n, raw, s in lines:
                if not s:
                    continue
                try:
                    self.line(s, raw, pass2)
                except AsmError as e:
                    raise AsmError("line %d: %s: %s" % (n, e, raw.strip()))

    @staticmethod
    def strip_comment(raw: str) -> str:
        out, q = [], False
        for ch in raw:
            if ch == "'":
                q = not q
            if ch == ";" and not q:
                break
            out.append(ch)
        return "".join(out)

    def line(self, s: str, raw: str, pass2: bool) -> None:
        labels = self.labels if pass2 else None
        m = re.match(r"^([A-Za-z_@$?][\w@$?]*)\s+equ\s+(.*)$", s, re.I)
        if m:
            self.equs[m.group(1).lower()] = self.expr(m.group(2), self.labels if pass2 else {}).const \
                if pass2 or True else 0
            return
        m = re.match(r"^([A-Za-z_@$?][\w@$?]*)\s*:\s*(.*)$", s)
        if m and not re.match(r"^(es|cs|ss|ds)$", m.group(1), re.I):
            name = m.group(1)
            if not pass2:
                if name.lower() in self.labels:
                    raise AsmError("label %s defined twice" % name)
                self.labels[name.lower()] = len(self.code)
                self.names[name.lower()] = name
            s = m.group(2).strip()
            if not s:
                return
        m = re.match(r"^public\s+(.*)$", s, re.I)
        if m:
            if not pass2:
                self.publics += [x.strip() for x in m.group(1).split(",") if x.strip()]
            return
        m = re.match(r"^(db|dw|dd)\s+(.*)$", s, re.I)
        if m:
            self.data(m.group(1).lower(), m.group(2), labels, raw)
            return
        parts = s.split(None, 1)
        mnem = parts[0]
        rest = parts[1] if len(parts) > 1 else ""
        low = mnem.lower()
        if low in ("jmp", "call", "loop") or low in JCC or low == "jcxz":
            self.branch(low, rest, labels, raw, pass2)
            return
        if low in ("jmp", "call"):
            return
        ops = [self.operand(o, labels) for o in self.split_operands(rest)] \
            if rest else []
        if low == "jmp" or low == "call":
            return
        buf, fixes = self.assemble_instruction(low, ops, len(self.code), pass2, raw)
        self.put(buf, fixes, raw.strip())

    @staticmethod
    def split_operands(rest: str) -> list[str]:
        out, cur, depth, q = [], "", 0, False
        for ch in rest:
            if ch == "'":
                q = not q
            if not q:
                if ch in "[(":
                    depth += 1
                elif ch in "])":
                    depth -= 1
                elif ch == "," and depth == 0:
                    out.append(cur)
                    cur = ""
                    continue
            cur += ch
        if cur.strip():
            out.append(cur)
        return out

    def data(self, kind: str, rest: str, labels, raw: str) -> None:
        buf, fixes = bytearray(), []
        for item in self.split_operands(rest):
            item = item.strip()
            m = re.match(r"^(.+?)\s+dup\s*\((.*)\)$", item, re.I)
            if m:
                count = self.expr(m.group(1), labels).const
                inner = bytearray()
                ifix = []
                self.data_item(kind, m.group(2).strip(), labels, inner, ifix)
                if ifix:
                    raise AsmError("dup of an address")
                buf += inner * count
                continue
            self.data_item(kind, item, labels, buf, fixes)
        self.put(buf, fixes, raw.strip())

    def data_item(self, kind: str, item: str, labels, buf: bytearray, fixes: list) -> None:
        if kind == "db" and len(item) >= 2 and item[0] == "'" and item[-1] == "'" and len(item) != 3:
            buf += item[1:-1].replace("''", "'").encode("latin-1")
            return
        v = self.expr(item, labels)
        if kind == "db":
            if v.relocatable:
                raise AsmError("db of an address")
            if not -128 <= v.const <= 255:
                raise AsmError("%d does not fit a byte" % v.const)
            buf.append(v.const & 0xFF)
        elif kind == "dd":
            if v.relocatable:
                raise AsmError("dd of an address")
            buf += struct.pack("<I", v.const & 0xFFFFFFFF)
        else:
            self.imm_bytes(v, 2, buf, fixes)

    def branch(self, m: str, rest: str, labels, raw: str, pass2: bool) -> None:
        pc = len(self.code)
        text = rest.strip()
        force = None
        mm = re.match(r"^(short|near)\s+(.*)$", text, re.I)
        if mm:
            force, text = mm.group(1).lower(), mm.group(2).strip()
        indirect = text.startswith("[") or re.match(r"^(word|dword)\s+ptr", text, re.I) or \
            text.lower() in R16 or re.match(r"^(es|cs|ss|ds)\s*:", text, re.I)
        if m in ("jmp", "call") and indirect:
            o = self.operand(text, labels)
            buf, fixes = bytearray(), []
            far = bool(re.match(r"^dword\s+ptr", text, re.I))
            if o.kind == "mem" or o.kind == "r16":
                self.seg_prefix(o, buf) if o.kind == "mem" else None
                buf.append(0xFF)
                self.emit_modrm((3 if far else 2) if m == "call" else (5 if far else 4), o, buf, fixes)
            else:
                raise AsmError("bad indirect branch")
            self.put(buf, fixes, raw.strip())
            return
        if labels is None:
            size = 3 if m in ("call",) or (m == "jmp" and force != "short") else 2
            if m == "jmp" and force != "short":
                # pass 1 does not know the distance yet: a forward jump is near, a backward one may be short
                key = text.lower()
                known = key in self.labels
                size = 2 if (known and force != "near" and self._fits(self.labels[key], pc + 2)) else 3
            self.code += bytes(size)
            return
        key = text.lower()
        if key not in self.labels:
            raise AsmError("undefined label %s" % text)
        target = self.labels[key]
        if m == "call":
            buf = bytearray([0xE8]) + struct.pack("<h", target - (pc + 3))
        elif m == "jmp":
            if force == "short" or (force != "near" and target <= pc and self._fits(target, pc + 2)):
                buf = bytearray([0xEB, (target - (pc + 2)) & 0xFF])
            else:
                buf = bytearray([0xE9]) + struct.pack("<h", target - (pc + 3))
        else:
            code = {"loop": 0xE2, "jcxz": 0xE3}.get(m)
            if code is None:
                code = 0x70 + JCC[m]
            rel = target - (pc + 2)
            if not -128 <= rel <= 127:
                raise AsmError("%s out of range (%d)" % (m, rel))
            buf = bytearray([code, rel & 0xFF])
        # the pass-1 placeholder length must equal the final one
        placeholder = len(self.listing_len_probe) if False else None
        self.put_branch(buf, raw, pc)

    def put_branch(self, buf: bytearray, raw: str, pc: int) -> None:
        self.code += buf
        self.listing.append((pc, bytes(buf), raw.strip()))

    @staticmethod
    def _fits(target: int, next_pc: int) -> bool:
        return -128 <= target - next_pc <= 127

    # object file ----------------------------------------------------------------------------------------
    def object(self, module: str) -> bytes:
        return omf(module, bytes(self.code), [(self.names.get(p.lower(), p), self.labels[p.lower()])
                                              for p in self.publics], self.fixups, self.labels)


def record(rtype: int, data: bytes) -> bytes:
    body = bytes([rtype]) + struct.pack("<H", len(data) + 1) + data
    return body + bytes([(-sum(body)) & 0xFF])


def lname(s: str) -> bytes:
    b = s.encode("ascii")
    return bytes([len(b)]) + b


def omf(module: str, code: bytes, publics: list[tuple[str, int]], fixups: list[Fixup],
        labels: dict[str, int]) -> bytes:
    """THEADR, LNAMES, SEGDEF (CODE, byte aligned, public), PUBDEF, LEDATA with its FIXUPPs, MODEND."""
    out = [record(0x80, lname(module))]
    out.append(record(0x96, lname("") + lname("CODE")))
    out.append(record(0x98, bytes([0x28]) + struct.pack("<H", len(code)) + bytes([2, 2, 1])))
    chunk, size = [], 0
    for n, off in publics:
        item = lname(n) + struct.pack("<H", off) + b"\x00"
        if size + len(item) > 900:
            out.append(record(0x90, b"\x00\x01" + b"".join(chunk)))
            chunk, size = [], 0
        chunk.append(item)
        size += len(item)
    if chunk:
        out.append(record(0x90, b"\x00\x01" + b"".join(chunk)))
    pos = 0
    fx = sorted(fixups, key=lambda f: f.offset)
    starts = {f.offset for f in fx}
    while pos < len(code):
        n = min(1024, len(code) - pos)
        if pos + n < len(code) and (pos + n - 1) in starts:      # a field must not straddle two records
            n -= 1
        out.append(record(0xA0, bytes([1]) + struct.pack("<H", pos) + code[pos:pos + n]))
        mine = [f for f in fx if pos <= f.offset < pos + n]
        if mine:
            body = b""
            for f in mine:
                rel = f.offset - pos
                if f.kind == "seg":
                    body += bytes([0x80 | 0x40 | (2 << 2) | (rel >> 8 & 3), rel & 0xFF, 0x04, 1, 1])
                else:
                    # 16-bit offset, segment relative, frame and target the CODE segment, no displacement:
                    # the linker adds the segment's placement to the offset the field already holds
                    body += bytes([0x80 | 0x40 | (1 << 2) | (rel >> 8 & 3), rel & 0xFF, 0x04, 1, 1])
            out.append(record(0x9C, body))
        pos += n
    out.append(record(0x8A, b"\x00"))
    return b"".join(out)


def assemble(text: str, module: str = "SOUND") -> tuple[bytes, Assembler]:
    a = Assembler()
    a.run(text)
    return a.object(module), a


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("source")
    ap.add_argument("-o", "--out")
    ap.add_argument("--binary", help="also write the assembled bytes (offsets relative to the start)")
    ap.add_argument("--map", action="store_true")
    ap.add_argument("--listing", action="store_true")
    a = ap.parse_args(argv)
    try:
        obj, asm = assemble(Path(a.source).read_text(), Path(a.source).stem.upper())
    except AsmError as e:
        print("asm86: %s" % e)
        return 1
    if a.out:
        Path(a.out).write_bytes(obj)
    if a.binary:
        Path(a.binary).write_bytes(bytes(asm.code))
    if a.map:
        for n, off in sorted(asm.labels.items(), key=lambda kv: kv[1]):
            print("%04X %s" % (off, asm.names.get(n, n)))
    if a.listing:
        for pos, b, line in asm.listing:
            print("%04X %-24s %s" % (pos, b.hex(" ")[:23], line))
    print("asm86: %d bytes, %d fixups, %d publics" % (len(asm.code), len(asm.fixups), len(asm.publics)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

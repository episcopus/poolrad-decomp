"""p2c_coco.py: the CoCo profile's pass over the generated text (SPEC 8, step 8.2; ports/coco3/docs/PHASE-8.1.md 2.1).

pas2c --profile coco emits CMOC-readable C. Two kinds of change: those that need the Pascal types (casts that
keep byte arithmetic in 16 bits, the named unions of variant records, string concatenation without compound
literals, zeroing with memset) are made while generating (p2c_expr.py, p2c_decl.py, pas2c.py, flag `coco`); the rest
are spelling problems of the C text and are made here, on the finished text of game.h and of each unit:

  * a parenthesised declarator `T (*Name)` and the cast `T (*)` become `T *Name`, `T *`;
  * a pointer to an array (`T (*)[N]`, `T (*Name)[N]`, a pointer to an array typedef) becomes a pointer to a struct
    `struct PA_T_N { T a[N]; }` whose only member is the array: `(*p)[i]` is `p->a[i]`, the global array macro
    `(*(T (*)[N])(addr))` is `(((struct PA_T_N *)(addr))->a)`, `&Array` is a cast to the wrapper pointer;
  * `x -= y;` is written out (CMOC 0.1.100 turns a byte at a fixed address into `DECB #n`);
  * a negative constant stored into a signed byte at a fixed address is stored as an unsigned byte constant (CMOC
    0.1.100 assembles `LDB #$FFFF`);
  * 32-bit and negative enumerators become `#define`s (CMOC enumerators are 16-bit; a negative one trips the bug above);
  * void operands in comma expressions are split into statements; a cast of an array to a LongInt is a pointer cast;
  * the PC build's own spellings stay valid C: the EGA window is `POOL_VIDEO(addr)`, array bounds over 32767 go
    through `POOL_CAP`, `#pragma pack` is hidden from CMOC (which does not pad).

The output compiles with clang (the host build keeps its memory model and still passes the recorded sessions) and with
CMOC (`ports/coco3/scripts/sizes.sh`). No transform changes what the program computes.
"""
from __future__ import annotations

import re

LOG_KEYS = ["pragma", "big_array", "big_enum", "proc_ids", "video_plane", "array_typedef_ptr", "array_ptr",
            "array_addr_of", "paren_declarator", "minus_equals", "negbyte_store", "comma_stmt", "s32_array_cast"]

TYPEWORDS = r"(?:const |struct )?[A-Za-z_]\w*"
DIMS = r"(?:\[[\w()]+\])+"
KEYWORDS = {"return", "sizeof", "case", "else", "do", "if", "while", "for", "switch"}


def find_close(s, i, open_ch="{", close_ch="}"):
    depth = 0
    while i < len(s):
        if s[i] == open_ch:
            depth += 1
        elif s[i] == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced " + open_ch)


class Coco:
    def __init__(self):
        self.log = dict.fromkeys(LOG_KEYS, 0)
        self.array_typedefs: dict[str, tuple[str, str]] = {}      # typedef name -> (base, dims)
        self.wrappers: dict[str, str] = {}                       # struct tag -> definition
        self.array_macros: dict[str, str] = {}                   # global array macro -> wrapper pointer expression
        self.neg_enums: dict[str, int] = {}
        self.s8_macros: set[str] = set()
        self.arr_ptr_type = re.compile("(" + TYPEWORDS + r") ?\(\*\)(" + DIMS + ")")
        self.arr_ptr_named = re.compile("(" + TYPEWORDS + r") ?\(\*(\w+)\)(" + DIMS + ")")

    # ---------------------------------------------------------------------------- wrappers
    def pa(self, base: str, dims: str) -> str:
        base = base.strip()
        tag = "PA_" + re.sub(r"\W+", "_", base) + "".join("_" + d for d in re.findall(r"\d+", dims))
        if tag not in self.wrappers:
            self.wrappers[tag] = "struct %s { %s a%s; };" % (tag, base, dims)
        return "struct " + tag       # CMOC needs the tag: it cannot typedef an incomplete struct

    def bound(self, dims: str) -> str:
        """Array bounds over 32,767 (typedefs used only to cast a block) go through POOL_CAP."""
        return re.sub(r"\[(\d+)\]", lambda m: "[POOL_CAP(%s)]" % m.group(1) if int(m.group(1)) > 32767 else m.group(0), dims)

    # ---------------------------------------------------------------------------- header
    def header(self, s: str) -> str:
        for m in re.finditer(r"^typedef (\w+) (\w+)((?:\[\d+\])+);", s, re.M):
            self.array_typedefs[m.group(2)] = (m.group(1), m.group(3))
        s = s.replace("#pragma pack(push, 1)", "#ifndef _CMOC_VERSION_\n#pragma pack(push, 1)\n#endif")
        s = s.replace("#pragma pack(pop)", "#ifndef _CMOC_VERSION_\n#pragma pack(pop)\n#endif")

        def cap(m):
            if int(m.group(2)) > 32767:
                self.log["big_array"] += 1
                return "%sPOOL_CAP(%s)%s" % (m.group(1), m.group(2), m.group(3))
            return m.group(0)
        s = re.sub(r"^(typedef [^\n]*\[)(\d+)(\];)", cap, s, flags=re.M)

        def big(m):
            self.log["big_enum"] += 1
            return "#define %s %sL" % (m.group(1), m.group(2))
        s = re.sub(r"enum \{ (\w+) = (\d{5,})U? \};", big, s)

        def neg(m):
            self.log["big_enum"] += 1
            self.neg_enums[m.group(1)] = int(m.group(2))
            return "#define %s (%s)" % (m.group(1), m.group(2))
        s = re.sub(r"enum \{ (\w+) = \((-\d+)\) \};", neg, s)

        m = re.search(r"enum \{ PROC_none = 0, (.*?) \};", s, re.S)
        if m:                                         # 32-bit far addresses: long constants, not 16-bit enumerators
            names = re.findall(r"(PROC_\w+) = (0x[0-9A-Fa-f]+)U", m.group(1))
            self.log["proc_ids"] += len(names)
            defs = "#define PROC_none 0\n" + "\n".join("#define %s %sUL" % (n, v) for n, v in names)
            s = s[:m.start()] + defs + s[m.end():]
        s = self.video(s)
        s = self.expand_array_typedef_ptrs(s)
        names = set()
        s = self.pointer_to_array(s, names)
        s = self.array_pointer_uses(s, names)
        for m in re.finditer(r"^#define (\w+) \((\(\(struct PA_\w+ \*\)\(.*?\)\))->a\)$", s, re.M):
            self.array_macros[m.group(1)] = m.group(2)
        s = self.paren_declarators(s)
        for m in re.finditer(r"^#define (\w+) \(\*\(s8 \*\)\(", s, re.M):
            self.s8_macros.add(m.group(1))
        return s

    def finish_header(self, s: str) -> str:
        """The wrapper structs: declared at the top (pointers only need the tag), defined at the end."""
        mark = '#include "pool.h"\n'
        fwd = "".join("struct %s;\n" % t for t in sorted(self.wrappers))
        s = s.replace(mark, mark + "\n/* CoCo profile: pointers to arrays are pointers to these one-array structs */\n" + fwd, 1)
        end = s.rindex("#endif")
        return s[:end] + "\n" + "\n".join(self.wrappers[t] for t in sorted(self.wrappers)) + "\n" + s[end:]

    # ---------------------------------------------------------------------------- units
    def unit(self, s: str) -> str:
        s = self.video(s)
        s = self.minus_equals(s)
        s = self.negbyte_stores(s)
        s = self.split_comma_statements(s)
        s = self.s32_array_casts(s)
        s = self.address_of_array_macros(s)
        s = self.expand_array_typedef_ptrs(s)
        out = []
        for c in re.split(r"(?m)^(?=/\*)", s):      # per routine (a comment block starts each): local names differ
            c = self.address_of_local_arrays(c)
            names = set()
            c = self.pointer_to_array(c, names)
            out.append(self.deref_wrapper_casts(self.array_pointer_uses(c, names)))
        return self.paren_declarators("".join(out))

    # ---------------------------------------------------------------------------- the transforms
    def video(self, s):
        def repl(m):
            self.log["video_plane"] += 1
            return "POOL_VIDEO(%s)" % m.group(1)
        return re.sub(r"\(pool_arena \+ (0x[0-9A-Fa-f]+)\)", repl, s)

    def minus_equals(self, s):
        def repl(m):
            self.log["minus_equals"] += 1
            return "%s%s = %s - %s;" % (m.group(1), m.group(2), m.group(2), m.group(3))
        return re.sub(r"^(\s+)([^=;\n{}]+?) -= (\w+);", repl, s, flags=re.M)

    def negbyte_stores(self, s):
        """`AttackRoll = MissRoll;` where AttackRoll is a signed byte at a fixed address and the constant is negative."""
        if not self.s8_macros:
            return s

        def repl(m):
            lhs, rhs = m.group(2), m.group(3)
            v = self.neg_enums.get(rhs)
            if v is None and re.fullmatch(r"\(-\d+\)", rhs):
                v = int(rhs[1:-1])
            if lhs in self.s8_macros and v is not None and -128 <= v < 0:
                self.log["negbyte_store"] += 1
                return "%s%s = (u8)0x%02X;" % (m.group(1), lhs, v & 0xFF)
            return m.group(0)
        return re.sub(r"^(\s+)(\w+) = (\w+|\(-\d+\));", repl, s, flags=re.M)

    @staticmethod
    def top_level_commas(st):
        depth, cuts, i, instr = 0, [], 0, False
        while i < len(st):
            ch = st[i]
            if instr:
                if ch == "\\":
                    i += 1
                elif ch == '"':
                    instr = False
            elif ch == '"':
                instr = True
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "," and depth == 0 and st[i + 1:i + 6] == " rtl_":
                cuts.append(i)
            i += 1
        return cuts

    def split_comma_statements(self, s):
        out = []
        for line in s.split("\n"):
            st = line.lstrip()
            if st.startswith("rtl_") and st.endswith(");"):
                cuts = self.top_level_commas(st)
                if cuts:
                    indent = line[:len(line) - len(st)]
                    parts, last = [], 0
                    for c in cuts:
                        parts.append(st[last:c] + ";")
                        last = c + 2
                    parts.append(st[last:])
                    out.extend(indent + p for p in parts)
                    self.log["comma_stmt"] += len(cuts)
                    continue
            out.append(line)
        return "\n".join(out)

    def s32_array_casts(self, s):
        def repl(m):
            self.log["s32_array_cast"] += 1
            return "*(s32 *)&" + m.group(1)
        return re.sub(r"\(s32\)(\(\*\w+\)\.Slots\[[^\]]*(?:\[[^\]]*\])?[^\]]*\]\.Data)", repl, s)

    def expand_array_typedef_ptrs(self, s):
        for name, (base, dims) in self.array_typedefs.items():
            def repl(m):
                self.log["array_typedef_ptr"] += 1
                var = m.group(1) if m.group(1) is not None else m.group(2)
                return "%s (*%s)%s" % (base, var, dims)
            s = re.sub(r"(?<!\w)" + re.escape(name) + r"(?: ?\(\*(\w*)\)| ?\*(\w*))", repl, s)
        return s

    def pointer_to_array(self, s, names_out):
        pat = re.compile(r"\(\*\((" + TYPEWORDS + r") ?\(\*\)(" + DIMS + r")\)(\w*)\(")
        out, i = [], 0
        while True:                                   # global array macros
            m = pat.search(s, i)
            if not m:
                out.append(s[i:])
                break
            addr_open = m.end() - 1
            addr_close = find_close(s, addr_open, "(", ")")
            out.append(s[i:m.start()])
            out.append("(((%s *)%s%s)->a)" % (self.pa(m.group(1), self.bound(m.group(2))), m.group(3), s[addr_open:addr_close + 1]))
            i = addr_close + 2
            self.log["array_ptr"] += 1
        s = "".join(out)
        out, i = [], 0
        fp = re.compile(r"\(\*(FP[DMB])\(")
        while True:                                   # (*FPD(T (*)[N], e))[  ->  FPD(W *, e)->a[   (FPM, FPB likewise)
            m = fp.search(s, i)
            if not m:
                out.append(s[i:])
                break
            j, mac = m.start(), m.group(1)
            close_fpd = find_close(s, j + 5, "(", ")")
            close_outer = find_close(s, j, "(", ")")
            args = s[m.end():close_fpd]
            if close_outer == close_fpd + 1 and self.arr_ptr_type.match(args):
                self.log["array_ptr"] += 1
                out.append(s[i:j])
                out.append(mac + "(" + self.arr_ptr_type.sub(lambda mm: self.pa(mm.group(1), self.bound(mm.group(2))) + " *", args, 1) + ")->a")
                i = close_outer + 1
            else:
                out.append(s[i:m.end()])
                i = m.end()
        s = "".join(out)

        def named(m):
            names_out.add(m.group(2))
            self.log["array_ptr"] += 1
            return self.pa(m.group(1), self.bound(m.group(3))) + " *" + m.group(2)
        s = self.arr_ptr_named.sub(named, s)

        def cast(m):
            self.log["array_ptr"] += 1
            return self.pa(m.group(1), self.bound(m.group(2))) + " *"
        return self.arr_ptr_type.sub(cast, s)

    def deref_wrapper_casts(self, s):
        pat = re.compile(r"\(\*\(struct PA_\w+ \*\)")
        i = 0
        while True:
            m = pat.search(s, i)
            if not m:
                return s
            close = find_close(s, m.start(), "(", ")")
            inner = s[m.start() + 2:close]
            s = s[:m.start()] + "(" + inner + ")->a" + s[close + 1:]
            self.log["array_ptr"] += 1
            i = m.start() + 1

    def array_pointer_uses(self, s, names):
        for n in names:
            s = re.sub(r"(?<=[=(,] )\*" + n + r"\b|(?<=[=(,])\*" + n + r"\b", n + "->a", s)
            s = re.sub(r"&\(\*" + n + r"\)(?!\[)", n, s)
            s = re.sub(r"\(\*" + n + r"\)\[", n + "->a[", s)
            s = re.sub(r"(?<![\w&])\(\*" + n + r"\)(?![\w\[.])", n + "->a", s)
        return s

    def address_of_array_macros(self, s):
        for name, ptr in self.array_macros.items():
            s, n = re.subn(r"&" + name + r"(?![\w\[])", lambda m: ptr, s)
            self.log["array_addr_of"] += n
        return s

    def address_of_local_arrays(self, s):
        arrays = dict((m.group(2), (m.group(1), m.group(3))) for m in
                      re.finditer(r"^\s+(u8|s8|u16|s16|s32|u32|farptr) (\w+)((?:\[\d+\])+);", s, re.M))
        for m in re.finditer(r"^\s+(\w+) (\w+);", s, re.M):
            if m.group(1) in self.array_typedefs:
                arrays[m.group(2)] = self.array_typedefs[m.group(1)]
        for n, (base, dims) in arrays.items():
            s, k = re.subn(r"&" + n + r"(?![\w\[])", lambda m: "(%s *)%s" % (self.pa(base, self.bound(dims)), n), s)
            self.log["array_addr_of"] += k
        return s

    def paren_declarators(self, s):
        def repl(m):
            before = s[max(0, m.start() - 40):m.start()]
            w = re.search(r"([A-Za-z_]\w*) $", before)
            after = s[m.end():m.end() + 2].lstrip()[:1]
            if w and w.group(1) not in KEYWORDS and after in ("", ",", ")", ";", "="):
                self.log["paren_declarator"] += 1
                return "*" + m.group(1)
            return m.group(0)
        return re.sub(r"\(\*(\w*)\)", repl, s)

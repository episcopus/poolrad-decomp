#!/usr/bin/env python3
"""cmocify.py: mechanical transforms that let CMOC read the Phase 7 generated C (step 8.1).
Usage: cmocify.py SRC_DIR OUT_DIR       (SRC_DIR = c/game; writes game.h and the unit files)

Each transform answers one thing CMOC 0.1.100 cannot parse or type; docs/PHASE-8.1.md lists them
with their counts. They exist to measure, not to ship: step 8.2 puts the same fixes into the
translator (a CoCo profile of tools/c/pas2c.py), so this list is the first draft of that
profile's requirements. The transforms keep the code's shape (same statements, same operators)
so the 6809 sizes measured from the result mean what they say.
"""
import os
import re
import sys

LOG_KEYS = ["pragma", "anon_union", "big_array", "big_enum", "proc_ids", "video_plane",
            "array_typedef_ptr", "array_ptr", "array_addr_of", "paren_declarator",
            "minus_equals", "zero_init", "comma_stmt", "compound_literal", "s32_array_cast"]

# ---------------------------------------------------------------------------------- helpers


def find_close(s, i):
    """Index of the brace that closes the one at s[i]."""
    depth = 0
    while i < len(s):
        if s[i] == "{":
            depth += 1
        elif s[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced braces")


def match_paren(s, i):
    """Index of the parenthesis closing the one at s[i]."""
    depth = 0
    while i < len(s):
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced parentheses")


# ---------------------------------------------------------------------------------- header only


def flatten_anon_unions(s, log):
    """union { struct {A}; struct {B}; }; -> A B   (CMOC has no anonymous unions; the members sit
    side by side, so the layout differs from the overlay but not the code: fields are still reached
    at fixed offsets)."""
    while True:
        m = re.search(r"\n(\s*)union \{", s)
        if not m:
            return s
        ob = s.index("{", m.start())
        cb = find_close(s, ob)
        end = s.index(";", cb) + 1
        inner = s[ob + 1:cb]
        out, i = [], 0
        while True:
            sm = re.search(r"struct \{", inner[i:])
            if not sm:
                out.append(inner[i:])
                break
            out.append(inner[i:i + sm.start()])
            sob = i + sm.end() - 1
            scb = find_close(inner, sob)
            out.append(inner[sob + 1:scb])
            i = inner.index(";", scb) + 1
        s = s[:m.start()] + "\n" + "".join(out).strip("\n") + s[end:]
        log["anon_union"] += 1


def big_arrays(s, log):
    """typedef u8 T[65520]: CMOC arrays stop at 32767 elements; a typedef used only to cast a block
    reached through a pointer keeps working with a smaller bound."""
    def cap(m):
        if int(m.group(2)) > 32767:
            log["big_array"] += 1
            return m.group(1) + "32767" + m.group(3)
        return m.group(0)
    return re.sub(r"^(typedef [^\n]*\[)(\d+)(\];)", cap, s, flags=re.M)


def big_enums(s, log):
    """enum { Name = 360000 }; CMOC enumerators are 16-bit ints: constants above 32767 become
    long #defines."""
    def repl(m):
        log["big_enum"] += 1
        return "#define %s %sL" % (m.group(1), m.group(2))
    s = re.sub(r"enum \{ (\w+) = (\d{5,})U? \};", repl, s)
    # CMOC bug: a negative constant stored in a signed byte at a fixed address compiles to `LDB #$FFFF` (found in ovl12;
    # minimal case `*(s8 *)0x6822 = -1;`). Kept as the byte it is; the value seen by wider code differs, the code shape does not
    def neg(m):
        log["big_enum"] += 1
        return "#define %s ((u8)0x%02X)" % (m.group(1), int(m.group(2)) & 0xFF)
    return re.sub(r"enum \{ (\w+) = \((-\d+)\) \};", neg, s)


def proc_enum_to_defines(s, log):
    """The procedure-pointer ids are 32-bit constants (the original's far addresses); number them
    1.. instead: only their distinctness matters here."""
    m = re.search(r"enum \{ PROC_none = 0, (.*?) \};", s, re.S)
    if not m:
        return s
    names = re.findall(r"(PROC_\w+) = 0x[0-9A-Fa-f]+U", m.group(1))
    defs = "#define PROC_none 0\n" + "\n".join("#define %s %d" % (n, i + 1) for i, n in enumerate(names))
    log["proc_ids"] += len(names)
    return s[:m.start()] + defs + s[m.end():]


# ---------------------------------------------------------------------------------- pointers to arrays

TYPEWORDS = r"(?:const |struct )?[A-Za-z_]\w*"
DIMS = r"(?:\[\d+\])+"
ARR_PTR_TYPE = re.compile("(" + TYPEWORDS + r") ?\(\*\)(" + DIMS + ")")
ARR_PTR_NAMED = re.compile("(" + TYPEWORDS + r") ?\(\*(\w+)\)(" + DIMS + ")")
ARRAY_TYPEDEFS = {}     # name -> (base, dims), read from game.h
PA_TYPES = {}           # wrapper struct name -> definition, written into game.h at the end
ARRAY_MACROS = {}       # global-array macro name -> its wrapper pointer expression, from game.h


def pa_name(base, dims):
    """The wrapper struct that stands for `base (*)dims`: CMOC cannot parse a pointer to an array,
    but it can point to a struct whose only member is the array."""
    base = base.strip()
    dims = re.sub(r"\[(\d+)\]", lambda m: "[%d]" % min(int(m.group(1)), 32767), dims)   # CMOC array limit
    name = "PA_" + re.sub(r"\W+", "_", base) + "".join("_" + d for d in re.findall(r"\d+", dims))
    if name not in PA_TYPES:
        PA_TYPES[name] = "struct %s { %s a%s; };" % (name, base, dims)
    return "struct " + name       # CMOC needs the tag: no typedef of an incomplete struct


def expand_array_typedef_ptrs(s, log):
    """A pointer to an array typedef (`TPictureShown *Shown`, `TPictureShown (*Shown)`,
    `(*(TPartyMoney *)(addr))`) is a pointer to an array: rewrite it to the explicit form."""
    for name, (base, dims) in ARRAY_TYPEDEFS.items():
        def repl(m):
            log["array_typedef_ptr"] += 1
            var = m.group(1) if m.group(1) is not None else m.group(2)
            return "%s (*%s)%s" % (base, var, dims)
        s = re.sub(r"(?<!\w)" + re.escape(name) + r"(?: ?\(\*(\w*)\)| ?\*(\w*))", repl, s)
    return s


def pointer_to_array(s, log, names_out):
    """`T (*)[N]` (casts), `T (*Name)[N]` (declarations) and their uses become pointers to a
    wrapper struct: `(*p)[i]` is `p->a[i]`, `(*p)` is `p->a`; the global-array macro
    `(*(T (*)[N])(addr))` is `(((W *)(addr))->a)`."""
    out, i = [], 0
    pat = re.compile(r"\(\*\((" + TYPEWORDS + r") ?\(\*\)(" + DIMS + r")\)\(")
    while True:                                   # global array macros
        m = pat.search(s, i)
        if not m:
            out.append(s[i:])
            break
        addr_open = m.end() - 1
        addr_close = match_paren(s, addr_open)
        out.append(s[i:m.start()])
        out.append("(((%s *)%s)->a)" % (pa_name(m.group(1), m.group(2)), s[addr_open:addr_close + 1]))
        i = addr_close + 2                         # skip the outer closing paren
        log["array_ptr"] += 1
    s = "".join(out)
    out, i = [], 0
    while True:                                   # (*FPD(T (*)[N], e))[  ->  FPD(W *, e)->a[
        j = s.find("(*FPD(", i)
        if j < 0:
            out.append(s[i:])
            break
        close_fpd = match_paren(s, j + 5)
        close_outer = match_paren(s, j)
        args = s[j + 6:close_fpd]
        if close_outer == close_fpd + 1 and ARR_PTR_TYPE.match(args):
            log["array_ptr"] += 1
            out.append(s[i:j])
            out.append("FPD(" + ARR_PTR_TYPE.sub(lambda m: pa_name(m.group(1), m.group(2)) + " *", args, 1) + ")->a")
            i = close_outer + 1
        else:
            out.append(s[i:j + 6])
            i = j + 6
    s = "".join(out)

    def named(m):                                 # declarations
        names_out.add(m.group(2))
        log["array_ptr"] += 1
        return pa_name(m.group(1), m.group(3)) + " *" + m.group(2)
    s = ARR_PTR_NAMED.sub(named, s)
    return re.sub(r"(" + TYPEWORDS + r") ?\(\*\)(" + DIMS + ")",   # casts that are left
                  lambda m: (log.__setitem__("array_ptr", log["array_ptr"] + 1) or pa_name(m.group(1), m.group(2)) + " *"), s)


def deref_wrapper_casts(s, log):
    """(*(struct PA_x *)expr)[i] and (*(struct PA_x *)expr) -> ((struct PA_x *)expr)->a[i] / ->a"""
    pat = re.compile(r"\(\*\(struct PA_\w+ \*\)")
    i = 0
    while True:
        m = pat.search(s, i)
        if not m:
            return s
        close = match_paren(s, m.start())
        inner = s[m.start() + 2:close]          # (struct PA_x *)expr
        s = s[:m.start()] + "(" + inner + ")->a" + s[close + 1:]
        log["array_ptr"] += 1
        i = m.start() + 1


def array_pointer_uses(s, names, log):
    """Uses of the declared names: `&(*p)` -> `p`, `(*p)[i]` -> `p->a[i]`, `(*p)` -> `p->a`."""
    for n in names:
        s = re.sub(r"(?<=[=(,] )\*" + n + r"\b|(?<=[=(,])\*" + n + r"\b", n + "->a", s)
        s = re.sub(r"&\(\*" + n + r"\)(?!\[)", n, s)
        s = re.sub(r"\(\*" + n + r"\)\[", n + "->a[", s)
        s = re.sub(r"(?<![\w&])\(\*" + n + r"\)(?![\w\[.])", n + "->a", s)
    return s


def address_of_array_macros(s, log):
    """`&Global` where Global is an array macro: the address of an array member through a cast is
    an indirection CMOC does not do; use the wrapper pointer the macro was built from."""
    for name, ptr in ARRAY_MACROS.items():
        s, n = re.subn(r"&" + name + r"(?![\w\[])", lambda m: ptr, s)
        log["array_addr_of"] += n
    return s


def address_of_local_arrays(s, log):
    """`&t1` where t1 is a local `u8 t1[256]`: pass the array as the wrapper pointer the callee
    declares."""
    arrays = dict((m.group(2), (m.group(1), m.group(3))) for m in
                  re.finditer(r"^\s+(u8|s8|u16|s16|s32|u32|farptr) (\w+)((?:\[\d+\])+);", s, re.M))
    for m in re.finditer(r"^\s+(\w+) (\w+);", s, re.M):          # locals of an array typedef
        if m.group(1) in ARRAY_TYPEDEFS:
            arrays[m.group(2)] = ARRAY_TYPEDEFS[m.group(1)]
    for n, (base, dims) in arrays.items():
        s, k = re.subn(r"&" + n + r"(?![\w\[])", lambda m: "(%s *)%s" % (pa_name(base, dims), n), s)
        log["array_addr_of"] += k
    return s


PAREN_STAR = re.compile(r"\(\*(\w*)\)")
KEYWORDS = {"return", "sizeof", "case", "else", "do", "if", "while", "for", "switch"}


def paren_declarators(s, log):
    """`T (*Name)` and the cast `T (*)` -> `T *Name`, `T *`: CMOC does not parse a parenthesised
    declarator. A use (`&(*Name)`, `(*Name).Field`, `(*Name)++`, `return (*Name)`) is left alone:
    a declarator is preceded by a type name and followed by `,` `)` `;` `=` or the end."""
    def repl(m):
        before = s[max(0, m.start() - 40):m.start()]
        w = re.search(r"([A-Za-z_]\w*) $", before)
        after = s[m.end():m.end() + 2].lstrip()[:1]
        if w and w.group(1) not in KEYWORDS and after in ("", ",", ")", ";", "="):
            log["paren_declarator"] += 1
            return "*" + m.group(1)
        return m.group(0)
    return PAREN_STAR.sub(repl, s)


# ---------------------------------------------------------------------------------- units only


def zero_initialisers(s, log):
    """`T x = {0};` -> `T x;` (CMOC rejects `= {0}` for arrays of structs and for structs holding
    arrays; the Pascal had no initialisation, locals were whatever the stack held)."""
    s, n = re.subn(r" = \{0\};", ";", s)
    log["zero_init"] += n
    return s


def split_top_level_commas(st):
    """Positions of the commas at depth 0 outside string literals."""
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


def split_comma_statements(s, log):
    """`rtl_write_str(...), rtl_write_ln(f);` -> two statements: CMOC rejects a void operand in a
    comma expression."""
    out = []
    for line in s.split("\n"):
        st = line.lstrip()
        if st.startswith("rtl_") and st.endswith(");"):
            cuts = split_top_level_commas(st)
            if cuts:
                indent = line[:len(line) - len(st)]
                parts, last = [], 0
                for c in cuts:
                    parts.append(st[last:c] + ";")
                    last = c + 2
                parts.append(st[last:])
                out.extend(indent + p for p in parts)
                log["comma_stmt"] += len(cuts)
                continue
        out.append(line)
    return "\n".join(out)


def compound_literals(s, log):
    """rtl_str_cat(dst, n, (const u8 *const[]){a, b}) -> rtl_str_cat(dst, n, a, b): CMOC has no
    compound literals; the shim's prototype is variadic."""
    key = "(const u8 *const[]){"
    while key in s:
        i = s.index(key)
        ob = i + len(key) - 1
        cb = find_close(s, ob)
        s = s[:i] + s[ob + 1:cb] + s[cb + 1:]
        log["compound_literal"] += 1
    return s


def minus_equals(s, log):
    """CMOC 0.1.100 bug: `x -= 5;` on a byte at a fixed address compiles to `DECB #$05`, which no
    assembler accepts (found in ovl12). Write the subtraction out."""
    def repl(m):
        log["minus_equals"] += 1
        return "%s%s = %s - %s;" % (m.group(1), m.group(2), m.group(2), m.group(3))
    return re.sub(r"^(\s+)([^=;\n{}]+?) -= (\w+);", repl, s, flags=re.M)


def video_planes(s, log):
    """(pool_arena + 0xB8000): the EGA planes are not part of the CoCo's memory model; keep the
    reference as a 16-bit address so the code that touches them still compiles."""
    def repl(m):
        log["video_plane"] += 1
        return "((u8 *)0x%04X)" % (int(m.group(1), 16) & 0xFFFF)
    return re.sub(r"\(pool_arena \+ (0x[0-9A-Fa-f]+)\)", repl, s)


def s32_array_casts(s, log):
    """(s32)(*Sprites).Slots[i].Data: a Pascal typecast of a 4-byte array to a LongInt; CMOC will not
    cast an array to long."""
    def repl(m):
        log["s32_array_cast"] += 1
        return "*(s32 *)&" + m.group(1)
    return re.sub(r"\(s32\)(\(\*\w+\)\.Slots\[[^\]]*(?:\[[^\]]*\])?[^\]]*\]\.Data)", repl, s)


# ---------------------------------------------------------------------------------- driver


def transform_unit(s, log, names_out):
    s = zero_initialisers(s, log)
    s = split_comma_statements(s, log)
    s = video_planes(s, log)
    s = minus_equals(s, log)
    s = s32_array_casts(s, log)
    s = address_of_array_macros(s, log)
    s = expand_array_typedef_ptrs(s, log)
    # the rest per routine: names of locals and parameters mean different things in different ones
    chunks = re.split(r"(?m)^(?=/\*)", s)          # one comment block (and the routine after it) at a time
    out = []
    for c in chunks:
        c = address_of_local_arrays(c, log)
        names = set()
        c = pointer_to_array(c, log, names)
        out.append(deref_wrapper_casts(array_pointer_uses(c, names, log), log))
    s = paren_declarators("".join(out), log)
    return compound_literals(s, log)


def transform_header(s, log, names_out):
    s = re.sub(r"^#pragma .*\n", lambda m: log.__setitem__("pragma", log["pragma"] + 1) or "", s, flags=re.M)
    s = flatten_anon_unions(s, log)
    s = big_arrays(s, log)
    s = big_enums(s, log)
    s = proc_enum_to_defines(s, log)
    s = video_planes(s, log)
    s = expand_array_typedef_ptrs(s, log)
    names = set()
    s = pointer_to_array(s, log, names)
    names_out |= names
    s = array_pointer_uses(s, names, log)
    # the global array macros: `#define Name (((W *)(addr))->a)` also get a `Name__p` pointer macro
    for m in re.finditer(r"^#define (\w+) \((\(\(struct PA_\w+ \*\)\(.*?\)\))->a\)$", s, re.M):
        ARRAY_MACROS[m.group(1)] = m.group(2)
    return paren_declarators(s, log)


def main(src, out):
    os.makedirs(out, exist_ok=True)
    log = dict.fromkeys(LOG_KEYS, 0)
    header = open(os.path.join(src, "game.h")).read()
    for m in re.finditer(r"^typedef (\w+) (\w+)((?:\[\d+\])+);", header, re.M):
        ARRAY_TYPEDEFS[m.group(2)] = (m.group(1), m.group(3))
    names = set()
    header = transform_header(header, log, names)
    for name in sorted(os.listdir(src)):
        if not name.endswith(".c"):
            continue
        s = open(os.path.join(src, name)).read()
        open(os.path.join(out, name), "w").write(transform_unit(s, log, names))
    mark = '#include "pool.h"\n'
    fwd = "".join("struct %s;\n" % n for n in sorted(PA_TYPES))
    header = header.replace(mark, mark + "\n/* cmocify: pointer-to-array wrappers (defined at the end) */\n" + fwd, 1)
    end = header.rindex("#endif")
    header = header[:end] + "\n" + "\n".join(sorted(PA_TYPES.values())) + "\n" + header[end:]
    open(os.path.join(out, "game.h"), "w").write(header)
    print("cmocify:", {k: v for k, v in log.items() if v}, "wrappers:", len(PA_TYPES))


if __name__ == "__main__":
    main(*sys.argv[1:3])

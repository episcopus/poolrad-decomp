#!/usr/bin/env python3
"""riskscan.py: look for the kinds of defect the CoCo port has met, in all of the game, not only where a session goes (`make risk-scan`).

Every bug of steps 8.5 to 8.7 sat in code that only a recorded session reached, and each one is an instance of a class: a record copied
out of a byte buffer without turning its words round, a constant comparison CMOC folds as unsigned, a wider value stored through an untyped
`var` parameter, a literal handed to another bank, a frame that outgrows the stack, a routine the engine does not have yet. This
scans the translated game (build/gen/vm, build/game/src) for those classes, whether a session runs the code or not, and prints one section
per class with the sites. It makes no verdict by itself: a section that lists sites is a list to read (docs/RISKS.md has what was read).

  python3 tools/riskscan.py [--write]        --write puts the report in build/risk/report.md

Needs `make game` (the translation and the build) and, for the CMOC warnings, scripts/risk_cmoc.sh (docker)."""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COCO = os.path.abspath(os.path.join(HERE, ".."))
GEN = os.path.join(COCO, "build/gen/vm")
SRC = os.path.join(COCO, "build/game/src")
SIZES = {"u8": 1, "s8": 1, "u16": 2, "s16": 2, "u32": 4, "s32": 4, "farptr": 4, "char": 1}
OUT = []


def say(s=""):
    OUT.append(s)


def read(p):
    return open(p, errors="replace").read()


def game_h():
    return read(os.path.join(GEN, "game.h"))


def struct_table(h):
    """name -> (size, has_wide) of the flat typedef structs of game.h"""
    ptr = set(re.findall(r"typedef (?:farptr|PMenuLine|PItem|PCharacter|PCombatant) (\w+);", h)) | {"farptr", "PItem", "PCharacter", "PCombatant"}
    tab = {}
    for m in re.finditer(r"typedef struct (\w+) \{\n(.*?)\n\} \1;", h, re.S):
        size, wide = 0, False
        for ln in m.group(2).split("\n"):
            mm = re.match(r"\s*(\w+) (\w+)((?:\[\d+\])*);", ln)
            if not mm:
                continue
            t, _, dims = mm.groups()
            n = 1
            for d in re.findall(r"\[(\d+)\]", dims):
                n *= int(d)
            w = SIZES.get(t, 4 if t in ptr else tab.get(t, (1, False))[0])
            size += w * n
            wide |= (SIZES.get(t, 4 if t in ptr else 1) > 1) or (t in tab and tab[t][1])
        tab[m.group(1)] = (size, wide)
    return tab


def globals_table():
    g = {}
    for ln in open(os.path.join(GEN, "globals.txt")):
        f = ln.split()
        if len(f) >= 5:
            g[f[2]] = (int(f[0], 16), int(f[1]), f[4])
    return g


def routines():
    """name -> (unit, body text) of the translated routines"""
    r = {}
    for f in sorted(glob.glob(os.path.join(GEN, "*.c"))):
        u = os.path.basename(f)[:-2]
        t = read(f)
        for m in re.finditer(r"^(?:static )?[\w\s\*]+? \**(\w+)\(([^)]*)\)\n\{\n(.*?)^\}", t, re.S | re.M):
            r[m.group(1)] = (u, m.group(2), m.group(3))
    return r


def sec1_blockio(tab, glo):
    say("## 1. BlockRead and BlockWrite of a typed value without the words turned round")
    say("The translator turns a record's words round after a read and before a write (`rtl_swapdesc`). A call without it is fine when the buffer holds bytes only.")
    n = 0
    for f in sorted(glob.glob(os.path.join(GEN, "*.c"))):
        L = read(f).split("\n")
        for i, l in enumerate(L):
            if re.search(r"rtl_block(read|write)\(", l) and "rtl_swapdesc" not in " ".join(L[max(0, i - 1):i + 2]):
                ids = re.findall(r"\b[A-Za-z_]\w*\b", l.split(",", 2)[1] if "," in l else l)
                wide = [x for x in ids if x in glo and glo[x][2] != "-"]
                if wide:
                    say("- %s:%d  %s   (globals with words: %s)" % (os.path.basename(f), i + 1, l.strip()[:120], ", ".join(wide)))
                    n += 1
    say("sites: %d" % n)
    say()


def sec2_move(tab):
    say("## 2. Move between a byte view and a typed value with words in it")
    say("`Move(buffer^, record^, n)` copies the bytes of a file or DAX block as they are: the words of the record are then in the file's order.")
    n = 0
    for f in sorted(glob.glob(os.path.join(SRC, "*.c"))):
        if re.search(r"_\d+\.c$", f):
            continue
        for i, l in enumerate(read(f).split("\n")):
            m = re.search(r"rtl_Move\(\(void \*\)(.*?), \(void \*\)(.*?), ([^;]*)\);", l)
            if not m:
                continue
            a, b = m.group(1), m.group(2)
            byte = lambda e: ("FPD(u8 *" in e) or ("PA_u8_" in e) or ("(u8 *)" in e)
            # a whole local or global record is `&Name`; a field, element or dereference is not a whole typed value
            whole = lambda e: re.fullmatch(r"&\(?\*?[A-Za-z_]\w*\)?", e.strip()) is not None
            typed = lambda e: next((t for t in tab if tab[t][1] and re.search(r"\b%s\b" % t, e)), None) or ("PA_u16" in e or "PA_s16" in e) or whole(e) or None
            if "rtl_swapdesc" in "\n".join(read(f).split("\n")[i + 1:i + 3]):
                continue                                        # the words are turned round on the next line
            if (byte(a) and typed(b)) or (byte(b) and typed(a)):
                say("- %s:%d  %s" % (os.path.basename(f), i + 1, l.strip()[:150]))
                n += 1
    say("sites: %d" % n)
    say()


def sec3_untyped(tab, glo, rt):
    say("## 3. Untyped `var` parameters: a callee that stores a wider value than a caller's variable holds")
    say("A callee that casts its `void *` parameter to a type of N bytes writes N bytes; a caller that passes a variable of fewer bytes loses the neighbours (on the PC the")
    say("neighbour is whatever the compiler put there; on the CoCo the layout is another). Locals get padding in the translation; globals are checked here.")
    h = game_h()
    n = 0
    prot = {}
    for m in re.finditer(r"^[\w\s\*]+? \**(\w+)\(([^)]*void \*[^)]*)\);", h, re.M):
        prot[m.group(1)] = [p.strip() for p in m.group(2).split(",")]
    for name, params in sorted(prot.items()):
        if name not in rt:
            continue
        body = rt[name][2]
        for p in params:
            mm = re.match(r"void \*(\w+)$", p)
            if not mm:
                continue
            pn = mm.group(1)
            widths = set()
            for c in re.finditer(r"\(\*\((\w+)(?: \(\*\))?\)%s\)|\(\*\((\w+) \*\)%s\)|\((\w+) \*\)%s\b" % (pn, pn, pn), body):
                t = next(x for x in c.groups() if x)
                if t in SIZES:
                    widths.add(SIZES[t])
                elif t in ("PCharacter", "PItem", "PCombatant", "PAffect", "PMenuLine"):
                    widths.add(4)
                elif t in tab:
                    widths.add(tab[t][0])
            w = max(widths) if widths else 0
            if w <= 1:
                continue
            for u, (u2, sig, b2) in rt.items():
                for c in re.finditer(r"\b%s\([^;]*" % name, b2):
                    args = c.group(0)
                    for g in glo:
                        if re.search(r"\(void \*\)&%s\b" % g, args) and glo[g][1] < w and not re.search(r"\(void \*\)&%s\b\)?\.|\[" % g, args):
                            say("- %s(%s): writes %d bytes; %s in %s passes global %s of %d bytes" % (name, pn, w, u, u2, g, glo[g][1]))
                            n += 1
    say("sites: %d" % n)
    say()


def sec4_const():
    say("## 4. A comparison of two constants with a negative one (CMOC 0.1.100 folds it as unsigned)")
    h = game_h()
    enums = {m.group(1): int(m.group(2), 0) for m in re.finditer(r"enum \{ (\w+) = (-?\w+) \};", h)}
    n = 0
    num = r"\(?-?(?:0x[0-9A-Fa-f]+|\d+|[A-Za-z_]\w*)\)?"
    pat = re.compile(r"(?<![\w)\]])(%s) (<=|>=|<|>|==|!=) (%s)(?![\w(\[])" % (num, num))
    def val(x):
        x = x.strip("()")
        try:
            return int(x, 0)
        except ValueError:
            return enums.get(x)
    for f in sorted(glob.glob(os.path.join(GEN, "*.c")) + glob.glob(os.path.join(SRC, "*.c"))):
        if re.search(r"_\d+\.c$", f):
            continue
        for i, l in enumerate(read(f).split("\n")):
            if l.lstrip().startswith(("/*", "*")):
                continue
            for m in pat.finditer(re.sub(r'"(\\.|[^"\\])*"', '""', l)):
                a, b = val(m.group(1)), val(m.group(3))
                if a is not None and b is not None and (a < 0 or b < 0):
                    say("- %s:%d  %s" % (os.path.basename(f), i + 1, l.strip()[:130]))
                    n += 1
    say("sites: %d" % n)
    say()


def sec5_engine():
    say("## 5. Engine routines the game calls that are not written yet, and the symbols missing at link time")
    names = [l.split()[1] for l in open(os.path.join(COCO, "build/game/engine_names.txt")) if l.strip()]
    api = read(os.path.join(COCO, "src/engine/api.c"))
    have = set(re.findall(r"^\w[\w ]*\bapi_(\w+)\(", api, re.M))
    cut = [n for n in names if n not in have]
    rt = routines()
    for n in cut:
        callers = sorted({u + ":" + k for k, (u, _, b) in rt.items() if re.search(r"\b%s\(" % n, b)})
        say("- %s: %s" % (n, ("called by " + ", ".join(callers[:8])) if callers else "no caller in the game (PC pixel helper or unused)"))
    miss = os.path.join(COCO, "build/game/missing.txt")
    if os.path.exists(miss):
        syms = [l.split()[1] for l in open(miss) if l.strip()]
        say("missing at link time: " + ", ".join(syms))
        reals = sorted({u + ":" + k for k, (u, _, b) in rt.items() if re.search(r"\bReal\b|rtl_real|\bdouble\b", b + _)})
        say("routines that use a Real: " + (", ".join(reals) if reals else "none found by name"))
    say()


def sec6_unswapped(glo):
    say("## 6. Words the layout leaves in the PC's byte order (a byte view of the same bytes exists)")
    f = os.path.join(GEN, "unswapped.txt")
    if not os.path.exists(f):
        return
    byname = {}
    for ln in open(f):
        a, w = ln.split()
        a = int(a, 16)
        owner = next((n for n, (o, s, _) in glo.items() if o <= a < o + s and not re.match(r"(Raw|ds)[0-9A-Fa-f]{4}$", n)), None)
        byname.setdefault(owner or "(unnamed)", []).append((a, int(w)))
    for n, v in sorted(byname.items()):
        say("- %s: %d value(s) at %s" % (n, len(v), ", ".join("%04X/%d" % x for x in v[:6])))
    say()


def sec7_stack(rt):
    say("## 7. Static upper bound of the stack a call chain can need (frames only, no knowledge of which branch runs)")
    say("The CoCo stack is 5.5 KB ($1F7F down to $0A00). A bound above it is not a defect (the longest chain may never run); a chain close to it is where to look.")
    frame = {}
    calls = {}
    names = set(rt)
    for n, (u, sig, b) in rt.items():
        sz = 8
        for m in re.finditer(r"^\s+(u8|s8|u16|s16|u32|s32|farptr|[A-Z]\w+) (\w+)((?:\[\d+\])*)", b, re.M):
            t, _, dims = m.groups()
            k = 1
            for d in re.findall(r"\[(\d+)\]", dims):
                k *= int(d)
            sz += SIZES.get(t, 4) * k
        frame[n] = sz
        calls[n] = {c for c in re.findall(r"\b([A-Za-z_]\w*)\(", b) if c in names and c != n}
    memo, onstack, cyc = {}, set(), set()

    def depth(n):
        if n in memo:
            return memo[n]
        if n in onstack:
            cyc.add(n)
            return (0, None)
        onstack.add(n)
        best, via = 0, None
        for c in calls[n]:
            d, _ = depth(c)
            if d > best:
                best, via = d, c
        onstack.discard(n)
        memo[n] = (frame[n] + 6 + best, via)
        return memo[n]
    res = []
    for n in rt:
        d, _ = depth(n)
        res.append((d, n))
    res.sort(reverse=True)
    for d, n in res[:6]:
        chain, c = [n], n
        while memo[c][1] and len(chain) < 12:
            c = memo[c][1]
            chain.append(c)
        say("- %5d bytes: %s" % (d, " > ".join(chain)))
    say("routines on a cycle (recursion): " + (", ".join(sorted(cyc)) if cyc else "none"))
    say()


def sec8_warnings():
    say("## 8. CMOC warnings (scripts/risk_cmoc.sh) by kind")
    f = os.path.join(COCO, "build/risk/cmoc-warnings.txt")
    if not os.path.exists(f):
        say("(run scripts/risk_cmoc.sh first)")
        say()
        return
    kinds = {}
    for ln in open(f):
        k = re.sub(r"^[^:]+:\d+: warning: ", "", ln.strip())
        k = re.sub(r"`[^']*'", "X", k)
        k = re.sub(r"\([^)]*\)", "(..)", k)
        kinds[k] = kinds.get(k, 0) + 1
    for k, v in sorted(kinds.items(), key=lambda x: -x[1])[:8]:
        say("- %4d  %s" % (v, k))
    say("(`assigning to unsigned char from larger type` and `argument is too large` are the Pascal byte truncations the translation writes as plain assignments; the ones to read are")
    say("floating-point (section 5) and any `byte-sized arguments` / `different signs` that appear.)")
    say()


def main():
    h = game_h()
    tab = struct_table(h)
    glo = globals_table()
    rt = routines()
    say("# Risk scan of the CoCo build (generated by tools/riskscan.py)")
    say()
    sec1_blockio(tab, glo)
    sec2_move(tab)
    sec3_untyped(tab, glo, rt)
    sec4_const()
    sec5_engine()
    sec6_unswapped(glo)
    sec7_stack(rt)
    sec8_warnings()
    text = "\n".join(OUT)
    print(text)
    if "--write" in sys.argv:
        os.makedirs(os.path.join(COCO, "build/risk"), exist_ok=True)
        open(os.path.join(COCO, "build/risk/report.md"), "w").write(text + "\n")


if __name__ == "__main__":
    main()

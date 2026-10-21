#!/usr/bin/env python3
"""hoist.py: fewer calls of the banked heap's accessor (step 8.9c, idea 4). In the translated C of the CoCo build a field of a record of the banked class is
`(*FPB(T, p)).Field`, a call of vm_bp (about 35 bytes of code and 100 cycles). Statements that name the same record more than once call it more than once.
This pass finds runs of statements in which one pointer variable is used by FPB two or more times and turns them into one call:

    hp0 = FPB(T, p);              (placed before the first statement of the run)
    ... (*hp0).Field ... (*hp0).Other ...

The data windows (vm.asm): two windows, two of eight pages, a miss takes the one used less recently, and a pointer from vm_bp or vm_ptr is good until a call
that misses. So a hoisted pointer is safe for as long as nothing else can take a window: the run contains no function call (a callee may use any page), p is not
assigned inside it, and at most ONE other access of the data windows (VMV, FPD, FPB of another pointer) is made, because with two windows one other page can sit
in the window the pointer does not use, and a second would evict it. Accesses that do not take a window (PEEKP, VMN, FPM) are free.
A run is made of consecutive simple statements (one `;` line, no braces, no control keyword) in the translated text, which has one statement a line.

hoist(text) -> (text, stats). Usage as a tool: hoist.py FILE...   prints, per file, how many uses were turned into how many calls (the files are not changed)."""
import re
import sys

KEYWORDS = ("if", "else", "for", "while", "do", "switch", "case", "default", "goto", "static", "typedef", "struct", "enum", "extern", "union")
PURE = {"FPB", "FPD", "VMV", "VMN", "VMU", "FPM", "PEEKP", "S", "sizeof", "POOL_FARPTR", "POOL_LINEAR", "POOL_CAP", "POOL_VIDEO", "POOL_TRACE"}
FPB_ID = re.compile(r"FPB\(([^,()]+?), ([A-Za-z_]\w*)\)")
CALL = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
WINDOW = re.compile(r"\b(VMV|FPD|FPB)\(")


def simple(line):
    t = line.strip()
    if not t.endswith(";") or "{" in t or "}" in t or t.startswith("//") or t.startswith("/*"):
        return False
    first = re.match(r"[A-Za-z_]\w*", t)
    if first and first.group(0) in KEYWORDS:
        return False
    return True


def calls_in(line):
    out = []
    for m in CALL.finditer(line):
        n = m.group(1)
        if n in PURE or n in ("u8", "s8", "u16", "s16", "u32", "s32", "double", "int", "char", "void", "unsigned", "return"):
            continue
        out.append(n)
    return out


def assigns(line, p):
    return re.search(r"(?<![\w.>])%s\s*(=(?!=)|\+\+|--|[-+*/&|^]=|<<=|>>=)" % re.escape(p), line) is not None or re.search(r"(\+\+|--)\s*%s\b" % re.escape(p), line) is not None


def hoist_function(lines, stats):
    """lines: the lines of one function body (between the braces). -> new lines"""
    body = "\n".join(lines)
    n = len(lines)
    elig = [simple(l) and not calls_in(l) for l in lines]
    taken = {p for p in re.findall(r"&\s*([A-Za-z_]\w*)\b", body)}      # a variable whose address is taken may change behind our back
    decls, inserts, repl = [], {}, {}
    k = 0
    i = 0
    while i < n:
        if not elig[i]:
            i += 1
            continue
        j = i
        while j < n and elig[j]:
            j += 1
        # lines i..j-1 are a run of eligible statements
        uses = {}
        for r in range(i, j):
            for T, p in FPB_ID.findall(lines[r]):
                uses.setdefault((T.strip(), p), []).append(r)
        best = None
        for (T, p), rs in uses.items():
            if p in taken or len(rs) < 2:
                continue
            first = rs[0]
            last = first
            other = 0
            end = first
            for r in range(first, j):
                if r != first and assigns(lines[r], p):
                    break
                oth = sum(1 for m in WINDOW.finditer(lines[r])) - len([1 for T2, q in FPB_ID.findall(lines[r]) if q == p and T2.strip() == T])
                if other + oth > 1:
                    break
                other += oth
                end = r
                if assigns(lines[r], p):
                    break
            cnt = sum(len([1 for T2, q in FPB_ID.findall(lines[r]) if q == p and T2.strip() == T]) for r in range(first, end + 1))
            if cnt >= 2 and (best is None or cnt > best[0]):
                best = (cnt, T, p, first, end)
        if best is None:
            i = j
            continue
        cnt, T, p, first, end = best
        v = "hp%d" % k
        k += 1
        decls.append("  %s %s;" % (T, v))
        inserts[first] = "  %s = FPB(%s, %s);" % (v, T, p)
        pat = "FPB(%s, %s)" % (T, p)
        for r in range(first, end + 1):
            repl[r] = [(pat, v)] + repl.get(r, [])
        stats["uses"] += cnt
        stats["calls"] += 1
        i = first + 1 if end == first else end + 1
        # the run continues after the group; lines before `first` were not touched
    out = []
    for r, l in enumerate(lines):
        if r in inserts:
            out.append(inserts[r])
        for a, b in repl.get(r, []):
            l = l.replace(a, b)
        out.append(l)
    return decls, out


def hoist(text):
    stats = {"uses": 0, "calls": 0}
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        out.append(lines[i])
        if lines[i] == "{" and i > 0 and re.match(r"^[A-Za-z_].*\)\s*$", lines[i - 1]) and not lines[i - 1].startswith(("typedef", "struct", "enum")):
            j = i + 1
            while j < len(lines) and lines[j] != "}":
                j += 1
            body = lines[i + 1:j]
            # declarations come first in the generated bodies; the hoisted variables are declared after the last of them
            d = 0
            while d < len(body) and (re.match(r"^\s+(?:const )?[A-Za-z_][\w ]*[ *]\w+(\[[^\]]*\])*( = [^;]*)?;\s*$", body[d]) and not body[d].strip().startswith(("return", "POOL_TRACE"))):
                d += 1
            head, rest = body[:d], body[d:]
            decls, new = hoist_function(rest, stats)
            out.extend(head + decls + new)
            i = j
            continue
        i += 1
    return "\n".join(out), stats


if __name__ == "__main__":
    tot = {"uses": 0, "calls": 0}
    for f in sys.argv[1:]:
        t, s = hoist(open(f).read())
        tot["uses"] += s["uses"]
        tot["calls"] += s["calls"]
        if s["calls"]:
            print("%-40s %4d uses -> %4d calls" % (f, s["uses"], s["calls"]))
    print("total: %d uses of FPB become %d calls (%d fewer)" % (tot["uses"], tot["calls"], tot["uses"] - tot["calls"]))


DECL = re.compile(r"^\s+(?:const )?[A-Za-z_][\w ]*?[ *]\**(\w+)( = [^;]*)?;\s*$")


def byref(text):
    """FPB(T, p) with p a variable or parameter of the function becomes FPBV(T, p): vm_bpv(&p), which reads the four bytes of the farptr where they are
    instead of having the caller copy them onto the stack (push4ByteStruct: a call, a loop of four moves, and the cleanup) and returns the pointer the same way."""
    lines = text.split("\n")
    out = []
    n = {"calls": 0}
    i = 0
    while i < len(lines):
        out.append(lines[i])
        if lines[i] == "{" and i > 0 and re.match(r"^[A-Za-z_].*\)\s*$", lines[i - 1]) and not lines[i - 1].startswith(("typedef", "struct", "enum")):
            hdr = lines[i - 1]
            j = i + 1
            while j < len(lines) and lines[j] != "}":
                j += 1
            body = lines[i + 1:j]
            names = set()
            m = re.match(r"^[^(]*\((.*)\)\s*$", hdr)
            if m and m.group(1).strip() not in ("", "void"):
                for a in m.group(1).split(","):
                    t = re.findall(r"[A-Za-z_]\w*", a)
                    if t and "[" not in a:
                        names.add(t[-1])
            for l in body:
                d = DECL.match(l)
                if d and "[" not in l.split("=")[0] and "(" not in l.split("=")[0]:
                    names.add(d.group(1))
            def rep(mo):
                if mo.group(2) in names:
                    n["calls"] += 1
                    return "FPBV(%s, %s)" % (mo.group(1), mo.group(2))
                return mo.group(0)
            out.extend(FPB_ID.sub(rep, l) for l in body)
            i = j
            continue
        i += 1
    return "\n".join(out), n

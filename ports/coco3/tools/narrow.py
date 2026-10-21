#!/usr/bin/env python3
"""narrow.py: pointers of the banked heap as 16-bit values in the registers of the generated code (step 8.9c, idea 6).

A pointer to a block of the banked heap is a handle (rtl_heap.c): the high word of the farptr is 0 and the low word holds the page and the offset.
A variable that holds one therefore needs two bytes, not four, wherever it is only a local, a parameter or a result; the fields of records, the
globals and the arrays keep four bytes (the layout of the records is the original's, and the files hold them). The widening and the narrowing between
the two forms are C's own conversions of an unsigned 16-bit value to an unsigned 32-bit one and back, which keep the high word 0, so no expression of
the generated code changes. What changes is the code the compiler writes: a call of vm_bp pushes two bytes instead of four, a copy of a pointer is a
load and a store of one word, a comparison with nil tests one word.

What is narrowed (type `hptr`, a u16, in place of a typedef of farptr):
  * the locals, the by-value parameters and the result of a routine, when the type is a pointer type of the banked class: the type's blocks are
    dereferenced by FPB everywhere (the translator chose the macro by the pointee's class, placement.toml), and by no other macro; the game takes no
    other address of such a block (it has no POOL_FARPTR or farptr cast, and rtl_far is only given to the engine);
  * not a variable whose address is taken (`&name`: a var parameter, a callee that writes through it) or whose size is asked for;
  * not the signature of a routine that can be called through a procedure variable (the table of procedure ids): the cast the call is made through
    names the typedefs, which stay four bytes;
  * not the signature of a routine another part of the build defines or calls with its own prototype (the engine's and the core's routines).
The prototypes in game.h follow the definitions.

analyse(units, header, exclude) -> a Narrowing; Narrowing.unit(text) and Narrowing.header(text) rewrite the text of one unit and of game.h."""
import re
import sys

FUNC_HEAD = re.compile(r"^(?P<pre>(?:static |extern )?)(?P<ret>[A-Za-z_][\w ]*?[ *]+)(?P<name>[A-Za-z_]\w*)\((?P<params>.*)\)$")
PROTO = re.compile(r"^(?P<pre>(?:static |extern )?)(?P<ret>[A-Za-z_][\w ]*?[ *]+)(?P<name>[A-Za-z_]\w*)\((?P<params>.*)\);(?P<tail>.*)$")
TYPEDEF = re.compile(r"^typedef (farptr|\w+) (\w+);")
DEREF = re.compile(r"\b(FPB|FPM|FPD|PEEKP)\((?:[^,()]|\([^()]*\))+?, (\w+)[,)]")
LOCAL = re.compile(r"^(?P<ind>\s+)(?P<type>\w+)(?P<sp>\s+)(?P<name>\w+)(?P<init>\s*=[^;]*)?;(?P<tail>\s*)$")
KEYWORDS = {"return", "goto", "case", "else", "typedef", "static", "extern", "struct", "union", "enum", "const", "do", "if", "while", "for", "switch"}
NARROW = "hptr"


def split_params(s):
    s = s.strip()
    if s in ("", "void"):
        return []
    return [p.strip() for p in s.split(",")]


def param_type_name(p):
    """(type, name) of a by-value parameter `PCharacter Who`; None for anything else (var parameters `PCharacter *Who`, arrays, strings)"""
    m = re.match(r"^(\w+)\s+(\w+)$", p)
    return (m.group(1), m.group(2)) if m else None


def functions(text):
    """[(start line, end line, head match, lines of the body)] of the routine definitions of a unit: a header line, then `{`, then lines up to `}`"""
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        if lines[i] == "{" and i > 0:
            m = FUNC_HEAD.match(lines[i - 1])
            if m and not lines[i - 1].startswith(("typedef", "struct", "enum", "union")):
                j = i + 1
                while j < len(lines) and lines[j] != "}":
                    j += 1
                out.append((i - 1, j, m, lines[i + 1:j]))
                i = j
        i += 1
    return lines, out


def address_taken(body, name):
    return re.search(r"&\s*\(?\s*%s\b" % re.escape(name), body) is not None or re.search(r"\bsizeof\s*\(\s*%s\s*\)" % re.escape(name), body) is not None


class Narrowing:
    def __init__(self):
        self.banked = set()                 # typedef names of banked pointers
        self.sig = {}                       # routine -> (narrow the result, set of parameter indices)
        self.stats = {"params": 0, "locals": 0, "results": 0, "kept": 0}

    # -- the text of one unit
    def unit(self, text):
        lines, funcs = functions(text)
        for head_i, end_i, m, body in funcs:
            name = m.group("name")
            sig = self.sig.get(name)
            btext = "\n".join(body)
            params = split_params(m.group("params"))
            new_params = list(params)
            ret = m.group("ret")
            if sig is not None:
                for k in sig[1]:
                    tn = param_type_name(params[k])
                    if tn is None or tn[0] not in self.banked:
                        raise SystemExit("narrow: %s parameter %d is not a banked pointer any more (%s)" % (name, k, params[k]))
                    if address_taken(btext, tn[1]):
                        raise SystemExit("narrow: %s takes the address of its parameter %s" % (name, tn[1]))
                    new_params[k] = "%s %s" % (NARROW, tn[1])
                    self.stats["params"] += 1
                if sig[0]:
                    ret = ret.replace(ret.strip(), NARROW, 1) if ret.strip() in self.banked else ret
                    self.stats["results"] += 1
            if sig is not None:
                lines[head_i] = "%s%s%s(%s)" % (m.group("pre"), ret, name, ", ".join(new_params) if new_params else m.group("params"))
            # the locals: declarations at the head of the body (the generated bodies declare first)
            for k, ln in enumerate(body):
                lm = LOCAL.match(ln)
                if lm is None or ln.strip().startswith("POOL_TRACE"):
                    if ln.strip().startswith("POOL_TRACE"):
                        continue
                    if ln.strip() and not ln.strip().startswith(("//", "/*")):
                        # declarations are over at the first statement; arrays and the like do not match LOCAL and do not end the head
                        if not re.match(r"^\s+[A-Za-z_][\w ]*[ *]\**\w+(\[[^\]]*\])*( = [^;]*)?;\s*$", ln):
                            break
                    continue
                t = lm.group("type")
                if t in KEYWORDS or t not in self.banked:
                    continue
                if address_taken(btext, lm.group("name")):
                    self.stats["kept"] += 1
                    continue
                lines[head_i + 2 + k] = "%s%s%s%s%s;%s" % (lm.group("ind"), NARROW, lm.group("sp"), lm.group("name"), lm.group("init") or "", lm.group("tail"))
                self.stats["locals"] += 1
        return "\n".join(lines)

    # -- game.h: the typedef of hptr and the prototypes
    def header(self, text):
        out = []
        for ln in text.split("\n"):
            m = PROTO.match(ln)
            if m and m.group("name") in self.sig and not ln.startswith(("typedef", "struct")):
                name = m.group("name")
                sig = self.sig[name]
                params = split_params(m.group("params"))
                for k in sig[1]:
                    tn = param_type_name(params[k])
                    params[k] = "%s %s" % (NARROW, tn[1]) if tn else params[k]
                ret = m.group("ret")
                if sig[0] and ret.strip() in self.banked:
                    ret = ret.replace(ret.strip(), NARROW, 1)
                ln = "%s%s%s(%s);%s" % (m.group("pre"), ret, name, ", ".join(params) if params else m.group("params"), m.group("tail"))
            out.append(ln)
        return "\n".join(out)


def match_paren(t, i):
    """index of the parenthesis closing the one at t[i]"""
    d = 0
    for k in range(i, len(t)):
        if t[k] == "(":
            d += 1
        elif t[k] == ")":
            d -= 1
            if d == 0:
                return k
    return -1


CHAIN = re.compile(r"^(?:\.\w+|->\w+|\[[^\[\]]*\])*$")


def is_lvalue(a):
    """the text of an expression that is a variable, a field or an element, not a computed value (so that its address can be taken)"""
    a = a.strip()
    m = re.match(r"^\w+", a)
    if m:
        return CHAIN.match(a[m.end():]) is not None and not a[0].isdigit()
    if a.startswith("(*"):
        e = match_paren(a, 0)
        return e > 0 and CHAIN.match(a[e + 1:]) is not None
    return False


def _conv(t, hp, cnt):
    """t with every FPB(T, x) rewritten, innermost first"""
    out, i = [], 0
    while True:
        j = t.find("FPB(", i)
        while j > 0 and (t[j - 1].isalnum() or t[j - 1] == "_"):
            j = t.find("FPB(", j + 1)
        if j < 0:
            out.append(t[i:])
            return "".join(out)
        e = match_paren(t, j + 3)
        inner = t[j + 4:e]
        d, c = 0, -1
        for q, ch in enumerate(inner):
            if ch == "(":
                d += 1
            elif ch == ")":
                d -= 1
            elif ch == "," and d == 0:
                c = q
                break
        out.append(t[i:j])
        if c < 0:
            out.append(t[j:e + 1])
        else:
            typ, arg = inner[:c], _conv(inner[c + 1:].strip(), hp, cnt)
            if arg not in hp and is_lvalue(arg):
                out.append("FPBL(%s, %s)" % (typ, arg))
                cnt[0] += 1
            else:
                out.append("FPB(%s, %s)" % (typ, arg))
        i = e + 1


def lowword(text):
    """FPB(T, x) where x is a 32 bit variable, field or element becomes FPBL(T, x): vm_bp of the low word read where it is. A cast `(u16)x` of a
    32 bit value makes CMOC call initWordFromDWord; the macro takes the address and reads the second word. A narrowed variable (hptr) needs no cast."""
    lines, funcs = functions(text)
    cnt = [0]
    for head_i, end_i, m, body in funcs:
        hp = set(re.findall(r"\bhptr (\w+)", m.group("params")))
        hp |= {lm.group("name") for lm in (LOCAL.match(l) for l in body) if lm and lm.group("type") == NARROW}
        for k, ln in enumerate(body):
            if "FPB(" in ln:
                body[k] = _conv(ln, hp, cnt)
        lines[head_i + 2:head_i + 2 + len(body)] = body
    return "\n".join(lines), cnt[0]


ACC16 = r"FPBL?\(struct PA_(?P<et>u16|u8)_\d+ \*, \w+\)->a\[[^\]]*\]"
CONST = r"(?P<k>-?(?:0x[0-9A-Fa-f]+|\d+))"
CMP = re.compile(r"\(s32\)(?P<x>%s|(?P<id>[A-Za-z_]\w*)) (?P<op>==|!=|>=|<=|>|<) %s(?=\s*(?:\)|&&|\|\||;|\?))" % (ACC16, CONST))
SMALL = {"u8": (0, 255, True), "u16": (0, 65535, True), "s8": (-128, 127, False), "s16": (-32768, 32767, False)}


def cmp16(text):
    """(s32)x OP constant, where x is a byte or a word (a local, a parameter or an element of a u8/u16 array) and the constant lies in x's type: the
    comparison needs no 32 bit helper (cmpDWordSignedInt is 150 cycles, a word compare 15). The translation widens a Word compared with an Integer constant
    above 32767 and every compare of the game variables; the result is the same. Returns (text, count)."""
    lines, funcs = functions(text)
    cnt = [0]
    for head_i, end_i, m, body in funcs:
        types = {}
        for prm in split_params(m.group("params")):
            tn = re.match(r"^(u8|u16|s8|s16)\s+(\w+)$", prm)
            if tn:
                types[tn.group(2)] = tn.group(1)
        clash = set()
        for ln in body:
            lm = LOCAL.match(ln)
            if lm and lm.group("type") in SMALL:
                nm = lm.group("name")
                if types.get(nm, lm.group("type")) != lm.group("type"):
                    clash.add(nm)                   # the same name with two types in nested blocks: left alone
                types[nm] = lm.group("type")
            elif lm and lm.group("name") in types:
                clash.add(lm.group("name"))
        for nm in clash:
            del types[nm]
        def rep(mo):
            x, op, k = mo.group("x"), mo.group("op"), int(mo.group("k"), 0)
            if mo.group("id"):
                t = types.get(x)
                if t is None:
                    return mo.group(0)
            else:
                t = mo.group("et")
            lo, hi, uns = SMALL[t]
            if not (lo <= k <= hi) and not (t in ("u8", "u16") and 0 <= k <= 65535):
                return mo.group(0)
            kk = mo.group("k") + ("u" if t in ("u8", "u16") and k > 32767 else "")      # (a constant above 32767 is unsigned)
            cnt[0] += 1
            return "%s %s %s" % (x, op, kk)
        for k, ln in enumerate(body):
            if "(s32)" in ln:
                body[k] = CMP.sub(rep, ln)
        lines[head_i + 2:head_i + 2 + len(body)] = body
    return "\n".join(lines), cnt[0]


def analyse(units, header, exclude=()):
    """units: {name: text} of the generated units that are compiled for the game; header: game.h; exclude: routines whose signature stays as it is"""
    n = Narrowing()
    # the typedef groups: `typedef farptr PMenuLine;` and `typedef PMenuLine PItem;` are one type
    parent = {}
    for ln in header.split("\n"):
        m = TYPEDEF.match(ln)
        if m:
            parent[m.group(2)] = m.group(2) if m.group(1) == "farptr" else m.group(1)

    def root(t):
        seen = 0
        while parent.get(t, t) != t and seen < 20:
            t = parent[t]
            seen += 1
        return t
    uses = {}                               # root typedef -> macros that dereference variables of it
    funcs = {}
    for u, text in units.items():
        lines, fl = functions(text)
        for head_i, end_i, m, body in fl:
            decl = {}
            for p in split_params(m.group("params")):
                tn = param_type_name(p)
                if tn and tn[0] in parent:
                    decl[tn[1]] = root(tn[0])
            for ln in body:
                lm = LOCAL.match(ln)
                if lm and lm.group("type") in parent and lm.group("type") not in KEYWORDS:
                    decl[lm.group("name")] = root(lm.group("type"))
            for dm in DEREF.finditer("\n".join(body)):
                v = dm.group(2)
                if v in decl:
                    uses.setdefault(decl[v], set()).add("FPB" if dm.group(1) in ("FPB", "PEEKP") else dm.group(1))
            funcs[m.group("name")] = (m, u)
    banked_roots = {t for t, mac in uses.items() if mac == {"FPB"}}
    n.banked = {t for t in parent if root(t) in banked_roots}
    for name, (m, u) in funcs.items():
        if name in exclude or name.startswith("init_"):
            continue
        params = split_params(m.group("params"))
        idx = set()
        for k, p in enumerate(params):
            tn = param_type_name(p)
            if tn and tn[0] in n.banked:
                idx.add(k)
        res = m.group("ret").strip() in n.banked
        if idx or res:
            n.sig[name] = (res, idx)
    # a parameter whose address is taken in the body stays four bytes: decided here so that the prototype agrees
    for u, text in units.items():
        lines, fl = functions(text)
        for head_i, end_i, m, body in fl:
            sig = n.sig.get(m.group("name"))
            if sig is None:
                continue
            btext = "\n".join(body)
            params = split_params(m.group("params"))
            keep = {k for k in sig[1] if address_taken(btext, param_type_name(params[k])[1])}
            if keep:
                n.sig[m.group("name")] = (sig[0], sig[1] - keep)
    return n


if __name__ == "__main__":
    import argparse
    import pathlib
    ap = argparse.ArgumentParser()
    ap.add_argument("gen")
    ap.add_argument("--exclude", default="")
    a = ap.parse_args()
    gen = pathlib.Path(a.gen)
    units = {p.stem: p.read_text() for p in sorted(gen.glob("*.c")) if p.stem.startswith(("ovl", "res")) and p.stem not in ("res07", "res08")}
    n = analyse(units, (gen / "game.h").read_text(), set(a.exclude.split(",")))
    print("banked pointer types:", " ".join(sorted(n.banked)))
    print("routines with a narrowed signature: %d" % len(n.sig))
    for u, t in units.items():
        n.unit(t)
    print(n.stats)

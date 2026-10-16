"""pasparse.py: a parser for the Turbo Pascal 6.0 dialect the project's matched sources use (SPEC 7.4).

It reads `src/*.PAS` (units and the main program) into a small syntax tree. Names are case
insensitive in Pascal; every identifier keeps its spelling and `Ident.key` is the lower case form.
Comments are kept: each token carries the comments before it (`lead`) and the ones on the same
line after it (`trail`), so the translator can put the original's remarks into the C source.

Nothing here knows what a name means; `pas2c.py` resolves names and types.
"""
from __future__ import annotations

import re


class ParseError(Exception):
    pass


class N:
    """A syntax tree node: kind `k` and named fields."""

    def __init__(self, k, **kw):
        self.k = k
        self.line = kw.pop("line", 0)
        self.lead = kw.pop("lead", ())
        self.trail = kw.pop("trail", ())
        self.__dict__.update(kw)

    def __repr__(self):
        d = {k: v for k, v in self.__dict__.items() if k not in ("k", "line", "lead", "trail")}
        return "%s(%s)" % (self.k, ", ".join("%s=%r" % kv for kv in d.items()))


KEYWORDS = set("""and array begin case const div do downto else end file for function goto if in label mod
nil not of or packed procedure program record repeat set shl shr then to type until var while with xor
unit interface implementation uses string inline asm object constructor destructor""".split())

TOKEN_RE = re.compile(r"""
  (?P<ws>[ \t\r\n]+)
 |(?P<cmt1>\{[^}]*\})
 |(?P<cmt2>\(\*.*?\*\))
 |(?P<cmt3>//[^\n]*)
 |(?P<str>(?:'(?:[^']|'')*'|\#\d+|\#\$[0-9A-Fa-f]+)+)
 |(?P<real>\d+\.\d+(?:[eE][+-]?\d+)?|\d+[eE][+-]?\d+)
 |(?P<hex>\$[0-9A-Fa-f]+)
 |(?P<int>\d+)
 |(?P<id>[A-Za-z_][A-Za-z_0-9]*)
 |(?P<sym>:=|\.\.|<>|<=|>=|\(\.|\.\)|[-+*/=<>()\[\]\.,;:\^@])
""", re.X | re.S)


class Tok:
    __slots__ = ("t", "v", "line", "lead", "trail", "text")

    def __init__(self, t, v, line, text):
        self.t, self.v, self.line, self.text = t, v, line, text
        self.lead = []
        self.trail = []

    def __repr__(self):
        return "%s:%r@%d" % (self.t, self.v, self.line)


def string_value(text: str) -> str:
    out = []
    i = 0
    while i < len(text):
        c = text[i]
        if c == "'":
            j = i + 1
            buf = []
            while True:
                if text[j] == "'":
                    if j + 1 < len(text) and text[j + 1] == "'":
                        buf.append("'")
                        j += 2
                        continue
                    break
                buf.append(text[j])
                j += 1
            out.append("".join(buf))
            i = j + 1
        elif c == "#":
            j = i + 1
            if text[j] == "$":
                j += 1
                k = j
                while k < len(text) and text[k] in "0123456789abcdefABCDEF":
                    k += 1
                out.append(chr(int(text[j:k], 16)))
            else:
                k = j
                while k < len(text) and text[k].isdigit():
                    k += 1
                out.append(chr(int(text[j:k])))
            i = k
        elif c == "^":
            out.append(chr(ord(text[i + 1].upper()) ^ 64))
            i += 2
        else:
            raise ParseError("bad string literal " + text)
    return "".join(out)


def lex(src: str, fname: str = "?") -> tuple[list[Tok], list[tuple[int, str]]]:
    toks: list[Tok] = []
    directives: list[tuple[int, str]] = []
    pos, line = 0, 1
    pending: list[str] = []
    last: Tok | None = None
    last_line = 0
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise ParseError("%s:%d: cannot scan %r" % (fname, line, src[pos:pos + 20]))
        kind = m.lastgroup
        text = m.group()
        pos = m.end()
        if kind == "ws":
            line += text.count("\n")
            continue
        if kind in ("cmt1", "cmt2", "cmt3"):
            body = text[1:-1] if kind == "cmt1" else (text[2:-2] if kind == "cmt2" else text[2:])
            if body.startswith("$"):
                directives.append((line, body))
            else:
                body = body.strip("\n")
                if last is not None and last_line == line and "\n" not in text:
                    last.trail.append(body)
                else:
                    pending.append(body)
            line += text.count("\n")
            continue
        if kind == "id":
            low = text.lower()
            t = Tok("kw" if low in KEYWORDS else "id", low if low in KEYWORDS else text, line, text)
        elif kind == "int":
            t = Tok("int", int(text), line, text)
        elif kind == "hex":
            t = Tok("int", int(text[1:], 16), line, text)
        elif kind == "real":
            t = Tok("real", float(text), line, text)
        elif kind == "str":
            t = Tok("str", string_value(text), line, text)
        else:
            t = Tok("sym", text, line, text)
        t.lead = pending
        pending = []
        toks.append(t)
        last, last_line = t, line
        line += text.count("\n")
    eof = Tok("eof", None, line, "")
    eof.lead = pending
    toks.append(eof)
    return toks, directives


class Parser:
    def __init__(self, src: str, fname: str):
        self.fname = fname
        self.toks, self.directives = lex(src, fname)
        self.i = 0

    # ---- token helpers ----------------------------------------------------------------------------
    @property
    def tok(self) -> Tok:
        return self.toks[self.i]

    def peek(self, n=1) -> Tok:
        return self.toks[min(self.i + n, len(self.toks) - 1)]

    def err(self, msg):
        raise ParseError("%s:%d: %s (at %r)" % (self.fname, self.tok.line, msg, self.tok.text))

    def next(self) -> Tok:
        t = self.toks[self.i]
        self.i += 1
        return t

    def is_kw(self, *ks) -> bool:
        return self.tok.t == "kw" and self.tok.v in ks

    def is_sym(self, *ss) -> bool:
        return self.tok.t == "sym" and self.tok.v in ss

    def accept_kw(self, k) -> bool:
        if self.is_kw(k):
            self.i += 1
            return True
        return False

    def accept_sym(self, s) -> bool:
        if self.is_sym(s):
            self.i += 1
            return True
        return False

    def kw(self, k):
        if not self.is_kw(k):
            self.err("expected %s" % k)
        return self.next()

    def sym(self, s):
        if not self.is_sym(s):
            self.err("expected %r" % s)
        return self.next()

    def ident(self) -> Tok:
        if self.tok.t != "id":
            self.err("expected identifier")
        return self.next()

    def is_id(self, name: str) -> bool:
        return self.tok.t == "id" and self.tok.v.lower() == name

    # ---- compilation units ------------------------------------------------------------------------
    def parse(self) -> N:
        lead = self.tok.lead
        if self.accept_kw("unit"):
            name = self.ident()
            self.sym(";")
            self.kw("interface")
            uses = self.uses()
            idecls = self.declarations(interface=True)
            self.kw("implementation")
            iuses = self.uses()
            decls = self.declarations(interface=False)
            init = None
            if self.is_kw("begin"):
                init = self.compound()
            else:
                self.kw("end")
            self.sym(".")
            return N("unit", name=name.v, lead=lead, uses=uses, idecls=idecls, iuses=iuses, decls=decls,
                     init=init)
        if self.accept_kw("program"):
            name = self.ident()
            self.sym(";")
            uses = self.uses()
            decls = self.declarations(interface=False)
            body = self.compound()
            self.sym(".")
            return N("program", name=name.v, lead=lead, uses=uses, decls=decls, body=body)
        self.err("expected unit or program")

    def uses(self) -> list[str]:
        out = []
        if self.accept_kw("uses"):
            out.append(self.ident().v)
            while self.accept_sym(","):
                out.append(self.ident().v)
            self.sym(";")
        return out

    # ---- declarations -----------------------------------------------------------------------------
    def declarations(self, interface: bool) -> list[N]:
        out: list[N] = []
        while True:
            t = self.tok
            if self.is_kw("const"):
                self.next()
                while self.tok.t == "id" and not self.is_reserved_section():
                    out.append(self.const_decl())
            elif self.is_kw("type"):
                self.next()
                while self.tok.t == "id":
                    out.append(self.type_decl())
            elif self.is_kw("var"):
                self.next()
                while self.tok.t == "id":
                    out.append(self.var_decl())
            elif self.is_kw("label"):
                self.next()
                labels = [self.label_name()]
                while self.accept_sym(","):
                    labels.append(self.label_name())
                self.sym(";")
                out.append(N("labels", names=labels, line=t.line, lead=t.lead))
            elif self.is_kw("procedure", "function"):
                out.append(self.routine(interface))
            else:
                return out

    def is_reserved_section(self) -> bool:
        return False

    def label_name(self) -> str:
        t = self.next()
        if t.t not in ("id", "int"):
            self.err("label")
        return str(t.v)

    def const_decl(self) -> N:
        name = self.ident()
        typ = None
        if self.accept_sym(":"):
            typ = self.type_()
            self.sym("=")
            val = self.typed_const_value()
            self.sym(";")
            return N("typedconst", name=name.v, type=typ, value=val, line=name.line, lead=name.lead,
                     trail=self.toks[self.i - 1].trail)
        self.sym("=")
        e = self.expr()
        self.sym(";")
        return N("const", name=name.v, value=e, line=name.line, lead=name.lead, trail=self.toks[self.i - 1].trail)

    def typed_const_value(self):
        """expr | ( v, v, ... ) | ( field: v; field: v )"""
        if self.is_sym("("):
            # either an aggregate or a parenthesised expression; an aggregate starts with `(` and has a
            # top-level comma, or `ident :` for a record, or nested aggregates.
            save = self.i
            self.next()
            if self.tok.t == "id" and self.peek().t == "sym" and self.peek().v == ":":
                items = []
                while not self.is_sym(")"):
                    f = self.ident()
                    self.sym(":")
                    items.append((f.v, self.typed_const_value()))
                    if not self.accept_sym(";"):
                        break
                self.sym(")")
                return N("recordval", items=items)
            first = self.typed_const_value()
            if self.is_sym(","):
                items = [first]
                while self.accept_sym(","):
                    items.append(self.typed_const_value())
                self.sym(")")
                return N("arrayval", items=items)
            if self.is_sym(")") and isinstance(first, N) and first.k in ("arrayval", "recordval"):
                self.next()
                return N("arrayval", items=[first])
            self.i = save
        return self.expr()

    def type_decl(self) -> N:
        name = self.ident()
        self.sym("=")
        t = self.type_()
        self.sym(";")
        return N("typedecl", name=name.v, type=t, line=name.line, lead=name.lead, trail=self.toks[self.i - 1].trail)

    def var_decl(self) -> N:
        first = self.ident()
        names = [first.v]
        while self.accept_sym(","):
            names.append(self.ident().v)
        self.sym(":")
        t = self.type_()
        absolute = None
        if self.is_id("absolute"):
            self.next()
            a = self.expr()
            if self.accept_sym(":"):
                b = self.expr()
                absolute = N("abs", seg=a, off=b)
            else:
                absolute = N("abs", seg=None, off=a)
        self.sym(";")
        return N("var", names=names, type=t, absolute=absolute, line=first.line, lead=first.lead,
                 trail=self.toks[self.i - 1].trail)

    # ---- types ------------------------------------------------------------------------------------
    def type_(self) -> N:
        t = self.tok
        if self.accept_sym("^"):
            return N("ptr", target=self.ident().v, line=t.line)
        if self.accept_kw("packed"):
            return self.type_()
        if self.is_kw("array"):
            self.next()
            self.sym("[")
            idx = [self.type_()]
            while self.accept_sym(","):
                idx.append(self.type_())
            self.sym("]")
            self.kw("of")
            return N("array", index=idx, elem=self.type_(), line=t.line)
        if self.is_kw("record"):
            self.next()
            fields, variant = self.field_list()
            self.kw("end")
            return N("record", fields=fields, variant=variant, line=t.line)
        if self.is_kw("set"):
            self.next()
            self.kw("of")
            return N("set", base=self.type_(), line=t.line)
        if self.is_kw("file"):
            self.next()
            if self.accept_kw("of"):
                return N("file", elem=self.type_(), line=t.line)
            return N("file", elem=None, line=t.line)
        if self.is_kw("string"):
            self.next()
            if self.accept_sym("["):
                e = self.expr()
                self.sym("]")
                return N("string", length=e, line=t.line)
            return N("string", length=None, line=t.line)
        if self.is_kw("procedure", "function"):
            fn = self.next().v == "function"
            params = self.param_list() if self.is_sym("(") else []
            ret = None
            if fn:
                self.sym(":")
                ret = self.type_()
            return N("proctype", params=params, ret=ret, line=t.line)
        if self.is_sym("("):
            self.next()
            names = [self.ident().v]
            while self.accept_sym(","):
                names.append(self.ident().v)
            self.sym(")")
            return N("enum", names=names, line=t.line)
        # a named type or a subrange (constant expressions)
        if self.tok.t == "id" and not (self.peek().t == "sym" and self.peek().v == ".."):
            # could still be `Ident + 1 .. x`; handle by scanning for `..` at depth 0 before ; = ] ,
            if not self.range_ahead():
                return N("named", name=self.ident().v, line=t.line)
        lo = self.expr()
        self.sym("..")
        hi = self.expr()
        return N("range", lo=lo, hi=hi, line=t.line)

    def range_ahead(self) -> bool:
        depth = 0
        j = self.i
        while True:
            t = self.toks[j]
            if t.t == "sym":
                if t.v in "([":
                    depth += 1
                elif t.v in ")]":
                    if depth == 0:
                        return False
                    depth -= 1
                elif t.v == ".." and depth == 0:
                    return True
                elif t.v in (";", "=", ",", ":") and depth == 0:
                    return False
            elif t.t == "kw" and t.v in ("of", "end", "case"):
                return False
            elif t.t == "eof":
                return False
            j += 1

    def field_list(self):
        fields = []
        variant = None
        while not self.is_kw("end") and not self.is_sym(")"):
            if self.is_kw("case"):
                variant = self.variant_part()
                break
            first = self.ident()
            names = [first.v]
            while self.accept_sym(","):
                names.append(self.ident().v)
            self.sym(":")
            t = self.type_()
            fields.append(N("field", names=names, type=t, line=first.line, lead=first.lead,
                            trail=self.toks[self.i - 1].trail))
            if not self.accept_sym(";"):
                break
        return fields, variant

    def variant_part(self):
        self.kw("case")
        tag = None
        if self.tok.t == "id" and self.peek().t == "sym" and self.peek().v == ":":
            tag = self.ident().v
            self.sym(":")
        tagtype = self.type_()
        self.kw("of")
        arms = []
        while not self.is_kw("end") and not self.is_sym(")"):
            labels = [self.expr()]
            while self.accept_sym(","):
                labels.append(self.expr())
            self.sym(":")
            self.sym("(")
            fields, sub = self.field_list()
            self.sym(")")
            arms.append(N("arm", labels=labels, fields=fields, variant=sub))
            if not self.accept_sym(";"):
                break
        return N("variant", tag=tag, tagtype=tagtype, arms=arms)

    def param_list(self) -> list[N]:
        self.sym("(")
        params = []
        while True:
            byref = self.accept_kw("var")
            first = self.ident()
            names = [first.v]
            while self.accept_sym(","):
                names.append(self.ident().v)
            typ = None
            if self.accept_sym(":"):
                typ = self.type_()
            params.append(N("param", names=names, type=typ, byref=byref, line=first.line))
            if not self.accept_sym(";"):
                break
        self.sym(")")
        return params

    def routine(self, interface: bool) -> N:
        t = self.next()
        is_fn = t.v == "function"
        name = self.ident()
        params = self.param_list() if self.is_sym("(") else []
        ret = None
        if is_fn:
            if self.accept_sym(":"):
                ret = self.type_()
        self.sym(";")
        mods = []
        while self.tok.t == "id" and self.tok.v.lower() in ("far", "near", "forward", "external", "interrupt"):
            mods.append(self.next().v.lower())
            self.sym(";")
        while self.is_kw("inline"):
            self.err("inline routines are not supported")
        head_trail = self.toks[self.i - 1].trail
        node = N("routine", name=name.v, fn=is_fn, params=params, ret=ret, mods=mods, decls=[], body=None,
                 line=t.line, lead=t.lead, trail=head_trail)
        if "forward" in mods or "external" in mods or interface:
            return node
        node.decls = self.declarations(interface=False)
        node.body = self.compound()
        self.sym(";")
        return node

    # ---- statements -------------------------------------------------------------------------------
    def compound(self) -> N:
        t = self.kw("begin")
        stmts = self.stmt_list("end")
        e = self.kw("end")
        return N("block", stmts=stmts, line=t.line, lead=t.lead, trail=t.trail, endlead=e.lead)

    def stmt_list(self, *enders) -> list[N]:
        out = []
        while True:
            while self.accept_sym(";"):
                pass
            if self.tok.t == "kw" and self.tok.v in enders:
                return out
            out.append(self.stmt())
            if not self.accept_sym(";"):
                if self.tok.t == "kw" and self.tok.v in enders:
                    return out
                self.err("expected ; or end of block")

    def stmt(self) -> N:
        t = self.tok
        lead = t.lead
        label = None
        if (t.t in ("id", "int")) and self.peek().t == "sym" and self.peek().v == ":" and not (
                self.peek(2).t == "sym" and self.peek(2).v == "="):
            self.next()
            self.next()
            label = str(t.v)
            t = self.tok
            node = self.stmt()
            return N("labeled", label=label, stmt=node, line=t.line, lead=lead)
        s = self._stmt()
        if not s.lead:
            s.lead = lead
        return s

    def _stmt(self) -> N:
        t = self.tok
        if self.is_kw("begin"):
            return self.compound()
        if self.accept_kw("if"):
            c = self.expr()
            self.kw("then")
            a = self.stmt() if not self.is_kw("else") else N("empty")
            b = None
            if self.accept_kw("else"):
                b = self.stmt() if not self.is_sym(";") else N("empty")
            return N("if", cond=c, then=a, els=b, line=t.line, lead=t.lead)
        if self.accept_kw("while"):
            c = self.expr()
            self.kw("do")
            return N("while", cond=c, body=self.stmt(), line=t.line, lead=t.lead)
        if self.accept_kw("repeat"):
            body = self.stmt_list("until")
            self.kw("until")
            return N("repeat", body=body, cond=self.expr(), line=t.line, lead=t.lead)
        if self.accept_kw("for"):
            var = self.ident()
            self.sym(":=")
            a = self.expr()
            down = False
            if self.accept_kw("downto"):
                down = True
            else:
                self.kw("to")
            b = self.expr()
            self.kw("do")
            return N("for", var=var.v, start=a, stop=b, down=down, body=self.stmt(), line=t.line, lead=t.lead)
        if self.accept_kw("case"):
            sel = self.expr()
            self.kw("of")
            arms = []
            els = None
            while not self.is_kw("end"):
                if self.accept_kw("else"):
                    els = self.stmt_list("end")
                    break
                labels = [self.case_label()]
                while self.accept_sym(","):
                    labels.append(self.case_label())
                self.sym(":")
                arms.append(N("arm", labels=labels, stmt=self.stmt()))
                if not self.accept_sym(";"):
                    break
            self.kw("end")
            return N("case", sel=sel, arms=arms, els=els, line=t.line, lead=t.lead)
        if self.accept_kw("with"):
            recs = [self.expr()]
            while self.accept_sym(","):
                recs.append(self.expr())
            self.kw("do")
            return N("with", recs=recs, body=self.stmt(), line=t.line, lead=t.lead)
        if self.accept_kw("goto"):
            lab = self.next()
            return N("goto", label=str(lab.v), line=t.line, lead=t.lead)
        if self.is_sym(";") or self.is_kw("end", "until", "else"):
            return N("empty", line=t.line)
        # assignment or call
        e = self.expr()
        if self.accept_sym(":="):
            rhs = self.expr()
            return N("assign", lhs=e, rhs=rhs, line=t.line, lead=t.lead)
        return N("callstmt", call=e, line=t.line, lead=t.lead)

    def case_label(self) -> N:
        a = self.expr()
        if self.accept_sym(".."):
            return N("range", lo=a, hi=self.expr())
        return a

    # ---- expressions ------------------------------------------------------------------------------
    REL = {"=": "=", "<>": "<>", "<": "<", ">": ">", "<=": "<=", ">=": ">="}

    def expr(self) -> N:
        a = self.simple()
        t = self.tok
        if t.t == "sym" and t.v in self.REL:
            self.next()
            return N("bin", op=t.v, a=a, b=self.simple(), line=t.line)
        if t.t == "kw" and t.v == "in":
            self.next()
            return N("bin", op="in", a=a, b=self.simple(), line=t.line)
        return a

    def simple(self) -> N:
        t = self.tok
        if t.t == "sym" and t.v in "+-":
            self.next()
            a = self.term()
            if t.v == "-":
                a = N("un", op="-", a=a, line=t.line)
        else:
            a = self.term()
        while True:
            t = self.tok
            if (t.t == "sym" and t.v in "+-") or (t.t == "kw" and t.v in ("or", "xor")):
                self.next()
                a = N("bin", op=t.v, a=a, b=self.term(), line=t.line)
            else:
                return a

    def term(self) -> N:
        a = self.factor()
        while True:
            t = self.tok
            if (t.t == "sym" and t.v in ("*", "/")) or (t.t == "kw" and t.v in ("div", "mod", "and", "shl", "shr")):
                self.next()
                a = N("bin", op=t.v, a=a, b=self.factor(), line=t.line)
            else:
                return a

    def factor(self) -> N:
        t = self.tok
        if t.t == "int":
            self.next()
            return self.selectors(N("int", value=t.v, text=t.text, line=t.line))
        if t.t == "real":
            self.next()
            return N("real", value=t.v, line=t.line)
        if t.t == "str":
            self.next()
            return N("str", value=t.v, line=t.line)
        if t.t == "kw":
            if t.v == "nil":
                self.next()
                return N("nil", line=t.line)
            if t.v == "not":
                self.next()
                return N("un", op="not", a=self.factor(), line=t.line)
            if t.v == "string":
                # string(x) never used as a cast here
                self.err("string in expression")
        if t.t == "sym":
            if t.v == "(":
                self.next()
                e = self.expr()
                self.sym(")")
                return self.selectors(N("paren", a=e, line=t.line))
            if t.v == "@":
                self.next()
                return N("addr", a=self.factor(), line=t.line)
            if t.v == "[":
                self.next()
                items = []
                while not self.is_sym("]"):
                    a = self.expr()
                    if self.accept_sym(".."):
                        a = N("range", lo=a, hi=self.expr())
                    items.append(a)
                    if not self.accept_sym(","):
                        break
                self.sym("]")
                return N("setlit", items=items, line=t.line)
            if t.v == "-":
                self.next()
                return N("un", op="-", a=self.factor(), line=t.line)
            if t.v == "+":
                self.next()
                return self.factor()
        if t.t == "id":
            self.next()
            return self.selectors(N("name", name=t.v, line=t.line))
        self.err("expected an expression")

    def selectors(self, e: N) -> N:
        while True:
            t = self.tok
            if t.t != "sym":
                return e
            if t.v == "[":
                self.next()
                idx = [self.expr()]
                if self.accept_sym(":"):
                    idx = [N("segoff", seg=idx[0], off=self.expr())]
                while self.accept_sym(","):
                    idx.append(self.expr())
                self.sym("]")
                e = N("index", a=e, idx=idx, line=t.line)
            elif t.v == ".":
                if self.peek().t != "id":
                    return e
                self.next()
                e = N("field", a=e, name=self.ident().v, line=t.line)
            elif t.v == "^":
                self.next()
                e = N("deref", a=e, line=t.line)
            elif t.v == "(" and e.k in ("name", "field", "paren", "index", "deref"):
                self.next()
                args = []
                while not self.is_sym(")"):
                    a = self.expr()
                    if self.accept_sym(":"):               # Str(x:width) / Write(x:w:d)
                        w = self.expr()
                        d = self.expr() if self.accept_sym(":") else None
                        a = N("fmt", a=a, width=w, dec=d)
                    args.append(a)
                    if not self.accept_sym(","):
                        break
                self.sym(")")
                e = N("call", fn=e, args=args, line=t.line)
            else:
                return e


def parse_file(path) -> N:
    from pathlib import Path
    p = Path(path)
    return Parser(p.read_text(encoding="latin-1"), p.name).parse()


if __name__ == "__main__":
    import sys
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    bad = 0
    for f in sorted((root / "src").glob("*.PAS")):
        try:
            parse_file(f)
        except ParseError as e:
            print(e)
            bad += 1
    print("parse errors:", bad)

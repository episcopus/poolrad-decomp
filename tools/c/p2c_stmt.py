"""p2c_stmt.py: statements and routines for the Pascal to C translator."""
from __future__ import annotations

import ptypes as P
from p2c_base import Scope, Sym, c_char, cstr_literal, ctype, decl, ptr_ctype
from p2c_decl import E, TransError
from pasparse import N
from ptypes import Ty


def cmt(lines) -> str:
    text = "\n".join(l for l in lines if l is not None)
    text = text.replace("*/", "* /").replace("/*", "/ *")
    return text


class Ctx:
    """The state of the routine being translated."""

    def __init__(self, name, parent=None):
        self.name = name
        self.parent = parent
        self.scope = Scope(None, name)
        self.withs = []
        self.temps = []
        self.ntemp = 0
        self.has_frame = False
        self.level = 0 if parent is None else parent.level + 1
        self.fn = None            # function result type
        self.result = None
        self.nwith = 0
        self.labels = {}
        self.arena = False
        self.is_main = False

    def exit_stmt(self):
        if self.arena:
            return "goto L_exit"
        if self.fn is not None:
            return "return %s" % self.result_ref()
        return "return"

    def result_ref(self):
        return "fr.Result" if self.has_frame else "Result"


class StmtMixin:
    def emit(self, text, ind=None):
        self.out.append("%s%s" % ("  " * (self.ind if ind is None else ind), text))

    def comment_lines(self, lead, ind=None):
        for c in lead or ():
            body = cmt([c])
            if "\n" in body:
                self.emit("/* %s" % body.split("\n")[0].strip(), ind)
                for l in body.split("\n")[1:-1]:
                    self.emit("   %s" % l.strip(), ind)
                self.emit("   %s */" % body.split("\n")[-1].strip(), ind)
            else:
                self.emit("/* %s */" % body.strip(), ind)

    def trailing(self, trail):
        if not trail:
            return ""
        return "  /* %s */" % cmt([" ".join(t.strip() for t in trail)]).replace("\n", " ")

    # ---- statements ---------------------------------------------------------------------------------
    def stmts(self, lst):
        for s in lst:
            self.stmt(s)

    def stmt(self, n: N):
        k = n.k
        if k == "empty":
            return
        self.comment_lines(n.lead)
        getattr(self, "st_" + k)(n)

    def body_of(self, n: N):
        """Emit a statement as the body of a control construct (inside braces already opened)."""
        self.ind += 1
        if n.k == "block":
            self.comment_lines(n.lead)
            self.stmts(n.stmts)
        else:
            self.stmt(n)
        self.ind -= 1

    def st_block(self, n):
        self.emit("{")
        self.ind += 1
        self.stmts(n.stmts)
        self.ind -= 1
        self.emit("}")

    def cond(self, n: N) -> str:
        e = self.ex(n)
        c = e.code
        if c.startswith("(") and c.endswith(")") and self.balanced(c[1:-1]):
            c = c[1:-1]
        return c

    @staticmethod
    def balanced(s):
        d = 0
        for ch in s:
            if ch == "(":
                d += 1
            elif ch == ")":
                d -= 1
                if d < 0:
                    return False
        return d == 0

    def st_if(self, n):
        self.emit("if (%s) {" % self.cond(n.cond))
        self.body_of(n.then)
        e = n.els
        while e is not None and e.k == "if":
            self.comment_lines(e.lead)
            self.emit("} else if (%s) {" % self.cond(e.cond))
            self.body_of(e.then)
            e = e.els
        if e is not None and e.k != "empty":
            self.emit("} else {")
            self.body_of(e)
        self.emit("}")

    def st_while(self, n):
        self.emit("while (%s) {" % self.cond(n.cond))
        self.body_of(n.body)
        self.emit("}")

    def st_repeat(self, n):
        self.emit("do {")
        self.ind += 1
        self.stmts(n.body)
        self.ind -= 1
        c = self.ex(n.cond)
        code = c.code
        if code.startswith("!") and (code[1:].isidentifier()):
            self.emit("} while (%s);" % code[1:])
        else:
            self.emit("} while (!%s);" % (code if (code.startswith("(") and self.balanced(code[1:-1])) else "(%s)" % code))

    def st_for(self, n):
        v = self.ex(N("name", name=n.var, line=n.line))
        a = self.ex(n.start)
        b = self.ex(n.stop)
        op = ">=" if n.down else "<="
        step = "--" if n.down else "++"
        limit = b.code
        if b.val is None:
            t = self.temp(decl(v.ty, "@") if v.ty.kind != "char" else "u8 @")
            self.emit("%s = %s;" % (t, b.code))
            limit = t
        self.emit("%s = %s;" % (v.code, a.code))
        self.emit("if (%s %s %s) for (;;) {" % (v.code, op, limit))
        self.body_of(n.body)
        self.emit("  if (%s == %s) break;" % (v.code, limit))
        self.emit("  %s%s;" % (v.code, step))
        self.emit("}")

    def st_case(self, n):
        sel = self.ex(n.sel)
        # expand labels
        total = 0
        for arm in n.arms:
            for lab in arm.labels:
                if lab.k == "range":
                    total += self.const_int(lab.hi, self.ce_scope()) - self.const_int(lab.lo, self.ce_scope()) + 1
                else:
                    total += 1
        wide = total > 400 or any(
            lab.k == "range" and self.const_int(lab.hi, self.ce_scope()) - self.const_int(lab.lo, self.ce_scope()) > 64
            for arm in n.arms for lab in arm.labels)
        if wide:
            return self.case_chain(n, sel)
        self.emit("switch (%s) {" % (sel.code if sel.ty.kind != "char" else "(u8)%s" % sel.code))
        seen = set()
        for arm in n.arms:
            nlab = 0
            for lab in arm.labels:
                if lab.k == "range":
                    lo = self.const_int(lab.lo, self.ce_scope())
                    hi = self.const_int(lab.hi, self.ce_scope())
                    for v in range(lo, hi + 1):
                        if v in seen:
                            continue
                        seen.add(v)
                        nlab += 1
                        self.emit("case %s:" % self.case_val(v, sel.ty), self.ind)
                else:
                    r = self.ce(lab, self.ce_scope())
                    if r is None:
                        raise TransError("case label is not constant (line %d)" % n.line)
                    v = r[0]
                    iv = ord(v) if isinstance(v, str) else v
                    if iv in seen:
                        continue
                    seen.add(iv)
                    nlab += 1
                    code = self.ex(lab).code if not isinstance(v, str) else c_char(ord(v))
                    self.emit("case %s:" % code, self.ind)
            if nlab == 0:
                continue
            self.emit("{")
            self.body_of(arm.stmt)
            self.emit("  break;")
            self.emit("}")
        if n.els is not None:
            self.emit("default:", self.ind)
            self.emit("{")
            self.ind += 1
            self.stmts(n.els)
            self.ind -= 1
            self.emit("}")
        self.emit("}")

    def case_chain(self, n, sel):
        """A case statement with wide ranges: an if chain over a copy of the selector."""
        t = self.temp("s32 @")
        self.emit("%s = %s;" % (t, sel.code if sel.ty.kind != "char" else "(u8)%s" % sel.code))
        first = True
        for arm in n.arms:
            conds = []
            for lab in arm.labels:
                if lab.k == "range":
                    lo = self.const_int(lab.lo, self.ce_scope())
                    hi = self.const_int(lab.hi, self.ce_scope())
                    conds.append("(%s >= %d && %s <= %d)" % (t, lo, t, hi))
                else:
                    r = self.ce(lab, self.ce_scope())
                    v = ord(r[0]) if isinstance(r[0], str) else r[0]
                    conds.append("%s == %d" % (t, v))
            self.emit("%sif (%s) {" % ("" if first else "} else ", " || ".join(conds)))
            first = False
            self.body_of(arm.stmt)
        if n.els is not None:
            self.emit("} else {")
            self.ind += 1
            self.stmts(n.els)
            self.ind -= 1
        if not first:
            self.emit("}")

    def case_val(self, v, t):
        if t.kind == "char":
            return c_char(v)
        return str(v)

    def ce_scope(self):
        """A scope object for constant evaluation inside the current routine."""
        return self.cur.scope if self.cur is not None and self.cur.scope is not None and self.cur_scope_chain() else self.unit_scope

    def cur_scope_chain(self):
        return True

    def st_with(self, n):
        self.emit("{")
        self.ind += 1
        added = 0
        for r in n.recs:
            e = self.ex(r)
            if e.ty.kind != "record":
                raise TransError("with over a non-record (line %d)" % n.line)
            self.cur.nwith += 1
            nm = "w%d" % self.cur.nwith
            self.emit("%s *%s = &%s;" % (self.record_ctype(e.ty), nm, self.paren(e)))
            self.cur.withs.append((e.ty, nm + "->"))
            added += 1
        self.body_of(n.body)
        for _ in range(added):
            self.cur.withs.pop()
        self.ind -= 1
        self.emit("}")

    def record_ctype(self, t: Ty) -> str:
        return ctype(t)

    def st_goto(self, n):
        self.emit("goto L_%s;" % n.label)

    def st_labeled(self, n):
        self.emit("L_%s:" % n.label, max(self.ind - 1, 0))
        self.emit(";")
        self.stmt(n.stmt)

    def st_callstmt(self, n):
        c = n.call
        if c.k == "name":
            e = self.ex_call(N("call", fn=c, args=[], line=c.line))
        elif c.k == "call":
            e = self.ex_call(c)
        else:
            e = self.ex(c)
        self.emit("%s;" % e.code)

    def st_assign(self, n):
        lhs, rhs = n.lhs, n.rhs
        # assignment to the function name: the result variable
        if lhs.k == "name" and self.cur.fn is not None and lhs.name.lower() == self.cur.name.lower() \
                and self.cur.scope.find_local(lhs.name) is None:
            tgt = E(self.cur.result_ref(), self.cur.fn, lv=True)
        else:
            tgt = self.ex(lhs)
        self.mutate(tgt)
        t = tgt.ty
        if t.kind == "proc":
            pv = self.proc_value(rhs)
            if pv is not None:
                self.emit("%s = %s;" % (tgt.code, pv.code))
                return
        wrap = t.kind in ("int", "bool", "char", "enum") and t.size() <= 2
        r = self.ex(rhs, wrap=wrap)
        self.emit(self.assign_code(tgt, r, n) + ";")

    def assign_code(self, tgt: E, r: E, n) -> str:
        t = tgt.ty
        if getattr(tgt, "memref", None):
            seg, off = tgt.memref
            fn = "rtl_poke16" if tgt.ty.size() == 2 else "rtl_poke8"
            return "%s(%s, %s, %s)" % (fn, seg, off, r.code)
        if getattr(tgt, "portref", None):
            return "%s(%s, %s)" % ("rtl_outpw" if tgt.ty.size() == 2 else "rtl_outp", tgt.portref, r.code)
        k = t.kind
        if k == "string":
            if r.ty.kind == "char" and r.strlit is None:
                tmp = self.str_temp()
                return "rtl_str_assign(%s, %d, rtl_str_char(%s, %s))" % (tgt.code, t.maxlen, tmp, r.code)
            return "rtl_str_assign(%s, %d, %s)" % (tgt.code, t.maxlen, self.to_pstr(r))
        if k in ("array", "set"):
            return "memcpy(%s, %s, %d)" % (tgt.code, r.code if r.ty.kind in ("array", "set") else "&" + r.code, t.size())
        if k == "record":
            return "%s = %s" % (tgt.code, r.code)
        if k == "real":
            return "%s = %s" % (tgt.code, self.real(r))
        if k in ("ptr", "proc"):
            return "%s = %s" % (tgt.code, r.code)
        if k == "file":
            raise TransError("file assignment")
        # ordinal
        return "%s = %s" % (tgt.code, r.code)

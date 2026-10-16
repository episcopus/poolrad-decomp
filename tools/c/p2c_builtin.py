"""p2c_builtin.py: the Turbo Pascal built-in procedures and functions."""
from __future__ import annotations

import ptypes as P
from p2c_base import Sym, c_char, cstr_literal, ctype, decl, ptr_ctype
from p2c_decl import DS_SEG, E, TransError
from p2c_expr import CLS_TYPE, int_class
from pasparse import N
from ptypes import Ty

BUILTINS = set("""length copy pos concat chr ord succ pred odd abs sqr hi lo swap sizeof high low trunc round ptr
paramstr eof eoln filepos filesize inc dec exit halt str val delete insert getmem freemem new dispose assign
reset rewrite append close seek erase truncate blockread blockwrite write writeln read readln lowercase
fillchar move flush seekeof""".split())


class BuiltinMixin:
    def builtin(self, name: str, n: N, as_expr=True):
        args = n.args if n.k == "call" else []
        f = getattr(self, "bi_" + name, None)
        if f is None:
            return None
        return f(args, n)

    def arg_e(self, args, i, **kw):
        return self.ex(args[i], **kw)

    # ---- strings ------------------------------------------------------------------------------------
    def bi_length(self, a, n):
        e = self.ex(a[0])
        if e.ty.kind == "char":
            return E("1", P.BYTE, val=1)
        if e.strlit is not None:
            return E(str(len(e.strlit)), P.BYTE, val=len(e.strlit))
        return E("%s[0]" % e.code, P.BYTE)

    def bi_copy(self, a, n):
        s, i, c = self.ex(a[0]), self.ex(a[1]), self.ex(a[2])
        t = self.str_temp()
        return E("rtl_str_copy(%s, %s, %s, %s)" % (t, self.to_pstr(s), i.code, c.code), Ty("string", maxlen=255))

    def bi_pos(self, a, n):
        sub, s = self.ex(a[0]), self.ex(a[1])
        return E("rtl_str_pos(%s, %s)" % (self.to_pstr(sub), self.to_pstr(s)), P.BYTE)

    def bi_concat(self, a, n):
        return self.concat([self.ex(x) for x in a])

    def bi_upcase(self, a, n):
        e = self.ex(a[0])
        return E("rtl_upcase(%s)" % e.code, P.CHAR)

    def bi_lowercase(self, a, n):
        e = self.ex(a[0])
        return E("rtl_lowercase(%s)" % e.code, P.CHAR)

    def bi_delete(self, a, n):
        s, i, c = self.ex(a[0]), self.ex(a[1]), self.ex(a[2])
        self.mutate(s)
        return E("rtl_str_delete(%s, %s, %s)" % (s.code, i.code, c.code), P.VOID)

    def bi_insert(self, a, n):
        src, s, i = self.ex(a[0]), self.ex(a[1]), self.ex(a[2])
        self.mutate(s)
        return E("rtl_str_insert(%s, %s, %d, %s)" % (self.to_pstr(src), s.code, s.ty.maxlen, i.code), P.VOID)

    def bi_str(self, a, n):
        v = a[0]
        width = "0"
        dec = None
        if v.k == "fmt":
            width = self.ex(v.width).code
            dec = self.ex(v.dec).code if v.dec is not None else None
            v = v.a
        e = self.ex(v)
        s = self.ex(a[1])
        self.mutate(s)
        if e.ty.kind == "real":
            return E("rtl_str_real(%s, %d, %s, %s, %s)" % (s.code, s.ty.maxlen, e.code, width, dec if dec else "-1"), P.VOID)
        return E("rtl_str_int(%s, %d, %s, %s)" % (s.code, s.ty.maxlen, e.code, width), P.VOID)

    def bi_val(self, a, n):
        s, v, c = self.ex(a[0]), self.ex(a[1]), self.ex(a[2])
        sz = v.ty.size() if v.ty.kind != "real" else 0
        signed = 1 if (v.ty.kind == "int" and v.ty.lo < 0) else 0
        return E("rtl_str_val(%s, &%s, %d, %d, &%s)" % (self.to_pstr(s), self.paren(v), sz, signed, self.paren(c)), P.VOID)

    # ---- ordinal functions ---------------------------------------------------------------------------
    def bi_chr(self, a, n):
        e = self.ex(a[0])
        if e.val is not None and not isinstance(e.val, str):
            return self.const_E(chr(e.val & 255), P.CHAR, c_char(e.val & 255))
        return E("(u8)%s" % self.paren(e), P.CHAR)

    def bi_ord(self, a, n):
        e = self.ex(a[0])
        if e.val is not None:
            v = ord(e.val) if isinstance(e.val, str) else int(e.val)
            return E(str(v), P.INTEGER if v < 32768 else P.LONGINT, val=v)
        if e.ty.kind in ("int",) and e.ty.size() == 4:
            return E(e.code, P.LONGINT)
        return E(e.code, e.ty if e.ty.kind == "int" else P.INTEGER) if e.ty.kind != "int" else E(e.code, e.ty)

    def bi_succ(self, a, n):
        e = self.ex(a[0])
        t = e.ty
        if e.val is not None and not isinstance(e.val, str):
            return E(str(e.val + 1), t, val=e.val + 1)
        return E("(%s)(%s + 1)" % (ctype(t), self.paren(e)), t)

    def bi_pred(self, a, n):
        e = self.ex(a[0])
        t = e.ty
        if e.val is not None and not isinstance(e.val, str):
            return E(str(e.val - 1), t, val=e.val - 1)
        return E("(%s)(%s - 1)" % (ctype(t), self.paren(e)), t)

    def bi_odd(self, a, n):
        e = self.ex(a[0])
        return E("(%s & 1)" % self.paren(e), P.BOOLEAN)

    def bi_abs(self, a, n):
        e = self.ex(a[0])
        if e.ty.kind == "real":
            return E("rtl_fabs(%s)" % e.code, P.REAL)
        cls = int_class(e.ty)
        return E("rtl_abs(%s)" % e.code, CLS_TYPE[cls] if cls != "b" else P.INTEGER)

    def bi_sqr(self, a, n):
        e = self.ex(a[0], wrap=True)
        if e.ty.kind == "real":
            return E("(%s * %s)" % (e.code, e.code), P.REAL, prec=0)
        return self.arith("*", e, e, False)

    def bi_hi(self, a, n):
        e = self.ex(a[0])
        return E("((u16)%s >> 8)" % self.paren(e), P.BYTE)

    def bi_lo(self, a, n):
        e = self.ex(a[0])
        return E("(u8)%s" % self.paren(e), P.BYTE)

    def bi_swap(self, a, n):
        e = self.ex(a[0])
        return E("rtl_swap(%s)" % e.code, e.ty if e.ty.kind == "int" else P.WORD)

    def bi_sizeof(self, a, n):
        arg = a[0]
        t = None
        if arg.k == "name":
            r = self.lookup(arg.name)
            if r and r[0] == "sym" and r[1].kind == "type":
                t = r[1].type
        if t is None:
            t = self.ex(arg).ty
        return E(str(t.size()), P.WORD, val=t.size())

    def bi_high(self, a, n):
        t = self.type_of_arg(a[0])
        if t.kind == "array":
            return E(str(t.hi), P.INTEGER, val=t.hi)
        if t.kind == "string":
            return E(str(t.maxlen), P.BYTE, val=t.maxlen)
        return E(str(t.hi), t, val=t.hi)

    def bi_low(self, a, n):
        t = self.type_of_arg(a[0])
        lo = t.lo
        return E(str(lo), P.INTEGER, val=lo)

    def type_of_arg(self, arg):
        if arg.k == "name":
            r = self.lookup(arg.name)
            if r and r[0] == "sym" and r[1].kind == "type":
                return r[1].type
        return self.ex(arg).ty

    def bi_trunc(self, a, n):
        e = self.ex(a[0])
        return E("rtl_trunc(%s)" % self.real(e), P.LONGINT)

    def bi_round(self, a, n):
        e = self.ex(a[0])
        return E("rtl_round(%s)" % self.real(e), P.LONGINT)

    def bi_ptr(self, a, n):
        s, o = self.ex(a[0]), self.ex(a[1])
        return E("POOL_FARPTR(%s, %s)" % (s.code, o.code), P.POINTER)

    def bi_paramstr(self, a, n):
        e = self.ex(a[0])
        t = self.str_temp()
        return E("rtl_paramstr(%s, %s)" % (t, e.code), Ty("string", maxlen=255))

    # ---- statements-as-calls --------------------------------------------------------------------------
    def bi_inc(self, a, n):
        return self.incdec(a, "+")

    def bi_dec(self, a, n):
        return self.incdec(a, "-")

    def incdec(self, a, op):
        x = self.ex(a[0])
        step = self.ex(a[1]).code if len(a) > 1 else "1"
        if getattr(x, "memref", None):
            seg, off = x.memref
            return E("rtl_poke8(%s, %s, rtl_peek8(%s, %s) %s %s)" % (seg, off, seg, off, op, step), P.VOID)
        t = x.ty
        if t.kind == "ptr":
            raise TransError("Inc of a pointer")
        if step == "1":
            return E("%s%s%s" % (x.code, op, op), P.VOID)
        return E("%s %s= %s" % (x.code, op, step), P.VOID)

    def bi_exit(self, a, n):
        return E(self.cur.exit_stmt(), P.VOID)

    def bi_halt(self, a, n):
        return E("rtl_Halt(%s)" % (self.ex(a[0]).code if a else "0"), P.VOID)

    def bi_getmem(self, a, n):
        p, sz = self.ex(a[0]), self.ex(a[1])
        return E("%s = rtl_getmem(%s)" % (p.code, sz.code), P.VOID)

    def bi_freemem(self, a, n):
        p, sz = self.ex(a[0]), self.ex(a[1])
        return E("rtl_freemem(%s, %s)" % (p.code, sz.code), P.VOID)

    def ptr_target(self, t: Ty) -> Ty:
        if t.elem is None and getattr(t, "target_name", None):
            s = t.target_scope.find(t.target_name)
            if s is not None and s.kind == "type":
                t.elem = s.type
        if t.elem is None:
            raise TransError("pointer without a target")
        return t.elem

    def bi_new(self, a, n):
        p = self.ex(a[0])
        sz = self.ptr_target(p.ty).size()
        return E("%s = rtl_getmem(%d)" % (p.code, sz), P.VOID)

    def bi_dispose(self, a, n):
        p = self.ex(a[0])
        sz = self.ptr_target(p.ty).size()
        return E("rtl_freemem(%s, %d)" % (p.code, sz), P.VOID)

    # ---- files ---------------------------------------------------------------------------------------------
    def file_arg(self, node):
        e = self.ex(node)
        if e.ty.kind != "file":
            raise TransError("not a file (line %d)" % node.line)
        return e

    def bi_assign(self, a, n):
        f = self.file_arg(a[0])
        s = self.ex(a[1])
        return E("rtl_assign(&%s, %s)" % (self.paren(f), self.to_pstr(s)), P.VOID)

    def recsize(self, f: E, a, idx):
        if len(a) > idx:
            return self.ex(a[idx]).code
        if getattr(f.ty, "text", False):
            return "1"
        if f.ty.elem is not None:
            return str(f.ty.elem.size())
        return "128"

    def bi_reset(self, a, n):
        f = self.file_arg(a[0])
        fn = "rtl_reset_text" if getattr(f.ty, "text", False) else "rtl_reset"
        if fn == "rtl_reset_text":
            return E("%s(&%s)" % (fn, self.paren(f)), P.VOID)
        return E("rtl_reset(&%s, %s)" % (self.paren(f), self.recsize(f, a, 1)), P.VOID)

    def bi_rewrite(self, a, n):
        f = self.file_arg(a[0])
        if getattr(f.ty, "text", False):
            return E("rtl_rewrite_text(&%s)" % self.paren(f), P.VOID)
        return E("rtl_rewrite(&%s, %s)" % (self.paren(f), self.recsize(f, a, 1)), P.VOID)

    def bi_append(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_append_text(&%s)" % self.paren(f), P.VOID)

    def bi_close(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_close(&%s)" % self.paren(f), P.VOID)

    def bi_erase(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_erase(&%s)" % self.paren(f), P.VOID)

    def bi_seek(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_seek(&%s, %s)" % (self.paren(f), self.ex(a[1]).code), P.VOID)

    def bi_truncate(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_truncate(&%s)" % self.paren(f), P.VOID)

    def bi_flush(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_flush(&%s)" % self.paren(f), P.VOID)

    def bi_eof(self, a, n):
        f = self.file_arg(a[0]) if a else None
        return E("rtl_eof(&%s)" % self.paren(f) if f else "rtl_eof(&Input)", P.BOOLEAN)

    def bi_eoln(self, a, n):
        f = self.file_arg(a[0]) if a else None
        return E("rtl_eoln(&%s)" % self.paren(f) if f else "rtl_eoln(&Input)", P.BOOLEAN)

    def bi_filepos(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_filepos(&%s)" % self.paren(f), P.LONGINT)

    def bi_filesize(self, a, n):
        f = self.file_arg(a[0])
        return E("rtl_filesize(&%s)" % self.paren(f), P.LONGINT)

    def bi_blockread(self, a, n):
        return self.block_io("rtl_blockread", a)

    def bi_blockwrite(self, a, n):
        return self.block_io("rtl_blockwrite", a)

    def block_io(self, fn, a):
        f = self.file_arg(a[0])
        buf = self.ex(a[1])
        if getattr(buf, "memref", None):
            bp = "rtl_mem_ptr(%s, %s)" % buf.memref
        else:
            bp = "(void *)&%s" % self.paren(buf)
        cnt = self.ex(a[2]).code
        res = "&%s" % self.paren(self.ex(a[3])) if len(a) > 3 else "NULL"
        return E("%s(&%s, %s, %s, %s)" % (fn, self.paren(f), bp, cnt, res), P.VOID)

    # ---- text i/o -------------------------------------------------------------------------------------------
    def text_target(self, a):
        """(file expression text, remaining args): the first argument is a text file when it is one."""
        if a:
            if a[0].k in ("name", "field", "index", "deref"):
                try:
                    e = self.ex(a[0])
                except TransError:
                    e = None
                if e is not None and e.ty.kind == "file":
                    return "&%s" % self.paren(e), a[1:], e
        return None, a, None

    def bi_write(self, a, n, ln=False):
        f, rest, fe = self.text_target(a)
        out = []
        if fe is not None and not getattr(fe.ty, "text", False):
            # a typed file: Write(f, record)
            for r in rest:
                e = self.ex(r)
                out.append("rtl_file_write(%s, (void *)&%s)" % (f, self.paren(e)))
            return E(", ".join(out), P.VOID)
        f = f or "&Output"
        for r in rest:
            width = "0"
            dec = None
            node = r
            if r.k == "fmt":
                width = self.ex(r.width).code
                dec = self.ex(r.dec).code if r.dec is not None else None
                node = r.a
            e = self.ex(node)
            if e.ty.kind in ("string",) or (e.ty.kind == "char" and e.strlit is not None and len(e.strlit) != 1):
                out.append("rtl_write_str(%s, %s, %s)" % (f, self.to_pstr(e), width))
            elif e.ty.kind == "char":
                out.append("rtl_write_char(%s, %s, %s)" % (f, e.code, width))
            elif e.ty.kind == "real":
                out.append("rtl_write_real(%s, %s, %s, %s)" % (f, e.code, width, dec or "-1"))
            elif e.ty.kind == "bool":
                out.append("rtl_write_bool(%s, %s, %s)" % (f, e.code, width))
            else:
                out.append("rtl_write_int(%s, %s, %s)" % (f, e.code, width))
        if ln:
            out.append("rtl_write_ln(%s)" % f)
        if not out:
            out.append("(void)0")
        return E(", ".join(out), P.VOID)

    def bi_writeln(self, a, n):
        return self.bi_write(a, n, ln=True)

    def bi_read(self, a, n, ln=False):
        f, rest, fe = self.text_target(a)
        out = []
        if fe is not None and not getattr(fe.ty, "text", False):
            for r in rest:
                e = self.ex(r)
                out.append("rtl_file_read(%s, (void *)&%s)" % (f, self.paren(e)))
            return E(", ".join(out), P.VOID)
        f = f or "&Input"
        for r in rest:
            e = self.ex(r)
            if e.ty.kind == "string":
                out.append("rtl_read_str(%s, %s, %d)" % (f, e.code, e.ty.maxlen))
            elif e.ty.kind == "char":
                out.append("rtl_read_char(%s, &%s)" % (f, self.paren(e)))
            elif e.ty.kind == "real":
                out.append("rtl_read_real(%s, &%s)" % (f, self.paren(e)))
            else:
                out.append("rtl_read_int(%s, &%s, %d, %d)" % (f, self.paren(e), e.ty.size(), 1 if e.ty.lo < 0 else 0))
        if ln:
            out.append("rtl_read_ln(%s)" % f)
        if not out:
            out.append("(void)0")
        return E(", ".join(out), P.VOID)

    def bi_readln(self, a, n):
        return self.bi_read(a, n, ln=True)

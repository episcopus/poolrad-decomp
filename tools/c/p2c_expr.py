"""p2c_expr.py: expressions, calls and the built-in procedures of the Pascal to C translator."""
from __future__ import annotations

import re

import ptypes as P
from p2c_base import Sym, c_char, cstr_literal, ctype, decl, ptr_ctype
from p2c_decl import DS_SEG, E, TransError
from pasparse import N
from ptypes import Ty

CMP = {"=": "==", "<>": "!=", "<": "<", ">": ">", "<=": "<=", ">=": ">="}


def int_class(t: Ty) -> str:
    """b byte-like, i integer, w word, l longint (Turbo Pascal's arithmetic classes)."""
    if t.kind in ("bool", "char", "enum"):
        return "b"
    if t.kind != "int":
        return "l"
    if t.lo >= 0 and t.hi <= 255:
        return "b"
    if t.lo >= -32768 and t.hi <= 32767:
        return "i"
    if t.lo >= 0 and t.hi <= 65535:
        return "w"
    return "l"


CLS_TYPE = {"b": P.INTEGER, "i": P.INTEGER, "w": P.WORD, "l": P.LONGINT}
CLS_CAST = {"i": "(s16)", "w": "(u16)", "l": "(s32)"}


def combine(ca: str, cb: str) -> str:
    if "l" in (ca, cb):
        return "l"
    if ca in "bi" and cb in "bi":
        return "i"
    return "w" if ("w" in (ca, cb) and "i" not in (ca, cb)) else "l"


def with_const(cls: str, c: int) -> str:
    """Class of `var-of-class op constant`."""
    if cls == "l":
        return "l"
    if c < 0:
        if cls in "bi":
            return "i" if c >= -32768 else "l"
        return "l"
    if cls == "b":
        return "i" if c <= 32767 else ("w" if c <= 65535 else "l")
    if cls == "i":
        return "i" if c <= 32767 else "l"
    return "w" if c <= 65535 else "l"


class ExprMixin:
    # ---- helpers --------------------------------------------------------------------------------------
    def temp(self, decl_text: str) -> str:
        c = self.cur
        c.ntemp += 1
        nm = "t%d" % c.ntemp
        c.temps.append(decl_text.replace("@", nm))
        return nm

    def str_temp(self, maxlen: int = 255) -> str:
        """A buffer for a string value of at most maxlen characters (the length byte included in the size). A string temporary
        lives inside one statement (the expression that makes it consumes it), so every statement starts again at ts1 and the
        routine declares each ts<n> once, at the largest size any statement gave it: a frame with seven 256 byte temporaries
        (DrawLocationLine) needs only as many as its busiest statement."""
        c = self.cur
        size = min(maxlen, 255) + 1
        i = c.sidx
        c.sidx += 1
        if i < len(c.stemps):
            c.stemps[i] = max(c.stemps[i], size)
        else:
            c.stemps.append(size)
        return "ts%d" % (i + 1)

    def lit(self, v, t: Ty) -> str:
        if isinstance(v, str):
            return c_char(ord(v)) if len(v) == 1 else "S(%s)" % cstr_literal(v)
        if t.kind == "real":
            return repr(float(v))
        if isinstance(v, bool):
            return "1" if v else "0"
        if v < 0:
            return "(%d)" % v if v > -2147483648 else "(-2147483647L - 1)"
        if v > 0x7FFFFFFF:
            return "%dU" % v
        return str(v)

    def paren(self, e: E) -> str:
        return "(%s)" % e.code if e.prec else e.code

    # ---- scope lookup -----------------------------------------------------------------------------------
    def lookup(self, name: str):
        """(kind, sym-or-field, with_prefix) for a name in the current context."""
        c = self.cur
        while c is not None:
            for rec, prefix in reversed(c.withs):
                f = self.field_type(rec, name)
                if f:
                    return ("field", f, prefix + self.field_path(rec, name))
            s = c.scope.find_local(name)
            if s is not None:
                return ("sym", s, None)
            c = c.parent
        s = self.unit_scope.find(name) or self.system.find(name)
        if s is None:
            return None
        return ("sym", s, None)

    def var_ref(self, s: Sym) -> str:
        """C expression for variable symbol s as seen from the current routine."""
        if s.where in ("macro", "static"):
            return s.cname
        owner = s.owner
        if owner is self.cur:
            prefix = "fr." if owner.has_frame else ""
        else:
            k = 0
            c = self.cur
            while c is not owner:
                c = c.parent
                k += 1
                if c is None:
                    raise TransError("variable %s not reachable from %s" % (s.name, self.cur.name))
            prefix = "up" + "->up" * (k - 1) + "->"
        ref = prefix + s.cname
        if (s.byref and s.type.kind != "untyped") or getattr(s, "arena", False):
            ref = "(*%s)" % ref
        return ref

    def mutate(self, e):
        r = getattr(e, "root", None)
        if r is not None and getattr(r, "valparam", False):
            r.mutated = True

    # ---- constants as expressions -----------------------------------------------------------------------
    def const_E(self, v, t: Ty, code=None) -> E:
        if t.kind == "string" or isinstance(v, str):
            if isinstance(v, str) and len(v) == 1 and t.kind != "string":
                e = E(code or c_char(ord(v)), P.CHAR, val=v)
            else:
                e = E(code or "S(%s)" % cstr_literal(v), Ty("string", maxlen=len(v)), val=v)
            e.strlit = v
            return e
        return E(code or self.lit(v, t), t, val=v)

    # ---- the main entry ---------------------------------------------------------------------------------
    def ex(self, n: N, wrap: bool = False, want: Ty | None = None) -> E:
        k = n.k
        m = getattr(self, "ex_" + k, None)
        if m is None:
            raise TransError("expression %s (line %d)" % (k, n.line))
        return m(n, wrap) if k in ("bin", "un") else m(n)

    def ex_int(self, n):
        v = n.value
        code = n.text if n.text.startswith("$") is False else "0x%X" % v
        if n.text.startswith("$"):
            code = "0x%X" % v + ("U" if v > 0x7FFFFFFF else "")
        else:
            code = str(v)
        t = P.BYTE if v < 256 else (P.INTEGER if v < 32768 else (P.WORD if v < 65536 else P.LONGINT))
        return E(code, t, val=v)

    def ex_real(self, n):
        return E(repr(n.value), P.REAL, val=n.value)

    def ex_str(self, n):
        return self.const_E(n.value, P.CHAR if len(n.value) == 1 else Ty("string", maxlen=len(n.value)))

    def ex_nil(self, n):
        return E("0", P.NILTYPE, val=0)

    def ex_paren(self, n):
        e = self.ex(n.a)
        r = E("(%s)" % e.code, e.ty, val=e.val, lv=False, strlit=e.strlit)
        return r

    def ex_name(self, n):
        r = self.lookup(n.name)
        if r is None or (r[0] == "sym" and r[1].kind == "routine" and getattr(r[1], "rtl", False)):
            bi = self.builtin(n.name.lower(), N("call", fn=n, args=[], line=n.line))
            if bi is not None:
                return bi
        if r is None:
            raise TransError("unknown identifier %s (line %d, %s)" % (n.name, n.line, self.cur.name if self.cur else "?"))
        kind, s, prefix = r
        if kind == "field":
            nm, ft = s
            return E("%s%s" % (prefix, self.safe(nm)), ft, lv=True)
        if s.kind == "var":
            if s.where == "special":
                raise TransError("%s used without an index (line %d)" % (s.name, n.line))
            e = E(self.var_ref(s), s.type, lv=True)
            e.root = s
            return e
        if s.kind in ("const", "enumconst"):
            return self.const_E(s.value, s.type, s.cname)
        if s.kind == "routine":
            return self.call_routine(s, [], n)
        if s.kind == "type":
            raise TransError("type %s used as a value (line %d)" % (n.name, n.line))
        raise TransError("name %s" % n.name)

    # ---- selectors ---------------------------------------------------------------------------------------
    def ex_field(self, n):
        # unit-qualified name (Unit.Name)?
        if n.a.k == "name":
            s = self.unit_scope.find(n.a.name)
            if s is None and n.a.name.lower() in self.units:
                u = self.units[n.a.name.lower()]
                sym = u.iface.find_local(n.name)
                if sym:
                    return self.ex(N("name", name=n.name, line=n.line)) if False else self.sym_value(sym, n)
        a = self.ex(n.a)
        t = a.ty
        if t.kind != "record":
            raise TransError("field %s of a non-record (line %d) %r" % (n.name, n.line, t))
        f = self.field_type(t, n.name)
        if not f:
            raise TransError("no field %s (line %d)" % (n.name, n.line))
        e = E("%s.%s%s" % (a.code, self.field_path(t, n.name), self.safe(f[0])), f[1], lv=True)
        e.root = a.root
        return e

    def sym_value(self, s, n):
        if s.kind == "var":
            return E(self.var_ref(s), s.type, lv=True)
        if s.kind == "routine":
            return self.call_routine(s, [], n)
        return self.const_E(s.value, s.type)

    def ex_deref(self, n):
        a = self.ex(n.a)
        t = a.ty
        if t.kind != "ptr" or t.elem is None:
            # a pointer declared before its target: resolve now
            if t.kind == "ptr" and getattr(t, "target_name", None):
                s = t.target_scope.find(t.target_name)
                if s is not None and s.kind == "type":
                    t.elem = s.type
            if t.kind == "ptr" and t.elem is None and not getattr(t, "target_name", None):
                return E("(*FPD(u8 *, %s))" % a.code, P.BYTE, lv=True)      # an untyped pointer: raw bytes
            if t.kind != "ptr" or t.elem is None:
                raise TransError("dereference of %r (line %d)" % (t, n.line))
        return E("(*%s(%s, %s))" % (self.deref_macro(t), ptr_ctype(t.elem), a.code), t.elem, lv=True)

    ENGINE_UNITS = {"RES05", "RES06", "RES07", "RES09", "OVL28", "OVL32", "OVL34"}

    def ptr_class(self, t: Ty) -> str:
        """mapped, banked or engine: where the blocks a pointer of type t points to live (placement.toml, by pointee type)."""
        if not self.placement or t.kind != "ptr":
            return "engine"
        if t.elem is None:
            try:
                self.ptr_target(t)
            except TransError:
                return "engine"
        name = re.sub(r"_(res|ovl)\d+$", "", (t.elem.cname or t.elem.name or "").lower())    # TMemPic_OVL16 -> tmempic
        if name in self.placement["mapped"]:
            return "mapped"
        if name in self.placement["banked"]:
            return "banked"
        return "engine"

    def deref_macro(self, t: Ty) -> str:
        """FPM (mapped: a 16-bit address in the 64 KB map), FPB (banked: map the block into the data window) or FPD."""
        c = self.ptr_class(t)
        if c == "engine" and self.placement and self.unit is not None and self.unit.name.upper() not in self.ENGINE_UNITS:
            key = (self.unit.name.upper(), t.elem.cname or t.elem.name or "?")
            self.engine_derefs[key] = self.engine_derefs.get(key, 0) + 1
        return {"mapped": "FPM", "banked": "FPB"}.get(c, "FPD")

    def ex_index(self, n):
        a = n.a
        # Mem[seg:ofs], Port[x]
        if a.k == "name":
            nm = a.name.lower()
            if nm == "mem":
                idx = n.idx[0]
                if idx.k != "segoff":
                    raise TransError("Mem index")
                seg, off = self.ex(idx.seg), self.ex(idx.off)
                e = E("rtl_peek8(%s, %s)" % (seg.code, off.code), P.BYTE)
                e.memref = (seg.code, off.code)
                return e
            if nm == "memw":
                idx = n.idx[0]
                seg, off = self.ex(idx.seg), self.ex(idx.off)
                e = E("rtl_peek16(%s, %s)" % (seg.code, off.code), P.WORD)
                e.memref = (seg.code, off.code)
                return e
            if nm == "port":
                x = self.ex(n.idx[0])
                e = E("rtl_inp(%s)" % x.code, P.BYTE)
                e.portref = x.code
                return e
            if nm == "portw":
                x = self.ex(n.idx[0])
                e = E("rtl_inpw(%s)" % x.code, P.WORD)
                e.portref = x.code
                return e
        base = self.ex(a)
        t = base.ty
        code = base.code
        for ix in n.idx:
            if t.kind == "string":
                i = self.ex(ix)
                code = "%s[%s]" % (code, i.code)
                t = P.CHAR
                continue
            if t.kind != "array":
                raise TransError("index of non-array %r (line %d)" % (t, n.line))
            i = self.ex(ix)
            lo = t.lo
            if i.val is not None and not isinstance(i.val, str):
                code = "%s[%d]" % (code, int(i.val) - lo)
            elif i.val is not None:
                code = "%s[%d]" % (code, ord(i.val) - lo)
            elif lo == 0:
                code = "%s[%s]" % (code, i.code)
            else:
                code = "%s[%s - %s]" % (code, self.paren(i), lo if lo > 0 else "(%d)" % lo)
            t = t.elem
        e = E(code, t, lv=True)
        e.root = base.root
        return e

    # ---- address-of ----------------------------------------------------------------------------------------
    def ex_addr(self, n):
        a = n.a
        if a.k == "name":
            r = self.lookup(a.name)
            if r and r[0] == "sym" and r[1].kind == "routine":
                s = r[1]
                return E(self.proc_id(s), P.POINTER)
        e = self.ex(a)
        if getattr(e, "memref", None):
            return E("POOL_FARPTR(%s, %s)" % e.memref, P.POINTER)
        ptr = Ty("ptr", elem=e.ty)
        ptr.cname = "farptr"
        return E("rtl_far(&%s)" % self.paren(e) if e.prec else "rtl_far(&%s)" % e.code, ptr)

    def proc_value(self, an):
        """A routine name used as a procedural value (no @)."""
        if an.k == "name":
            r = self.lookup(an.name)
            if r and r[0] == "sym" and r[1].kind == "routine" and not getattr(r[1], "rtl", False):
                return E(self.proc_id(r[1]), P.POINTER)
        return None

    def proc_id(self, s: Sym) -> str:
        self.proc_ids.setdefault(s.cname, s)
        return "PROC_%s" % s.cname

    # ---- unary / binary ------------------------------------------------------------------------------------
    def ex_un(self, n, wrap=False):
        a = self.ex(n.a, wrap=(n.op == "-"))
        if n.op == "-":
            if a.val is not None and not isinstance(a.val, str):
                v = -a.val
                return E("(%d)" % v if v < 0 else str(v), P.INTEGER if v >= -32768 else P.LONGINT, val=v)
            if a.ty.kind == "real":
                return E("(-%s)" % a.code, a.ty, prec=1)
            cls = combine(int_class(a.ty), "b") if int_class(a.ty) != "w" else "l"
            t = CLS_TYPE[cls]
            code = "-%s" % (self.widen(a, cls) if self.coco else self.paren(a))
            if not wrap:
                code = "%s(%s)" % (CLS_CAST[cls], code)
            return E("(%s)" % code if wrap else code, t, prec=0 if not wrap else 1) if wrap else E(code, t)
        if n.op == "not":
            if a.ty.kind == "bool":
                return E("!%s" % self.paren(a), P.BOOLEAN, prec=0, val=None if a.val is None else int(not a.val))
            cls = int_class(a.ty)
            cast = {"b": "(u8)", "i": "(s16)", "w": "(u16)", "l": "(s32)"}[cls]
            if a.ty.kind == "int" and a.ty.size() == 1:
                cast = "(u8)" if a.ty.lo >= 0 else "(s8)"
            return E("%s~%s" % (cast, self.paren(a)), a.ty if cls == "b" else CLS_TYPE[cls])
        raise TransError("unary " + n.op)

    def arith(self, op, a: E, b: E, wrap: bool) -> E:
        ca, cb = int_class(a.ty), int_class(b.ty)
        av = a.val if isinstance(a.val, int) else None
        bv = b.val if isinstance(b.val, int) else None
        if a.ty.kind == "char" and a.val is not None:
            av = ord(a.val)
        if av is not None and bv is not None:
            r = {"+": av + bv, "-": av - bv, "*": av * bv}.get(op)
            if r is not None:
                t = P.LONGINT if not (-32768 <= r <= 65535) else (P.INTEGER if r <= 32767 else P.WORD)
                return E("(%d)" % r if r < 0 else str(r), t, val=r)
        if bv is not None and av is None:
            cls = with_const(ca if ca != "b" else "b", bv)
        elif av is not None and bv is None:
            cls = with_const(cb if cb != "b" else "b", av)
        else:
            cls = combine(ca, cb)
        t = CLS_TYPE[cls]
        code = "%s %s %s" % (self.widen(a, cls), op, self.paren(b))
        if cls == "l" or wrap:
            return E(code, t, prec=1)
        return E("%s(%s)" % (CLS_CAST[cls], code), t)

    def widen(self, a: E, cls: str) -> str:
        """The left operand of an arithmetic operation. Under CMOC an operation on two byte-sized operands is done in
        8 bits, and Word with Integer in 16 (Turbo Pascal: Longint): the CoCo profile casts the left operand to the
        class of the result, so that the operation has the width the Pascal gives it (probes/byte-arith.c)."""
        if not self.coco or cls not in CLS_CAST:
            return self.paren(a)
        return "%s%s" % (CLS_CAST[cls], self.paren(a))

    def ex_bin(self, n, wrap=False):
        op = n.op
        if op in ("+", "-", "*") :
            return self.ex_addsub(n, wrap)
        if op == "in":
            return self.ex_in(n)
        a = self.ex(n.a)
        b = self.ex(n.b)
        if op in CMP:
            return self.ex_compare(op, a, b)
        if op == "/":
            return E("(%s / %s)" % (self.real(a), self.real(b)), P.REAL, prec=1)
        if op in ("div", "mod"):
            ca, cb = int_class(a.ty), int_class(b.ty)
            av = a.val if isinstance(a.val, int) else None
            bv = b.val if isinstance(b.val, int) else None
            if bv is not None and av is None:
                cls = with_const(ca, bv)
            elif av is not None and bv is None:
                cls = with_const(cb, av)
            else:
                cls = combine(ca, cb)
            if av is not None and bv is not None and bv != 0:
                r = int(av / bv) if op == "div" else av - int(av / bv) * bv
                return E(str(r) if r >= 0 else "(%d)" % r, P.INTEGER, val=r)
            code = "%s %s %s" % (self.widen(a, cls), "/" if op == "div" else "%", self.paren(b))
            if cls in ("i", "w") and a.ty.kind == "int" and b.ty.kind == "int":
                # the dividend is read as its own 16 bit type: wrapped operands keep their meaning
                pass
            return E("(%s)" % code, CLS_TYPE[cls], prec=0)
        if op in ("and", "or", "xor"):
            if a.ty.kind == "bool":
                cop = {"and": "&&", "or": "||", "xor": "!="}[op]
                if op == "xor":
                    return E("(!%s != !%s)" % (self.paren(a), self.paren(b)), P.BOOLEAN)
                return E("(%s %s %s)" % (self.paren(a), cop, self.paren(b)), P.BOOLEAN)
            cop = {"and": "&", "or": "|", "xor": "^"}[op]
            ca, cb = int_class(a.ty), int_class(b.ty)
            bv = b.val if isinstance(b.val, int) else None
            av = a.val if isinstance(a.val, int) else None
            if bv is not None and av is None:
                cls = with_const(ca, bv)
            elif av is not None and bv is None:
                cls = with_const(cb, av)
            else:
                cls = combine(ca, cb)
            if a.ty.kind == "set":
                raise TransError("set operator")
            return E("(%s %s %s)" % (self.paren(a), cop, self.paren(b)), CLS_TYPE[cls])
        if op in ("shl", "shr"):
            ca = int_class(a.ty)
            av = a.val if isinstance(a.val, int) else None
            bv = b.val if isinstance(b.val, int) else None
            if av is not None and bv is not None:
                r = (av << bv) if op == "shl" else (av >> bv)
                return E(str(r), P.LONGINT if r > 65535 else P.WORD, val=r)
            if ca == "b":
                cls = "i"
            else:
                cls = ca
            t = CLS_TYPE[cls]
            if op == "shl":
                code = "%s << %s" % (self.widen(a, cls), self.paren(b))
                if cls == "l" or wrap:
                    return E(code, t, prec=1)
                return E("%s(%s)" % (CLS_CAST[cls], code), t)
            # shr is logical on the operand's own width
            ucast = "(u16)" if cls in ("i", "w") else "(u32)"
            return E("(%s)(%s%s >> %s)" % (CLS_CAST[cls][1:-1], ucast, self.paren(a), self.paren(b)), t)
        raise TransError("operator " + op)

    def real(self, e: E) -> str:
        return e.code if e.ty.kind == "real" else "(double)%s" % self.paren(e)

    def ex_addsub(self, n, wrap):
        op = n.op
        if op == "+":
            # strings and sets
            parts = self.flatten_add(n)
            if any(self.is_stringish(p) for p in parts):
                return self.concat(parts)
            if any(p.ty.kind == "set" for p in parts):
                return self.set_op(n)
        a = self.ex(n.a, wrap=True)
        b = self.ex(n.b, wrap=True)
        if a.ty.kind == "real" or b.ty.kind == "real":
            return E("(%s %s %s)" % (self.real(a), op, self.real(b)), P.REAL, prec=0)
        if a.ty.kind == "set":
            return self.set_op(n)
        if a.ty.kind == "ptr" or b.ty.kind == "ptr":
            raise TransError("pointer arithmetic (line %d)" % n.line)
        return self.arith(op, a, b, wrap)

    def flatten_add(self, n):
        out = []

        def walk(x):
            if x.k == "bin" and x.op == "+":
                walk(x.a)
                walk(x.b)
            else:
                out.append(self.ex(x))
        # evaluate left to right
        walk(n)
        return out

    def is_stringish(self, e: E):
        return e.ty.kind == "string" or (e.ty.kind == "char" and e.strlit is not None) or e.ty.kind == "string"

    def to_pstr(self, e: E) -> str:
        """C expression of type const u8* for a string-or-char expression."""
        if e.ty.kind == "string":
            return e.code
        if e.ty.kind == "char":
            if e.strlit is not None:
                return "S(%s)" % cstr_literal(e.strlit)
            t = self.str_temp(1)
            return "rtl_str_char(%s, %s)" % (t, e.code)
        raise TransError("not a string: %r" % e.ty)

    def concat(self, parts):
        items = [self.to_pstr(p) for p in parts]
        # the longest the result can be: the parts' longest, 255 at most (a smaller buffer keeps the frames small)
        total = 0
        for p in parts:
            if p.ty.kind == "char":
                total += 1
            elif p.strlit is not None:
                total += len(p.strlit)
            elif p.ty.kind == "string":
                total += p.ty.maxlen
            else:
                total += 255
        total = min(total, 255)
        t = self.str_temp(total)
        if self.coco:                                   # CMOC has no compound literals
            return E("rtl_str_cat_v(%s, %d, %s)" % (t, len(items), ", ".join(items)), Ty("string", maxlen=total))
        return E("rtl_str_cat(%s, %d, (const u8 *const[]){%s})" % (t, len(items), ", ".join(items)),
                 Ty("string", maxlen=total))

    def ex_compare(self, op, a: E, b: E) -> E:
        c = CMP[op]
        if self.is_stringish(a) or self.is_stringish(b):
            if a.ty.kind in ("string", "char") and b.ty.kind in ("string", "char"):
                if a.ty.kind == "char" and b.ty.kind == "char":
                    return E("(%s %s %s)" % (a.code, c, b.code), P.BOOLEAN)
                return E("(rtl_str_cmp(%s, %s) %s 0)" % (self.to_pstr(a), self.to_pstr(b), c), P.BOOLEAN)
        if a.ty.kind == "set" or b.ty.kind == "set":
            if op in ("=", "<>"):
                return E("(%srtl_set_eq(%s, %s, %d))" % ("!" if op == "<>" else "", a.code, b.code, a.ty.size()), P.BOOLEAN)
            return E("(%s(%s, %s, %d))" % ("rtl_set_le" if op == "<=" else "rtl_set_ge", a.code, b.code, a.ty.size()),
                     P.BOOLEAN)
        if a.ty.kind == "real" or b.ty.kind == "real":
            return E("(%s %s %s)" % (self.real(a), c, self.real(b)), P.BOOLEAN)
        ac = a.code if not (a.ty.kind == "char" and a.val is not None and False) else a.code
        # a word against an integer compares as longints: promote the unsigned one explicitly
        return E("(%s %s %s)" % (self.cmp_operand(a, b), c, self.cmp_operand(b, a, left=False)), P.BOOLEAN)

    def cmp_operand(self, a: E, other: E, left: bool = True) -> str:
        if self.coco and left and a.ty.kind in ("int", "bool", "char", "enum") and other.ty.kind in ("int", "bool", "char", "enum"):
            # CMOC compares with the signedness of the left operand and, for two bytes, in 8 bits: widen the left
            # operand when the two do not agree (Turbo Pascal compares as Integer, Word or Longint)
            ca, co = int_class(a.ty), int_class(other.ty)
            av = a.val if isinstance(a.val, int) else None
            bv = other.val if isinstance(other.val, int) else None
            if bv is not None:
                co = with_const(co, bv)
            if av is not None:
                ca = with_const(ca, av)
            unsigned = lambda c: c in ("b", "w")
            cls = combine(ca, co)
            if unsigned(ca) != unsigned(co) or cls == "l":
                return "%s%s" % (CLS_CAST[cls if cls in CLS_CAST else "i"], self.paren(a))
        return a.code

    def ex_in(self, n):
        a = self.ex(n.a)
        s = n.b
        if s.k == "setlit":
            conds = []
            x = a.code
            if a.prec or not x.replace("_", "").isalnum():
                tmp = x
            for it in s.items:
                if it.k == "range":
                    lo, hi = self.ex(it.lo), self.ex(it.hi)
                    conds.append("(%s >= %s && %s <= %s)" % (x, lo.code, x, hi.code))
                else:
                    v = self.ex(it)
                    conds.append("%s == %s" % (x, v.code))
            if not conds:
                return E("0", P.BOOLEAN)
            single_eval = all(c.isalnum() or c in "_.->[]()*" for c in x) and "(" not in x or x.isidentifier()
            if single_eval or len(conds) == 1:
                return E("(%s)" % " || ".join(conds), P.BOOLEAN)
            # a complex operand is evaluated once
            t = self.temp("s32 @")
            return E("((%s = %s), (%s))" % (t, x, " || ".join(c.replace(x, t) for c in conds)), P.BOOLEAN)
        cv = self.ce(s, self.ce_scope())
        if cv is not None and isinstance(cv[0], frozenset):
            vals = sorted(cv[0])
            runs = []
            for v in vals:
                if runs and runs[-1][1] == v - 1:
                    runs[-1][1] = v
                else:
                    runs.append([v, v])
            x = a.code
            if not x.isidentifier():
                t = self.temp("s32 @")
                pre = "(%s = %s, " % (t, x)
                x = t
            else:
                pre = "("
            conds = [("%s == %d" % (x, r[0])) if r[0] == r[1] else ("(%s >= %d && %s <= %d)" % (x, r[0], x, r[1]))
                     for r in runs]
            return E("%s%s)" % (pre, " || ".join(conds) if conds else "0"), P.BOOLEAN)
        b = self.ex(s)
        if b.ty.kind == "set" and b.ty.size() != 32:
            first = P.set_first_byte(b.ty)
            return E("rtl_set_in_at(%s, %d, %d, %s)" % (b.code, first, b.ty.size(), a.code), P.BOOLEAN)
        return E("rtl_set_in(%s, %s)" % (b.code, a.code), P.BOOLEAN)

    def ex_setlit(self, n):
        t = Ty("set", elem=P.BYTE)
        tmp = self.temp("u8 @[32]")
        parts = ["rtl_set_clear(%s, 32)" % tmp]
        for it in n.items:
            if it.k == "range":
                lo, hi = self.ex(it.lo), self.ex(it.hi)
                parts.append("rtl_set_range(%s, %s, %s)" % (tmp, lo.code, hi.code))
            else:
                v = self.ex(it)
                parts.append("rtl_set_add(%s, %s)" % (tmp, v.code))
        return E("(%s, %s)" % (", ".join(parts), tmp), t)

    def set_op(self, n):
        a, b = self.ex(n.a), self.ex(n.b)
        t = self.temp("u8 @[32]")
        fn = {"+": "rtl_set_union", "-": "rtl_set_diff", "*": "rtl_set_inter"}[n.op]
        return E("%s(%s, %s, %s, 32)" % (fn, t, a.code, b.code), a.ty)

    # ---- calls ---------------------------------------------------------------------------------------------
    def ex_call(self, n):
        fn = n.fn
        if fn.k == "name":
            r = self.lookup(fn.name)
            if r is None or (r[0] == "sym" and r[1].kind == "routine" and getattr(r[1], "rtl", False)):
                bi = self.builtin(fn.name.lower(), n, True)
                if bi is not None:
                    return bi
            if r is None:
                raise TransError("unknown routine %s (line %d, in %s)" % (fn.name, n.line, self.cur.name if self.cur else "?"))
            kind, s, prefix = r
            if kind == "sym":
                if s.kind == "routine":
                    bi = self.builtin_override(s, n)
                    if bi is not None:
                        return bi
                    return self.call_routine(s, n.args, n)
                if s.kind == "type":
                    return self.typecast(s.type, n.args[0], n)
                if s.kind == "var" and s.type.kind == "proc":
                    return self.call_var(self.ex(fn), s.type, n.args, n)
            if kind == "field" and s[1].kind == "proc":
                return self.call_var(self.ex(fn), s[1], n.args, n)
            raise TransError("cannot call %s (line %d)" % (fn.name, n.line))
        if fn.k == "field" and fn.a.k == "name" and fn.a.name.lower() in self.units:
            u = self.units[fn.a.name.lower()]
            s = u.iface.find_local(fn.name)
            if s is not None and s.kind == "routine":
                return self.call_routine(s, n.args, n)
        e = self.ex(fn)
        if e.ty.kind == "proc":
            return self.call_var(e, e.ty, n.args, n)
        raise TransError("call of %r (line %d)" % (e.ty, n.line))

    def builtin_override(self, s, n):
        return None

    def typecast(self, t: Ty, arg: N, n) -> E:
        e = self.ex(arg)
        k = t.kind
        if e.ty.kind == "untyped":
            return E("(*(%s)%s)" % (ptr_ctype(t), e.code), t, lv=True)
        if k in ("ptr", "proc") and e.lv and (e.ty.kind in ("ptr", "proc") or e.ty.size() == 4):
            r = E(e.code, t, lv=True)
            r.root = e.root
            return r
        if k in ("int", "enum", "bool", "char"):
            if e.ty.kind == "real":
                raise TransError("cast of real")
            if e.lv and e.ty.kind in ("int", "enum", "bool", "char") and e.ty.size() == t.size():
                if ctype(e.ty) != ctype(t) and e.ty.size() > 1:
                    # Integer(WordVar): the variable is read (and written) as the other type, or `Integer(W) < 0` compares an unsigned
                    r = E("(*(%s)&%s)" % (ptr_ctype(t), self.paren(e)), t, lv=True)
                else:
                    r = E(e.code, t, lv=True)
                r.root = e.root
                return r
            if e.val is not None and not isinstance(e.val, str):
                return E(self.lit(e.val, t) if k != "enum" else str(e.val), t, val=e.val)
            if e.ty.kind == "char" and e.val is not None:
                return E(e.code, t, val=ord(e.val))
            return E("(%s)%s" % (ctype(t), self.paren(e)), t, prec=0, lv=False)
        if k in ("ptr", "proc"):
            return E("((farptr)%s)" % self.paren(e), t)
        if k == "real":
            return E(self.real(e), t)
        if k in ("record", "array", "string", "set"):
            # a variable typecast reinterprets the storage
            if not e.lv:
                raise TransError("cast of a non-variable to %r (line %d)" % (t, n.line))
            return E("(*(%s)&%s)" % (ptr_ctype(t), self.paren(e)), t, lv=True)
        raise TransError("typecast to %r" % t)

    def arg_pass(self, p: Sym, an: N, ctx_n) -> str:
        """The C argument text for one actual parameter."""
        t = p.type
        if p.byref:
            e = self.ex(an)
            self.mutate(e)
            if getattr(e, "memref", None):
                return "rtl_mem_ptr(%s, %s)" % e.memref
            if e.ty.kind == "untyped":
                return "(void *)%s" % e.code
            if getattr(e, "portref", None):
                raise TransError("Port as var parameter")
            if not e.lv:
                # a value passed to a var parameter (typed constants, function results): through a temporary
                tmp = self.temp(decl(e.ty, "@"))
                return "(%s = %s, &%s)" % (tmp, e.code, tmp)
            addr = "&%s" % self.paren(e)
            if t.kind == "untyped":
                if self.coco and e.code.isidentifier() and e.ty.size() < 4:
                    # the Pascal frame lets the callee write a pointer over a byte local and the bytes next to it (ovl09 TryTurnUndead:
                    # Done is a byte, SelectTurnUndeadTarget stores a PCharacter in it); CMOC lays locals out the other way round
                    self.cur.padded.add(e.code)
                return "(void *)%s" % addr
            if t.kind == "file" or e.ty.kind == "file":
                return "(void *)%s" % addr
            if decl(e.ty, "(*)") != decl(t, "(*)") and not (t.kind in ("int", "bool", "char", "enum") and e.ty.kind in ("int", "bool", "char", "enum") and t.size() == e.ty.size()):
                return "(%s)%s" % (ptr_ctype(t), addr)
            return addr
        if t.kind == "proc":
            e = self.proc_value(an)
            if e is not None:
                return e.code
        e = self.ex(an)
        k = t.kind
        if k == "string":
            return self.to_pstr(e)
        if k in ("array",):
            return "&%s" % self.paren(e)
        if k == "proc":
            return e.code
        if k == "real":
            return self.real(e)
        if k == "set":
            return e.code
        if k == "char" and e.ty.kind == "string":
            return "%s[1]" % e.code
        return e.code

    def call_routine(self, s: Sym, args, n) -> E:
        params = s.params
        if len(args) != len(params):
            # optional trailing parameters of the runtime (e.g. Str); the table of built-ins handles them
            raise TransError("%s expects %d arguments, got %d (line %d)" % (s.name, len(params), len(args), n.line))
        out = []
        if s.nested_in is not None:
            out.append(self.static_link(s))
        if s.ret is not None and s.ret.kind == "string":
            out.append(self.str_temp())
        for p, a in zip(params, args):
            out.append(self.arg_pass(p, a, n))
        code = "%s(%s)" % (s.cname, ", ".join(out))
        if self.coco and s.name.lower() == "move" and len(args) == 3:
            code = self.move_swaps(code, out, args)
        return E(code, s.ret if s.ret is not None else P.VOID)

    def move_swaps(self, code, out, args):
        """Move(Source, Dest, 2 or 4) between a byte buffer and a word, long or pointer variable (a value as a file or a DAX block
        has it, little endian): the CoCo's variable is big endian, so the value is turned round after (into a variable) or around
        (out of one) the copy."""
        cnt = self.ex(args[2]).code
        if not cnt.isdigit():
            return code
        try:
            sty, dty = self.ex(args[0]).ty, self.ex(args[1]).ty
        except TransError:
            return code
        byte = lambda t: t.kind in ("int", "enum", "char", "bool") and t.size() == 1
        whole = lambda t: t.kind in ("record", "array") and t.size() == int(cnt)
        if byte(sty) and whole(dty):              # Move(Block^[Offset], Item, SizeOf(Item)): a record out of a DAX block's bytes
            d = self.swap_descriptor(dty)
            return "%s, rtl_swapdesc(%s, %s)" % (code, out[1], d) if d else code
        if byte(dty) and whole(sty):
            d = self.swap_descriptor(sty)
            return "rtl_swapdesc(%s, %s), %s, rtl_swapdesc(%s, %s)" % (out[0], d, code, out[0], d) if d else code
        if int(cnt) not in (2, 4):
            return code
        scalar = lambda t: t.kind in ("int", "enum", "ptr") and t.size() == int(cnt)
        if scalar(dty) and not scalar(sty):
            return "%s, rtl_swapdesc(%s, %s)" % (code, out[1], self.swap_descriptor(dty))
        if scalar(sty) and not scalar(dty):
            d = self.swap_descriptor(sty)
            return "rtl_swapdesc(%s, %s), %s, rtl_swapdesc(%s, %s)" % (out[0], d, code, out[0], d)
        return code

    def static_link(self, s: Sym) -> str:
        """The frame pointer to pass to nested routine s: the frame of its parent."""
        parent = s.nested_in
        c = self.cur
        k = 0
        while c is not parent:
            c = c.parent
            k += 1
            if c is None:
                raise TransError("nested routine %s called out of its scope" % s.name)
        if k == 0:
            return "&fr"
        return "up" + "".join("->up" for _ in range(k - 1))

    def call_var(self, e: E, pt: Ty, args, n) -> E:
        out = []
        for p, a in zip(pt.params, args):
            out.append(self.arg_pass(p, a, n))
        ret = pt.ret
        sig = ", ".join(decl(p.type, "") if not p.byref else ("void *" if p.type.kind == "untyped" else ptr_ctype(p.type))
                        for p in pt.params) or "void"
        rt = decl(ret, "") if ret is not None else "void"
        code = "((%s (*)(%s))rtl_proc(%s))(%s)" % (rt, sig, e.code, ", ".join(out))
        return E(code, ret if ret is not None else P.VOID)

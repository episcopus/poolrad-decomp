"""p2c_decl.py: declarations for the Pascal to C translator: unit scopes, naming, type resolution, constant
evaluation, the DGROUP layout and typed constant images."""
from __future__ import annotations

import struct

import ptypes as P
from p2c_base import C_RESERVED, Scope, Sym, c_char, cstr_literal, decl, ctype, ptr_ctype
from ptypes import Ty
from pasparse import N

DS_SEG = 0x1C7C                       # the data segment as the oracle loads it (load paragraph 1000 + 0C7C)
DS_LINEAR = DS_SEG * 16
FIRST_CONST = 0x0002
VARS_START = 0x442E


class TransError(Exception):
    pass


class E:
    """An expression's C text and Pascal type. val: its constant value when known."""

    def __init__(self, code, ty, val=None, lv=False, strlit=None, prec=0):
        self.code = code
        self.ty = ty
        self.val = val
        self.lv = lv
        self.strlit = strlit       # python str when the expression is a string/char literal
        self.prec = prec           # 0 atom, 1 anything else (needs parentheses when nested)
        self.root = None           # the variable symbol an lvalue is part of


class UnitScope(Scope):
    """Name lookup of a unit: its own symbols, then the used units' interfaces (last used first), then System."""

    def __init__(self, name):
        super().__init__(None, name)
        self.uses: list[Scope] = []

    def find(self, name):
        k = name.lower()
        s = self.syms.get(k)
        if s is not None:
            return s
        for u in reversed(self.uses):
            s = u.syms.get(k)
            if s is not None:
                return s
        return None


class DeclMixin:
    # ---- C names ------------------------------------------------------------------------------------
    def unique(self, base, key, unit):
        """A C name for a global thing: plain if free, else suffixed with the unit's id."""
        b = base
        if b in C_RESERVED or b in self.macros:
            b += "_"
        if b not in self.taken:
            self.taken[b] = key
            return b
        b2 = "%s_%s" % (b, unit)
        n = 2
        while b2 in self.taken:
            b2 = "%s_%s%d" % (b, unit, n)
            n += 1
        self.taken[b2] = key
        return b2

    def safe(self, name):
        """A C name for a local, parameter, field or label."""
        if name in C_RESERVED or name in self.macros or name in self.taken_global_fn:
            return name + "_"
        return name

    # ---- types ------------------------------------------------------------------------------------
    def resolve_type(self, n: N, scope, hint=None) -> Ty:
        k = n.k
        if k == "named":
            nm = n.name.lower()
            s = scope.find(n.name)
            if s is None or s.kind != "type":
                raise TransError("unknown type %s (line %d)" % (n.name, n.line))
            return s.type
        if k == "range":
            lo, hi = self.const_int(n.lo, scope), self.const_int(n.hi, scope)
            lt = self.const_type(n.lo, scope)
            if lt is not None and lt.kind in ("enum", "char", "bool"):
                t = Ty(lt.kind, lo=lo, hi=hi, members=lt.members)
                t.base = lt
                t.cname = lt.cname
                return t
            return P.range_type(lo, hi)
        if k == "enum":
            t = Ty("enum", members=list(n.names), lo=0, hi=len(n.names) - 1)
            t.cname = None
            t.pending_enum = True
            return t
        if k == "string":
            t = Ty("string", maxlen=self.const_int(n.length, scope) if n.length is not None else 255)
            return t
        if k == "ptr":
            s = scope.find(n.target)
            t = Ty("ptr")
            t.cname = "farptr"
            t.target_name = n.target
            t.target_scope = scope
            t.elem = s.type if (s is not None and s.kind == "type") else None
            return t
        if k == "array":
            idx = n.index
            elem = self.resolve_type(n.elem, scope)
            for it in reversed(idx):
                lo, hi = self.index_bounds(it, scope)
                a = Ty("array", lo=lo, hi=hi, elem=elem)
                elem = a
            return elem
        if k == "record":
            return self.resolve_record(n, scope, hint)
        if k == "set":
            b = self.resolve_type(n.base, scope)
            t = Ty("set", elem=b)
            return t
        if k == "file":
            if n.elem is None:
                t = Ty("file", elem=None)
            else:
                t = Ty("file", elem=self.resolve_type(n.elem, scope))
            t.cname = "FileRec"
            t.size_ = 128
            return t
        if k == "proctype":
            t = Ty("proc")
            t.cname = "farptr"
            t.params = self.resolve_params(n.params, scope)
            t.ret = self.resolve_type(n.ret, scope) if n.ret else None
            return t
        raise TransError("type node %s" % k)

    def index_bounds(self, it: N, scope):
        if it.k == "range":
            return self.const_int(it.lo, scope), self.const_int(it.hi, scope)
        t = self.resolve_type(it, scope)
        if t.kind == "bool":
            return 0, 1
        return t.lo, t.hi

    def resolve_record(self, n, scope, hint):
        t = Ty("record")
        t.fields = []
        t.variant = None
        t.arms = []

        def add(fields, into):
            for f in fields:
                ft = self.resolve_type(f.type, scope, hint)
                for nm in f.names:
                    into.append((nm, ft))

        add(n.fields, t.fields)

        def walk_variant(v, owner_arms):
            if v is None:
                return
            if v.tag:
                pass
            for arm in v.arms:
                items = []
                add(arm.fields, items)
                sub = Ty("record")
                sub.fields = items
                sub.variant = None
                sub.arms = []
                owner_arms.append(sub)
                if arm.variant is not None:
                    walk_variant(arm.variant, sub.arms)
                    sub.variant = sub.arms[:]  # nested variants are rare; kept for size

        if n.variant is not None:
            if n.variant.tag:
                tt = self.resolve_type(n.variant.tagtype, scope)
                t.fields.append((n.variant.tag, tt))
            walk_variant(n.variant, t.arms)
            t.variant = [a.fields + [(nm, ft) for sub in (a.arms or []) for (nm, ft) in sub.fields] for a in t.arms]
        return t

    def field_type(self, rec: Ty, name: str):
        k = name.lower()
        for nm, ft in rec.fields:
            if nm.lower() == k:
                return nm, ft
        for arm in rec.arms:
            r = self.field_type(arm, name)
            if r:
                return r
        return None

    def resolve_params(self, params, scope):
        out = []
        for p in params:
            t = self.resolve_type(p.type, scope) if p.type is not None else P.UNTYPED
            for nm in p.names:
                out.append(Sym("var", nm, type=t, byref=p.byref, param=True))
        return out

    # ---- constants ----------------------------------------------------------------------------------
    def const_type(self, n: N, scope):
        r = self.ce(n, scope)
        return r[1] if r else None

    def const_int(self, n: N, scope) -> int:
        r = self.ce(n, scope)
        if r is None:
            raise TransError("not a constant (line %d): %r" % (n.line, n))
        v = r[0]
        if isinstance(v, str):
            if len(v) == 1:
                return ord(v)
            raise TransError("string constant where an integer was expected (line %d)" % n.line)
        return int(v)

    def ce(self, n: N, scope):
        """Evaluate a constant expression: (value, type) or None."""
        k = n.k
        if k == "int":
            v = n.value
            return v, (P.BYTE if v < 256 else (P.INTEGER if v < 32768 else (P.WORD if v < 65536 else P.LONGINT)))
        if k == "real":
            return n.value, P.REAL
        if k == "str":
            return n.value, (P.CHAR if len(n.value) == 1 else Ty("string", maxlen=len(n.value)))
        if k == "paren":
            return self.ce(n.a, scope)
        if k == "setlit":
            vals = set()
            for it in n.items:
                if it.k == "range":
                    lo, hi = self.ce(it.lo, scope), self.ce(it.hi, scope)
                    if lo is None or hi is None:
                        return None
                    a, b = (ord(x) if isinstance(x, str) else x for x in (lo[0], hi[0]))
                    vals.update(range(a, b + 1))
                else:
                    r = self.ce(it, scope)
                    if r is None:
                        return None
                    vals.add(ord(r[0]) if isinstance(r[0], str) else int(r[0]))
            return frozenset(vals), Ty("set", elem=P.BYTE)
        if k == "nil":
            return 0, P.NILTYPE
        if k == "name":
            s = scope.find(n.name) if not isinstance(n.name, Ty) else None
            if s is None:
                return None
            if s.kind == "const":
                return s.value, s.type
            if s.kind == "enumconst":
                return s.value, s.type
            return None
        if k == "un":
            r = self.ce(n.a, scope)
            if r is None:
                return None
            v, t = r
            if n.op == "-":
                return -v, (P.INTEGER if -32768 <= -v else P.LONGINT) if t.kind == "int" else t
            if n.op == "not":
                return (not v) if t.kind == "bool" else ~v, t
            return None
        if k == "bin":
            ra, rb = self.ce(n.a, scope), self.ce(n.b, scope)
            if ra is None or rb is None:
                return None
            (a, ta), (b, tb) = ra, rb
            op = n.op
            if isinstance(a, str) or isinstance(b, str):
                if op == "+":
                    return str(a) + str(b), Ty("string", maxlen=255)
                return None
            try:
                r = {"+": lambda: a + b, "-": lambda: a - b, "*": lambda: a * b, "div": lambda: int(a / b),
                     "mod": lambda: a - int(a / b) * b, "shl": lambda: a << b, "shr": lambda: a >> b,
                     "and": lambda: a & b, "or": lambda: a | b, "xor": lambda: a ^ b,
                     "=": lambda: int(a == b), "<>": lambda: int(a != b), "<": lambda: int(a < b),
                     ">": lambda: int(a > b), "<=": lambda: int(a <= b), ">=": lambda: int(a >= b),
                     "/": lambda: a / b}[op]()
            except KeyError:
                return None
            if op in ("=", "<>", "<", ">", "<=", ">="):
                return r, P.BOOLEAN
            t = P.LONGINT if not (-32768 <= r <= 65535) else (P.INTEGER if r <= 32767 else P.WORD)
            if ta.kind == "real" or tb.kind == "real" or op == "/":
                t = P.REAL
            return r, t
        if k == "call" and n.fn.k == "name":
            fn = n.fn.name.lower()
            if fn in ("ord", "chr", "lo", "hi", "succ", "pred", "sizeof", "length", "abs", "swap", "high", "low",
                      "odd"):
                if fn == "sizeof":
                    try:
                        s = scope.find(n.args[0].name) if n.args[0].k == "name" else None
                        if s is not None and s.kind == "type":
                            return s.type.size(), P.WORD
                        if s is not None and s.kind == "var":
                            return s.type.size(), P.WORD
                    except Exception:
                        return None
                    return None
                a = self.ce(n.args[0], scope)
                if a is None:
                    return None
                v, t = a
                if fn == "ord":
                    return (ord(v) if isinstance(v, str) else int(v)), P.INTEGER
                if fn == "chr":
                    return chr(int(v)), P.CHAR
                if fn == "lo":
                    return int(v) & 255, P.BYTE
                if fn == "hi":
                    return (int(v) >> 8) & 255, P.BYTE
                if fn == "succ":
                    return (v + 1) if not isinstance(v, str) else chr(ord(v) + 1), t
                if fn == "pred":
                    return (v - 1) if not isinstance(v, str) else chr(ord(v) - 1), t
                if fn == "length":
                    return len(v), P.BYTE
                if fn == "abs":
                    return abs(v), t
                if fn == "swap":
                    return ((v & 255) << 8) | ((v >> 8) & 255), P.WORD
                return None
        return None

    # ---- typed constant images ------------------------------------------------------------------------
    def serialize(self, t: Ty, v, scope) -> bytes:
        """The bytes a typed constant of type t with value node v occupies."""
        k = t.kind
        if k == "array" and isinstance(v, N) and v.k == "paren":
            v = N("arrayval", items=[v.a])
        if isinstance(v, N) and v.k in ("arrayval", "recordval"):
            if k == "array":
                n = t.hi - t.lo + 1
                items = v.items
                if v.k == "arrayval" and len(items) != n:
                    raise TransError("array constant has %d items for %d" % (len(items), n))
                return b"".join(self.serialize(t.elem, it, scope) for it in items)
            if k == "record":
                vals = {nm.lower(): val for nm, val in v.items}
                out = b""
                done = 0
                for nm, ft in t.fields:
                    if nm.lower() in vals:
                        out += self.serialize(ft, vals[nm.lower()], scope)
                    else:
                        out += bytes(ft.size())
                    done += ft.size()
                if t.arms and v.items:
                    # the variant part: the first arm that names one of the given fields
                    for arm in t.arms:
                        names = [nm.lower() for nm, _ in arm.fields]
                        if any(nm.lower() in names for nm, _ in v.items):
                            body = b""
                            for nm, ft in arm.fields:
                                body += self.serialize(ft, vals.get(nm.lower()), scope) if nm.lower() in vals else bytes(ft.size())
                            out += body.ljust(max(a.size() for a in t.arms), b"\0")
                            return out
                    out += bytes(max(a.size() for a in t.arms))
                elif t.arms:
                    out += bytes(max(a.size() for a in t.arms))
                return out
            raise TransError("aggregate for %s" % k)
        r = self.ce(v, scope)
        if r is None:
            raise TransError("typed constant value is not constant (line %d)" % v.line)
        val = r[0]
        if k in ("int", "bool", "char", "enum"):
            n = t.size()
            if isinstance(val, str):
                val = ord(val)
            return int(val & ((1 << (8 * n)) - 1)).to_bytes(n, "little")
        if k == "string":
            s = val if isinstance(val, str) else chr(val)
            s = s[: t.maxlen]
            return (bytes([len(s)]) + s.encode("latin-1")).ljust(t.maxlen + 1, b"\0")
        if k == "ptr" or k == "proc":
            if val == 0:
                return bytes(4)
            raise TransError("pointer constant")
        if k == "real":
            return self.real_bytes(float(val), t.size())
        if k == "set":
            return bytes(t.size())
        raise TransError("serialize %s of %r" % (k, v))

    def real_bytes(self, x: float, size: int) -> bytes:
        if size == 4:
            return struct.pack("<f", x)
        if size == 8:
            return struct.pack("<d", x)
        if size == 6:                     # Turbo Pascal Real: exponent byte, 39 bit mantissa
            if x == 0:
                return bytes(6)
            import math
            sign = x < 0
            m, e = math.frexp(abs(x))      # x = m * 2^e, 0.5 <= m < 1
            exp = e + 128
            mant = int(m * (1 << 40)) & ((1 << 39) - 1)
            b = bytearray(6)
            b[0] = exp & 255
            for i in range(5):
                b[1 + i] = (mant >> (8 * i)) & 255
            if sign:
                b[5] |= 0x80
            return bytes(b)
        raise TransError("real size %d" % size)

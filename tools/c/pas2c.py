#!/usr/bin/env python3
"""pas2c.py: translate the matched Pascal of src/ into C (SPEC 7.4, Phase 7).

  .venv/bin/python tools/c/pas2c.py [--out c/game] [UNIT ...]

One C file per unit plus `game.h` (types, constants, DGROUP globals as macros, prototypes), the typed-constant
image of DGROUP and the table behind procedure pointers. The generated C keeps the Pascal's names, comments and
control flow; the runtime it needs is c/rtl (Turbo Pascal semantics: strings, sets, files, heap, EGA).
"""
from __future__ import annotations

import argparse
import copy
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ptypes as P  # noqa: E402
from p2c_base import C_RESERVED, Scope, Sym, c_bytes, c_char, cstr_literal, ctype, decl, ptr_ctype  # noqa: E402
from p2c_builtin import BuiltinMixin  # noqa: E402
from p2c_decl import (DS_LINEAR, DS_SEG, FIRST_CONST, VARS_START, DeclMixin, E, TransError,  # noqa: E402
                      UnitScope)
from p2c_expr import ExprMixin  # noqa: E402
from p2c_stmt import Ctx, StmtMixin, cmt  # noqa: E402
from pasparse import N, parse_file, Parser  # noqa: E402
from ptypes import Ty  # noqa: E402

ROOT = HERE.parents[1]
RTL_UNITS = {"system", "crt", "dos", "overlay", "printer", "graph"}
LAYOUT_NAME = re.compile(r"^(ds|Raw)([0-9A-Fa-f]{4})$")


class Unit:
    def __init__(self, node: N):
        self.node = node
        self.name = node.name
        self.iface = Scope(None, node.name)
        self.scope = UnitScope(node.name)
        self.c: list[str] = []             # the unit's .c file
        self.init_name = None


class Gen(DeclMixin, ExprMixin, BuiltinMixin, StmtMixin):
    def __init__(self):
        self.coco = False                  # the CoCo profile (CMOC-readable C, step 8.2)
        self.placement = None              # pointee type name -> mapped | banked (default engine), --placement FILE
        self.engine_derefs = {}            # (unit, type) -> dereferences of an engine-class block by game logic
        self.taken: dict[str, tuple] = {}
        self.macros: set[str] = set()
        self.taken_global_fn: set[str] = set()
        self.global_const_names: set[str] = set()
        self.units: dict[str, Unit] = {}
        self.order: list[Unit] = []
        self.h: list[str] = []             # game.h body in order
        self.protos: list[str] = []
        self.image: dict[int, bytes] = {}  # DGROUP typed constant image
        self.proc_ids: dict[str, Sym] = {}
        self.system = Scope(None, "System")
        self.cur: Ctx | None = None
        self.unit_scope: UnitScope | None = None
        self.unit: Unit | None = None
        self.out: list[str] = []
        self.ind = 1
        self.cursor_c = FIRST_CONST
        self.cursor_v = VARS_START
        self.stats = {"routines": 0}
        self.errors: list[str] = []
        self.install_base_types()

    def install_base_types(self):
        for t in (P.BYTE, P.SHORTINT, P.INTEGER, P.WORD, P.LONGINT, P.BOOLEAN, P.CHAR, P.REAL, P.SINGLE, P.DOUBLE,
                  P.EXTENDED, P.COMP, P.POINTER, P.STRING255, P.TEXTFILE):
            self.system.add(Sym("type", t.name, type=t))
        self.system.add(Sym("type", "Longint", type=P.LONGINT))
        self.system.add(Sym("type", "File", type=P.ANYFILE))
        self.system.add(Sym("type", "text", type=P.TEXTFILE))
        self.system.add(Sym("type", "string", type=P.STRING255))
        for nm, v in (("MaxInt", 32767), ("MaxLongInt", 2147483647)):
            self.system.add(Sym("const", nm, type=P.INTEGER if nm == "MaxInt" else P.LONGINT, value=v, cname=str(v)))
        for nm, v in (("False", 0), ("True", 1)):
            self.system.add(Sym("enumconst", nm, type=P.BOOLEAN, value=v, cname=str(v)))
        # procedure-pointer and port arrays
        for nm in ("Mem", "MemW", "Port", "PortW"):
            self.system.add(Sym("var", nm, type=P.BYTE, where="special", byref=False, cname=nm))
        self.system.add(Sym("var", "Input", type=P.TEXTFILE, where="special", byref=False, cname="Input"))

    # ---- program ---------------------------------------------------------------------------------------
    def load(self, files):
        nodes = {}
        for f in files:
            n = parse_file(f)
            nodes[n.name.lower()] = n
        rtl = Parser((HERE / "rtl.pas").read_text(), "rtl.pas").parse()
        self.process_rtl(rtl)
        done: set[str] = set()
        visiting: set[str] = set()

        def visit(name):
            k = name.lower()
            if k in done or k in RTL_UNITS or k not in nodes:
                return
            if k in visiting:
                raise TransError("circular uses at " + name)
            visiting.add(k)
            n = nodes[k]
            for u in list(n.uses) + list(getattr(n, "iuses", []) or []):
                visit(u)
            visiting.discard(k)
            done.add(k)
            self.order_nodes.append(n)
        self.order_nodes = []
        for k, n in nodes.items():
            visit(k)
        return nodes

    def process_rtl(self, rtl: N):
        self.unit_scope = self.system
        self.unit = Unit(rtl)
        self.unit.name = "System"
        self.rtl_mode = True
        self.declare(rtl.idecls, self.system, True)
        self.rtl_mode = False
        for s in self.system.syms.values():
            if s.kind == "routine":
                s.rtl = True

    # ---- unit processing -----------------------------------------------------------------------------------
    def process_unit(self, n: N):
        u = Unit(n)
        self.units[n.name.lower()] = u
        self.unit = u
        self.unit_scope = u.scope
        for name in list(n.uses) + list(getattr(n, "iuses", []) or []):
            k = name.lower()
            if k in RTL_UNITS:
                continue
            if k in self.units:
                u.scope.uses.append(self.units[k].iface)
        u.scope.uses.append(self.system)
        u.c.append('#include "game.h"\n')
        self.h.append("\n/* ---- unit %s ---- */" % n.name)
        if n.k == "unit":
            self.declare(n.idecls, u.scope, True, iface=u.iface)
            self.declare(n.decls, u.scope, False)
            self.gen_bodies(n.decls, u)
            if n.init is not None:
                self.gen_init(u, n)
        else:
            self.declare(n.decls, u.scope, False)
            self.gen_bodies(n.decls, u)
            self.gen_main(u, n)
        self.order.append(u)

    # ---- declarations ------------------------------------------------------------------------------------
    def declare(self, decls, scope, is_iface, iface=None):
        for d in decls:
            k = d.k
            if k == "const":
                self.decl_const(d, scope, iface)
            elif k == "typedecl":
                self.decl_type(d, scope, iface)
            elif k == "typedconst":
                self.decl_typedconst(d, scope, iface)
            elif k == "var":
                self.decl_var(d, scope, iface)
            elif k == "routine":
                self.decl_routine_header(d, scope, iface, is_iface)
            elif k == "labels":
                pass
            else:
                raise TransError("declaration %s" % k)

    def put(self, scope, sym, iface):
        scope.add(sym)
        if iface is not None:
            iface.add(sym)

    def decl_const(self, d, scope, iface):
        r = self.ce(d.value, scope)
        if r is None:
            raise TransError("constant %s is not constant (line %d)" % (d.name, d.line))
        v, t = r
        cn = self.unique(d.name, ("const", self.unit.name, d.name), self.unit.name)
        s = Sym("const", d.name, type=t, value=v, cname=cn, unit=self.unit.name)
        self.put(scope, s, iface)
        self.emit_header_comment(d.lead)
        trail = self.trailing(d.trail)
        if isinstance(v, frozenset):
            bits = bytearray(32)
            for x in v:
                bits[x >> 3] |= 1 << (x & 7)
            self.macros.add(cn)
            self.h.append("static const u8 %s[32] = { %s };%s" % (cn, ", ".join(str(b) for b in bits), trail))
        elif isinstance(v, str):
            if len(v) == 1:
                s.type = P.CHAR
                self.h.append("enum { %s = %d };%s" % (cn, ord(v), trail))
            else:
                self.macros.add(cn)
                self.h.append("#define %s S(%s)%s" % (cn, cstr_literal(v), trail))
        elif isinstance(v, float):
            self.macros.add(cn)
            self.h.append("#define %s %r%s" % (cn, v, trail))
        else:
            txt = d.value.text if d.value.k == "int" and d.value.text.startswith("$") else None
            val = ("0x%X" % v) if txt else str(v)
            if v < 0:
                val = "(%d)" % v
            self.h.append("enum { %s = %s };%s" % (cn, val, trail))

    def emit_header_comment(self, lead):
        for c in lead or ():
            self.h.append("/* %s */" % cmt([c.strip()]).replace("\n", "\n   "))

    def decl_type(self, d, scope, iface):
        nm = d.name
        t = self.resolve_type(d.type, scope, nm)
        cn = self.unique(nm, ("type", self.unit.name, nm), self.unit.name)
        if d.type.k == "named":
            base = ctype(t)
            t = copy.copy(t)
            t.name = nm
            t.cname = cn
            t.unit = self.unit.name
            s = Sym("type", nm, type=t, cname=cn, unit=self.unit.name)
            self.put(scope, s, iface)
            self.emit_header_comment(d.lead)
            if not getattr(self, "rtl_mode", False):
                self.h.append("typedef %s %s;%s" % (base, cn, self.trailing(d.trail)))
            return
        t.name = nm
        t.unit = self.unit.name
        s = Sym("type", nm, type=t, cname=cn, unit=self.unit.name)
        self.put(scope, s, iface)
        self.emit_header_comment(d.lead)
        trail = self.trailing(d.trail)
        if getattr(self, "rtl_mode", False):
            t.cname = cn if t.kind != "record" else cn
            return
        self.emit_type(t, cn, scope, trail)

    def emit_enum_members(self, t: Ty, tname: str):
        names = []
        for i, m in enumerate(t.members):
            cn = self.unique(m, ("enum", self.unit.name, m), self.unit.name)
            names.append("%s = %d" % (cn, i))
            sym = Sym("enumconst", m, type=t, value=i, cname=cn, unit=self.unit.name)
            self.unit_scope.add(sym)
            if self.unit.iface is not None:
                self.unit.iface.add(sym)
        self.h.append("enum { %s };" % ", ".join(names))

    def emit_type(self, t: Ty, cn: str, scope, trail=""):
        k = t.kind
        if getattr(t, "pending_enum", False):
            t.pending_enum = False
            self.emit_enum_members(t, cn)
            t.cname = cn
            self.h.append("typedef u8 %s;%s" % (cn, trail))
            return
        if k == "record":
            t.cname = cn
            self.h.append(self.record_text(t, cn) + trail)
            return
        if k in ("ptr", "proc"):
            t.cname = cn
            self.h.append("typedef farptr %s;%s" % (cn, trail))
            return
        # arrays, strings, sets, subranges, aliases: a typedef of the declarator
        t.cname = None
        text = decl(t, cn)
        t.cname = cn
        self.h.append("typedef %s;%s" % (text, trail))

    def record_text(self, t: Ty, cn: str) -> str:
        lines = ["typedef struct %s {" % cn]
        for nm, ft in t.fields:
            self.anon_types(ft, cn + "_" + nm)
            lines.append("  %s;" % decl(ft, self.safe(nm)))
        if t.arms and self.coco:
            # CMOC has no anonymous unions: a named union of named structs; field_path gives the way in
            lines.append("  union {")
            for i, arm in enumerate(t.arms):
                lines.append("    struct {")
                for nm, ft in arm.fields:
                    self.anon_types(ft, cn + "_" + nm)
                    lines.append("      %s;" % decl(ft, self.safe(nm)))
                if arm.arms:
                    lines.append("      union {")
                    for j, sa in enumerate(arm.arms):
                        lines.append("        struct { %s } a%d;" % (" ".join("%s;" % decl(ft, self.safe(nm)) for nm, ft in sa.fields), j))
                    lines.append("      } u;")
                lines.append("    } a%d;" % i)
            lines.append("  } u;")
        elif t.arms:
            lines.append("  union {")
            for i, arm in enumerate(t.arms):
                lines.append("    struct {")
                for nm, ft in arm.fields:
                    self.anon_types(ft, cn + "_" + nm)
                    lines.append("      %s;" % decl(ft, self.safe(nm)))
                for sub in arm.arms:
                    # a nested variant: flattened as an anonymous union of structs
                    lines.append("      union {")
                    for sa in sub.arms if sub.arms else [sub]:
                        lines.append("        struct { %s };" % " ".join("%s;" % decl(ft, self.safe(nm)) for nm, ft in sa.fields))
                    lines.append("      };")
                lines.append("    };")
            lines.append("  };")
        lines.append("} %s;" % cn)
        return "\n".join(lines)

    def anon_types(self, ft: Ty, hint: str):
        """Declare inline records and enums so that C can name them."""
        while ft.kind == "array":
            ft = ft.elem
        if ft.cname is not None:
            return
        if getattr(ft, "pending_enum", False):
            ft.pending_enum = False
            self.emit_enum_members(ft, hint)
            ft.cname = "u8"
        elif ft.kind == "record":
            cn = self.unique(hint, ("type", self.unit.name, hint), self.unit.name)
            ft.cname = cn
            self.h.append(self.record_text(ft, cn))

    def decl_typedconst(self, d, scope, iface):
        t = self.resolve_type(d.type, scope, d.name)
        cn = self.unique(d.name, ("var", self.unit.name, d.name), self.unit.name)
        if self.unit.name.upper() == "POOLVARS":
            off = self.cursor_c
            self.cursor_c += t.size()
            self.check_layout(d.name, off)
            data = self.serialize(t, d.value, scope)
            if len(data) != t.size():
                raise TransError("typed constant %s: %d bytes for %d" % (d.name, len(data), t.size()))
            self.image[off] = data
            s = Sym("var", d.name, type=t, where="macro", cname=cn, offset=off, byref=False, unit=self.unit.name)
            self.define_macro(s, t, off)
            self.put(scope, s, iface)
            return
        raise TransError("typed constant %s outside POOLVARS (line %d)" % (d.name, d.line))

    def check_layout(self, name, off):
        m = LAYOUT_NAME.match(name)
        if m and int(m.group(2), 16) != off:
            raise TransError("layout: %s is at %04X, not where its name says" % (name, off))

    def define_macro(self, s: Sym, t: Ty, off: int):
        self.macros.add(s.cname)
        self.anon_types(t, s.cname + "_T")
        self.h.append("#define %s (*(%s)(pool_ds + 0x%04X))" % (s.cname, ptr_ctype(t), off))

    def decl_var(self, d, scope, iface):
        for nm in d.names:
            t = self.resolve_type(d.type, scope, nm)
            cn = self.unique(nm, ("var", self.unit.name, nm), self.unit.name)
            absolute = d.absolute
            poolvars = self.unit.name.upper() == "POOLVARS" or getattr(self, "rtl_mode", False)
            if absolute is not None:
                s = Sym("var", nm, type=t, cname=cn, byref=False, unit=self.unit.name)
                if absolute.seg is not None:
                    seg = self.const_int(absolute.seg, scope)
                    off = self.const_int(absolute.off, scope)
                    if seg == DS_SEG:
                        s.where, s.offset = "macro", off
                        self.define_macro(s, t, off)
                    else:
                        lin = (seg * 16 + off) & 0xFFFFF
                        s.where = "macro"
                        self.macros.add(cn)
                        self.anon_types(t, cn + "_T")
                        self.h.append("#define %s (*(%s)(pool_arena + 0x%05X))" % (cn, ptr_ctype(t), lin))
                else:
                    base = absolute.off
                    if base.k != "name":
                        raise TransError("absolute expression (line %d)" % d.line)
                    tgt = scope.find(base.name)
                    if tgt is None or tgt.where != "macro" or not hasattr(tgt, "offset"):
                        raise TransError("absolute %s: unknown variable (line %d)" % (base.name, d.line))
                    s.where, s.offset = "macro", tgt.offset
                    self.define_macro(s, t, tgt.offset)
                self.put(scope, s, iface)
                self.emit_header_comment(d.lead)
                continue
            if poolvars:
                off = self.cursor_v
                self.cursor_v += t.size()
                self.check_layout(nm, off)
                s = Sym("var", nm, type=t, where="macro", cname=cn, offset=off, byref=False, unit=self.unit.name)
                self.emit_header_comment(d.lead)
                self.define_macro(s, t, off)
                self.put(scope, s, iface)
                continue
            # a unit-private variable outside DGROUP's modelled part: a C static
            s = Sym("var", nm, type=t, where="static", cname=cn, byref=False, unit=self.unit.name)
            self.anon_types(t, cn + "_T")
            self.unit.c.append("%s;" % decl(t, cn))
            self.put(scope, s, iface)

    def decl_routine_header(self, d, scope, iface, is_iface, parent_ctx=None):
        params = self.resolve_params(d.params, scope)
        ret = self.resolve_type(d.ret, scope) if d.ret is not None else None
        existing = scope.find_local(d.name)
        ext = "@stub" in " ".join(d.lead)
        if existing is not None and existing.kind == "routine" and (existing.node is None or existing.forward) \
                and not getattr(self, "rtl_mode", False):
            s = existing
            if d.params or d.ret is not None:
                s.params = params
                s.ret = ret
            if d.body is not None:
                s.node = d
                s.forward = False
            s.ext = s.ext or ext
            return s
        rtl = getattr(self, "rtl_mode", False)
        if rtl:
            cn = "rtl_" + d.name
        elif parent_ctx is not None:
            cn = self.unique("%s_%s" % (parent_ctx.cname, d.name), ("fn", self.unit.name, d.name), self.unit.name)
        else:
            cn = self.unique(d.name, ("fn", self.unit.name, d.name), self.unit.name)
        s = Sym("routine", d.name, params=params, ret=ret, cname=cn, unit=self.unit.name, node=None,
                nested_in=parent_ctx, static=(not is_iface and parent_ctx is None) or parent_ctx is not None,
                forward=("forward" in d.mods or (d.body is None and not is_iface and not rtl)),
                ext=ext, rtl=rtl)
        if d.body is not None and not is_iface:
            s.node = d
        self.put(scope, s, iface)
        return s

    # ---- bodies ----------------------------------------------------------------------------------------------
    def gen_bodies(self, decls, u: Unit):
        for d in decls:
            if d.k == "routine" and d.body is not None:
                s = u.scope.find_local(d.name)
                self.gen_routine(s, d, None)
            elif d.k == "routine" and d.body is None and "external" in d.mods:
                pass

    def sig_params(self, s: Sym, frame_parent=None, renamed=()):
        parts = []
        if s.nested_in is not None:
            parts.append("struct Frame_%s *up" % s.nested_in.cname)
        if s.ret is not None and s.ret.kind == "string":
            parts.append("u8 *Result_out")
        for p in s.params:
            d = self.param_decl(p)
            if p.name in renamed:
                d = decl(p.type, self.safe(p.name) + "_in")
            parts.append(d)
        return ", ".join(parts) or "void"

    def param_decl(self, p: Sym) -> str:
        t = p.type
        cn = self.safe(p.name)
        if p.byref:
            if t.kind == "untyped":
                return "void *%s" % cn
            return "%s" % decl(t, "(*%s)" % cn)
        k = t.kind
        if k == "string":
            return "const u8 *%s_in" % cn
        if k == "array":
            return "%s" % decl(t, "(*%s_in)" % cn)
        if k == "set":
            return "const u8 *%s_in" % cn
        return decl(t, cn)

    def ret_ctype(self, s: Sym) -> str:
        if s.ret is None:
            return "void"
        if s.ret.kind == "string":
            return "u8 *"
        return decl(s.ret, "")

    def proto(self, s: Sym) -> str:
        pre = "static " if s.static else ""
        return "%s%s%s(%s);" % (pre, self.ret_ctype(s) + ("" if self.ret_ctype(s).endswith("*") else " "), s.cname,
                                self.sig_params(s))

    def scan_addr_locals(self, node, names, found):
        """Local names whose address is taken with @."""
        if isinstance(node, N):
            if node.k == "addr":
                a = node.a
                while a.k in ("field", "index"):
                    a = a.a
                if a.k == "name" and a.name.lower() in names:
                    found.add(a.name.lower())
            for v in node.__dict__.values():
                self.scan_addr_locals(v, names, found)
        elif isinstance(node, (list, tuple)):
            for x in node:
                self.scan_addr_locals(x, names, found)

    def gen_routine(self, s: Sym, node: N, parent: Ctx | None):
        if s.ext:
            self.protos.append(self.proto(s).replace("static ", ""))
            s.proto_done = True
            return
        ctx = Ctx(s.name, parent)
        ctx.cname = s.cname
        s.nested_in = parent
        ctx.scope.parent = parent.scope if parent is not None else self.unit_scope
        ctx.fn = s.ret
        saved = (self.cur, self.out, self.ind)
        self.cur = ctx
        self.out = []
        self.ind = 1
        # parameters
        param_syms = []
        for p in s.params:
            ps = Sym("var", p.name, type=p.type, where="param", owner=ctx, byref=p.byref, cname=self.safe(p.name))
            ps.valparam = (not p.byref) and p.type.kind in ("string", "array", "set")
            ps.mutated = False
            ctx.scope.add(ps)
            param_syms.append(ps)
        if s.ret is not None:
            rs = Sym("var", "Result", type=s.ret, where="local", owner=ctx, byref=False, cname="Result")
            ctx.result_sym = rs
            ctx.result = "Result"
        ctx.param_syms = param_syms
        # local declarations
        local_vars: list[Sym] = []
        nested: list[tuple[Sym, N]] = []
        static_decls: list[str] = []
        local_scope = ctx.scope
        for d in node.decls:
            k = d.k
            if k == "const":
                r = self.ce(d.value, local_scope)
                if r is None:
                    raise TransError("local constant %s (line %d)" % (d.name, d.line))
                v, t = r
                cn = self.unique("%s_%s" % (s.name, d.name), ("const", s.name, d.name), self.unit.name)
                if isinstance(v, str) and len(v) == 1:
                    t = P.CHAR
                    self.h.append("enum { %s = %d };" % (cn, ord(v)))
                elif isinstance(v, str):
                    self.macros.add(cn)
                    self.h.append("#define %s S(%s)" % (cn, cstr_literal(v)))
                elif isinstance(v, float):
                    self.macros.add(cn)
                    self.h.append("#define %s %r" % (cn, v))
                else:
                    self.h.append("enum { %s = %s };" % (cn, "(%d)" % v if v < 0 else v))
                local_scope.add(Sym("const", d.name, type=t, value=v, cname=cn))
            elif k == "typedecl":
                t = self.resolve_type(d.type, local_scope, d.name)
                cn = self.unique("%s_%s" % (s.name, d.name), ("type", s.name, d.name), self.unit.name)
                if d.type.k == "named":
                    t = copy.copy(t)
                t.name = d.name
                local_scope.add(Sym("type", d.name, type=t, cname=cn))
                self.emit_type(t, cn, local_scope)
            elif k == "var":
                for nm in d.names:
                    t = self.resolve_type(d.type, local_scope, nm)
                    self.anon_types(t, "%s_%s" % (s.name, nm))
                    vs = Sym("var", nm, type=t, where="local", owner=ctx, byref=False, cname=self.safe(nm))
                    if d.absolute is not None:
                        vs.arena = True              # reached through a pointer into the variable it overlays
                        vs.alias = d.absolute
                    local_scope.add(vs)
                    local_vars.append(vs)
            elif k == "typedconst":
                t = self.resolve_type(d.type, local_scope, d.name)
                cn = self.unique("%s_%s" % (s.name, d.name), ("var", s.name, d.name), self.unit.name)
                self.anon_types(t, cn + "_T")
                vs = Sym("var", d.name, type=t, where="static", cname=cn, byref=False)
                local_scope.add(vs)
                static_decls.append("static %s = %s;" % (decl(t, cn), self.init_text(t, d.value, local_scope)))
            elif k == "labels":
                for l in d.names:
                    ctx.labels[l] = True
            elif k == "routine":
                ns = self.decl_routine_header(d, local_scope, None, False, parent_ctx=ctx)
                ns.nested_in = ctx
                if d.body is not None:
                    nested.append((ns, d))
            else:
                raise TransError("local declaration %s" % k)
        ctx.has_frame = bool(nested)
        # variables whose address is taken live in the arena stack
        names = {v.name.lower() for v in local_vars}
        found: set[str] = set()
        self.scan_addr_locals(node.body, names, found)
        for v in local_vars:
            if v.name.lower() in found and not getattr(v, "alias", None):
                v.arena = True
                ctx.arena = True
        # nested routines first (they come before the parent in the C file)
        frame_text = ""
        if ctx.has_frame:
            frame_text = self.frame_struct(s, ctx, parent)
            self.unit.c.append(frame_text)
        for ns, nd in nested:
            self.protos_nested(ns)
            self.gen_routine(ns, nd, ctx)
        self.cur = ctx
        self.out = []
        self.ind = 1
        # body
        try:
            self.comment_lines(node.body.lead)
            self.stmts(node.body.stmts)
        except TransError as e:
            self.errors.append("%s.%s: %s" % (self.unit.name, s.name, e))
            self.emit("/* TRANSLATION ERROR: %s */" % str(e).replace("*/", "* /"))
        body_lines = self.out
        # assemble
        text = []
        for c in node.lead:
            if c.strip().startswith("@stub"):
                continue
            body = cmt([c])
            text.append("/* %s */" % body.strip().replace("\n", "\n   "))
        pre = "static " if s.static else ""
        rt = self.ret_ctype(s)
        text.append("%s%s%s%s(%s)" % (pre, rt, "" if rt.endswith("*") else " ", s.cname, self.sig_params(s)))
        text.append("{")
        if parent is None:          # the original's trace names top-level routines only
            text.append('  POOL_TRACE("%s");' % s.name)
        for sd in static_decls:
            text.append("  " + sd)
        zero_stmts = []

        def zero_init(t, name=None):
            if t.kind in ("int", "bool", "char", "enum", "ptr", "proc", "real"):
                return " = 0"
            if self.coco and name is not None:
                # CMOC rejects `= {0}` for arrays of records and records holding arrays: clear after the declarations
                zero_stmts.append("  memset(%s, 0, sizeof(%s));" % (("&" + name) if t.kind != "array" else name, name))
                return ""
            return " = {0}" if t.kind != "array" else " = {0}"
        if ctx.has_frame:
            text.append("  Frame_%s fr;" % s.cname)
            text.append("  memset(&fr, 0, sizeof fr);")
            if parent is not None:
                text.append("  fr.up = up;")
            for ps in param_syms:
                nm = ps.cname
                if ps.byref:
                    text.append("  fr.%s = %s;" % (nm, nm))
                elif ps.type.kind in ("string",):
                    text.append("  rtl_str_assign(fr.%s, %d, %s_in);" % (nm, ps.type.maxlen, nm))
                elif ps.type.kind == "array":
                    text.append("  memcpy(fr.%s, *%s_in, %d);" % (nm, nm, ps.type.size()))
                elif ps.type.kind == "set":
                    text.append("  memcpy(fr.%s, %s_in, %d);" % (nm, nm, ps.type.size()))
                else:
                    text.append("  fr.%s = %s;" % (nm, nm))
            if s.ret is not None and s.ret.kind == "string":
                text.append("  fr.Result = Result_out;")
            if ctx.arena:
                text.append("  u16 stack_mark = rtl_stack_mark();")
            for vs in local_vars:
                if getattr(vs, "alias", None):
                    text.append("  fr.%s = %s;" % (vs.cname, self.alias_init(vs, ctx, scope=local_scope)))
                elif getattr(vs, "arena", False):
                    text.append("  fr.%s = (%s)rtl_stack_alloc(%d);" % (vs.cname, ptr_ctype(vs.type), vs.type.size()))
        else:
            for ps in param_syms:
                nm = ps.cname
                if ps.valparam:
                    if ps.mutated:
                        text.append("  %s;" % decl(ps.type, nm))
                        if ps.type.kind == "string":
                            text.append("  rtl_str_assign(%s, %d, %s_in);" % (nm, ps.type.maxlen, nm))
                        elif ps.type.kind == "array":
                            text.append("  memcpy(%s, *%s_in, %d);" % (nm, nm, ps.type.size()))
                        else:
                            text.append("  memcpy(%s, %s_in, %d);" % (nm, nm, ps.type.size()))
                    else:
                        if ps.type.kind == "array":
                            text.append("  %s = *%s_in;" % (decl(ps.type.elem, "(*%s)" % nm), nm))
                        else:
                            text.append("  const u8 *%s = %s_in;" % (nm, nm))
            if s.ret is not None:
                if s.ret.kind == "string":
                    text.append("  u8 *Result = Result_out;")
                else:
                    text.append("  %s%s;" % (decl(s.ret, "Result"), zero_init(s.ret, "Result")))
            if ctx.arena:
                text.append("  u16 stack_mark = rtl_stack_mark();")      # before the first allocation
            for vs in local_vars:
                if getattr(vs, "alias", None):
                    text.append("  %s = %s;" % (decl(vs.type, "(*%s)" % vs.cname), self.alias_init(vs, ctx, scope=local_scope)))
                elif getattr(vs, "arena", False):
                    text.append("  %s = (%s)rtl_stack_alloc(%d);" % (decl(vs.type, "(*%s)" % vs.cname), ptr_ctype(vs.type), vs.type.size()))
                else:
                    text.append("  %s%s;" % (decl(vs.type, vs.cname), zero_init(vs.type, vs.cname)))
        if ctx.has_frame:
            # locals live in the frame (declared in the struct)
            pass
        elif False:
            pass
        for tdecl in ctx.temps:
            text.append("  %s;" % tdecl)
        text.extend(zero_stmts)
        text.extend(body_lines)
        if ctx.arena:
            text.append("L_exit:")
            text.append("  rtl_stack_release(stack_mark);")
        if s.ret is not None:
            text.append("  return %s;" % ctx.result_ref() if not ctx.arena else "  return %s;" % ctx.result_ref())
        text.append("}")
        self.unit.c.append("\n".join(text) + "\n")
        self.stats["routines"] += 1
        self.cur, self.out, self.ind = saved
        if parent is None and not getattr(s, "proto_done", False):
            self.protos.append(self.proto(s))
            s.proto_done = True

    def alias_init(self, vs: Sym, ctx: Ctx, scope) -> str:
        """The pointer a variable declared `absolute` is reached through."""
        a = vs.alias
        saved = self.cur
        self.cur = ctx
        try:
            if a.seg is not None:
                seg, off = self.const_int(a.seg, scope), self.const_int(a.off, scope)
                return "(%s)(pool_arena + 0x%05X)" % (ptr_ctype(vs.type), (seg * 16 + off) & 0xFFFFF)
            if a.off.k != "name":
                raise TransError("absolute expression")
            r = self.lookup(a.off.name)
            if r is None or r[0] != "sym" or r[1].kind != "var":
                raise TransError("absolute %s: not a variable" % a.off.name)
            return "(%s)&%s" % (ptr_ctype(vs.type), self.var_ref(r[1]))
        finally:
            self.cur = saved

    def protos_nested(self, ns: Sym):
        pass

    def frame_struct(self, s: Sym, ctx: Ctx, parent) -> str:
        lines = ["typedef struct Frame_%s {" % s.cname]
        if parent is not None:
            lines.append("  struct Frame_%s *up;" % parent.cname)
        for p in ctx.param_syms:
            t = p.type
            if p.byref:
                lines.append("  %s;" % (("void *%s" % p.cname) if t.kind == "untyped" else decl(t, "(*%s)" % p.cname)))
            else:
                lines.append("  %s;" % decl(t, p.cname))
        if s.ret is not None:
            lines.append("  %s;" % ("u8 *Result" if s.ret.kind == "string" else decl(s.ret, "Result")))
        for nm, sym in ctx.scope.syms.items():
            if sym.kind == "var" and sym.where == "local":
                if getattr(sym, "arena", False):
                    lines.append("  %s;" % decl(sym.type, "(*%s)" % sym.cname))
                else:
                    lines.append("  %s;" % decl(sym.type, sym.cname))
        lines.append("} Frame_%s;" % s.cname)
        return "\n".join(lines) + "\n"

    def init_text(self, t: Ty, v, scope) -> str:
        k = t.kind
        if isinstance(v, N) and v.k == "arrayval":
            if k != "array":
                raise TransError("array value for %s" % k)
            return "{ %s }" % ", ".join(self.init_text(t.elem, it, scope) for it in v.items)
        if isinstance(v, N) and v.k == "recordval":
            parts = []
            for nm, val in v.items:
                f = self.field_type(t, nm)
                parts.append(".%s = %s" % (self.safe(f[0]), self.init_text(f[1], val, scope)))
            return "{ %s }" % ", ".join(parts)
        r = self.ce(v, scope)
        if r is None:
            raise TransError("typed constant is not constant (line %d)" % v.line)
        val = r[0]
        if k == "string":
            return c_bytes(bytes([len(val)]) + val.encode("latin-1"))
        if isinstance(val, str):
            val = ord(val)
        if k == "real":
            return repr(float(val))
        return str(val) if val >= 0 else "(%d)" % val

    # ---- initialisation parts and the main program -----------------------------------------------------------
    def gen_init(self, u: Unit, n: N):
        s = Sym("routine", "init", params=[], ret=None, cname="init_%s" % u.name, unit=u.name, node=None,
                nested_in=None, static=False, forward=False, ext=False)
        u.init_name = s.cname
        self.taken[s.cname] = ("init", u.name)
        fake = N("routine", name="init", fn=False, params=[], ret=None, mods=[], decls=[], body=n.init, line=0,
                 lead=("Initialisation part of unit %s." % u.name,), trail=())
        self.gen_routine(s, fake, None)

    def gen_main(self, u: Unit, n: N):
        s = Sym("routine", "pool_main", params=[], ret=None, cname="pool_main", unit=u.name, node=None,
                nested_in=None, static=False, forward=False, ext=False)
        fake = N("routine", name="pool_main", fn=False, params=[], ret=None, mods=[], decls=[], body=n.body,
                 line=0, lead=("The main program.",), trail=())
        self.taken["pool_main"] = ("main",)
        self.gen_routine(s, fake, None)
        calls = []
        for name in n.uses:
            k = name.lower()
            if k in self.units and self.units[k].init_name:
                calls.append("  %s();" % self.units[k].init_name)
        u.c.append("void pool_init_units(void)\n{\n%s\n}\n" % "\n".join(calls))
        self.protos.append("void pool_init_units(void);")

    def proc_addresses(self, pids):
        """The far address the original gives each routine whose address the game takes: an overlay routine through its
        stub entry (stub segment + 20h + 5 * entry number), a resident one at its own paragraph; the load segment is
        1000h."""
        import tomllib
        sy = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
        un = tomllib.loads((ROOT / "re/units.toml").read_text())
        stub = {u["id"]: int(u["stub_segment"], 16) for u in un.get("overlay", [])}
        by = {}
        for r in sy:
            by.setdefault((r["unit"], r["name"]), r)
        out = {}
        for p in pids:
            s = self.proc_ids[p]
            r = by.get((s.unit.lower(), s.name))
            if r is None:
                raise TransError("no registry entry for %s.%s" % (s.unit, s.name))
            if r["unit"] in stub:
                import re as _re
                m = _re.search(r"_e(\d+)$", r.get("c_name", ""))
                if not m:
                    raise TransError("%s.%s: no stub entry number" % (s.unit, s.name))
                seg, ofs = stub[r["unit"]] + 0x1000, 0x20 + 5 * int(m.group(1))
            else:
                a, b = r["addr"].split(":")
                seg, ofs = int(a, 16) + 0x1000, int(b, 16)
            out[p] = (seg << 16) | ofs
        return out

    # ---- output --------------------------------------------------------------------------------------------------
    def write(self, outdir: Path):
        outdir.mkdir(parents=True, exist_ok=True)
        cc = None
        if self.coco:
            from p2c_coco import Coco
            cc = Coco()
        hdr = ["/* game.h: generated by tools/c/pas2c.py from the Pascal in src/; do not edit. */",
               "#ifndef GAME_H", "#define GAME_H", '#include "pool.h"', "", "#pragma pack(push, 1)"]
        hdr.extend(self.h)
        hdr.append("#pragma pack(pop)\n")
        pids = sorted(self.proc_ids)
        addrs = self.proc_addresses(pids)
        hdr.append("/* A procedure pointer is the original's far address (overlay stub or resident code, load segment 1000h), so the\n   tables of handlers in DGROUP hold the same words as the original's. */")
        hdr.append("enum { PROC_none = 0, %s };" % ", ".join("PROC_%s = 0x%08XU" % (p, addrs[p]) for p in pids) if pids else "enum { PROC_none = 0 };")
        hdr.append("#define POOL_PROC_COUNT %d" % len(pids))
        hdr.append("typedef struct ProcEntry { u32 id; void (*fn)(void); } ProcEntry;")
        hdr.append("extern const ProcEntry pool_procs[];")
        hdr.extend(self.protos)
        hdr.append("\n#endif")
        htext = "\n".join(hdr) + "\n"
        if cc:
            htext = cc.header(htext)                  # first: it learns the array typedefs and global array macros
        for u in self.order:
            text = "\n".join(u.c)
            (outdir / ("%s.c" % u.name.lower())).write_text(cc.unit(text) if cc else text)
        if cc:
            htext = cc.finish_header(htext)
            self.coco_log = cc.log
        (outdir / "game.h").write_text(htext)
        pt = ['#include "game.h"', "/* sorted by id */", "const ProcEntry pool_procs[POOL_PROC_COUNT + 1] = {"]
        for p in sorted(pids, key=lambda q: addrs[q]):
            pt.append("  {PROC_%s, (void (*)(void))%s}," % (p, self.proc_ids[p].cname))
        pt.append("  {0, 0}")
        pt.append("};")
        pt.append("const u32 pool_proc_count = POOL_PROC_COUNT;")
        (outdir / "proc_table.c").write_text("\n".join(pt) + "\n")
        # the typed constant image
        lo = min(self.image)
        hi = max(o + len(b) for o, b in self.image.items())
        buf = bytearray(hi - lo)
        for o, b in self.image.items():
            buf[o - lo:o - lo + len(b)] = b
        lines = ['#include "pool.h"', "const u32 pool_image_org = 0x%04X;" % lo, "const u32 pool_image_size = %d;" % len(buf),
                 "const u8 pool_image[] = {"]
        for i in range(0, len(buf), 24):
            lines.append("  " + ",".join("0x%02X" % b for b in buf[i:i + 24]) + ",")
        lines.append("};")
        (outdir / "image.c").write_text("\n".join(lines) + "\n")
        gl = []
        for u in self.units.values():
            for sym in u.scope.syms.values():
                if sym.kind == "var" and sym.where == "macro" and hasattr(sym, "offset") and sym.unit == u.name:
                    gl.append("%04X %d %s %s %s" % (sym.offset, sym.type.size(), sym.name, "file" if sym.type.kind == "file" else "-",
                                                    swap_text(sym.type)))
        for sym in self.system.syms.values():
            if sym.kind == "var" and sym.where == "macro" and hasattr(sym, "offset"):
                gl.append("%04X %d %s %s %s" % (sym.offset, sym.type.size(), sym.name, "file" if sym.type.kind == "file" else "-",
                                                swap_text(sym.type)))
        (outdir / "globals.txt").write_text("\n".join(sorted(set(gl))) + "\n")
        return {"units": len(self.order), "routines": self.stats["routines"], "procs": len(pids),
                "image": len(buf)}


def swap_text(ty):
    """the multi-byte scalars of a global as `offset:width:count,...` for tools/mkvm.py's byte order conversion ('-' = none)"""
    try:
        sw = ty.swaps(0)
    except (ValueError, AttributeError):
        return "-"
    return ",".join("%d:%d:%d" % s for s in sw) or "-"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(ROOT / "c/game"))
    ap.add_argument("--profile", choices=("pc", "coco"), default="pc",
                    help="pc: the PC memory model (c/game); coco: C that CMOC reads (step 8.2, tools/c/p2c_coco.py)")
    ap.add_argument("--placement", help="a TOML file placing pointer types: mapped (a native 16-bit address), banked (an accessor), "
                    "engine (default: the PC heap); only with --profile coco (ports/coco3/placement.toml)")
    ap.add_argument("units", nargs="*", help="unit ids to translate (default: all)")
    a = ap.parse_args(argv)
    files = sorted((ROOT / "src").glob("*.PAS"))
    g = Gen()
    g.coco = a.profile == "coco"
    if a.placement:
        import tomllib
        pl = tomllib.loads(Path(a.placement).read_text())
        g.placement = {"mapped": {t.lower() for t in pl.get("mapped", {}).get("types", [])},
                       "banked": {t.lower() for t in pl.get("banked", {}).get("types", [])},
                       "fields": {k.lower(): v.lower() for k, v in pl.get("pointer_fields", {}).items()}}
    g.load(files)
    # every global constant and enumeration member of every unit: a local or parameter of the same spelling would shadow
    # it in C, which CMOC mishandles (a one byte parameter BottomRow, shadowing the constant BottomRow = 24, was stored as
    # a word); such locals get an underscore (safe())
    for n in g.order_nodes:
        for decls in (getattr(n, "idecls", None) or [], getattr(n, "decls", None) or []):
            for d in decls:
                if d.k == "const":
                    g.global_const_names.add(d.name)
                elif d.k == "typedecl" and getattr(d.type, "k", None) == "enum":
                    g.global_const_names.update(d.type.names)
    errors = 0
    for n in g.order_nodes:
        try:
            g.process_unit(n)
        except TransError as e:
            print("%s: %s" % (n.name, e), file=sys.stderr)
            errors += 1
            if not a.units:
                break
    for e in g.errors:
        print(e, file=sys.stderr)
    if errors:
        return 1
    print(g.write(Path(a.out)), "errors:", len(g.errors))
    if g.coco:
        print("coco profile:", {k: v for k, v in g.coco_log.items() if v})
    if g.placement:
        rep = sorted(g.engine_derefs.items(), key=lambda kv: -kv[1])
        Path(a.out, "placement-report.txt").write_text("".join("%5d %s dereferences %s (engine class) \n" % (c, u, t) for (u, t), c in rep))
        print("placement: %d dereferences of engine-class blocks by game logic (placement-report.txt)" % sum(c for _, c in rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())

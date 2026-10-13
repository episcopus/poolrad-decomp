#!/usr/bin/env python3
"""match.py: prove decompiled Pascal against the original machine code (SPEC 8.3, playbook 30).

  .venv/bin/python tools/match/match.py UNIT [--routine NAME ...] [--write]
  .venv/bin/python tools/match/match.py --all [--write]     every unit that has source with a decompiled routine
  make match UNIT=res04 [FN=res04_fn_0059] [WRITE=1]           (no UNIT: --all; `make check` runs --all)

The unit's source `src/<UNIT>.PAS` and every other `src/*.PAS` are compiled with the pinned Turbo
Pascal 6.0 (tools/re/tp_toolchain.py) inside a generated program that references each routine. The
code of each decompiled routine (and the literal pool the compiler puts right before it: string and set
constants) is then compared with the original's bytes, instruction by instruction.

Every byte must be equal except address fields, and an address field must name the same thing on both
sides:

  global        a DS operand (memory displacement or immediate): our variable V plus delta d must be
                the original's offset of V plus d. V's original offset comes from re/dseg.toml (by name)
                or from the name itself: `dsXXXX` is DS:XXXX. A global declared in an interface of src/
                as `V: T absolute W` (W another global) has W's original offset (absolute_aliases()):
                the map lists V and W at one address in an order that changes with the layout.
  routine       a near call inside the unit or a far call: our target's name (a routine of re/symbols.toml
                by name, or `resNN_fn_XXXX` / `ovlNN_fn_XXXX` / `resNN_init`) must be the original target
                (runtime library targets are identified through tp_toolchain.runtime_names).
  literal       an offset into the code segment (a string or set constant): same distance from the entry
                on both sides, and the pool bytes are compared as they are.
  routine ofs   `mov ax, ofs; mov dx, seg` of a routine in another unit (`ds6B84 := @ovl22_e4`).
                The offset moves by the padding procedure, like an offset in this unit. It names the
                public at that offset in the segment the following relocated word selects. The original's
                word is that routine's address (an overlay stub offset for an overlay unit).
  segment       a segment fixup: the same unit (or DGROUP) on both sides.

An immediate counts as an address only if it moves when the layout moves: the unit is compiled a
second time with padding inserted into every unit of ours (data and code), and the fields that change
are the address fields. Constants never move.

A unit with no `{@stub}` routines is also compared as a whole: routines, pools, the initialization part
and the paragraph padding cover the original segment exactly.

`--write` records level L2 (matched) for each matched routine in re/symbols.toml (only tools write
levels, AGENTS.md rule 2) and prints where re/symbols.toml's boundaries disagree with the compiler's.

Nested routines have no map symbol; TP 6.0 puts their code in the parent's pre-entry region. A range
proven nested by nested_routines() is compared instruction by instruction, with the same address
resolution as a top-level routine; every other pre-entry byte stays byte-exact
(escalate-res06-20261012110841). A matched parent proves a nested routine (reported `NESTED`, L2 with
a note saying so) only by the strict rule of nested_routines(): called as `push bp; push cs; call`
from the parent or an already proven nested routine, and wholly inside that region
(escalate-general-20261012012957).

Conventions for the sources (playbook 30): one file per original unit, named after its id (RES04.PAS
is unit RES04); every routine is declared in the interface (the map lists only interface symbols);
top-level routine headers start in column 1, nested ones are indented; a routine not decompiled yet is
a stub with the right signature and an empty body, marked `{@stub}` at the start of its header line;
globals whose owning unit is not known yet live in POOLVARS.PAS.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))

from capstone import Cs, CS_ARCH_X86, CS_MODE_16  # noqa: E402
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_REG_BP, X86_REG_CS, X86_REG_DS, X86_REG_ES, X86_REG_SS  # noqa: E402

import tp_toolchain as tp  # noqa: E402

SRC = ROOT / "src"
BUILD = ROOT / "build/match"
RTL_UNITS = ("SYSTEM", "CRT", "DOS", "OVERLAY")
DATA_PAD = 64                      # bytes of padding variable per unit in variant B
CODE_PAD = 5                       # `procedure P; begin end;` = push bp; mov bp,sp; pop bp; retf
NAME_RE = re.compile(r"^(res|ovl)(\d\d)_(?:fn_([0-9a-f]{4})|init)$", re.I)
DS_RE = re.compile(r"^ds([0-9a-f]{4})$", re.I)
STUB_INIT = "{@stub-init}"          # on the line before the `begin` of an initialisation part not decompiled yet
HEADER_RE = re.compile(r"^(\{@stub\}\s*)?(procedure|function)\s+([A-Za-z_][A-Za-z0-9_]*)", re.I | re.M)


class MatchError(Exception):
    pass


# --------------------------------------------------------------------------- the original
class Original:
    """The original program: unit segments, routine ids and names, DGROUP names."""

    def __init__(self):
        self.image, self.relocs = tp.read_mz(tp.EXE)
        units = tomllib.loads((ROOT / "re/units.toml").read_text())
        self.units = {u["id"]: u for u in units["resident"] + units["overlay"]}
        # The main program (POOL.PAS): segment 0000 up to the first overlay stub segment (entry 0000:0006).
        first_stub = min(int(u["stub_segment"], 16) for u in units["overlay"])
        self.units["main"] = {"id": "main", "name": "POOL (main program)", "kind": "program",
                              "code_start": "0000:0000", "code_bytes": first_stub * 16, "init": ""}
        self.routines = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
        self.by_name = {r["name"].upper(): r for r in self.routines}
        self.by_id = {r["id"]: r for r in self.routines}
        self.globals = {g["name"].upper(): g["offset"]
                        for g in tomllib.loads((ROOT / "re/dseg.toml").read_text()).get("global", [])}
        self.stub_entry: dict[tuple[int, int], str] = {}
        self.stub_unit: dict[int, str] = {}
        man = json.loads((ROOT / "build/re/overlays.json").read_text())
        stub_seg = {u["id"]: int(u["stub_segment"], 16) for u in units["overlay"]}
        self.stub_seg = stub_seg
        self.stub_unit = {v: k for k, v in stub_seg.items()}
        for o in man["overlays"]:
            uid = "ovl%02d" % o["overlay"]
            for e in o["entries"]:
                self.stub_entry[(stub_seg[uid], e["stub_offset"])] = "%s:%04X" % (uid, e["code_offset"])
        self.res_ranges = []
        for u in units["resident"]:
            a = int(u["code_start"].split(":")[0], 16)
            b = int(u["code_end"].split(":")[0], 16)
            self.res_ranges.append((a, b, u["id"]))
        # An external object file (`{$L X.OBJ}`, code Turbo Pascal links after the initialisation part):
        # from `external_from` to the end of the unit the bytes are not Pascal and stay as the original's.
        self.external = {uid: int(u["external_from"].split(":")[1], 16)
                         for uid, u in self.units.items() if u.get("external_from")}

    def external_names(self, uid: str) -> set[str]:
        """Upper-case names of the unit's routines inside its external object (registry `external = true`,
        or an address at or after `external_from`)."""
        ext = self.external.get(uid)
        out = set()
        for r in self.routines:
            if r["unit"] != uid:
                continue
            off = int(r["addr"].split(":")[1], 16)
            if r.get("external") or (ext is not None and off >= ext):
                out.add(r["name"].upper())
        return out

    def segment(self, uid: str) -> tuple[bytes, int | None]:
        """(code bytes of the unit, paragraph of the unit in the image or None for an overlay)."""
        u = self.units[uid]
        if "code_start" in u:
            seg = int(u["code_start"].split(":")[0], 16)
            return self.image[seg * 16: seg * 16 + u["code_bytes"]], seg
        p = ROOT / "build/re/overlays" / (uid + ".bin")
        if not p.exists():
            raise MatchError("build/re/overlays/%s.bin missing: run `make overlays`" % uid)
        return p.read_bytes(), None

    def routine_id(self, uid: str, off: int) -> str:
        if "code_start" in self.units[uid]:
            return "%s:%04X" % (self.units[uid]["code_start"].split(":")[0].upper(), off)
        return "%s:%04X" % (uid, off)

    def id_of_name(self, name: str) -> str | None:
        r = self.by_name.get(name.upper())
        if r is not None:
            return r["id"]
        m = NAME_RE.match(name)
        if not m:
            return None
        uid = "%s%s" % (m.group(1).lower(), m.group(2))
        if uid not in self.units:
            return None
        if m.group(3) is None:                      # resNN_init
            init = self.units[uid].get("init", "")
            return init.upper() if uid.startswith("res") else None
        return self.routine_id(uid, int(m.group(3), 16))

    def far_target(self, seg: int, off: int) -> str:
        if (seg, off) in self.stub_entry:
            return self.stub_entry[(seg, off)]
        return "%04X:%04X" % (seg, off)

    def segment_unit(self, seg: int) -> str:
        if seg == tp.DGROUP_PARA:
            return "DATA"
        if seg in self.stub_unit:                    # an overlay is reached through its stub segment
            return self.stub_unit[seg]
        for a, b, uid in self.res_ranges:
            if a <= seg < b:
                return uid
        return "%04X" % seg

    def init_id(self, uid: str) -> str | None:
        if uid.startswith("res"):
            init = self.units[uid].get("init", "")
            return init.upper() or None
        r = self.by_name.get(("%s_init" % uid).upper())
        return r["id"] if r else None

    def code_address(self, uid: str, value: int) -> str | None:
        """The routine an address immediate names: an entry of the unit, or of its overlay stub."""
        if uid.startswith("ovl"):
            return self.stub_entry.get((self.stub_seg[uid], value))
        return self.routine_id(uid, value)

    def global_offset(self, name: str) -> int | None:
        if name.upper() in self.globals:
            return self.globals[name.upper()]
        m = DS_RE.match(name)
        return int(m.group(1), 16) if m else None


# --------------------------------------------------------------------------- our build
@dataclass
class Build:
    img: bytes
    relocs: set
    segs: dict
    pubs: dict
    lines: dict = field(default_factory=dict)        # unit segment name -> sorted [(offset, line)]
    rtl: dict = field(default_factory=dict)
    sources: dict = field(default_factory=dict)      # unit name -> the text compiled (padded in variant B)
    entry: tuple = (0, 0)                            # program entry point (segment, offset)
    _aliases: dict | None = None

    def init_entry(self, segname: str) -> int | None:
        """Offset of the unit's initialisation part in its segment: its first source line's code."""
        text = self.sources.get(segname)
        line = init_begin_line(text) if text else None
        if line is None:
            return None
        rows = [o for o, l in self.lines.get(segname, []) if l >= line]
        return min(rows) if rows else None

    def seg_start(self, name: str) -> int:
        return self.segs[name][0]

    def seg_of_para(self, para: int) -> str | None:
        for name, (start, length, cls) in self.segs.items():
            if cls == "CODE" and length and start >> 4 == para:     # empty segments share an address
                return name
        if self.segs.get("DATA") and self.segs["DATA"][0] >> 4 == para:
            return "DATA"
        return None

    def public_at(self, segname: str, off: int) -> str | None:
        para = self.segs[segname][0] >> 4
        for n, (s, o) in self.pubs.items():
            if s == para and o == off:
                return n
        return None

    def aliases(self) -> dict[str, str]:
        """{ALIAS: BASE} of the `absolute` declarations of the compiled sources (absolute_aliases)."""
        if self._aliases is None:
            self._aliases = {}
            for text in self.sources.values():
                self._aliases.update(absolute_aliases(text))
        return self._aliases

    def data_var(self, off: int) -> tuple[str, int] | None:
        para = self.segs["DATA"][0] >> 4
        best = None
        for n, (s, o) in self.pubs.items():
            if s == para and o <= off and (best is None or o > best[1]):
                best = (n, o)
        return (best[0], off - best[1]) if best else None


PROGRAM = "POOL"                    # src/POOL.PAS, the main program (matched as unit "main")


def all_sources() -> dict[str, str]:
    return {p.stem.upper(): p.read_text() for p in sorted(SRC.glob("*.PAS"))}


def unit_sources() -> dict[str, str]:
    """The units of src/ (the main program excluded)."""
    return {n: t for n, t in all_sources().items() if not re.match(r"\s*program\b", t, re.I)}


def init_begin_line(text: str) -> int | None:
    """1-based line of the `begin` of the unit's initialisation part (column 1 by convention), or None.
    Scanning up from `end.`: a column-1 `begin` first means an initialisation part; a column-1 `end;`
    first means the file ends with a routine."""
    lines = text.split("\n")
    last = max((i for i, l in enumerate(lines) if re.match(r"end\.", l, re.I)), default=None)
    if last is None:
        return None
    for i in range(last - 1, -1, -1):
        if re.match(r"begin\b", lines[i], re.I):
            return i + 1
        if re.match(r"end;", lines[i], re.I):
            return None
    return None


COMMENT_RE = re.compile(r"\{[^}]*\}|\(\*.*?\*\)", re.S)
ABSOLUTE_RE = re.compile(r"^\s*(?:var\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:[^:]*?\babsolute\s+"
                         r"([A-Za-z_]\w*)\s*$", re.I | re.S)


def absolute_aliases(text: str) -> dict[str, str]:
    """{ALIAS: BASE} for each global of the unit's interface declared `ALIAS: T absolute BASE`, BASE a
    variable (TP 6.0 gives ALIAS BASE's address: `absolute <variable>` takes no offset). An `absolute`
    on a fixed segment:offset (`absolute $B800:$0000`, res09) is not an alias and is left out."""
    text = COMMENT_RE.sub(" ", text)
    m = re.search(r"^\s*interface\b(.*?)^\s*implementation\b", text, re.I | re.M | re.S)
    if not m:
        return {}
    out = {}
    for stmt in m.group(1).split(";"):
        d = ABSOLUTE_RE.match(stmt)
        if d:
            for name in d.group(1).split(","):
                out[name.strip().upper()] = d.group(2).upper()
    return out


def routines_of(text: str) -> list[tuple[str, bool]]:
    """(name, is_stub) of every top-level routine in the implementation part, in order."""
    m = re.search(r"^\s*implementation\b", text, re.I | re.M)
    if not m:
        raise MatchError("no implementation part")
    return [(h.group(3), bool(h.group(1))) for h in HEADER_RE.finditer(text, m.end())]


def with_pads(name: str, text: str) -> str:
    """Variant B: a padding variable and a padding procedure first in the unit."""
    def after(keyword: str, insert: str, s: str) -> str:
        m = re.search(r"^\s*%s\b\s*(uses\b[^;]*;)?" % keyword, s, re.I | re.M)
        if not m:
            raise MatchError("%s: no %s part" % (name, keyword))
        return s[:m.end()] + "\n" + insert + "\n" + s[m.end():]
    text = after("interface", "var MPadV%s: array[0..%d] of Byte; procedure MPadC%s;" % (name, DATA_PAD - 1, name),
                 text)
    return after("implementation", "procedure MPadC%s; begin end;" % name, text)


def compile_variant(units: list[str], sources: dict[str, str], pads: bool, out: Path,
                    program: str | None = None) -> Build:
    """Compile every unit of `sources` (padded in variant B) inside a generated program that references
    each routine of `units`, or, with `program`, that program itself (the main program)."""
    ver = tp.pinned_version()
    bin_dir = tp.TC / ver / "BIN"
    if not (bin_dir / "TPC.EXE").exists():
        raise MatchError("Turbo Pascal %s not installed: `make tp-pin` (docs/setup/SETUP-tp.md)" % ver)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for f in ("TPC.EXE", "TURBO.TPL"):
        shutil.copy(bin_dir / f, out / f)
    refs = []
    for name, text in sources.items():
        (out / (name + ".PAS")).write_text(with_pads(name, text) if pads else text)
        if pads:                                 # referenced, or the smart linker drops them
            refs += ["@MPadC%s" % name, "@MPadV%s" % name]
    for unit in units:
        refs += ["@%s" % n for n, _stub in routines_of(sources[unit.upper()])]
    if program is None:
        main = "MATCH"
        prog = ["program MATCH;", "{$F+,S-,R-,G-,I-}", "uses"] + ["  %s%s" % (n, "," if k < len(sources) - 1 else ";")
                                                                  for k, n in enumerate(sources)]
        prog += ["var P: Pointer;", "begin"]              # one unit per line: TP lines end at 127 characters
        if pads:                                         # the pads are not referenced by a real program
            prog += ["  P := %s;" % r for r in refs if r.startswith("@MPad")]
        prog += ["  P := %s;" % r for r in refs if not r.startswith("@MPad")] + ["end."]
        (out / "MATCH.PAS").write_text("\r\n".join(prog) + "\r\n")
    else:
        main = PROGRAM                                   # compiled as written (variant A only)
        (out / (main + ".PAS")).write_text(program)
    kind, emu = tp.find_emulator(None)
    log = tp.run_tpc(kind, emu, out, ["/B", "/GD", main + ".PAS"])
    exe, mapf = tp.ci(out, main + ".EXE"), tp.ci(out, main + ".MAP")
    if exe is None or mapf is None or "Error" in log:
        errs = "\n".join(re.findall(r"\w+\.PAS\(\d+\): Error[^\n]*", log))   # not the progress lines
        raise MatchError("compile failed%s:\n%s" % (" (variant B)" if pads else "", errs or log))
    img, relocs = tp.read_mz(exe)
    segs, pubs = tp.read_map(mapf)
    b = Build(img, relocs, segs, pubs)
    b.sources = {n: (with_pads(n, t) if pads else t) for n, t in sources.items()}
    text = mapf.read_text(errors="replace")
    m = re.search(r"Program entry point at ([0-9A-F]{4}):([0-9A-F]{4})", text)
    if m:
        b.entry = (int(m.group(1), 16), int(m.group(2), 16))
    for blk in re.finditer(r"Line numbers for (\w+)\([^)]*\) segment (\w+)\s*\n((?:\s*\d+ [0-9A-F]{4}:[0-9A-F]{4})+)",
                           text):
        rows = [(int(m.group(2), 16), int(m.group(1)))
                for m in re.finditer(r"(\d+) [0-9A-F]{4}:([0-9A-F]{4})", blk.group(3))]
        b.lines[blk.group(2).upper()] = sorted(rows)
    b.rtl = tp.runtime_names(img, segs)
    return b


# --------------------------------------------------------------------------- compare
@dataclass
class Region:
    name: str
    entry: int          # offset of the entry in the unit segment (ours)
    pool: int           # bytes of literal pool before the entry
    end: int            # end of the code (after the ret)


@dataclass
class Result:
    name: str
    id: str | None
    status: str                  # matched, differs, stub, missing
    detail: str = ""
    size: int = 0                # code bytes from the entry
    pool: int = 0
    symbols: int = 0


md = Cs(CS_ARCH_X86, CS_MODE_16)
md.detail = True


def return_end(seg_bytes: bytes, entry: int, limit: int) -> int | None:
    """End of the routine's code in `seg_bytes` (a whole segment): the first return at or after every
    forward jump target seen so far (Turbo Pascal emits one epilogue; `exit` and loops jump to it)."""
    reach = entry
    for i in md.disasm(seg_bytes[entry:limit], entry):
        if i.group(1) or i.mnemonic.startswith("loop") or i.mnemonic == "jcxz":      # 1 = CS_GRP_JUMP
            for op in i.operands:
                if op.type == X86_OP_IMM and entry <= op.imm < limit:
                    reach = max(reach, op.imm)
        if i.mnemonic in ("ret", "retf", "iret") and i.address >= reach:
            return i.address + i.size
    return None


def code_end(b: Build, seg: str, entry: int, limit: int) -> int:
    start = b.seg_start(seg)
    end = return_end(b.img[start: start + limit], entry, limit)
    if end is None:
        raise MatchError("%s+%04X: no return instruction found" % (seg, entry))
    return end


def pad_proc(unit: str) -> str:
    """Variant B's padding procedure of `unit` (with_pads): first in the segment, never one of ours."""
    return "MPadC%s" % unit.upper()


def regions(b: Build, unit: str, names: list[str], pad: str | None = None) -> list[Region]:
    seg = unit.upper()
    if seg not in b.segs:
        raise MatchError("unit %s is not in the compiled program" % unit)
    seglen = b.segs[seg][1]
    entries = []
    for n in names:
        if n.upper() not in b.pubs:
            raise MatchError("%s is not in the map: declare it in the interface" % n)
        entries.append((b.pubs[n.upper()][1], n))
    if pad is not None:                              # variant B: the padding procedure comes first
        entries.append((b.pubs[pad.upper()][1], pad))
    entries.sort()
    out, prev = [], 0
    for k, (e, n) in enumerate(entries):
        nxt = entries[k + 1][0] if k + 1 < len(entries) else seglen
        end = code_end(b, seg, e, nxt)
        out.append(Region(n, e, e - prev, end))
        prev = end
    return out


def init_region(b: Build, unit: str, after: int, pad: str | None = None) -> Region | None:
    """The initialization part: the first line-numbered code at or after `after`. In variant B, `pad`
    (pad_proc) is skipped exactly as regions() skips it: in a unit with no interface routines the padding
    procedure is the first code of the segment and would otherwise be taken for the init part."""
    seg = unit.upper()
    seglen = b.segs[seg][1]
    if pad is not None:
        after = max(after, regions(b, unit, [], pad=pad)[0].end)
    lines = [o for o, _l in b.lines.get(seg, []) if o >= after]
    if not lines:
        return None
    entry = min(lines)
    return Region("%s_init" % unit.lower(), entry, entry - after, code_end(b, seg, entry, seglen))


PUSH_BP, PUSH_CS, CALL_NEAR = 0x55, 0x0E, 0xE8


def nested_routines(seg_bytes: bytes, region_start: int, parent_entry: int,
                    parent_end: int) -> dict[int, tuple[int, int]]:
    """Nested routines of a matched parent, proven by the parent's match: {entry: (end, caller entry)}.

    Turbo Pascal 6.0 puts a nested routine's code before its parent's body, inside the parent's
    pre-entry region [region_start, parent_entry). The matcher compares a proven nested range
    instruction by instruction and keeps every other pre-entry byte exact. The map has no symbol
    for it, so its entry is proven by how it is called. A routine counts only when ALL hold (operator
    decision on escalation escalate-general-20261012012957, the strict rule):
      1. its entry is the target of a near call inside the parent, or inside a nested routine already
         proven this way; with {$F+} (every unit) TP 6.0 calls a nested routine as `push cs; call near`
         (probe: `make tpc` of a parent with nested routines; ovl26:01D7 calls ovl26:00C7 the same way);
      2. that call is preceded by the static link push `push bp`, so the bytes are 55 0E E8 rel16;
         a sibling call pushes the caller's own static link (`push word ptr [bp+6]`) and does not count;
      3. the routine, from its entry to its return, lies wholly inside the pre-entry region.
    Never by address range alone: the region also holds string and set literals."""
    found: dict[int, tuple[int, int]] = {}
    work = [(parent_entry, parent_end)]
    while work:
        start, end = work.pop()
        prev: list = []
        for i in md.disasm(seg_bytes[start:end], start):
            if (i.bytes[0] == CALL_NEAR and i.size == 3 and len(prev) >= 2
                    and bytes(prev[-1].bytes) == bytes([PUSH_CS]) and bytes(prev[-2].bytes) == bytes([PUSH_BP])):
                target = (i.address + 3 + int.from_bytes(i.bytes[1:3], "little", signed=True)) & 0xFFFF
                if region_start <= target < parent_entry and target not in found:
                    t_end = return_end(seg_bytes[:parent_entry], target, parent_entry)
                    if t_end is not None and t_end <= parent_entry:
                        found[target] = (t_end, start)
                        work.append((target, t_end))
            prev.append(i)
    return found


def original_global(orig: Original, aliases: dict[str, str], name: str) -> int:
    """The original's offset of our global `name`. A global declared `absolute` on another global (an
    alias, absolute_aliases()) has its base's offset, found the same way: the map lists both names at one
    address in an order that depends on the layout, so the name data_var() finds there may be either."""
    seen = [name.upper()]
    while seen[-1] in aliases:
        base = aliases[seen[-1]]
        if base in seen:
            raise MatchError("global %s: `absolute` declarations form a cycle (%s)" % (name, " -> ".join(seen + [base])))
        seen.append(base)
    off = orig.global_offset(seen[-1])
    if off is None:
        if len(seen) > 1:
            raise MatchError("global %s is declared absolute %s, which has no original offset: name it dsXXXX or "
                             "add it to re/dseg.toml" % (name, seen[-1]))
        raise MatchError("global %s has no original offset: name it dsXXXX or add it to re/dseg.toml" % name)
    for alias in seen[:-1]:                          # an alias with an offset of its own must agree
        own = orig.global_offset(alias)
        if own is not None and own != off:
            raise MatchError("global %s is declared absolute %s, but re/dseg.toml gives it DS:%04X, not DS:%04X"
                             % (alias, seen[-1], own, off))
    return off


class Comparer:
    def __init__(self, orig: Original, unit: str, a: Build, b: Build, regs_a: dict, regs_b: dict):
        self.orig, self.unit, self.a, self.b = orig, unit, a, b
        self.ra, self.rb = regs_a, regs_b
        self.obytes, self.opara = orig.segment(unit)
        self.seg = PROGRAM if unit == "main" else unit.upper()

    # --- symbol resolution, ours -> what the original must hold
    def expect_global(self, build: Build, value: int) -> tuple[int, str] | None:
        hit = build.data_var(value)
        if hit is None:
            return None
        name, delta = hit
        off = original_global(self.orig, build.aliases(), name)
        return off + delta, "%s+%d" % (name, delta) if delta else name

    def expect_routine(self, build: Build, segname: str, off: int) -> str:
        if segname in RTL_UNITS:
            name = build.rtl.get((build.segs[segname][0] >> 4, off))
            m = re.search(r"POOL ([0-9A-F]{4}:[0-9A-F]{4})", name or "")
            if not m:
                raise MatchError("call into %s+%04X: no POOL routine corresponds (runtime routine POOL never "
                                 "uses: wrong library call?)" % (segname, off))
            return m.group(1)
        name = build.public_at(segname, off)
        if name is None and off == build.init_entry(segname):
            init = self.orig.init_id(segname.lower())    # the main program calls every initialisation part
            if init is None:
                raise MatchError("call to the initialisation part of %s, which the original does not have" % segname)
            return init
        if name is None:
            raise MatchError("call into %s+%04X: not a routine entry in the map" % (segname, off))
        rid = self.orig.id_of_name(name)
        if rid is None:
            raise MatchError("routine %s: not in re/symbols.toml and not named resNN_fn_XXXX / ovlNN_fn_XXXX" % name)
        return rid

    # --- one region
    def compare(self, ra: Region, rb: Region, orig_entry: int) -> tuple[bool, str, int]:
        base_a = self.a.seg_start(self.seg)
        base_b = self.b.seg_start(self.seg)
        A = self.a.img[base_a + ra.entry - ra.pool: base_a + ra.end]
        B = self.b.img[base_b + rb.entry - rb.pool: base_b + rb.end]
        o0 = orig_entry - ra.pool
        if o0 < 0 or orig_entry + (ra.end - ra.entry) > len(self.obytes):
            return False, "the original segment is too short here", 0
        O = self.obytes[o0: orig_entry + (ra.end - ra.entry)]
        if len(A) != len(B):
            return False, "our code changes length with the layout (%d vs %d bytes)" % (len(A), len(B)), 0
        symbols = 0
        if A[:ra.pool] != O[:ra.pool]:
            ok, why, n = self.pre_entry(A, B, O, ra, orig_entry)
            if not ok:
                return False, why, n
            symbols += n
        insns_a = list(md.disasm(A[ra.pool:], ra.entry))
        insns_o = {i.address: i for i in md.disasm(O[ra.pool:], ra.entry)}
        if sum(i.size for i in insns_a) != len(A) - ra.pool:
            return False, "our code does not disassemble cleanly", 0
        for ia in insns_a:
            p = ra.pool + (ia.address - ra.entry)
            sa, so, sb = A[p:p + ia.size], O[p:p + ia.size], B[p:p + ia.size]
            io = insns_o.get(ia.address)
            if sa == so:
                continue
            if io is None or io.size != ia.size or io.bytes[0] != ia.bytes[0]:
                return False, self.diff(ia, io, "instruction differs"), symbols
            ok, why, n = self.fields(ia, io, sa, so, sb, ra, orig_entry, p)
            symbols += n
            if not ok:
                return False, self.diff(ia, io, why), symbols
        return True, "", symbols

    def pre_entry(self, A: bytes, B: bytes, O: bytes, ra: Region, orig_entry: int) -> tuple[bool, str, int]:
        """Compare the parent's pre-entry bytes. Proven nested ranges use fields(); the rest stay exact.

        Only ranges nested_routines() proves from the original parent are carved out. A nested range
        with a wrong global or a wrong callee fails here, the same way a top-level routine does.
        """
        region_start = orig_entry - ra.pool
        body_end = orig_entry + (len(A) - ra.pool)
        found = nested_routines(self.obytes, region_start, orig_entry, body_end)
        spans = []
        for entry, (end, _caller) in sorted(found.items()):
            a, b = entry - region_start, end - region_start
            if 0 <= a < b <= ra.pool:
                spans.append((a, b, entry))
        nested_ours = {entry: (ra.entry - ra.pool) + (entry - region_start) for entry, _rest in found.items()}
        covered = bytearray(ra.pool)
        symbols = 0
        for a, b, entry in spans:
            ok, why, n = self.compare_slice(A[a:b], B[a:b], O[a:b], entry, nested_ours)
            if not ok:
                return False, why, symbols + n
            symbols += n
            covered[a:b] = b"\x01" * (b - a)
        for i in range(ra.pool):
            if not covered[i] and A[i] != O[i]:
                return False, "literal pool byte %d before the entry: ours %02X, original %02X" % (
                    ra.pool - i, A[i], O[i]), symbols
        return True, "", symbols

    def compare_slice(self, sa_all: bytes, sb_all: bytes, so_all: bytes, entry: int,
                      nested_ours: dict[int, int]) -> tuple[bool, str, int]:
        """Instruction-compare one proven nested range.

        `entry` is the original address. Both sides are disassembled at our address (nested_ours),
        the same way compare() disassembles a top-level body at our entry, so a near call's target
        is an address in our build and fields() can name it."""
        ours_entry = nested_ours[entry]
        insns_a = list(md.disasm(sa_all, ours_entry))
        insns_o = {i.address: i for i in md.disasm(so_all, ours_entry)}
        if sum(i.size for i in insns_a) != len(sa_all) or len(sb_all) != len(sa_all):
            return False, "nested routine at %04X does not disassemble cleanly" % entry, 0
        ra = Region("nested", ours_entry, 0, ours_entry + len(sa_all))
        symbols = 0
        for ia in insns_a:
            p = ia.address - ours_entry
            sa, so, sb = sa_all[p:p + ia.size], so_all[p:p + ia.size], sb_all[p:p + ia.size]
            io = insns_o.get(ia.address)
            if sa == so:
                continue
            if io is None or io.size != ia.size or io.bytes[0] != ia.bytes[0]:
                return False, self.diff(ia, io, "nested instruction differs"), symbols
            ok, why, n = self.fields(ia, io, sa, so, sb, ra, entry, p, nested_ours)
            symbols += n
            if not ok:
                return False, self.diff(ia, io, why), symbols
        return True, "", symbols

    def fields(self, ia, io, sa, so, sb, ra: Region, orig_entry: int, p: int, nested_ours=None):
        """Check that every differing byte of one instruction is an address field naming the same thing."""
        covered = set()
        n = 0
        op0 = sa[0]
        # near call: E8 rel16 to another routine of the unit
        if op0 == 0xE8:
            ta = (ia.address + 3 + int.from_bytes(sa[1:3], "little", signed=True)) & 0xFFFF
            to = (ia.address - ra.entry + orig_entry + 3 + int.from_bytes(so[1:3], "little", signed=True)) & 0xFFFF
            if nested_ours and to in nested_ours:
                if ta != nested_ours[to]:
                    return False, "near call: nested target ours %04X, original %04X" % (ta, to), n
            else:
                want = self.expect_routine(self.a, self.seg, ta)
                got = self.orig.routine_id(self.unit, to)
                if want != got:
                    return False, "near call: ours goes to %s, the original to %s" % (want, got), n
            covered |= {1, 2}
            n += 1
        elif op0 == 0x9A:
            offa, sega = int.from_bytes(sa[1:3], "little"), int.from_bytes(sa[3:5], "little")
            offo, sego = int.from_bytes(so[1:3], "little"), int.from_bytes(so[3:5], "little")
            segname = self.a.seg_of_para(sega)
            if segname is None:
                return False, "far call into an unknown segment %04X of ours" % sega, n
            want = self.expect_routine(self.a, segname, offa)
            got = self.orig.far_target(sego, offo)
            if want != got:
                return False, "far call: ours goes to %s, the original to %s" % (want, got), n
            covered |= {1, 2, 3, 4}
            n += 1
        else:
            for op in ia.operands:
                if op.type == X86_OP_MEM and op.mem.disp and ia.disp_size == 2:
                    k = ia.disp_offset
                    if sa[k:k + 2] == so[k:k + 2]:
                        continue
                    if op.mem.base == X86_REG_BP or op.mem.segment in (X86_REG_ES, X86_REG_SS):
                        continue                    # stack or ES-based: compared as plain bytes below
                    if op.mem.segment not in (0, X86_REG_DS):
                        continue
                    va, vo = int.from_bytes(sa[k:k + 2], "little"), int.from_bytes(so[k:k + 2], "little")
                    e = self.expect_global(self.a, va)
                    if e is None or e[0] != vo:
                        return False, "global: ours is %s (DS:%04X expected), the original has DS:%04X" % (
                            e[1] if e else "DS:%04X" % va, e[0] if e else va, vo), n
                    covered |= {k, k + 1}
                    n += 1
                elif op.type == X86_OP_IMM and ia.imm_size == 2:
                    k = ia.imm_offset
                    if sa[k:k + 2] == so[k:k + 2]:
                        continue
                    if sa[k:k + 2] == sb[k:k + 2]:
                        return False, "constant %04X (it does not move with the layout, so it is not an address)" % (
                            int.from_bytes(sa[k:k + 2], "little")), n
                    va, vo = int.from_bytes(sa[k:k + 2], "little"), int.from_bytes(so[k:k + 2], "little")
                    vb = int.from_bytes(sb[k:k + 2], "little")
                    ok, why = self.immediate(va, vb, vo, ra, orig_entry, p + k)
                    if not ok:
                        return False, why, n
                    covered |= {k, k + 1}
                    n += 1
        rest = [i for i in range(len(sa)) if i not in covered and sa[i] != so[i]]
        if rest:
            return False, "bytes %s differ and are not an address" % rest, n
        return True, "", n

    def immediate(self, va: int, vb: int, vo: int, ra: Region, orig_entry: int, pos: int):
        abs_a = self.a.seg_start(self.seg) + ra.entry - ra.pool + pos
        if abs_a in self.a.relocs:                   # a segment value
            sa = self.a.seg_of_para(va)
            so = self.orig.segment_unit(vo)
            want = "DATA" if sa == "DATA" else (sa or "").lower()
            if want != so.lower() and not (want == "data" and so == "DATA"):
                return False, "segment: ours is %s, the original %s" % (sa, so)
            return True, ""
        if vb - va == CODE_PAD:                      # an offset that the padding procedure shifts
            routine = self.a.public_at(self.seg, va)
            if routine is not None:                  # @Routine in this unit
                ok, why = self.routine_address(routine, self.unit, vo)
                if ok:
                    return True, ""
            else:
                ok, why = False, ""
            cross_ok, cross_why = self.cross_unit_address(va, vb, abs_a, vo)
            if cross_ok:
                return True, ""
            if cross_why:
                return False, cross_why
            if routine is not None:
                return False, why
            if va - ra.entry != vo - orig_entry:     # a literal of the pool
                return False, "literal at entry%+d (ours) vs entry%+d (original)" % (va - ra.entry, vo - orig_entry)
            return True, ""
        e = self.expect_global(self.a, va)
        if e is None or e[0] != vo:
            return False, "address immediate: ours %s (DS:%04X expected), the original DS:%04X" % (
                e[1] if e else "%04X" % va, e[0] if e else va, vo)
        return True, ""

    def routine_address(self, routine: str, uid: str, vo: int) -> tuple[bool, str]:
        """True when `routine` is the original routine whose address immediate is `vo`."""
        want = self.orig.id_of_name(routine)
        got = self.orig.code_address(uid, vo) if uid in getattr(self.orig, "units", {uid: None}) else None
        if want is None or want != got:
            return False, "routine address: ours is %s (%s), the original names %s" % (routine, want, got)
        return True, ""

    def cross_unit_address(self, va: int, vb: int, abs_a: int, vo: int) -> tuple[bool, str]:
        """`@Routine` in another unit: ofs in ax, that unit's segment in the next relocated word.

        Several units can have a routine at the same offset (each is padded by one procedure, so
        every offset moves by CODE_PAD). The `mov dx, seg` immediately after `mov ax, ofs`
        (probe build/probe-ptr; the original does the same at ovl08:0069 and ovl08:0085) names
        which one. The original word is a stub offset for an overlay and a code offset for a
        resident unit; code_address accepts either.
        """
        bpubs = {n.upper(): pair for n, pair in self.b.pubs.items()}
        hits = []
        for n, (para, off) in self.a.pubs.items():
            other = bpubs.get(n.upper())
            if off != va or not other or other[1] != vb:
                continue
            # Padding shifts later units to new paragraphs; the segment name is what stays.
            if self.a.seg_of_para(para) != self.b.seg_of_para(other[0]):
                continue
            hits.append((n, para))
        if not hits:
            return False, ""
        # Only `mov ax, ofs; mov dx, seg` is a cross-unit routine address. Any other immediate
        # that happens to equal a public's offset stays on the literal or same-unit rule.
        seg_abs = abs_a + 3
        mov_dx = seg_abs >= 1 and seg_abs + 2 <= len(self.a.img) and self.a.img[seg_abs - 1] == 0xBA
        if not (mov_dx and seg_abs in self.a.relocs):
            return False, ""
        sega = int.from_bytes(self.a.img[seg_abs:seg_abs + 2], "little")
        chosen = [(n, para) for n, para in hits if para == sega]
        if len(chosen) != 1:
            return False, "routine address: offset %04X is shared by %s" % (
                va, ", ".join(sorted(n for n, _p in hits)))
        name, para = chosen[0]
        segname = self.a.seg_of_para(para)
        if segname is None or segname.upper() == self.seg.upper():
            return False, ""
        return self.routine_address(name, segname.lower(), vo)

    def diff(self, ia, io, why: str) -> str:
        a = "%04X  %-16s %s %s" % (ia.address, ia.bytes.hex(), ia.mnemonic, ia.op_str)
        o = ("%04X  %-16s %s %s" % (io.address, io.bytes.hex(), io.mnemonic, io.op_str)) if io else "(no instruction)"
        return "%s\n    ours:     %s\n    original: %s" % (why, a, o)


# --------------------------------------------------------------------------- driver
def compare_unit(orig: Original, unit: str, a: Build, b: Build, only: list[str] | None) -> tuple[list[Result], str]:
    """Compare one unit of builds A and B with the original."""
    source = a.sources[unit.upper()]                       # unpadded
    routines = routines_of(source)
    names = [n for n, _s in routines]
    ra = regions(a, unit, names)
    rb = [r for r in regions(b, unit, names, pad=pad_proc(unit)) if r.name.upper() != pad_proc(unit).upper()]
    by_a, by_b = {r.name.upper(): r for r in ra}, {r.name.upper(): r for r in rb}
    cmp = Comparer(orig, unit, a, b, by_a, by_b)
    results = []
    externals = orig.external_names(unit)
    stubs = {n.upper() for n, s in routines if s} - externals
    for n, _s in routines:
        if only and n.upper() not in {x.upper() for x in only}:
            continue
        rid = orig.id_of_name(n)
        r = by_a[n.upper()]
        if n.upper() in externals:                 # declared for its callers; its code is the object's
            results.append(Result(n, rid, "external"))
            continue
        if n.upper() in stubs:
            results.append(Result(n, rid, "stub"))
            continue
        if rid is None or not rid.upper().startswith(orig.routine_id(unit, 0)[:-4].upper()):
            results.append(Result(n, rid, "missing", "name does not give a routine of %s" % unit))
            continue
        entry = int(rid.split(":")[1], 16)
        try:
            ok, why, nsym = cmp.compare(r, by_b[n.upper()], entry)
        except MatchError as e:
            ok, why, nsym = False, str(e), 0
        results.append(Result(n, rid, "matched" if ok else "differs", why, r.end - r.entry, r.pool, nsym))
    whole = ""
    if STUB_INIT in source:
        results.append(Result("%s_init" % unit, orig.init_id(unit), "stub"))
    elif not stubs and not only:
        whole = whole_unit(cmp, a, b, ra, rb, results)
    return results + nested_results(orig, unit, cmp.obytes, results), whole


def nested_results(orig: Original, unit: str, obytes: bytes, results: list[Result]) -> list[Result]:
    """Results (status "nested") for the nested routines each matched routine proves (nested_routines)."""
    out = []
    for r in results:
        if r.status != "matched" or r.id is None or r.name.lower().endswith("_init"):
            continue
        entry = int(r.id.split(":")[1], 16)
        for t, (end, _caller) in sorted(nested_routines(obytes, entry - r.pool, entry, entry + r.size).items()):
            rid = orig.routine_id(unit, t)
            known = orig.by_id.get(rid)
            out.append(Result(known["name"] if known else "%s_fn_%04x" % (unit, t), rid, "nested",
                              "nested in %s (%s), proven by the parent's match" % (r.name, r.id), end - t, 0, 0))
    return out


def compare_main(orig: Original, a: Build) -> tuple[list[Result], str]:
    """The main program: its literal pool, the initialisation calls and the main block, as one region."""
    seg = PROGRAM
    if seg not in a.segs:
        raise MatchError("the program segment %s is not in the map" % seg)
    seglen = a.segs[seg][1]
    entry = a.entry[1]
    region = Region("main", entry, entry, seglen)          # ends with the call to Halt, not a return
    cmp = Comparer(orig, "main", a, a, {}, {})
    orig_entry = 6                                          # start-unpack.exe CS:IP = 0000:0006
    try:
        ok, why, nsym = cmp.compare(region, region, orig_entry)
    except MatchError as e:
        ok, why, nsym = False, str(e), 0
    res = Result("main", "0000:%04X" % orig_entry, "matched" if ok else "differs", why, seglen - entry, entry, nsym)
    whole = ""
    if ok:
        tail = cmp.obytes[seglen:]
        whole = ("unit: complete, %d bytes of code plus %d of paragraph padding cover the original segment" % (
            seglen, len(tail))) if len(tail) < 16 and not any(tail) else \
            "unit: the original main segment continues after ours (%d more bytes)" % len(tail)
    return [res], whole


def match_units(units: list[str], only: list[str] | None = None) -> dict[str, tuple[list[Result], str]]:
    """Match several units from one pair of builds (and the main program from its own build)."""
    orig = Original()
    sources = unit_sources()
    out: dict[str, tuple[list[Result], str]] = {}
    plain = [u.lower() for u in units if u.lower() != "main"]
    for u in plain:
        if u not in orig.units:
            raise MatchError("no unit %s in re/units.toml" % u)
        if u.upper() not in sources:
            raise MatchError("no source src/%s.PAS" % u.upper())
    if plain:
        tag = plain[0] if len(plain) == 1 else "all"
        a = compile_variant(plain, sources, False, BUILD / tag / "A")
        b = compile_variant(plain, sources, True, BUILD / tag / "B")
        for u in plain:
            out[u] = compare_unit(orig, u, a, b, only)
    if any(u.lower() == "main" for u in units):
        prog = all_sources().get(PROGRAM)
        if prog is None:
            raise MatchError("no source src/%s.PAS" % PROGRAM)
        a = compile_variant([], sources, False, BUILD / "main" / "A", program=prog)
        out["main"] = compare_main(orig, a)
    return out


def match_unit(unit: str, only: list[str] | None = None) -> tuple[list[Result], str]:
    return match_units([unit], only)[unit.lower()]


def whole_unit(cmp: Comparer, a: Build, b: Build, ra: list[Region], rb: list[Region], results: list[Result]) -> str:
    """With every routine decompiled: the initialization part, then exact coverage of the segment."""
    seg = cmp.seg
    last_a = max(r.end for r in ra) if ra else 0
    last_b = max(r.end for r in rb) if rb else 0
    ia, ib = init_region(a, cmp.unit, last_a), init_region(b, cmp.unit, last_b, pad=pad_proc(cmp.unit))
    if ia is not None:
        init_id = cmp.orig.init_id(cmp.unit)
        if not init_id:
            return "unit: we have an initialization part, the original has none"
        entry = int(init_id.split(":")[1], 16)
        ok, why, nsym = cmp.compare(ia, ib, entry)
        results.append(Result(ia.name, init_id, "matched" if ok else "differs", why, ia.end - ia.entry, ia.pool, nsym))
        if not ok:
            return "unit: initialization part differs"
        last_a = ia.end
    elif cmp.orig.init_id(cmp.unit):
        return "unit: the original has an initialization part (%s), ours has none" % cmp.orig.init_id(cmp.unit)
    seglen = a.segs[seg][1]
    if any(r.status not in ("matched", "external") for r in results):
        return "unit: not every routine matches"
    ext = cmp.orig.external.get(cmp.unit)
    if ext is not None:
        # The Pascal part must tile the original up to the object; the object is the original's bytes.
        ends = [int(r.id.split(":")[1], 16) + r.size for r in results if r.status == "matched" and r.id]
        covered = max(ends) if ends else 0
        if covered != ext:
            return "unit: the Pascal part ends at %04X, the external object starts at %04X" % (covered, ext)
        return "unit: complete, %d bytes of Pascal code; external object of %d bytes from %04X (%s)" % (
            ext, len(cmp.obytes) - ext, ext, cmp.orig.units[cmp.unit].get("external_note", "not Pascal"))
    if last_a != seglen:
        return "unit: %d bytes of ours after the last routine are not accounted for" % (seglen - last_a)
    tail = cmp.obytes[seglen:]
    if len(tail) >= 16 or any(tail):
        return "unit: the original segment continues after ours (%d more bytes, not padding)" % len(tail)
    return "unit: complete, %d bytes of code plus %d of paragraph padding cover the original segment" % (
        seglen, len(tail))


# --------------------------------------------------------------------------- the registry
def registry_blocks(text: str) -> list[tuple[int, int, str | None]]:
    """(start, end, id) of every `[[routine]]` block of re/symbols.toml, in file order; `end` is the start of
    the next block (or the end of the text), so a block carries its trailing blank line."""
    starts = [m.start() for m in re.finditer(r"^\[\[routine\]\]\n", text, re.M)]
    out = []
    for k, s in enumerate(starts):
        e = starts[k + 1] if k + 1 < len(starts) else len(text)
        m = re.search(r'^id = "([^"]*)"', text[s:e], re.M)
        out.append((s, e, m.group(1) if m else None))
    return out


def set_field(text: str, rid: str, key: str, raw: str) -> str:
    """Set `key = raw` in the record of `rid` (replacing the line, or appending it before the trailing blank)."""
    for s, e, i in registry_blocks(text):
        if i != rid:
            continue
        block = text[s:e]
        line = "%s = %s\n" % (key, raw)
        block, k = re.subn(r"^%s = .*\n" % re.escape(key), line, block, count=1, flags=re.M)
        if not k:
            body = block.rstrip("\n") + "\n"
            block = body + line + block[len(body):]
        return text[:s] + block + text[e:]
    return text


def delete_record(text: str, rid: str) -> str:
    for s, e, i in registry_blocks(text):
        if i == rid:
            return text[:s] + text[e:]
    return text


def insert_record(text: str, unit: str, record: str) -> str:
    """Insert a record in address order among the unit's records (after the last one when it is the highest)."""
    off = int(re.search(r'^addr = "[^:]+:([0-9A-Fa-f]+)"', record, re.M).group(1), 16)
    blocks = registry_blocks(text)
    unit_blocks = [(s, e, i) for s, e, i in blocks
                   if re.search(r'^unit = "%s"' % re.escape(unit), text[s:e], re.M)]
    if not unit_blocks:
        return text.rstrip("\n") + "\n\n" + record.rstrip("\n") + "\n"
    for s, e, i in unit_blocks:
        here = int(i.split(":")[1], 16) if i and ":" in i else -1
        if here > off:
            return text[:s] + record.rstrip("\n") + "\n\n" + text[s:]
    s, e, i = unit_blocks[-1]
    block = text[s:e].rstrip("\n") + "\n\n"
    return text[:s] + block + record.rstrip("\n") + "\n" + ("\n" if e < len(text) else "") + text[e:]


def write_levels(results: list[Result], orig: Original, unit: str) -> list[str]:
    """Record L2 for matched routines, and the compiler's boundaries: a map size the compiler disproves is
    corrected, a map entry that lies inside a matched routine (or its literal pool) is removed, a routine
    the map lacks is added, and routines inside an external object are flagged `external`. Returns notes
    on what was written (the mapper role of playbook 10 is this function, SYSTEM-REVIEW 6.8)."""
    path = ROOT / "re/symbols.toml"
    text = path.read_text()
    notes = []
    ordered = [r for r in results if r.status == "matched" and r.id]
    nested = [r for r in results if r.status == "nested" and r.id]
    nested_ids = {r.id for r in nested}
    ext = orig.external.get(unit)
    unit_records = [r for r in orig.routines if r["unit"] == unit]
    for k, r in enumerate(ordered):
        entry = int(r.id.split(":")[1], 16)
        known = orig.by_id.get(r.id)
        nxt = ordered[k + 1] if k + 1 < len(ordered) else None
        gap = None
        if nxt is not None:
            n_entry = int(nxt.id.split(":")[1], 16)
            if n_entry - nxt.pool == entry + r.size:            # contiguous: the pool between is the next's
                gap = r.size + nxt.pool
        elif r.name.lower().endswith("_init"):                   # the last routine: to the object or the end
            gap = (ext if ext is not None else len(orig_segment(orig, unit))) - entry
        if known is None:
            size = gap if gap is not None else r.size
            record = ('[[routine]]\nid = "%s"\nunit = "%s"\naddr = "%s"\nsize = %d\nname = "%s"\n'
                      'c_name = "%s_fn_%04x"\nlevel = "L2"\njustification = ""\n'
                      'notes = "added by make match WRITE=1: a routine the map lacked, boundaries from the compiler"\n'
                      'evidence = ["compiler"]\n' % (r.id, unit, r.id, size, r.name, unit, entry))
            text = insert_record(text, unit, record)
            notes.append("%s (%s, %d bytes) was not in re/symbols.toml: added" % (r.name, r.id, size))
            continue
        if gap is not None and known["size"] != gap:
            text = set_field(text, r.id, "size", str(gap))
            notes.append("%s: size %d corrected to %d (the compiler: %d bytes of code plus the next %d-byte literal pool)"
                         % (r.id, known["size"], gap, r.size, gap - r.size))
        elif gap is None and known["size"] < r.size:
            text = set_field(text, r.id, "size", str(r.size))
            notes.append("%s: size %d corrected to at least %d (the compiler's code bytes)" % (r.id, known["size"], r.size))
        for other in unit_records:
            o = int(other["addr"].split(":")[1], 16)
            if other["id"] != r.id and other["id"] not in nested_ids and entry - r.pool <= o < entry + r.size \
                    and other.get("level") not in ("L2", "L3"):
                text = delete_record(text, other["id"])
                notes.append("%s (%s) lies inside %s (%s..%04X): removed from the map" % (
                    other["name"], other["id"], r.name, r.id, entry + r.size))
        block = re.compile(r'(\[\[routine\]\]\nid = "%s"\n(?:(?!\[\[routine\]\]).)*?\nlevel = )"[^"]*"' % re.escape(r.id),
                           re.S)
        text, k2 = block.subn(r'\1"L2"', text, count=1)
        if not k2:
            notes.append("%s: no level field found" % r.id)
    for r in nested:
        if orig.by_id.get(r.id) is None:            # a nested routine the map lacked: recorded like any other
            entry = int(r.id.split(":")[1], 16)
            record = ('[[routine]]\nid = "%s"\nunit = "%s"\naddr = "%s"\nsize = %d\nname = "%s"\n'
                      'c_name = "%s_fn_%04x"\nlevel = "L2"\njustification = ""\nnotes = "%s"\n'
                      'evidence = ["compiler"]\n' % (r.id, unit, r.id, r.size, r.name, unit, entry, r.detail))
            text = insert_record(text, unit, record)
            notes.append("%s (%s, %d bytes) was not in re/symbols.toml: added as nested" % (r.name, r.id, r.size))
            continue
        text = set_field(text, r.id, "level", '"L2"')
        nb = re.compile(r'(\[\[routine\]\]\nid = "%s"\n(?:(?!\[\[routine\]\]).)*?\nnotes = ")([^"]*)"' % re.escape(r.id),
                        re.S)
        m = nb.search(text)
        if m is None:
            text = set_field(text, r.id, "notes", '"%s"' % r.detail)
        elif r.detail not in m.group(2):
            joined = (m.group(2) + "; " if m.group(2) else "") + r.detail
            text = text[:m.start(2)] + joined + text[m.end(2):]
    if ext is not None:
        for other in unit_records:
            if int(other["addr"].split(":")[1], 16) >= ext and not other.get("external"):
                text = set_field(text, other["id"], "external", "true")
                notes.append("%s (%s) is inside the external object: flagged external" % (other["name"], other["id"]))
    path.write_text(text)
    return notes


def orig_segment(orig: Original, unit: str) -> bytes:
    return orig.segment(unit)[0]


def units_with_source() -> list[str]:
    """Units of re/units.toml whose source has at least one decompiled (non-stub) routine, and "main"
    when src/POOL.PAS exists."""
    units = tomllib.loads((ROOT / "re/units.toml").read_text())
    ids = {u["id"] for u in units["resident"] + units["overlay"]}
    out = []
    for name, text in unit_sources().items():
        rs = routines_of(text)
        init_done = STUB_INIT not in text and init_begin_line(text) is not None
        if name.lower() in ids and (any(not stub for _n, stub in rs) or (not rs and init_done)):
            out.append(name.lower())
    if PROGRAM in all_sources():
        out.append("main")
    return sorted(out)


def report(unit: str, results: list[Result], whole: str) -> int:
    bad = 0
    for r in results:
        if r.status == "matched":
            print("MATCH   %-16s %-12s %4d bytes code, %3d pool, %d address fields" % (
                r.name, r.id, r.size, r.pool, r.symbols))
        elif r.status == "nested":
            print("NESTED  %-16s %-12s %4d bytes code, %s" % (r.name, r.id, r.size, r.detail))
        elif r.status == "stub":
            print("stub    %-16s %s" % (r.name, r.id or ""))
        elif r.status == "external":
            print("extern  %-16s %s  (external object, not Pascal)" % (r.name, r.id or ""))
        else:
            bad += 1
            print("DIFF    %-16s %-12s %s" % (r.name, r.id or "?", r.detail))
    if whole:
        print(whole)
        if "complete" not in whole:
            bad += 1
    print("match %s: %d matched, %d nested, %d differ, %d stubs" % (
        unit, sum(r.status == "matched" for r in results), sum(r.status == "nested" for r in results),
        sum(r.status in ("differs", "missing") for r in results), sum(r.status == "stub" for r in results)))
    return bad


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit", nargs="?")
    ap.add_argument("--all", action="store_true", help="every unit that has source with a decompiled routine")
    ap.add_argument("--routine", action="append", help="only these routines (names)")
    ap.add_argument("--write", action="store_true", help="record L2 for matched routines in re/symbols.toml")
    a = ap.parse_args(argv)
    if bool(a.unit) == bool(a.all):
        ap.error("give a UNIT or --all")
    units = units_with_source() if a.all else [a.unit.lower()]
    bad, total = 0, []
    try:
        done = match_units(units, a.routine)
    except MatchError as e:
        print("match: %s" % e)
        return 2
    for u in units:
        results, whole = done[u]
        bad += report(u, results, whole)
        total += [r for r in results if r.name != "main"]
    if a.write:
        orig = Original()
        for u in units:
            if u == "main":                          # the main program has no registry record
                continue
            for n in write_levels(done[u][0], orig, u):
                print("note: " + n)
    if a.all:
        print("match --all: %d units, %d routines matched, %d nested, %s" % (
            len(units), sum(r.status == "matched" for r in total), sum(r.status == "nested" for r in total),
            "all match" if not bad else "%d problems" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

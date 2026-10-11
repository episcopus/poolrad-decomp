#!/usr/bin/env python3
"""packet.py: write a work packet for a unit or routine (SPEC 9.3, playbook 30).

  make packet UNIT=ovl00
  make packet FN=ovl00:0042        (an id, or a name: FN=res04_fn_0059)

Writes build/packets/<id>.md: per routine its disassembly with every call and global named (runtime
routines and game routines from re/symbols.toml, globals from re/dseg.toml or `dsXXXX`), string constants
in the code segment decoded, the frame (parameter bytes from `retf n`, local bytes from `sub sp`), its
callers, the bytes after its return (usually the next routine's literal pool), and the current Pascal if
the unit has source. Everything comes from our bytes and re/; nothing from memory.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))
sys.path.insert(0, str(ROOT / "tools/re"))

from capstone import Cs, CS_ARCH_X86, CS_MODE_16  # noqa: E402
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_REG_BP, X86_REG_DS  # noqa: E402

import match  # noqa: E402

md = Cs(CS_ARCH_X86, CS_MODE_16)
md.detail = True


class Namer:
    def __init__(self):
        self.o = match.Original()
        self.names = {r["id"].upper(): r["name"] for r in self.o.routines}
        g = tomllib.loads((ROOT / "re/dseg.toml").read_text()).get("global", [])
        self.globals = sorted((x["offset"], x.get("size", 1), x["name"]) for x in g)

    def routine(self, rid: str) -> str:
        return "%s (%s)" % (self.names.get(rid.upper(), "?"), rid)

    def glob(self, off: int) -> str:
        for o, size, name in self.globals:
            if o <= off < o + max(size, 1):
                return name if off == o else "%s+%d" % (name, off - o)
        return "ds%04X" % off


def pascal_string(code: bytes, off: int) -> str | None:
    if not 0 <= off < len(code):
        return None
    n = code[off]
    s = code[off + 1: off + 1 + n]
    if n and len(s) == n and all(32 <= c < 127 for c in s):
        return "'%s'" % s.decode("ascii")
    return None


def listing(namer: Namer, uid: str, code: bytes, r: dict) -> tuple[list[str], dict]:
    off = int(r["addr"].split(":")[1], 16)
    end = min(off + r["size"], len(code))
    out, frame, last = [], {}, off
    for i in md.disasm(code[off:end], off):
        note = ""
        if i.mnemonic == "lcall" and i.bytes[0] == 0x9A:
            o = int.from_bytes(i.bytes[1:3], "little")
            s = int.from_bytes(i.bytes[3:5], "little")
            note = namer.routine(namer.o.far_target(s, o))
        elif i.mnemonic == "call" and i.bytes[0] == 0xE8:
            note = namer.routine(namer.o.routine_id(uid, i.operands[0].imm & 0xFFFF))
        else:
            for op in i.operands:
                if op.type == X86_OP_MEM and op.mem.base != X86_REG_BP and op.mem.segment in (0, X86_REG_DS) \
                        and i.disp_size == 2 and op.mem.disp:
                    note = namer.glob(op.mem.disp & 0xFFFF)
                elif op.type == X86_OP_IMM and i.imm_size == 2 and i.mnemonic == "mov":
                    lit = pascal_string(code, op.imm)
                    if lit and i.op_str.startswith("di"):
                        note = "literal %s (if pushed with cs) / %s (if with ds)" % (lit, namer.glob(op.imm))
        if i.mnemonic == "sub" and i.op_str.startswith("sp,") and "locals" not in frame:
            frame["locals"] = i.operands[1].imm
        if i.mnemonic in ("ret", "retf"):
            frame["params"] = i.operands[0].imm if i.operands else 0
        out.append("%04X  %-16s %-6s %s%s" % (i.address, i.bytes.hex(), i.mnemonic, i.op_str,
                                               ("   ; " + note) if note else ""))
        last = i.address + i.size
        if i.mnemonic in ("ret", "retf") and last < end:
            tail = code[last:end]
            strings = [pascal_string(code, k) for k in range(last, end)]
            shown = ", ".join("%04X %s" % (last + k, s) for k, s in enumerate(strings) if s)
            out.append("      ; %d bytes after the return (next routine's literal pool, padding, or a routine the "
                       "map missed): %s%s" % (len(tail), tail[:48].hex(" "), ("; strings: " + shown) if shown else ""))
            break
    return out, frame


def callers_of(namer: Namer, image_code: dict, targets: set[str]) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {t: [] for t in targets}
    for r in namer.o.routines:
        uid = r["unit"]
        if uid not in image_code:
            continue
        code = image_code[uid]
        off = int(r["addr"].split(":")[1], 16)
        for i in md.disasm(code[off:off + r["size"]], off):
            t = None
            if i.bytes[0] == 0x9A and i.size == 5:
                t = namer.o.far_target(int.from_bytes(i.bytes[3:5], "little"), int.from_bytes(i.bytes[1:3], "little"))
            elif i.bytes[0] == 0xE8 and i.size == 3:
                t = namer.o.routine_id(uid, i.operands[0].imm & 0xFFFF)
            caller = "%s %s" % (r["id"], r["name"])
            if t and t.upper() in found and caller not in found[t.upper()]:
                found[t.upper()].append(caller)
    return found


def source_of(uid: str, name: str) -> str | None:
    p = match.SRC / (uid.upper() + ".PAS")
    if not p.exists():
        return None
    text = p.read_text()
    impl = re.search(r"^\s*implementation\b", text, re.I | re.M)
    pat = re.compile(r"^(\{@stub\}\s*)?(procedure|function)\s+%s\b" % re.escape(name), re.I | re.M)
    m = pat.search(text, impl.end()) if impl else None
    if not m:
        return None
    nxt = match.HEADER_RE.search(text, m.end())
    stop = nxt.start() if nxt else len(text)
    return text[m.start():stop].rstrip()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--unit", default="")
    ap.add_argument("--fn", default="")
    a = ap.parse_args(argv)
    namer = Namer()
    routines = namer.o.routines
    if a.fn:
        hit = [r for r in routines if a.fn.upper() in (r["id"].upper(), r["name"].upper())]
        if not hit:
            print("packet: no routine %s in re/symbols.toml" % a.fn, file=sys.stderr)
            return 2
        uid, scope = hit[0]["unit"], hit
    elif a.unit:
        uid = a.unit.lower()
        scope = [r for r in routines if r["unit"] == uid]
        if not scope:
            print("packet: no routines for unit %s" % uid, file=sys.stderr)
            return 2
    else:
        print("packet: need UNIT=<id> or FN=<id or name>", file=sys.stderr)
        return 2
    meta = namer.o.units[uid]
    image_code = {}
    for u in namer.o.units:
        try:
            image_code[u] = namer.o.segment(u)[0]
        except match.MatchError:
            pass
    code = image_code[uid]
    callers = callers_of(namer, image_code, {r["id"].upper() for r in scope})
    library = meta.get("name") in ("System", "Crt", "Dos", "Overlay")
    lines = ["# Work packet: %s" % (a.fn or uid), "",
             "Generated by `tools/agent/packet.py` (SPEC 9.3). Unit %s (%s), %s, %s bytes of code%s." % (
                 uid, meta.get("name"), meta.get("kind"), meta.get("code_bytes"),
                 "; **runtime library: linked from TURBO.TPL, never decompiled**" if library else ""),
             "", "Source: `src/%s.PAS` %s. Directives: `{$A-,%sF+,S-,R-,G-,I-}` (playbook 30)." % (
                 uid.upper(), "(exists)" if (match.SRC / (uid.upper() + ".PAS")).exists() else "(not yet)",
                 "O+," if uid.startswith("ovl") else ""), ""]
    for r in sorted(scope, key=lambda x: int(x["addr"].split(":")[1], 16)):
        body, frame = listing(namer, uid, code, r)
        lines += ["## %s %s" % (r["id"], r["name"]), "",
                  "- level %s, %d bytes in re/symbols.toml (may include the next routine's literal pool)" % (
                      r.get("level"), r["size"]),
                  "- frame: %s bytes of parameters (`retf`), %s bytes of locals (`sub sp`)" % (
                      frame.get("params", "?"), frame.get("locals", 0)),
                  "- signature: %s" % (r.get("signature") or "(not recorded)"),
                  "- notes: %s" % (r.get("notes") or ""),
                  "- callers: %s" % (", ".join(callers.get(r["id"].upper(), [])[:12]) or "none found by direct call "
                                     "(entry point, procedural value, or called from code the map missed)"),
                  "", "```"] + body + ["```", ""]
        src = source_of(uid, r["name"])
        if src:
            lines += ["Current source:", "", "```pascal", src, "```", ""]
    lines += ["## Next steps (playbook 30)", "",
              "1. Write the routine in `src/%s.PAS` (stubs for callees, names for globals)." % uid.upper(),
              "2. `make match UNIT=%s FN=<name>` until it matches; probe idioms with `make tpc`." % uid,
              "3. `make match UNIT=%s WRITE=1`, commit with the routine id." % uid, ""]
    out = ROOT / "build/packets" / ("%s.md" % (a.fn or uid).replace(":", "_"))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines))
    print("packet: wrote %s (%d routines)" % (out.relative_to(ROOT), len(scope)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

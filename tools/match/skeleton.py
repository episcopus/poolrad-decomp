#!/usr/bin/env python3
"""skeleton.py: write the starting source of a game unit (SPEC 7.1, playbook 30).

  .venv/bin/python tools/match/skeleton.py UNIT [--force]
  .venv/bin/python tools/match/skeleton.py --all       every game unit that has no source yet
  make skeleton [UNIT=<id>]

A skeleton is `src/<ID>.PAS`: the unit header with POOL's directives, every routine of re/symbols.toml
in address order declared in the interface, a `{@stub}` body for each (with the signature recorded in
re/symbols.toml if there is one, else no parameters and a comment with the frame the code shows), and
an empty initialisation part when the original has one. Every unit has source from the start, so the
whole program compiles (`make rebuild`) and a decompiler fixes stub signatures in place instead of
creating files. Existing files are never overwritten without --force.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

from capstone import Cs, CS_ARCH_X86, CS_MODE_16  # noqa: E402

import match  # noqa: E402

LIBRARY = ("System", "Crt", "Dos", "Overlay")
EMPTY_INIT = bytes.fromhex("5589e55dcb")           # `begin end.`: push bp; mov bp,sp; pop bp; retf
STUB_INIT = match.STUB_INIT
md = Cs(CS_ARCH_X86, CS_MODE_16)
md.detail = True


def game_units(orig: match.Original) -> list[str]:
    return sorted(uid for uid, u in orig.units.items() if uid != "main" and u.get("name") not in LIBRARY)


def has_init(orig: match.Original, uid: str) -> bool:
    return bool(orig.init_id(uid))


def frame(code: bytes, off: int, size: int) -> str:
    params, locals_ = None, 0
    for i in md.disasm(code[off:off + size], off):
        if i.mnemonic == "sub" and i.op_str.startswith("sp,") and not locals_:
            locals_ = i.operands[1].imm
        if i.mnemonic in ("ret", "retf"):
            params = i.operands[0].imm if i.operands else 0
            break
    if params is None:
        return "frame not read"
    return "retf %d: %d bytes of parameters; %d bytes of locals" % (params, params, locals_)


def header(r: dict) -> str:
    """`procedure NAME(...)` / `function NAME(...): T` from the recorded signature, else bare."""
    sig = (r.get("signature") or "").strip()
    m = re.match(r"^(procedure|function)\s+\w+\s*(.*)$", sig, re.I)
    if m:
        return "%s %s%s" % (m.group(1).lower(), r["name"], m.group(2).rstrip(";"))
    return "procedure %s" % r["name"]


def skeleton(orig: match.Original, uid: str) -> str:
    u = orig.units[uid]
    routines = sorted((r for r in orig.routines if r["unit"] == uid and not r["name"].endswith("_init")),
                      key=lambda r: int(r["addr"].split(":")[1], 16))
    code, _seg = orig.segment(uid)
    overlay = uid.startswith("ovl")
    lines = ["unit %s;" % uid.upper(),
             "{ %s: %s unit, %d bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub",
             "  until decompiled (playbook 30). }" ]
    lines[1] = lines[1] % (u.get("name", uid), "overlay" if overlay else "resident", u.get("code_bytes", 0))
    lines += ["{$A-,%sF+,S-,R-,G-,%s}" % ("O+," if overlay else "", "I+" if uid == "res05" else "I-"),
              "interface"]
    lines += ["%s;" % header(r) for r in routines]
    lines += ["implementation", ""]
    for r in routines:
        off = int(r["addr"].split(":")[1], 16)
        lines.append("{ %s: %s }" % (r["id"], frame(code, off, r["size"])))          # TP lines end at 127
        lines.append("{@stub} %s; begin end;" % header(r))
    lines.append("")
    if has_init(orig, uid):
        off = int(orig.init_id(uid).split(":")[1], 16)
        if code[off:off + 5] != EMPTY_INIT:              # real initialisation code: not decompiled yet
            lines.append(STUB_INIT)
        lines += ["begin", "end."]
    else:
        lines.append("end.")
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit", nargs="?")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--force", action="store_true", help="overwrite an existing file")
    a = ap.parse_args(argv)
    orig = match.Original()
    units = game_units(orig) if a.all else [a.unit.lower()] if a.unit else []
    if not units:
        ap.error("give a UNIT or --all")
    wrote = 0
    for uid in units:
        if uid not in orig.units or orig.units[uid].get("name") in LIBRARY:
            print("skeleton: %s is not a game unit" % uid)
            return 2
        path = match.SRC / (uid.upper() + ".PAS")
        if path.exists() and not a.force:
            if not a.all:
                print("skeleton: %s exists (use --force to replace it)" % path.relative_to(ROOT))
            continue
        path.write_text(skeleton(orig, uid))
        wrote += 1
        print("skeleton: wrote %s" % path.relative_to(ROOT))
    print("skeleton: %d file(s) written" % wrote)
    return 0


if __name__ == "__main__":
    sys.exit(main())

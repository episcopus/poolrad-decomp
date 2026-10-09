#!/usr/bin/env python3
"""export.py: write Ghidra user-defined names back into re/symbols.toml (playbook 10).

Only updates name/c_name/notes for existing ids, and appends [[routine]] rows for
new labels that look like unit addresses (ovlNN_* or load-image seg:off forms).

Usage:
  . tools/setup/env.local.sh
  python3 tools/ghidra/export.py [--project-dir build/ghidra] [--symbols re/symbols.toml]
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOAD_SEG = 0x1000
OVL_SEG = 0x8000


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--project-dir", default=str(ROOT / "build/ghidra"))
    ap.add_argument("--project-name", default="poolrad")
    ap.add_argument("--program-name", default="start-unpack")
    ap.add_argument("--symbols", default=str(ROOT / "re/symbols.toml"))
    args = ap.parse_args(argv[1:])

    install = os.environ.get("GHIDRA_INSTALL_DIR")
    if not install:
        print("export: set GHIDRA_INSTALL_DIR", file=sys.stderr)
        return 1

    import pyghidra

    pyghidra.start(install_dir=Path(install))

    from ghidra.program.model.symbol import SourceType

    proj = Path(args.project_dir).resolve()
    # open existing project / program without re-import
    with pyghidra.open_program(
        None,
        project_location=str(proj),
        project_name=args.project_name,
        analyze=False,
        program_name=args.program_name,
    ) as flat:
        prog = flat.getCurrentProgram()
        symtab = prog.getSymbolTable()
        exported = []
        it = symtab.getAllSymbols(True)
        while it.hasNext():
            s = it.next()
            if s.getSource() != SourceType.USER_DEFINED:
                continue
            name = str(s.getName())
            a = s.getAddress()
            # Ghidra string form "ssss:oooo" or with space name
            astr = str(a)
            m = re.match(r"^([0-9a-fA-F]+):([0-9a-fA-F]+)$", astr)
            if not m:
                continue
            seg = int(m.group(1), 16)
            off = int(m.group(2), 16)
            # Overlay blocks are named ovlNN; address space may report as 8000:off
            space = str(a.getAddressSpace().getName()) if hasattr(a, "getAddressSpace") else ""
            if space.startswith("ovl"):
                uid = space[:5] if len(space) >= 5 else space
                rid = "%s:%04X" % (uid, off)
            elif seg == OVL_SEG:
                # ambiguous without block name; skip
                continue
            elif seg >= LOAD_SEG:
                rid = "%04X:%04X" % (seg - LOAD_SEG, off)
                uid = ""
            else:
                continue
            exported.append((rid, uid, name))

    # merge into symbols.toml names
    path = Path(args.symbols)
    text = path.read_text() if path.exists() else ""
    updated = 0
    for rid, uid, name in exported:
        if re.search(r'^id\s*=\s*"%s"' % re.escape(rid), text, re.M):
            def repl_name(part: str) -> str:
                part = re.sub(r'^name\s*=\s*".*"', 'name = "%s"' % name, part, count=1, flags=re.M)
                part = re.sub(r'^c_name\s*=\s*".*"', 'c_name = "%s"' % name, part, count=1, flags=re.M)
                return part

            parts = re.split(r"(?=\[\[routine\]\])", text)
            new_parts = []
            for part in parts:
                if re.search(r'^id\s*=\s*"%s"' % re.escape(rid), part, re.M):
                    part = repl_name(part)
                    updated += 1
                new_parts.append(part)
            text = "".join(new_parts)

    path.write_text(text)
    print("export: %d user symbols seen, %d names updated in %s" % (len(exported), updated, path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

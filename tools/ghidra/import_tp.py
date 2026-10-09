#!/usr/bin/env python3
"""import_tp.py: rebuild the Ghidra project for Pool of Radiance (playbook 10).

Loads poolrad/start-unpack.exe as x86:LE:16:Real Mode (MZ loader places the image
at segment 1000h), adds one memory block per overlay from build/re/overlays/,
applies overlay fixups, labels stub thunks and overlay entries, then applies
names from re/symbols.toml.

Usage:
  . tools/setup/env.local.sh
  python3 tools/ghidra/import_tp.py [--no-analyze] [--project-dir build/ghidra]

Requires GHIDRA_INSTALL_DIR and JDK 21+. Writes under build/ghidra/ (gitignored).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOAD_SEG = 0x1000
# Overlay code: Ghidra overlay blocks all mapped at this segment (mutually exclusive views).
# Absolute address for labels: 8000:offset inside block ovlNN.
OVL_SEG = 0x8000


def _parse_symbols(path: Path) -> list[dict]:
    if not path.exists():
        return []
    routines, cur = [], None
    for line in path.read_text().splitlines():
        s = line.strip()
        if s == "[[routine]]":
            if cur and "id" in cur:
                routines.append(cur)
            cur = {}
            continue
        if cur is None or not s or s.startswith("#"):
            continue
        m = re.match(r'^([A-Za-z0-9_]+)\s*=\s*(.+)$', s)
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip()
        if raw.startswith('"') and raw.endswith('"'):
            cur[key] = raw[1:-1]
        else:
            try:
                cur[key] = int(raw, 0)
            except ValueError:
                cur[key] = raw
    if cur and "id" in cur:
        routines.append(cur)
    return routines


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--exe", default=str(ROOT / "poolrad/start-unpack.exe"))
    ap.add_argument("--overlays-json", default=str(ROOT / "build/re/overlays.json"))
    ap.add_argument("--overlays-dir", default=str(ROOT / "build/re/overlays"))
    ap.add_argument("--symbols", default=str(ROOT / "re/symbols.toml"))
    ap.add_argument("--project-dir", default=str(ROOT / "build/ghidra"))
    ap.add_argument("--project-name", default="poolrad")
    ap.add_argument("--no-analyze", action="store_true")
    args = ap.parse_args(argv[1:])

    install = os.environ.get("GHIDRA_INSTALL_DIR")
    if not install or not Path(install).is_dir():
        print(
            "import_tp: set GHIDRA_INSTALL_DIR (source tools/setup/env.local.sh)",
            file=sys.stderr,
        )
        return 1

    overlays_json = Path(args.overlays_json)
    if not overlays_json.exists():
        print("import_tp: %s missing; run make overlays" % overlays_json, file=sys.stderr)
        return 1
    man = json.loads(overlays_json.read_text())
    ovl_dir = Path(args.overlays_dir)
    symbols = _parse_symbols(Path(args.symbols))

    import pyghidra

    pyghidra.start(install_dir=Path(install))

    from ghidra.program.model.listing import CodeUnit
    from ghidra.program.model.symbol import SourceType

    proj_dir = Path(args.project_dir).resolve()
    proj_dir.mkdir(parents=True, exist_ok=True)
    exe = Path(args.exe).resolve()

    # Remove prior project files so rebuild is deterministic.
    for p in proj_dir.glob(args.project_name + ".*"):
        if p.is_file():
            p.unlink()
    lock = proj_dir / (args.project_name + ".lock")
    if lock.exists():
        lock.unlink()
    repo = proj_dir / (args.project_name + ".rep")
    if repo.exists():
        import shutil

        shutil.rmtree(repo)

    print("import_tp: opening %s (analyze=%s)" % (exe, not args.no_analyze))
    with pyghidra.open_program(
        str(exe),
        project_location=str(proj_dir),
        project_name=args.project_name,
        analyze=False,
        language="x86:LE:16:Real Mode",
        program_name="start-unpack",
    ) as flat:
        prog = flat.getCurrentProgram()
        mem = prog.getMemory()
        sym = prog.getSymbolTable()
        listing = prog.getListing()
        space = prog.getAddressFactory().getDefaultAddressSpace()

        def addr(seg: int, off: int = 0):
            # Real Mode space: segment:offset encoded in Ghidra address
            return space.getAddress("%x:%04x" % (seg & 0xFFFF, off & 0xFFFF))

        txn = prog.startTransaction("poolrad import overlays + symbols")
        try:
            # --- overlay blocks ---
            for o in man["overlays"]:
                idx = o["overlay"]
                code_path = ovl_dir / ("ovl%02d.bin" % idx)
                code = code_path.read_bytes()
                # prefer manifest; ovlNN.fix is text lines of "%04x" (tpovl.py)
                fixups = list(o.get("fixups") or [])
                if not fixups:
                    fix_path = ovl_dir / ("ovl%02d.fix" % idx)
                    if fix_path.exists():
                        fixups = [
                            int(line, 16)
                            for line in fix_path.read_text().splitlines()
                            if line.strip()
                        ]
                start = addr(OVL_SEG, 0)
                block_name = "ovl%02d" % idx
                from java.io import ByteArrayInputStream

                # overlay=True: each unit shares 8000:0000 as a separate view
                block = mem.createInitializedBlock(
                    block_name,
                    start,
                    ByteArrayInputStream(bytes(code)),
                    len(code),
                    flat.getMonitor(),
                    True,
                )
                block.setWrite(True)
                block.setExecute(True)
                block.setComment(
                    "GAME.OVR unit %d; fixups patched with segment %04X" % (idx, OVL_SEG)
                )

                # Addresses in this overlay block (space may be named ovlNN)
                def ovl_addr(off: int):
                    return block.getStart().add(off)

                # apply fixups: store overlay load segment at each listed offset
                seg_bytes = struct.pack("<H", OVL_SEG)
                for fo in fixups:
                    if 0 <= fo + 1 < len(code):
                        mem.setBytes(ovl_addr(fo), seg_bytes)

                # label entries
                for e in o["entries"]:
                    a = ovl_addr(e["code_offset"])
                    name = "ovl%02d_e%d" % (idx, e["index"])
                    sym.createLabel(a, name, SourceType.USER_DEFINED)
                    flat.createFunction(a, name)

                # stub thunks in the load image: stub at LOAD_SEG+stub_segment
                stub_seg = LOAD_SEG + o["stub_segment"]
                for e in o["entries"]:
                    stub_off = e["stub_offset"]
                    sa = addr(stub_seg, stub_off)
                    try:
                        b0 = mem.getByte(sa) & 0xFF
                        b1 = mem.getByte(sa.add(1)) & 0xFF
                    except Exception:
                        continue
                    if b0 != 0xCD or b1 != 0x3F:
                        continue
                    tname = "ovl%02d_stub_e%d" % (idx, e["index"])
                    sym.createLabel(sa, tname, SourceType.USER_DEFINED)
                    listing.setComment(
                        sa,
                        CodeUnit.EOL_COMMENT,
                        "thunk -> ovl%02d_e%d (overlay %04X:%04X)"
                        % (idx, e["index"], OVL_SEG, e["code_offset"]),
                    )
                    flat.createFunction(sa, tname)

            # --- apply symbols.toml ---
            applied = 0
            for r in symbols:
                name = r.get("name") or r["id"]
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
                    name = re.sub(r"[^A-Za-z0-9_]", "_", name)
                uid = r.get("unit", "")
                addr_s = r.get("addr") or r["id"]
                try:
                    seg_s, off_s = addr_s.split(":")
                    off_i = int(off_s, 16)
                except Exception:
                    continue
                if uid.startswith("ovl") or seg_s.startswith("ovl"):
                    if uid.startswith("ovl"):
                        idx = int(uid[3:5])
                    else:
                        idx = int(seg_s[3:5])
                    b = mem.getBlock("ovl%02d" % idx)
                    if b is None:
                        continue
                    a = b.getStart().add(off_i)
                else:
                    try:
                        seg_i = int(seg_s, 16)
                    except ValueError:
                        continue
                    a = addr(LOAD_SEG + seg_i, off_i)
                try:
                    sym.createLabel(a, name, SourceType.USER_DEFINED)
                    flat.createFunction(a, name)
                    applied += 1
                except Exception as ex:
                    print("import_tp: label %s at %s failed: %s" % (name, addr_s, ex))

            # entry point label
            flat.createFunction(addr(LOAD_SEG + 0, 6), "PROGRAM_entry")
            print(
                "import_tp: %d overlays, %d symbols applied (from %d entries)"
                % (len(man["overlays"]), applied, len(symbols))
            )
        finally:
            prog.endTransaction(txn, True)

        if not args.no_analyze:
            print("import_tp: running auto-analysis ...")
            flat.analyzeAll(prog)
            print("import_tp: analysis done")

        print(
            "import_tp: project %s/%s  (open with ghidraRun; do not commit build/ghidra)"
            % (proj_dir, args.project_name)
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""rtl_ident.py: identify Turbo Pascal runtime units and name RTL entry points.

Names every System/Crt/Overlay (and Dos-like) routine that is far-called from
outside its own unit. Classification uses INT 21h AH values and known Pascal
string/file record shapes (playbook 10 step 3).

Usage:
  python3 tools/re/rtl_ident.py [--exe poolrad/start-unpack.exe] \
      [--units re/units.toml] [--symbols re/symbols.toml]
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mzutil import DGROUP_PARA, read_mz  # noqa: E402

try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_16
except ImportError:  # pragma: no cover
    Cs = None

# Hand-verified System entries (disassembly in whitepaper / this tool's notes).
SYSTEM_NAMED = {
    0x0000: ("System_init", "[V] sets DS=DGROUP; installs INT vectors"),
    0x00E9: ("System_Halt", "[V] teardown / exit path; clears ExitProc"),
    0x023F: ("System_rtl_023F", "[I] external callee; classify later"),
    0x0254: ("System_FreeMem", "[I] far ptr+size; calls heap helper; retf 6"),
    0x04A2: ("System_IOResult", "[V] xchg InOutRes at DS:4426, return old"),
    0x04A9: ("System_CheckInOutRes", "[V] non-zero InOutRes -> error path"),
    0x0B0B: ("System_StrCopy", "[V] Pascal string copy; retf 4"),
    0x0B25: ("System_StrLCopy", "[V] Pascal string copy with max length; retf 0Ah"),
    0x0B57: ("System_rtl_0B57", "[I] string helper family"),
    0x0B98: ("System_StrConcat", "[V] Pascal string concatenate; retf 4"),
    0x1366: ("System_Str_Format", "[I] builds Pascal string with padding/spaces"),
    0x13E2: ("System_Assign", "[V] fills FileRec (magic D7B0) from path string"),
    0x1410: ("System_Reset", "[V] INT 21h AH=3Dh open existing; FileRec"),
    0x1491: ("System_Close", "[V] INT 21h AH=3Eh close; FileRec"),
    0x14FB: ("System_BlockRead", "[V] INT 21h AH=3Fh; FileRec + count"),
    0x1502: ("System_BlockWrite", "[V] INT 21h AH=40h twin of BlockRead"),
    0x1563: ("System_rtl_1563", "[I] file I/O helper; INT 21h"),
    0x1685: ("System_Move", "[V] Move(src,dst,count); overlapping-safe"),
    0x16A8: ("System_FillChar", "[V] FillChar(dst,count,value)"),
    0x16BC: ("System_DosVersion", "[V] INT 21h AH=30h"),
}

CRT_NAMED = {
    0x0000: ("Crt_init", "[V] INT 10h video probe (smoke)"),
}

OVERLAY_NAMED = {
    0x00A4: ("Overlay_init", "[V] opens GAME.OVR; Assign/Reset path"),
}


def parse_unit_ranges(text: str) -> list[tuple[str, str, int, int]]:
    ranges: list[tuple[str, str, int, int]] = []
    cur: dict = {}

    def flush() -> None:
        if cur.get("_kind") != "resident":
            return
        if not (cur.get("id") and cur.get("code_start") and cur.get("code_end")):
            return
        a = int(cur["code_start"].split(":")[0], 16)
        b = int(cur["code_end"].split(":")[0], 16)
        ranges.append((cur["id"], cur.get("name", cur["id"]), a, b))

    for line in text.splitlines():
        s = line.strip()
        if s in ("[[resident]]", "[[overlay]]"):
            flush()
            cur = {"_kind": "resident" if s == "[[resident]]" else "overlay"}
            continue
        m = re.match(r'^(\w+)\s*=\s*"([^"]*)"', s)
        if m:
            cur[m.group(1)] = m.group(2)
            continue
        m = re.match(r"^(\w+)\s*=\s*(\d+)", s)
        if m:
            cur[m.group(1)] = m.group(2)
    flush()
    return ranges


def owner(ranges, seg: int):
    for uid, name, a, b in ranges:
        if a <= seg < b:
            return uid, name
    return None, None


def set_unit_field(text: str, unit_id: str, field: str, value: str) -> str:
    parts = re.split(r"(?=\[\[resident\]\]|\[\[overlay\]\])", text)
    out = []
    for part in parts:
        if re.search(r'^id\s*=\s*"%s"' % re.escape(unit_id), part, re.M):
            if re.search(r"^%s\s*=" % field, part, re.M):
                part = re.sub(
                    r'^%s\s*=\s*".*"' % field,
                    '%s = "%s"' % (field, value.replace('"', '\\"')),
                    part,
                    count=1,
                    flags=re.M,
                )
            else:
                part = part.rstrip() + '\n%s = "%s"\n' % (field, value.replace('"', '\\"'))
        out.append(part)
    return "".join(out)


def patch_routine(text: str, rid: str, name: str, notes: str, evidence: str) -> str:
    parts = re.split(r"(?=\[\[routine\]\])", text)
    out = []
    found = False
    for part in parts:
        if re.search(r'^id\s*=\s*"%s"' % re.escape(rid), part, re.M):
            found = True
            part = re.sub(r'^name\s*=\s*".*"', 'name = "%s"' % name, part, count=1, flags=re.M)
            part = re.sub(r'^c_name\s*=\s*".*"', 'c_name = "%s"' % name, part, count=1, flags=re.M)
            part = re.sub(
                r'^notes\s*=\s*".*"',
                'notes = "%s"' % notes.replace('"', '\\"'),
                part,
                count=1,
                flags=re.M,
            )
            if re.search(r"^evidence\s*=", part, re.M):
                part = re.sub(
                    r"^evidence\s*=\s*\[.*\]",
                    'evidence = ["%s"]' % evidence.replace('"', '\\"'),
                    part,
                    count=1,
                    flags=re.M,
                )
        out.append(part)
    if not found:
        # append new routine stub (size unknown; enumerator should have created it)
        block = (
            "\n[[routine]]\n"
            'id = "%s"\n'
            'unit = "res00"\n'
            'addr = "%s"\n'
            "size = 0\n"
            'name = "%s"\n'
            'signature = ""\n'
            'c_name = "%s"\n'
            'level = "none"\n'
            'justification = ""\n'
            'notes = "%s"\n'
            'evidence = ["%s"]\n'
        ) % (rid, rid, name, name, notes.replace('"', '\\"'), evidence.replace('"', '\\"'))
        return "".join(out) + block
    return "".join(out)


def classify_unknown(image: bytes, seg: int, off: int) -> tuple[str, str]:
    """Best-effort name from INT 21h in the first bytes / one near call."""
    if Cs is None:
        return "System_rtl_%04X" % off, "[I] external callee; no capstone"
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    lin = seg * 16 + off
    code = image[lin : lin + 100]
    ah = None
    ints = []
    for insn in md.disasm(code, off):
        if insn.mnemonic == "mov" and insn.op_str.startswith("ah,"):
            try:
                ah = int(insn.op_str.split(",")[1].strip(), 0)
            except ValueError:
                pass
        if insn.mnemonic == "int":
            try:
                ints.append((int(insn.op_str, 0), ah))
            except ValueError:
                pass
        if insn.mnemonic in ("retf", "ret") and insn.address > off:
            break
    ah_map = {
        0x3D: "System_DosOpen",
        0x3C: "System_DosCreate",
        0x3E: "System_DosClose",
        0x3F: "System_DosRead",
        0x40: "System_DosWrite",
        0x42: "System_DosSeek",
        0x48: "System_DosAlloc",
        0x49: "System_DosFree",
        0x4A: "System_DosRealloc",
        0x30: "System_DosVersion",
        0x2C: "System_DosGetTime",
        0x2A: "System_DosGetDate",
        0x35: "System_DosGetVector",
        0x25: "System_DosSetVector",
    }
    for ino, a in ints:
        if ino == 0x21 and a in ah_map:
            return ah_map[a] + "_%04X" % off, "[V] INT 21h AH=%02Xh at %04X:%04X" % (a, seg, off)
    # string-ish: lodsb/stosb/movsb without int
    head = code[:16]
    if b"\xac" in head and b"\xaa" in head:
        return "System_StrOp_%04X" % off, "[I] string move opcodes; external callee"
    if b"\xf3\xa4" in code[:40]:
        return "System_MemOp_%04X" % off, "[I] rep movsb; external callee"
    return "System_rtl_%04X" % off, "[I] external far-call target from game/other units"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--exe", default=str(ROOT / "poolrad/start-unpack.exe"))
    ap.add_argument("--units", default=str(ROOT / "re/units.toml"))
    ap.add_argument("--symbols", default=str(ROOT / "re/symbols.toml"))
    args = ap.parse_args(argv[1:])

    _, image = read_mz(args.exe)
    units_path = Path(args.units)
    units_text = units_path.read_text()
    ranges = parse_unit_ranges(units_text)
    if not ranges:
        print("rtl_ident: no resident ranges; run update_units.py", file=sys.stderr)
        return 1

    # Unit tags
    units_text = set_unit_field(units_text, "res00", "name", "System")
    units_text = set_unit_field(
        units_text,
        "res00",
        "evidence",
        "[V] Turbo Pascal System: DS:=%04X; Runtime error / Borland copyright; INT 21h vector install"
        % DGROUP_PARA,
    )
    units_text = set_unit_field(units_text, "res01", "name", "Crt")
    units_text = set_unit_field(
        units_text,
        "res01",
        "evidence",
        "[V] Crt: INT 10h AH=0Fh/11h/08h in init (smoke)",
    )
    units_text = set_unit_field(units_text, "res08", "name", "Overlay")
    units_text = set_unit_field(
        units_text,
        "res08",
        "evidence",
        "[V] Overlay: GAME.OVR / Overlay error / Not enough memory strings",
    )

    # Detect Dos-like unit: resident with many INT 21h sites, not System/Crt/Overlay
    # res02 at 0A31 is adjacent to Crt; mark as Dos [I] if INT 21h present in range
    for uid, name, a, b in ranges:
        if uid in ("res00", "res01", "res08"):
            continue
        blob = image[a * 16 : b * 16]
        if blob.find(b"\xcd\x21") >= 0 and uid == "res02":
            units_text = set_unit_field(units_text, uid, "name", "Dos")
            units_text = set_unit_field(
                units_text,
                uid,
                "evidence",
                "[I] resident unit with INT 21h; likely Turbo Pascal Dos (between Crt and Overlay in typical uses)",
            )
            print("rtl_ident: %s -> Dos [I]" % uid)

    # Far-call graph
    calls = defaultdict(set)  # (seg,off) -> caller paras
    for i in range(len(image) - 5):
        if image[i] != 0x9A:
            continue
        off, seg = struct.unpack_from("<HH", image, i + 1)
        calls[(seg, off)].add(i // 16)

    sym_path = Path(args.symbols)
    sym = sym_path.read_text() if sym_path.exists() else ""

    named = 0
    rtl_units = {"res00", "res01", "res08", "res02"}
    for (seg, off), callers in sorted(calls.items()):
        uid, uname = owner(ranges, seg)
        if uid not in rtl_units and seg not in (0xAF8, 0xA40, 0x42B, 0xA31, 0xA32, 0xAA2):
            continue
        if uid is None:
            # map known segs
            if seg == 0xAF8:
                uid = "res00"
            elif seg == 0xA40:
                uid = "res01"
            elif seg == 0x42B:
                uid = "res08"
            elif seg in (0xA31, 0xA32, 0xAA2):
                uid = "res02"
            else:
                continue
        ext = [c for c in callers if owner(ranges, c)[0] != uid]
        if not ext and off not in (
            list(SYSTEM_NAMED) + list(CRT_NAMED) + list(OVERLAY_NAMED)
        ):
            # still name verified table entries even if only internal
            if not (uid == "res00" and off in SYSTEM_NAMED):
                if not (uid == "res01" and off in CRT_NAMED):
                    if not (uid == "res08" and off in OVERLAY_NAMED):
                        continue

        if uid == "res00" and off in SYSTEM_NAMED:
            name, note = SYSTEM_NAMED[off]
        elif uid == "res01" and off in CRT_NAMED:
            name, note = CRT_NAMED[off]
        elif uid == "res08" and off in OVERLAY_NAMED:
            name, note = OVERLAY_NAMED[off]
        elif uid == "res00":
            name, note = classify_unknown(image, seg, off)
            note = "%s; ext_callers=%d" % (note, len(ext))
        elif uid == "res01":
            name, note = "Crt_rtl_%04X" % off, "[I] Crt entry; ext_callers=%d" % len(ext)
        elif uid == "res08":
            name, note = "Overlay_rtl_%04X" % off, "[I] Overlay entry; ext_callers=%d" % len(ext)
        else:
            name, note = "Dos_rtl_%04X" % off, "[I] Dos-like entry; ext_callers=%d" % len(ext)

        # Prefer unit-base relative id as used by enumerator for resident
        # Enumerator uses start_para:offset_from_unit_start
        start = next(a for u, _, a, _ in ranges if u == uid)
        rel = (seg * 16 + off) - start * 16
        rid = "%04X:%04X" % (start, rel)
        # Also try seg:off form
        rid_alt = "%04X:%04X" % (seg, off)
        if rid not in sym and rid_alt in sym:
            rid = rid_alt
        ev = "far-called from outside %s (%d sites)" % (uid, len(ext))
        sym = patch_routine(sym, rid, name, note, ev)
        named += 1

    # Force-apply hand table even if not in call graph as external
    for off, (name, note) in SYSTEM_NAMED.items():
        rid = "0AF8:%04X" % off
        sym = patch_routine(sym, rid, name, note, "hand-verified System entry")
    for off, (name, note) in CRT_NAMED.items():
        rid = "0A40:%04X" % off
        sym = patch_routine(sym, rid, name, note, "hand-verified Crt entry")
    for off, (name, note) in OVERLAY_NAMED.items():
        rid = "042B:%04X" % off
        sym = patch_routine(sym, rid, name, note, "hand-verified Overlay entry")

    units_path.write_text(units_text)
    sym_path.write_text(sym)
    print("rtl_ident: named/updated %d RTL-facing routines -> %s" % (named, sym_path))
    print(
        "rtl_ident: TP version bound [I]: FBOV + copyright 1983,91 => Turbo Pascal 6.0 or 7.0 "
        "(not 5.x TPOV). Exact pin needs compiler disks."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

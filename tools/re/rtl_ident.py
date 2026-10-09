#!/usr/bin/env python3
"""rtl_ident.py: identify Turbo Pascal runtime units and key RTL routines.

Updates re/units.toml names/evidence for System, Crt, Overlay (when strings prove it)
and patches re/symbols.toml names for a small set of high-confidence RTL entries.

Usage:
  python3 tools/re/rtl_ident.py [--exe poolrad/start-unpack.exe] \
      [--units re/units.toml] [--symbols re/symbols.toml]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mzutil import DGROUP_PARA, read_mz  # noqa: E402

# Strings observed in our image (whitepaper 3.2 / smoke).
STRING_EVIDENCE = [
    # (needle, load-image linear offset hint search, unit id to tag, note)
    (b"Runtime error ", "res00", "System runtime error text"),
    (b"Portions Copyright (c) 1983,91 Borland", "res00", "Borland RTL copyright"),
    (b"GAME.OVR", "res08", "opens overlay file name"),
    (b"Overlay error, program abort!", "res08", "overlay manager abort text"),
    (b"Please insert overlay disk.", None, "overlay disk prompt (see unit owning the bytes)"),
    (b"Not enough memory to run game.", None, "memory error text"),
]


def find_all(image: bytes, needle: bytes) -> list[int]:
    out, i = [], 0
    while True:
        j = image.find(needle, i)
        if j < 0:
            return out
        out.append(j)
        i = j + 1


def owning_resident(linear: int, unit_ranges: list[tuple[str, int, int]]) -> str | None:
    for uid, start, end in unit_ranges:
        if start * 16 <= linear < end * 16:
            return uid
    return None


def parse_unit_ranges(text: str) -> list[tuple[str, int, int]]:
    ranges = []
    cur_id = None
    start = end = None
    for line in text.splitlines():
        s = line.strip()
        if s == "[[resident]]":
            if cur_id and start is not None and end is not None:
                ranges.append((cur_id, start, end))
            cur_id, start, end = None, None, None
            continue
        m = re.match(r'^id\s*=\s*"([^"]+)"', s)
        if m:
            cur_id = m.group(1)
        m = re.match(r'^code_start\s*=\s*"([0-9A-Fa-f]+):', s)
        if m:
            start = int(m.group(1), 16)
        m = re.match(r'^code_end\s*=\s*"([0-9A-Fa-f]+):', s)
        if m:
            end = int(m.group(1), 16)
    if cur_id and start is not None and end is not None:
        ranges.append((cur_id, start, end))
    return ranges


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


def patch_symbol_name(text: str, rid: str, name: str, notes: str) -> str:
    parts = re.split(r"(?=\[\[routine\]\])", text)
    out = []
    for part in parts:
        if re.search(r'^id\s*=\s*"%s"' % re.escape(rid), part, re.M):
            part = re.sub(r'^name\s*=\s*".*"' % (), 'name = "%s"' % name, part, count=1, flags=re.M)
            part = re.sub(r'^c_name\s*=\s*".*"', 'c_name = "%s"' % name, part, count=1, flags=re.M)
            if re.search(r"^notes\s*=", part, re.M):
                part = re.sub(
                    r'^notes\s*=\s*".*"',
                    'notes = "%s"' % notes.replace('"', '\\"'),
                    part,
                    count=1,
                    flags=re.M,
                )
        out.append(part)
    return "".join(out)


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
        print("rtl_ident: no code_start/code_end in units.toml; run update_units.py first", file=sys.stderr)
        return 1

    findings = []
    for needle, force_uid, note in STRING_EVIDENCE:
        locs = find_all(image, needle)
        for lin in locs:
            uid = force_uid or owning_resident(lin, ranges)
            para, off = divmod(lin, 16)
            findings.append((uid, needle.decode("ascii", "replace"), lin, note))
            print(
                "rtl_ident: %r at %04X:%04X (linear %d) -> %s (%s)"
                % (needle, para, off, lin, uid, note)
            )
            if uid in ("res00", "res01", "res08") or (uid and force_uid):
                if uid == "res00":
                    units_text = set_unit_field(units_text, "res00", "name", "System")
                    units_text = set_unit_field(
                        units_text,
                        "res00",
                        "evidence",
                        "[V] Turbo Pascal System: init sets DS=DGROUP %04X; strings %r / Borland copyright; smoke INT 21h vector install"
                        % (DGROUP_PARA, "Runtime error "),
                    )
                if uid == "res01":
                    units_text = set_unit_field(units_text, "res01", "name", "Crt")
                    units_text = set_unit_field(
                        units_text,
                        "res01",
                        "evidence",
                        "[V] Crt: init probes INT 10h AH=0Fh/11h/08h (tools/oracle/smoke.py)",
                    )
                if uid == "res08" or (uid and "Overlay" in note) or needle.startswith(b"GAME.OVR") or needle.startswith(b"Overlay error"):
                    owner = uid or owning_resident(lin, ranges)
                    if owner:
                        units_text = set_unit_field(units_text, owner, "name", "Overlay")
                        units_text = set_unit_field(
                            units_text,
                            owner,
                            "evidence",
                            "[V] Overlay manager: nearby strings GAME.OVR / Overlay error (image offset %d)" % lin,
                        )

    # "Please insert overlay disk." sits in another resident range on this build; note it only.
    for lin in find_all(image, b"Please insert overlay disk."):
        uid = owning_resident(lin, ranges)
        print(
            "rtl_ident: note: 'Please insert overlay disk.' in %s at linear %d (not used to rename)"
            % (uid, lin)
        )

    units_path.write_text(units_text)

    # Symbol renames for inits
    sym_path = Path(args.symbols)
    if sym_path.exists():
        sym = sym_path.read_text()
        sym = patch_symbol_name(sym, "0AF8:0000", "System_init", "rtl_ident: System unit init [V]")
        sym = patch_symbol_name(sym, "0A40:0000", "Crt_init", "rtl_ident: Crt unit init [V]")
        # Overlay init at res08
        sym = patch_symbol_name(sym, "042B:00A4", "Overlay_init", "rtl_ident: Overlay unit init [V]")
        sym_path.write_text(sym)
        print("rtl_ident: patched System_init, Crt_init, Overlay_init in %s" % sym_path)

    print("rtl_ident: %d string hits; units -> %s" % (len(findings), units_path))
    print(
        "rtl_ident: TP version bound [I]: FBOV overlays + copyright '1983,91' => Turbo Pascal 6.0 or 7.0 "
        "(not 5.x TPOV). Exact version still open (SPEC Q1)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

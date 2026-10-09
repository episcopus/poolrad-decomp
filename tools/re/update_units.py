#!/usr/bin/env python3
"""update_units.py: fill code ranges in re/units.toml from the overlay manifest and resident layout.

Usage:
  python3 tools/re/update_units.py [--exe poolrad/start-unpack.exe] \
      [--overlays build/re/overlays.json] [--units re/units.toml] [-o re/units.toml]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from enumerate_routines import _parse_units_toml, resident_ranges  # noqa: E402
from mzutil import DGROUP_PARA, load_overlays_json, read_mz  # noqa: E402


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--exe", default=str(ROOT / "poolrad/start-unpack.exe"))
    ap.add_argument("--overlays", default=str(ROOT / "build/re/overlays.json"))
    ap.add_argument("--units", default=str(ROOT / "re/units.toml"))
    ap.add_argument("-o", "--output", default=str(ROOT / "re/units.toml"))
    args = ap.parse_args(argv[1:])

    hdr, image = read_mz(args.exe)
    man = load_overlays_json(args.overlays)
    text = Path(args.units).read_text()
    residents, overlays = _parse_units_toml(text)
    stub_paras = [o["stub_segment"] for o in man["overlays"]]
    ranges = resident_ranges(residents, len(image) // 16, stub_paras)

    # Preserve hand evidence/name; rewrite structural fields.
    lines = [
        "# Units of the original program (SPEC 6, playbook 10).",
        "# Code ranges filled by tools/re/update_units.py; names/evidence edited by hand.",
        "# Order of resident entries = unit init call order at the entry point.",
        "# Segments are load-image paragraphs (relative to image start, before relocation).",
        "# Ghidra load segment is 1000h: absolute segment = 1000h + load-image paragraph.",
        "",
    ]

    for r in residents:
        uid = r["id"]
        start, end = ranges[uid]
        code_bytes = (end - start) * 16
        lines += [
            "[[resident]]",
            'id = "%s"' % uid,
            'name = "%s"' % r.get("name", uid),
            'kind = "resident"',
            'init = "%s"' % r["init"],
            'segment = "%04X"' % start,
            'code_start = "%04X:0000"' % start,
            'code_end = "%04X:0000"' % end,
            "code_bytes = %d" % code_bytes,
            'evidence = "%s"' % str(r.get("evidence", "")).replace('"', '\\"'),
            'source = "%s"' % r.get("source", ""),
            "",
        ]

    by_stub = {o["stub_segment"]: o for o in man["overlays"]}
    for o in overlays:
        stub = int(str(o["stub_segment"]), 16) if isinstance(o.get("stub_segment"), str) else o.get("stub_segment")
        # match by id
        m = re.match(r"ovl(\d+)", o["id"])
        idx = int(m.group(1)) if m else None
        man_o = next((x for x in man["overlays"] if x["overlay"] == idx), None)
        if man_o is None:
            continue
        lines += [
            "[[overlay]]",
            'id = "%s"' % o["id"],
            'name = "%s"' % o.get("name", o["id"]),
            'kind = "overlay"',
            'stub_segment = "%04X"' % man_o["stub_segment"],
            'ovr_file_offset = "0x%X"' % man_o["file_offset"],
            "code_bytes = %d" % man_o["code_size"],
            "fixup_bytes = %d" % man_o["fixup_size"],
            "entries = %d" % man_o["entry_count"],
            'init_entry = "%s_e0"' % o["id"],
            'evidence = "%s"' % str(o.get("evidence", "")).replace('"', '\\"'),
            'source = "%s"' % o.get("source", ""),
            "",
        ]

    Path(args.output).write_text("\n".join(lines))
    print(
        "update_units: %d resident, %d overlay -> %s (DGROUP para %04X)"
        % (len(residents), len(overlays), args.output, DGROUP_PARA)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

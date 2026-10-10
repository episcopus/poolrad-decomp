#!/usr/bin/env python3
"""enumerate_routines.py: discover routines in the resident image and overlays.

Seeds re/symbols.toml from:
  - overlay entry points (manifest)
  - far-call targets (9Ah) and near-call targets (E8) within each unit range
  - Turbo Pascal frame prologues (55 8B EC)

Sizes are the gap to the next start in the same unit (or to the end of the unit's
code). Bytes that are not reached stay uncovered; make status reports coverage.

Usage:
  python3 tools/re/enumerate_routines.py [--exe poolrad/start-unpack.exe]
      [--overlays build/re/overlays.json] [--units re/units.toml]
      [-o re/symbols.toml] [--merge]
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mzutil import DGROUP_PARA, load_overlays_json, read_mz  # noqa: E402

PROLOGUE = b"\x55\x8b\xec"


def _parse_units_toml(text: str) -> tuple[list[dict], list[dict]]:
    """Minimal TOML reader for our [[resident]] / [[overlay]] tables."""
    residents, overlays, cur, kind = [], [], None, None
    for line in text.splitlines():
        s = line.strip()
        if s == "[[resident]]":
            if cur:
                (residents if kind == "resident" else overlays).append(cur)
            cur, kind = {}, "resident"
            continue
        if s == "[[overlay]]":
            if cur:
                (residents if kind == "resident" else overlays).append(cur)
            cur, kind = {}, "overlay"
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
    if cur:
        (residents if kind == "resident" else overlays).append(cur)
    return residents, overlays


def resident_ranges(
    residents: list[dict],
    image_paras: int,
    stub_paras: list[int] | None = None,
) -> dict[str, tuple[int, int]]:
    """Map unit id -> (start_para, end_para exclusive).

    Cuts are resident init segments, overlay stub segments, DGROUP, and image end
    so interleaved stubs do not inflate resident code_bytes.
    """
    items = []
    for r in residents:
        seg = int(str(r["segment"]), 16) if isinstance(r["segment"], str) else r["segment"]
        items.append((seg, r["id"]))
    items.sort()
    bounds = [p for p, _ in items] + [DGROUP_PARA, image_paras]
    if stub_paras:
        bounds.extend(stub_paras)
    cuts = sorted(set(bounds))
    out = {}
    for seg, uid in items:
        i = cuts.index(seg)
        end = cuts[i + 1]
        out[uid] = (seg, end)
    return out


def add_start(starts: dict[int, str], off: int, why: str) -> None:
    if off < 0:
        return
    if off not in starts:
        starts[off] = why


def find_in_region(image: bytes, base: int, length: int) -> dict[int, str]:
    """Return region-relative offsets of likely routine starts."""
    region = image[base : base + length]
    starts: dict[int, str] = {}
    # prologues
    i = 0
    while True:
        j = region.find(PROLOGUE, i)
        if j < 0:
            break
        add_start(starts, j, "prologue")
        i = j + 1
    # near calls
    for i in range(len(region) - 3):
        if region[i] != 0xE8:
            continue
        rel = struct.unpack_from("<h", region, i + 1)[0]
        tgt = i + 3 + rel
        if 0 <= tgt < length:
            add_start(starts, tgt, "near_call")
    # far calls into this same linear range (segment may differ representation)
    for i in range(len(region) - 5):
        if region[i] != 0x9A:
            continue
        off, seg = struct.unpack_from("<HH", region, i + 1)
        linear = seg * 16 + off
        if base <= linear < base + length:
            add_start(starts, linear - base, "far_call")
    return starts


def sizes_from_starts(starts: list[int], end: int) -> dict[int, int]:
    ordered = sorted(starts)
    out = {}
    for i, s in enumerate(ordered):
        nxt = ordered[i + 1] if i + 1 < len(ordered) else end
        out[s] = max(0, nxt - s)
    return out


def merge_existing(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    text = path.read_text()
    cur = None
    by_id: dict[str, dict] = {}
    for line in text.splitlines():
        s = line.strip()
        if s == "[[routine]]":
            if cur and "id" in cur:
                by_id[cur["id"]] = cur
            cur = {}
            continue
        if cur is None or not s or s.startswith("#"):
            continue
        m = re.match(r'^([A-Za-z0-9_]+)\s*=\s*(.+)$', s)
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip()
        if raw.startswith("["):
            cur[key] = raw
            continue
        if raw.startswith('"') and raw.endswith('"'):
            cur[key] = raw[1:-1]
        else:
            try:
                cur[key] = int(raw, 0)
            except ValueError:
                cur[key] = raw
    if cur and "id" in cur:
        by_id[cur["id"]] = cur
    return by_id


def write_symbols(path: Path, routines: list[dict], header_notes: str) -> None:
    lines = [
        "# Every routine the project knows (SPEC 9.4).",
        "# Generated by tools/re/enumerate_routines.py; hand edits to name/signature/notes are",
        "# preserved on --merge by id. Only tools write `level` (AGENTS.md rule 2).",
        "#",
        header_notes.rstrip(),
        "",
    ]
    for r in routines:
        lines.append("[[routine]]")
        for key in (
            "id",
            "unit",
            "addr",
            "size",
            "name",
            "signature",
            "c_name",
            "level",
            "justification",
            "notes",
            "evidence",
        ):
            if key not in r:
                continue
            val = r[key]
            if key == "evidence":
                if isinstance(val, list):
                    esc = ", ".join('"%s"' % e.replace('"', '\\"') for e in val)
                    lines.append("evidence = [%s]" % esc)
                else:
                    lines.append("evidence = %s" % val)
            elif isinstance(val, int):
                lines.append("%s = %d" % (key, val))
            else:
                lines.append('%s = "%s"' % (key, str(val).replace("\\", "\\\\").replace('"', '\\"')))
        lines.append("")
    path.write_text("\n".join(lines))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--exe", default=str(ROOT / "poolrad/start-unpack.exe"))
    ap.add_argument("--overlays", default=str(ROOT / "build/re/overlays.json"))
    ap.add_argument("--units", default=str(ROOT / "re/units.toml"))
    ap.add_argument("-o", "--output", default=str(ROOT / "re/symbols.toml"))
    ap.add_argument("--merge", action="store_true", help="keep hand-edited fields from existing -o")
    args = ap.parse_args(argv[1:])

    hdr, image = read_mz(args.exe)
    man = load_overlays_json(args.overlays)
    residents, overlays = _parse_units_toml(Path(args.units).read_text())
    image_paras = len(image) // 16
    stub_paras = [o["stub_segment"] for o in man["overlays"]]
    ranges = resident_ranges(residents, image_paras, stub_paras)

    existing = merge_existing(Path(args.output)) if args.merge else {}
    routines: list[dict] = []

    # --- overlays ---
    ovl_dir = Path(args.overlays).resolve().parent / "overlays"
    for o in man["overlays"]:
        idx = o["overlay"]
        uid = "ovl%02d" % idx
        code = Path(ovl_dir / ("ovl%02d.bin" % idx)).read_bytes()
        starts = find_in_region(code, 0, len(code))
        for e in o["entries"]:
            add_start(starts, e["code_offset"], "entry_%d" % e["index"])
        # entry 0 is init
        sizes = sizes_from_starts(list(starts), len(code))
        for off in sorted(starts):
            rid = "%s:%04X" % (uid, off)
            prev = existing.get(rid, {})
            name = prev.get("name") or (
                "%s_init" % uid if any(
                    e["code_offset"] == off and e["index"] == 0 for e in o["entries"]
                )
                else "%s_e%d" % (uid, next(
                    (e["index"] for e in o["entries"] if e["code_offset"] == off),
                    -1,
                ))
                if any(e["code_offset"] == off for e in o["entries"])
                else "%s_fn_%04X" % (uid, off)
            )
            if name.endswith("_e-1"):
                name = "%s_fn_%04X" % (uid, off)
            routines.append(
                {
                    "id": rid,
                    "unit": uid,
                    "addr": rid,
                    "size": sizes[off],
                    "name": name,
                    "signature": prev.get("signature", ""),
                    "c_name": prev.get("c_name", name),
                    "level": prev.get("level", "none"),
                    "justification": prev.get("justification", ""),
                    "notes": prev.get("notes", "auto:%s" % starts[off]),
                    "evidence": prev.get("evidence")
                    if isinstance(prev.get("evidence"), list)
                    else [starts[off]],
                }
            )

    # --- resident ---
    # also accept far-call targets whose segment falls in a unit range
    far_targets: list[tuple[int, int]] = []
    for i in range(len(image) - 5):
        if image[i] != 0x9A:
            continue
        off, seg = struct.unpack_from("<HH", image, i + 1)
        far_targets.append((seg, off))

    for r in residents:
        uid = r["id"]
        start_para, end_para = ranges[uid]
        base = start_para * 16
        length = (end_para - start_para) * 16
        length = min(length, len(image) - base)
        if length <= 0:
            continue
        starts = find_in_region(image, base, length)
        # unit init
        init_seg = int(str(r["segment"]), 16) if isinstance(r["segment"], str) else r["segment"]
        # runtime units without an initialisation part (Dos, Overlay) have init = ""
        init_off = int(str(r["init"]).split(":")[1], 16) if r.get("init") else -1
        if init_off >= 0:
            add_start(starts, init_off, "init")
        for seg, off in far_targets:
            if start_para <= seg < end_para:
                # offset is relative to seg, convert to unit-base relative
                linear = seg * 16 + off
                rel = linear - base
                if 0 <= rel < length:
                    add_start(starts, rel, "far_call")
        sizes = sizes_from_starts(list(starts), length)
        for off in sorted(starts):
            # prefer id as unit-segment:offset when off is within first segment page...
            # Use load-image segment of the byte: (base+off)//16 form with offset in segment
            linear = base + off
            seg = linear // 16
            seg_off = linear % 16
            # Better ids: use unit segment + offset from unit start (common in whitepaper)
            # Playbook: id is ovlNN:XXXX or seg:XXXX. For resident use SSSS:OOOO of the entry.
            rid = "%04X:%04X" % (seg, seg_off)
            # If offset spans, prefer unit_base_para:offset_from_unit for stability
            rid = "%04X:%04X" % (start_para, off)
            prev = existing.get(rid, {})
            is_init = off == init_off
            default_name = (
                r.get("name", uid) + "_init"
                if is_init and r.get("name") not in ("", uid)
                else ("%s_init" % uid if is_init else "%s_fn_%04X" % (uid, off))
            )
            # special-case known System/Crt inits
            if uid == "res00" and is_init:
                default_name = "System_init"
            if uid == "res01" and is_init:
                default_name = "Crt_init"
            name = prev.get("name") or default_name
            routines.append(
                {
                    "id": rid,
                    "unit": uid,
                    "addr": rid,
                    "size": sizes[off],
                    "name": name,
                    "signature": prev.get("signature", ""),
                    "c_name": prev.get("c_name", name),
                    "level": prev.get("level", "none"),
                    "justification": prev.get("justification", ""),
                    "notes": prev.get("notes", "auto:%s" % starts[off]),
                    "evidence": prev.get("evidence")
                    if isinstance(prev.get("evidence"), list)
                    else [starts[off]],
                }
            )

    routines.sort(key=lambda r: (r["unit"], r["id"]))
    covered = sum(r["size"] for r in routines)
    note = (
        "# enumerate_routines: %d routines, sum(sizes)=%d "
        "(sizes are gaps between starts; not a proof of coverage)"
        % (len(routines), covered)
    )
    out = Path(args.output)
    write_symbols(out, routines, note)
    print(
        "enumerate_routines: %d routines -> %s (sum sizes %d)"
        % (len(routines), out, covered)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

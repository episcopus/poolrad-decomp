#!/usr/bin/env python3
"""enumerate_routines.py: discover routines in the resident image and overlays.

Seeds re/symbols.toml from:
  - overlay entry points (manifest)
  - far-call targets (9Ah) and near-call targets (E8) within each unit range
  - Turbo Pascal frame prologues (55 8B EC)

Sizes are the gap to the next start in the same unit (or to the end of the unit's
code). Bytes that are not reached stay uncovered; make status reports coverage.

With --merge nothing already known is lost (escalate-ovl11-20261012040038):
  - forced starts (tools/re/forced_starts.py: re/forced_starts.toml and the hand-verified
    runtime entries of rtl_ident.py) are always starts, so a leaf with no prologue such as
    System.Randomize (0AF8:1247) is never merged into the routine before it;
  - every routine of the existing re/symbols.toml stays a start, with all its fields
    (name, signature, level, review, notes, evidence...);
  - a scanned start strictly inside a routine whose extent is proven (level set by
    `make match WRITE=1`, or evidence citing `make match`) is dropped: the compiler showed
    there is no routine there (the false far-call split ovl11:0435 inside StartGame).

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
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mzutil import DGROUP_PARA, load_overlays_json, read_mz  # noqa: E402
import forced_starts  # noqa: E402

# Frame prologues: push bp; mov bp,sp. Turbo Pascal 6.0 encodes the mov as 89 E5 (every routine
# make match compiles); 8B EC is the other encoding, kept for hand-written assembly.
PROLOGUES = (b"\x55\x89\xe5", b"\x55\x8b\xec")


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
    for prologue in PROLOGUES:
        i = 0
        while True:
            j = region.find(prologue, i)
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
    return {r["id"]: r for r in tomllib.loads(path.read_text()).get("routine", [])}


def proven(r: dict) -> bool:
    """The routine's extent was proven by the compiler (make match), so no routine starts inside."""
    ev = r.get("evidence", [])
    return r.get("level", "none") not in ("", "none") or any("make match" in e for e in ev)


def apply_known(starts: dict[int, str], prefix: str, existing: dict[str, dict],
                forced: dict[str, dict], log: list[str]) -> None:
    """Add forced and existing starts of one unit (ids `prefix` + XXXX); drop scanned starts
    strictly inside a proven routine."""
    def ids():
        for rid in list(existing) + list(forced):
            if rid.startswith(prefix) and len(rid) == len(prefix) + 4:
                yield rid, int(rid[len(prefix):], 16)
    for rid, off in ids():
        if rid in forced:
            starts[off] = "forced"
        else:
            add_start(starts, off, "symbols")
    for rid, r in existing.items():
        if not (rid.startswith(prefix) and proven(r)):
            continue
        a = int(rid[len(prefix):], 16)
        for off in [o for o in starts if a < o < a + r["size"]]:
            fid = "%s%04X" % (prefix, off)
            if fid in forced:
                log.append("CONFLICT forced start %s inside proven routine %s (%d bytes)" % (fid, rid, r["size"]))
            elif fid in existing:
                log.append("kept %s although it lies inside proven routine %s" % (fid, rid))
            else:
                log.append("dropped scanned start %s (%s) inside proven routine %s" % (fid, starts.pop(off), rid))


def record(rid: str, uid: str, size: int, default_name: str, why: str,
           existing: dict[str, dict], forced: dict[str, dict]) -> dict:
    """The routine entry: the existing one with its size refreshed, else a new one."""
    prev = existing.get(rid)
    if prev is not None:
        r = dict(prev)
        r["size"] = size
        return r
    f = forced.get(rid, {})
    name = f.get("name") or default_name
    return {
        "id": rid,
        "unit": uid,
        "addr": rid,
        "size": size,
        "name": name,
        "signature": "",
        "c_name": name,
        "level": "none",
        "justification": "",
        "notes": "auto:%s" % why,
        "evidence": [f["evidence"]] if f else [why],
    }


def write_symbols(path: Path, routines: list[dict], header_notes: str) -> None:
    lines = [
        "# Every routine the project knows (SPEC 9.4).",
        "# Generated by tools/re/enumerate_routines.py; hand edits to name/signature/notes are",
        "# preserved on --merge by id. Only tools write `level` (AGENTS.md rule 2).",
        "#",
        header_notes.rstrip(),
        "",
    ]
    order = ("id", "unit", "addr", "size", "name", "signature", "c_name", "level", "review",
             "justification", "notes", "evidence")
    for r in routines:
        lines.append("[[routine]]")
        for key in list(order) + sorted(k for k in r if k not in order):
            if key not in r:
                continue
            val = r[key]
            if isinstance(val, list):
                esc = ", ".join('"%s"' % str(e).replace("\\", "\\\\").replace('"', '\\"') for e in val)
                lines.append("%s = [%s]" % (key, esc))
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
    ap.add_argument("--forced", default=str(forced_starts.TOML), help="forced starts (re/forced_starts.toml)")
    ap.add_argument("-o", "--output", default=str(ROOT / "re/symbols.toml"))
    ap.add_argument("--merge", action="store_true", help="keep every routine and field of the existing -o")
    args = ap.parse_args(argv[1:])

    hdr, image = read_mz(args.exe)
    man = load_overlays_json(args.overlays)
    residents, overlays = _parse_units_toml(Path(args.units).read_text())
    image_paras = len(image) // 16
    stub_paras = [o["stub_segment"] for o in man["overlays"]]
    ranges = resident_ranges(residents, image_paras, stub_paras)

    existing = merge_existing(Path(args.output)) if args.merge else {}
    forced = forced_starts.forced(Path(args.forced))
    log: list[str] = []
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
        apply_known(starts, uid + ":", existing, forced, log)
        sizes = sizes_from_starts(list(starts), len(code))
        entry_of = {e["code_offset"]: e["index"] for e in o["entries"]}
        for off in sorted(starts):
            rid = "%s:%04X" % (uid, off)
            if off not in entry_of:
                default_name = "%s_fn_%04X" % (uid, off)
            elif entry_of[off] == 0:
                default_name = "%s_init" % uid
            else:
                default_name = "%s_e%d" % (uid, entry_of[off])
            routines.append(record(rid, uid, sizes[off], default_name, starts[off], existing, forced))

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
        # runtime units without an initialisation part (Dos, Overlay) have init = ""
        init_off = int(str(r["init"]).split(":")[1], 16) if r.get("init") else -1
        if init_off >= 0:
            add_start(starts, init_off, "init")
        for seg, off in far_targets:
            if start_para <= seg < end_para:
                # offset is relative to seg, convert to unit-base relative
                rel = seg * 16 + off - base
                if 0 <= rel < length:
                    add_start(starts, rel, "far_call")
        # ids are unit_base_para:offset_from_unit_start
        prefix = "%04X:" % start_para
        apply_known(starts, prefix, existing, forced, log)
        for off in [o for o in starts if o >= length]:
            log.append("CONFLICT start %s%04X lies past the end of %s" % (prefix, off, uid))
            del starts[off]
        sizes = sizes_from_starts(list(starts), length)
        for off in sorted(starts):
            rid = "%s%04X" % (prefix, off)
            is_init = off == init_off
            if uid == "res00" and is_init:
                default_name = "System_init"
            elif uid == "res01" and is_init:
                default_name = "Crt_init"
            elif is_init:
                default_name = (r.get("name", uid) if r.get("name") not in ("", None) else uid) + "_init"
            else:
                default_name = "%s_fn_%04X" % (uid, off)
            routines.append(record(rid, uid, sizes[off], default_name, starts[off], existing, forced))

    # existing routines outside every unit range are kept as they are
    made = {r["id"] for r in routines}
    for rid, r in existing.items():
        if rid not in made:
            log.append("CONFLICT %s (%s) is outside every unit range; kept unchanged" % (rid, r.get("name")))
            routines.append(r)
    for rid in forced:
        if rid not in made:
            log.append("CONFLICT forced start %s is outside every unit range" % rid)

    for r in routines:
        old = existing.get(r["id"])
        if old is not None and old["size"] != r["size"]:
            log.append("size %s %s: %d -> %d" % (r["id"], r["name"], old["size"], r["size"]))
        elif old is None and existing:
            log.append("new %s %s (%d bytes, %s)" % (r["id"], r["name"], r["size"], r["evidence"][0]))
        if old is not None and proven(old) and old["size"] != r["size"]:
            log.append("CONFLICT proven routine %s changed size" % r["id"])

    routines.sort(key=lambda r: (r["unit"], r["id"]))
    covered = sum(r["size"] for r in routines)
    note = (
        "# enumerate_routines: %d routines, sum(sizes)=%d "
        "(sizes are gaps between starts; not a proof of coverage)"
        % (len(routines), covered)
    )
    out = Path(args.output)
    write_symbols(out, routines, note)
    for line in log:
        print("enumerate_routines: " + line)
    print(
        "enumerate_routines: %d routines -> %s (sum sizes %d)"
        % (len(routines), out, covered)
    )
    return 1 if any(line.startswith("CONFLICT") for line in log) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

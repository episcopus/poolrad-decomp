#!/usr/bin/env python3
"""rebuild.py: link the whole game from src/ and compare it with the original (SPEC 8.4, Phase 5).

  .venv/bin/python tools/match/rebuild.py [--json FILE]
  make rebuild

Compiles src/POOL.PAS (the main program, which uses every unit) with the pinned Turbo Pascal 6.0, with
`{$O OVLnn}` for each overlay unit so the linker writes the overlay file, into build/rebuild/POOL.EXE and
POOL.OVR. Then compares, segment by segment, with start-unpack.exe and GAME.OVR:

  layout     where each segment starts and how long it is, ours against the original
  identical  the segment's bytes are the original's, apart from relocation words (EXE relocations,
             overlay fixups) on either side
  image      the load image and the overlay file as a whole

Until every unit is decompiled the rebuild is smaller (skeleton stubs are empty, and the smart linker
drops routines nothing calls), so most segments differ; the report shows how close it is. Phase 5 ends
when every segment is identical, the load image and the relocation table are the original's and the overlay
file is GAME.OVR (the EXE header is the unpacker's output, not the program's). Exit status: 0 when the
rebuild is identical, 1 when it differs or does not compile (the gate of Phase 5).
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))
sys.path.insert(0, str(ROOT / "tools/re"))

import match  # noqa: E402
import tp_toolchain as tp  # noqa: E402
import asm86  # noqa: E402

OUT = ROOT / "build/rebuild"
LIBRARY = ("SYSTEM", "CRT", "DOS", "OVERLAY")


def program_with_overlays(text: str, overlays: list[str]) -> str:
    """POOL.PAS with `{$O unit}` directives for the overlay units (before the main block)."""
    lines = "\n".join("{$O %s}" % u for u in overlays)
    out, n = re.subn(r"\n(begin\b)", "\n" + lines + "\n\n\\1", text, count=1, flags=re.I)
    if not n:
        raise match.MatchError("POOL.PAS: no main block")
    return out


def link_external(unit: str, text: str) -> tuple[str, bytes]:
    """The unit's source with its public routines of the assembly source declared `external` and `{$L}` of
    the object file tools/re/asm86.py assembles from `src/<UNIT>.ASM` (the code the original linked from an
    .OBJ: res03's sound driver). The matcher keeps `{@stub}` declarations; only the rebuild links the
    object. Returns the Pascal text and the object."""
    source = ROOT / "src" / (unit.upper() + ".ASM")
    if not source.exists():
        raise match.MatchError("%s has an external object in re/units.toml but no src/%s.ASM" % (
            unit, unit.upper()))
    try:
        obj, assembler = asm86.assemble(source.read_text(), unit.upper() + "X")
    except asm86.AsmError as e:
        raise match.MatchError("%s: %s" % (source.name, e))
    obj_name = unit.upper() + "X.OBJ"
    for n in assembler.publics:
        text, k = re.subn(r"^\{@stub\}\s+((?:procedure|function)\s+%s\b[^;]*;)\s*begin\s+end;" % re.escape(n),
                         r"\1 external;", text, count=1, flags=re.M | re.I)
        if not k:
            raise match.MatchError("%s: the public %s of %s is not a `{@stub}` line of the unit" % (
                unit, n, source.name))
    text, k = re.subn(r"^(implementation\b[^\n]*\n)", r"\1{$L %s}\n" % obj_name, text, count=1,
                      flags=re.M | re.I)
    if not k:
        raise match.MatchError("%s: no implementation part" % unit)
    return text, obj


def compile_rebuild() -> tuple[Path, Path, Path, str]:
    sources = match.all_sources()
    if match.PROGRAM not in sources:
        raise match.MatchError("no src/%s.PAS" % match.PROGRAM)
    ver = tp.pinned_version()
    bin_dir = tp.TC / ver / "BIN"
    if not (bin_dir / "TPC.EXE").exists():
        raise match.MatchError("Turbo Pascal %s not installed: `make tp-pin`" % ver)
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for f in ("TPC.EXE", "TURBO.TPL"):
        shutil.copy(bin_dir / f, OUT / f)
    overlays = sorted(n for n in sources if n.startswith("OVL"))
    units = tomllib.loads((ROOT / "re/units.toml").read_text())
    external = {u["id"].upper() for u in units["resident"] if u.get("external_from")}
    for name, text in sources.items():
        if name == match.PROGRAM:
            text = program_with_overlays(text, overlays)
        if name in external:
            text, obj = link_external(name.lower(), text)
            (OUT / (name + "X.OBJ")).write_bytes(obj)
        # {$D-,L-}: no debug or local-symbol information, which changes no code and which the comparison
        # does not read (only the map's segments). With it TPC ran out of memory linking the whole game
        # once ovl03, the event dispatcher, was decompiled (2026-10-14).
        (OUT / (name + ".PAS")).write_text("{$D-,L-}\r\n" + text)
    kind, emu = tp.find_emulator(None)
    log = tp.run_tpc(kind, emu, OUT, ["/B", "/GD", "POOL.PAS"])
    exe, ovr, mapf = tp.ci(OUT, "POOL.EXE"), tp.ci(OUT, "POOL.OVR"), tp.ci(OUT, "POOL.MAP")
    if exe is None or ovr is None or mapf is None or "Error" in log:
        errs = "\n".join(l for l in log.splitlines() if "Error" in l)
        raise match.MatchError("rebuild failed to compile:\n%s" % (errs or log))
    return exe, ovr, mapf, log


def overlay_manifest(exe: Path, ovr: Path, dest: Path) -> dict:
    dest.mkdir(parents=True, exist_ok=True)
    out = dest / "overlays.json"
    r = subprocess.run([sys.executable, str(ROOT / "tools/re/tpovl.py"), str(exe), str(ovr), "-o", str(out),
                        "--extract", str(dest)], capture_output=True, text=True)
    if r.returncode or not out.exists():
        raise match.MatchError("tpovl could not read the rebuilt overlays:\n%s%s" % (r.stdout, r.stderr))
    return json.loads(out.read_text())


def same(a: bytes, b: bytes, mask: set[int]) -> bool:
    """Equal apart from the 2-byte words at the offsets in `mask`; b may carry zero paragraph padding."""
    if len(a) > len(b) or any(b[len(a):]) or len(b) - len(a) >= 16:
        return False
    hidden = {o + k for o in mask for k in (0, 1)}
    return all(a[i] == b[i] for i in range(len(a)) if i not in hidden)


def compare(exe: Path, ovr: Path, mapf: Path) -> dict:
    orig = match.Original()
    ours_img, ours_rel = tp.read_mz(exe)
    segs, _pubs = tp.read_map(mapf)
    units = tomllib.loads((ROOT / "re/units.toml").read_text())
    rows = []

    def resident(uid: str, name: str):
        o_bytes, o_seg = orig.segment(uid)
        o_start = o_seg * 16
        mine = segs.get(name)
        if mine is None:
            rows.append({"unit": uid, "kind": "resident", "orig_at": "%04X" % o_seg, "orig_bytes": len(o_bytes),
                         "ours_at": "-", "ours_bytes": 0, "identical": False})
            return
        start, length, _cls = mine
        a = ours_img[start:start + length]
        mask = {r - start for r in ours_rel if start <= r < start + length} | \
               {r - o_start for r in orig.relocs if o_start <= r < o_start + len(o_bytes)}
        rows.append({"unit": uid, "kind": "resident", "orig_at": "%04X" % o_seg, "orig_bytes": len(o_bytes),
                     "ours_at": "%04X" % (start >> 4), "ours_bytes": length, "identical": same(a, o_bytes, mask)})

    resident("main", match.PROGRAM)
    for u in units["resident"]:
        name = u.get("name", "").upper() if u.get("name", "").upper() in LIBRARY else u["id"].upper()
        resident(u["id"], name)
    ours_ovl = overlay_manifest(exe, ovr, OUT / "overlays")
    orig_ovl = json.loads((ROOT / "build/re/overlays.json").read_text())
    by = {o["overlay"]: o for o in ours_ovl["overlays"]}
    for o in orig_ovl["overlays"]:
        uid = "ovl%02d" % o["overlay"]
        mine = by.get(o["overlay"])
        o_code = (ROOT / "build/re/overlays" / (uid + ".bin")).read_bytes()
        if mine is None:
            rows.append({"unit": uid, "kind": "overlay", "orig_bytes": len(o_code), "ours_bytes": 0,
                         "identical": False})
            continue
        a = (OUT / "overlays" / (uid + ".bin")).read_bytes()
        mask = set(mine.get("fixups", [])) | set(o.get("fixups", []))
        rows.append({"unit": uid, "kind": "overlay", "orig_bytes": len(o_code), "ours_bytes": len(a),
                     "orig_entries": len(o["entries"]), "ours_entries": len(mine["entries"]),
                     "identical": len(a) == len(o_code) and same(a, o_code, mask)})
    o_img, o_rel = tp.read_mz(tp.EXE)
    orig_ovr = (ROOT / "poolrad/GAME.OVR").read_bytes()
    image_same = ours_img == o_img
    relocs_same = ours_rel == o_rel
    ovr_same = ovr.read_bytes() == orig_ovr
    first = next((i for i in range(min(len(ours_img), len(o_img))) if ours_img[i] != o_img[i]), None)
    return {"rows": rows,
            "image": {"orig": len(o_img), "ours": len(ours_img), "identical": image_same,
                      "first_difference": first, "differing_bytes": sum(
                          1 for a, b in zip(ours_img, o_img) if a != b) + abs(len(ours_img) - len(o_img))},
            "relocations": {"orig": len(o_rel), "ours": len(ours_rel), "identical": relocs_same},
            "ovr": {"orig": len(orig_ovr), "ours": ovr.stat().st_size, "identical": ovr_same},
            "segments_identical": all(r["identical"] for r in rows),
            # the program is its load image, its relocation table and its overlay file. The EXE header of
            # start-unpack.exe is the unpacker's (padded, with the packed file's checksum), not the program's
            "files_identical": image_same and relocs_same and ovr_same}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--json", help="also write the comparison as JSON")
    a = ap.parse_args(argv)
    try:
        exe, ovr, mapf, log = compile_rebuild()
        result = compare(exe, ovr, mapf)
    except match.MatchError as e:
        print("rebuild: %s" % e)
        return 1
    lines = [l for l in log.splitlines() if re.search(r"lines,", l)]
    print("rebuild: %s" % (lines[0].strip() if lines else "compiled"))
    rows = result["rows"]
    for r in rows:
        print("  %-5s %-8s %-9s ours %6d bytes%s  original %6d bytes%s" % (
            "same" if r["identical"] else "-", r["unit"], r["kind"], r["ours_bytes"],
            (" at %s" % r["ours_at"]) if r.get("ours_at", "-") != "-" else "", r["orig_bytes"],
            (" at %s" % r["orig_at"]) if r.get("orig_at") else ""))
    same_n = sum(r["identical"] for r in rows)
    print("rebuild: %d of %d segments identical (apart from relocations); load image %d of %d bytes%s; "
          "relocations %d of %d%s; overlay file %d of %d bytes%s" % (
              same_n, len(rows), result["image"]["ours"], result["image"]["orig"],
              "" if result["image"]["identical"] else " (%d differ)" % result["image"]["differing_bytes"],
              result["relocations"]["ours"], result["relocations"]["orig"],
              "" if result["relocations"]["identical"] else " (not the same set)",
              result["ovr"]["ours"], result["ovr"]["orig"], "" if result["ovr"]["identical"] else " (differ)"))
    print("rebuild: %s" % ("IDENTICAL: the rebuilt load image, relocation table and overlay file are the "
                           "original's (the EXE header is the unpacker's; SPEC 8.4)" if result["files_identical"]
                           else "DIFFERENT from the original (Phase 5 goal: identical)"))
    (OUT / "result.json").write_text(json.dumps(result, indent=1))
    if a.json:
        Path(a.json).write_text(json.dumps(result, indent=1))
    return 0 if result["files_identical"] else 1


if __name__ == "__main__":
    sys.exit(main())

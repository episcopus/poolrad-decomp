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
when every segment is identical and the files compare equal (SPEC 8.4). Exit status: 0 when the program
compiles and links, 1 otherwise; the comparison itself is a report, not a gate, until Phase 5.
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

OUT = ROOT / "build/rebuild"
LIBRARY = ("SYSTEM", "CRT", "DOS", "OVERLAY")


def program_with_overlays(text: str, overlays: list[str]) -> str:
    """POOL.PAS with `{$O unit}` directives for the overlay units (before the main block)."""
    lines = "\n".join("{$O %s}" % u for u in overlays)
    out, n = re.subn(r"\n(begin\b)", "\n" + lines + "\n\n\\1", text, count=1, flags=re.I)
    if not n:
        raise match.MatchError("POOL.PAS: no main block")
    return out


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
    for name, text in sources.items():
        if name == match.PROGRAM:
            text = program_with_overlays(text, overlays)
        (OUT / (name + ".PAS")).write_text(text)
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
    o_img, _ = tp.read_mz(tp.EXE)
    return {"rows": rows,
            "image": {"orig": len(o_img), "ours": len(ours_img)},
            "ovr": {"orig": (ROOT / "poolrad/GAME.OVR").stat().st_size, "ours": ovr.stat().st_size},
            "files_identical": exe.read_bytes() == tp.EXE.read_bytes() and
                               ovr.read_bytes() == (ROOT / "poolrad/GAME.OVR").read_bytes()}


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
    print("rebuild: %d of %d segments identical (apart from relocations); load image %d of %d bytes; overlay file "
          "%d of %d bytes; files %s" % (same_n, len(rows), result["image"]["ours"], result["image"]["orig"],
                                       result["ovr"]["ours"], result["ovr"]["orig"],
                                       "IDENTICAL" if result["files_identical"] else "differ (Phase 5 goal)"))
    if a.json:
        Path(a.json).write_text(json.dumps(result, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

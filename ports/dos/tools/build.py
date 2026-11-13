#!/usr/bin/env python3
"""build.py: the DOS port's game, from the decompiled Pascal of src/ plus this port's patch series.

  .venv/bin/python ports/dos/tools/build.py [--faithful] [--ref] [--only NAME ...] [--without NAME ...]
  make -C ports/dos game [FAITHFUL=1]

src/ is never edited: its units are copied to build/stage, the fixes of the original that every port takes
(fixes/series at the repository root, named `fixes/<name>` here) and then the patches named in patches/series are applied there
(`patch -p1 --fuzz=0`: a patch that no longer applies exactly fails the build, so a change of src/ under it is
seen), and the pinned Turbo Pascal 6.0 links the stage the way tools/match/rebuild.py links src/ (overlay units
with `{$O}`, res03's sound driver assembled from its .ASM). Out:

  build/link/     POOL.EXE, POOL.OVR, POOL.MAP: what the oracle runs (oracle.layout.rebuilt reads this folder)
  build/game/     START.EXE and GAME.OVR, the two files that replace the original's on a DOS machine
  build/game.json what went in: patches, sizes, hashes

--faithful applies no patch: the result must be the original program (same load image, relocations and
overlay file as poolrad/start-unpack.exe and GAME.OVR), which proves this pipeline before any patch is trusted.

--ref links the series without its speed patches (those under patches/speed/) into build/ref (staged in
build/ref-stage), and publishes nothing: the game whose behaviour the speed patches must keep (tools/func.py).
--only and --without pick from the series (with --ref too): `make sessions` replays a reference without the sound
patches.
Exit status 0 when built (and, with --faithful, identical), 1 otherwise.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
ROOT = PORT.parents[1]
sys.path.insert(0, str(ROOT / "tools/match"))
sys.path.insert(0, str(ROOT / "tools/re"))
sys.path.insert(0, str(ROOT / "fixes"))

import apply as fixes  # noqa: E402
import asm86  # noqa: E402
import match  # noqa: E402
import rebuild  # noqa: E402
import tp_toolchain as tp  # noqa: E402

BUILD = PORT / "build"
STAGE = BUILD / "stage"
LINK = BUILD / "link"
GAME = BUILD / "game"
SERIES = PORT / "patches/series"


class BuildError(Exception):
    pass


def series() -> list[str]:
    """The fixes of fixes/series (`fixes/<name>`), then the patch names of patches/series, in order (`#` starts a comment)."""
    names = ["fixes/" + f.name for f in fixes.series()]
    for line in SERIES.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            names.append(line)
    return names


def use_dirs(stage_dir: Path, link_dir: Path) -> None:
    global STAGE, LINK
    STAGE, LINK = stage_dir, link_dir


def is_speed(name: str) -> bool:
    """A speed patch: it must not change what the game does, only how fast (tools/func.py checks it)."""
    return name.startswith("speed/")


def stage(patches: list[str]) -> None:
    """src/*.PAS and *.ASM copied to build/stage, then each patch applied in order."""
    if STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir(parents=True)
    for p in sorted(match.SRC.iterdir()):
        if p.suffix.upper() in (".PAS", ".ASM"):
            shutil.copy(p, STAGE / p.name)
    for name in patches:
        f = ROOT / name if name.startswith("fixes/") else PORT / "patches" / name
        if not f.exists():
            raise BuildError("patches/series names %s, which is not in patches/" % name)
        r = subprocess.run(["patch", "-p1", "--fuzz=0", "--no-backup-if-mismatch", "--batch", "-d", str(STAGE),
                            "-i", str(f)], capture_output=True, text=True)
        if r.returncode:
            raise BuildError("%s does not apply to src/ any more (refresh it):\n%s%s" % (name, r.stdout, r.stderr))
    for leftover in STAGE.glob("*.rej"):
        raise BuildError("patch left %s" % leftover.name)


def staged_sources() -> dict[str, str]:
    return {p.stem.upper(): p.read_text() for p in sorted(STAGE.glob("*.PAS"))}


def link() -> str:
    """Compile and link the stage into build/link (tools/match/rebuild.py's recipe, on the staged files)."""
    sources = staged_sources()
    if match.PROGRAM not in sources:
        raise BuildError("no %s.PAS in the stage" % match.PROGRAM)
    bin_dir = tp.TC / tp.pinned_version() / "BIN"
    if not (bin_dir / "TPC.EXE").exists():
        raise BuildError("Turbo Pascal not installed: `make tp-pin` at the repository root")
    if LINK.exists():
        shutil.rmtree(LINK)
    LINK.mkdir(parents=True)
    for f in ("TPC.EXE", "TURBO.TPL"):
        shutil.copy(bin_dir / f, LINK / f)
    overlays = sorted(n for n in sources if n.startswith("OVL"))
    units = tomllib.loads((ROOT / "re/units.toml").read_text())
    external = {u["id"].upper() for u in units["resident"] if u.get("external_from")}
    for name, text in sources.items():
        if name == match.PROGRAM:
            text = rebuild.program_with_overlays(text, overlays)
        if name in external:
            text, obj = link_external(name, text)
            (LINK / (name + "X.OBJ")).write_bytes(obj)
        (LINK / (name + ".PAS")).write_text("{$D-,L-}\r\n" + text)   # as rebuild.py: TPC's memory
    kind, emu = tp.find_emulator(None)
    log = tp.run_tpc(kind, emu, LINK, ["/B", "/GD", "POOL.PAS"])
    if any(tp.ci(LINK, n) is None for n in ("POOL.EXE", "POOL.OVR", "POOL.MAP")) or "Error" in log:
        errs = "\n".join(l for l in log.splitlines() if "Error" in l)
        raise BuildError("the stage does not compile:\n%s" % (errs or log))
    return log


def link_external(name: str, text: str) -> tuple[str, bytes]:
    """rebuild.link_external on the staged .ASM (a patch may change it) instead of src/'s: the unit's publics
    of the assembly source declared `external`, `{$L}` of the object tools/re/asm86.py assembles."""
    source = STAGE / (name + ".ASM")
    if not source.exists():
        raise BuildError("%s has an external object in re/units.toml but no %s.ASM" % (name, name))
    try:
        obj, assembler = asm86.assemble(source.read_text(), name + "X")
    except asm86.AsmError as e:
        raise BuildError("%s: %s" % (source.name, e))
    for n in assembler.publics:
        text, k = re.subn(r"^\{@stub\}\s+((?:procedure|function)\s+%s\b[^;]*;)\s*begin\s+end;" % re.escape(n),
                          r"\1 external;", text, count=1, flags=re.M | re.I)
        if not k:
            raise BuildError("%s: the public %s of %s is not a `{@stub}` line of the unit" % (name, n, source.name))
    text, k = re.subn(r"^(implementation\b[^\n]*\n)", r"\1{$L %sX.OBJ}\n" % name, text, count=1, flags=re.M | re.I)
    if not k:
        raise BuildError("%s: no implementation part" % name)
    return text, obj


def changed_segments() -> list[str]:
    """The units whose code differs from the original's (tools/match/rebuild.py's comparison, relocation words
    excepted): what the patches touched, and nothing else, is the check."""
    saved = rebuild.OUT
    rebuild.OUT = BUILD / "compare"                 # where compare() extracts the overlays (not build/rebuild)
    try:
        result = rebuild.compare(tp.ci(LINK, "POOL.EXE"), tp.ci(LINK, "POOL.OVR"), tp.ci(LINK, "POOL.MAP"))
    finally:
        rebuild.OUT = saved
    return [r["unit"] for r in result["rows"] if not r["identical"]]


def identical_to_original() -> tuple[bool, str]:
    img, rel = tp.read_mz(tp.ci(LINK, "POOL.EXE"))
    o_img, o_rel = tp.read_mz(tp.EXE)
    ovr_same = tp.ci(LINK, "POOL.OVR").read_bytes() == (ROOT / "poolrad/GAME.OVR").read_bytes()
    what = "load image %s, relocations %s, overlay file %s" % (
        "same" if img == o_img else "differs", "same" if rel == o_rel else "differ", "same" if ovr_same else "differs")
    return img == o_img and rel == o_rel and ovr_same, what


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def publish(patches: list[str]) -> dict:
    """START.EXE and GAME.OVR in build/game (the names the original's disks use; res08 opens GAME.OVR)."""
    if GAME.exists():
        shutil.rmtree(GAME)
    GAME.mkdir(parents=True)
    shutil.copy(tp.ci(LINK, "POOL.EXE"), GAME / "START.EXE")
    shutil.copy(tp.ci(LINK, "POOL.OVR"), GAME / "GAME.OVR")
    info = {"patches": patches,
            "files": {n: {"bytes": (GAME / n).stat().st_size, "sha256": sha256(GAME / n)}
                      for n in ("START.EXE", "GAME.OVR")}}
    (BUILD / "game.json").write_text(json.dumps(info, indent=1) + "\n")
    return info


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--faithful", action="store_true", help="no patch: must link the original program")
    ap.add_argument("--only", action="append", metavar="NAME", help="apply only these patches of the series")
    ap.add_argument("--ref", action="store_true", help="the series without speed patches, into build/ref only")
    ap.add_argument("--without", action="append", metavar="NAME", help="leave these patches of the series out")
    a = ap.parse_args(argv)
    patches = [] if a.faithful else series()
    if a.only:
        unknown = set(a.only) - set(patches)
        if unknown:
            print("build: not in patches/series: %s" % ", ".join(sorted(unknown)))
            return 1
        patches = [p for p in patches if p in a.only]
    if a.without:
        unknown = set(a.without) - set(patches)
        if unknown:
            print("build: not in patches/series: %s" % ", ".join(sorted(unknown)))
            return 1
        patches = [p for p in patches if p not in a.without]
    if a.ref:
        use_dirs(BUILD / "ref-stage", BUILD / "ref")
        try:
            stage([p for p in patches if not is_speed(p)])
            link()
        except BuildError as e:
            print("build: %s" % e)
            return 1
        print("build: reference (no speed patch) in %s" % LINK.relative_to(ROOT))
        return 0
    try:
        stage(patches)
        log = link()
    except BuildError as e:
        print("build: %s" % e)
        return 1
    lines = [l.strip() for l in log.splitlines() if re.search(r"lines,", l)]
    info = publish(patches)
    print("build: %s; patches: %s" % (lines[0] if lines else "compiled", ", ".join(patches) or "none (faithful)"))
    for n, f in info["files"].items():
        print("  %-9s %7d bytes  %s" % (n, f["bytes"], (GAME / n).relative_to(ROOT)))
    same, what = identical_to_original()
    changed = changed_segments()
    info["changed_units"] = changed
    (BUILD / "game.json").write_text(json.dumps(info, indent=1) + "\n")
    print("build: against the original: %s; units whose code differs: %s" % (what, ", ".join(changed) or "none"))
    if a.faithful and not same:
        print("build: FAIL: with no patch the build must be the original program")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

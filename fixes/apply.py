#!/usr/bin/env python3
"""apply.py: the fixes of fixes/series applied to a copy of src/ (fixes/README.md).

  python3 fixes/apply.py DIR      copy src/*.PAS and *.ASM to DIR (emptied first) and apply every fix

src/ is the original program and never changes; a port that wants the fixes translates or compiles the copy. Used by
tools/c/pas2c.py (the C translation, c/game, and the CoCo 3 port's) and ports/dos/tools/build.py (the DOS port).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

FIXES = Path(__file__).resolve().parent
ROOT = FIXES.parent
SERIES = FIXES / "series"


def series() -> list[Path]:
    """The patches of fixes/series, in order (`#` starts a comment)."""
    out = []
    for line in SERIES.read_text().splitlines():
        name = line.split("#", 1)[0].strip()
        if name:
            f = FIXES / name
            if not f.exists():
                raise SystemExit("fixes/series names %s, which is not in fixes/" % name)
            out.append(f)
    return out


def apply(stage: Path, patches: list[Path] | None = None) -> None:
    """Apply the patches (default: the series) to the Pascal already in `stage`; one that does not apply exactly fails."""
    for f in series() if patches is None else patches:
        r = subprocess.run(["patch", "-p1", "--fuzz=0", "--no-backup-if-mismatch", "--batch", "-d", str(stage),
                            "-i", str(f)], capture_output=True, text=True)
        if r.returncode:
            raise SystemExit("fixes/%s does not apply to src/ any more (refresh it):\n%s%s" % (f.name, r.stdout, r.stderr))
    for leftover in stage.glob("*.rej"):
        raise SystemExit("a fix left %s" % leftover.name)


def stage(dest: Path) -> Path:
    """src/*.PAS and *.ASM copied to `dest` (emptied first) with every fix applied; returns `dest`."""
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for p in sorted((ROOT / "src").iterdir()):
        if p.suffix.upper() in (".PAS", ".ASM"):
            shutil.copy(p, dest / p.name)
    apply(dest)
    return dest


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    print(stage(Path(sys.argv[1])))

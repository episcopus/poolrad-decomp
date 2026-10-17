#!/usr/bin/env python3
"""c_golden.py: play every session on the C translation and compare it with the original (SPEC 8.5, Phase 7).

  .venv/bin/python tools/c/c_golden.py [--session NAME ...] [--export] [--keep-going]
  make c-golden [SESSION=name]

For each `tests/sessions/NAME.keys` this exports the oracle's run of the original (build/c/replay/NAME.rpl;
`tools/c/export_replay.py`, about a minute for a long session; kept until the script or the golden changes), then
runs `build/cmake/poolrad_replay` on it: every read of the outside world must be the one the original made, the
screen must equal the original's at every checkpoint, and the files written and the number of Random calls must
match. Exit status 1 when any session differs.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/c"))

REPLAY = ROOT / "build/cmake/poolrad_replay"
OUT = ROOT / "build/c/replay"
SESSIONS = ROOT / "tests/sessions"


def stale(rpl: Path, name: str) -> bool:
    if not rpl.exists():
        return True
    newest = max((SESSIONS / (name + ".keys")).stat().st_mtime,
                 (ROOT / "poolrad/start-unpack.exe").stat().st_mtime,
                 (ROOT / "tools/c/export_replay.py").stat().st_mtime)
    return rpl.stat().st_mtime < newest


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--session", action="append")
    ap.add_argument("--export", action="store_true", help="export again even if the replay file is current")
    ap.add_argument("--keep-going", action="store_true")
    a = ap.parse_args(argv)
    if not REPLAY.exists():
        print("build the replay tool first: make c-build", file=sys.stderr)
        return 2
    names = a.session or sorted(p.stem for p in SESSIONS.glob("*.keys"))
    rc = 0
    for n in names:
        rpl = OUT / (n + ".rpl")
        if a.export or stale(rpl, n):
            import export_replay
            t = time.time()
            if export_replay.export(n, rpl, check_golden=(SESSIONS / "golden" / n).exists()) != 0:
                rc = 1
                if not a.keep_going:
                    return rc
                continue
            print("[%s] exported in %.0fs" % (n, time.time() - t))
        t = time.time()
        p = subprocess.run([str(REPLAY), "--data", str(ROOT / "poolrad"), "--save", str(ROOT / "build/c/save"), str(rpl)],
                           capture_output=True, text=True)
        lines = [l for l in p.stdout.splitlines() if l.strip()]
        print("\n".join(lines[-3:]) + "  (%.1fs)" % (time.time() - t))
        if p.returncode != 0:
            rc = 1
            if not a.keep_going:
                break
    return rc


if __name__ == "__main__":
    sys.exit(main())

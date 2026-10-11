#!/usr/bin/env python3
"""p3_check.py: verify the Phase 3 exit criteria (SPEC 10, P3 row).

  .venv/bin/python tools/agent/p3_check.py
  make check (plus the slow suites: make test, make fuzz, make sessions)

Checks, in order (stops at the first failure):

  1. DGROUP mirror is up to date with re/dseg.toml (gen_dseg --check).
  2. Host binary and hybrid library build (cmake).
  3. Portability lint passes over the engine.
  4. Fuzz passes for the three spike routines (writes L2 verdicts).
Sessions with the C routines (record/replay, tools/oracle/replay.py) run once
in `make sessions`, which `make check` calls after this tool; they are not
repeated here. `make test` (pytest, fast set) also runs from the Makefile.
Exit 0 with a summary when green.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PY = str(ROOT / ".venv/bin/python") if (ROOT / ".venv/bin/python").exists() else "python3"


def run(cmd: list[str], what: str) -> None:
    print("p3-check: %s: %s" % (what, " ".join(cmd[2:] if cmd[0] == PY else cmd)), flush=True)
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        print("p3-check: FAIL: %s (exit %d)" % (what, r.returncode))
        sys.exit(1)
    print("p3-check: ok: %s" % what)


def smoke_host() -> None:
    print("p3-check: host self-test", flush=True)
    r = subprocess.run(["./build/host/poolrad", "--self-test"], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0 or "host self-test ok" not in r.stdout:
        print("p3-check: FAIL: host self-test:\n%s\n%s" % (r.stdout, r.stderr))
        sys.exit(1)
    print("p3-check: ok: %s" % r.stdout.strip())
    env = dict(os.environ, SDL_VIDEO_DRIVER="dummy")
    print("p3-check: host smoke: build/host/poolrad (SDL dummy driver)", flush=True)
    r = subprocess.run(["./build/host/poolrad"], cwd=ROOT, env=env, capture_output=True, text=True)
    if r.returncode != 0 or "poolrad P3 spike" not in r.stdout:
        print("p3-check: FAIL: host smoke:\n%s\n%s" % (r.stdout, r.stderr))
        sys.exit(1)
    print("p3-check: ok: host smoke: %s" % r.stdout.strip())


def main() -> int:
    run([PY, "tools/re/gen_dseg.py", "--check"], "dseg mirror up to date")
    run(["cmake", "--build", "build/host"], "host + hybrid build")
    smoke_host()
    run([PY, "tools/lint/portability.py"], "portability lint")
    for fn in ("0AF8:1685", "0AF8:16A8", "0AF8:11C0"):
        run([PY, "tools/fuzz/fuzz.py", "--routine", fn], "fuzz %s" % fn)
    print("p3-check: GREEN: memory-model spike passes in both builds")
    print("p3-check: note: the session replays run once, in `make sessions` (part of `make check`)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

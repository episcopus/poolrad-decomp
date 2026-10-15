#!/usr/bin/env python3
"""Run the unchanged proof gates plus safety checks, and receipt the exact checked inputs.

A receipt is operational evidence, not authentication. It prevents accidental hand-off cleanup on a
different or unchecked merged tree. Fingerprints include tools, sources, registry, goldens and compiler.
"""
from __future__ import annotations

import hashlib
import fcntl
import argparse
import json
import subprocess
import sys
import time
import uuid
import os
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import control

PATHS = ("src", "re", "tools", "tests", "poolrad", "Makefile", "AGENTS.md", "pyproject.toml", "uv.lock",
         "docs/design", "docs/process", "docs/spec", "docs/reference/prior-art.md")
STAGES = (("inputs", "tools/setup/inputs.py", "--check"),
          ("safety", "tools/agent/safety.py"),
          ("learning", "tools/agent/learning.py", "--check"),
          ("tests", "-m", "pytest", "-q", "-m", "not slow", "tests/unit"),
          ("match", "tools/agent/activity.py", "match", "--", "--all"),
          ("readability", "tools/match/readability.py"),
          ("rebuild", "tools/match/rebuild.py"),
          ("golden", "tools/oracle/golden.py", "--check"),
          # Phase 5: the rebuilt program plays every golden session, behaviour and state (playbook 50);
          # never cached: it depends on src/, which the original goldens do not
          ("rebuilt-golden", "tools/oracle/golden.py", "--check", "--rebuilt", "--strict-state"),
          # the sound driver, every tune on both devices: the hardware trace of the rebuild is the original's
          ("rebuilt-sound", "tools/oracle/soundprobe.py", "--check", "--rebuilt"))


def fingerprint() -> str:
    paths = common.git("ls-files", "-z", "--", *PATHS).split("\0")
    digest = hashlib.sha256()
    for rel in sorted(p for p in paths if p):
        path = common.ROOT / rel
        digest.update(rel.encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest() if path.exists() else b"missing")
    # Include untracked source/tool files too, so an unchecked local unit cannot disappear from a receipt.
    for rel in sorted(common.git("ls-files", "--others", "--exclude-standard", "-z", "--", *PATHS).split("\0")):
        if rel:
            digest.update(rel.encode() + b"\0" + hashlib.sha256((common.ROOT / rel).read_bytes()).digest())
    for path in sorted((common.ROOT / "build/toolchain/tp60-1991/BIN").glob("*")):
        if path.name.upper() in ("TPC.EXE", "TURBO.TPL"):
            digest.update(path.name.upper().encode() + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def receipts() -> Path:
    directory = common.common_dir() / "poolrad-checks"
    directory.mkdir(exist_ok=True)
    return directory


def run_stage(args: list[str], env: dict):
    return subprocess.run([sys.executable, *args], cwd=common.ROOT, env=env)


def require_receipt() -> dict:
    current = fingerprint()
    path = receipts() / (current + ".json")
    if not path.exists():
        raise ValueError("no passing make check receipt for these exact inputs; check the merged result first")
    record = json.loads(path.read_text())
    if record.get("fingerprint") != current or record.get("stages") != [s[0] for s in STAGES]:
        raise ValueError("invalid check receipt; rerun make check")
    return record


def main(argv=()) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--fresh", action="store_true", help="rerun even unchanged original goldens")
    options = ap.parse_args(argv)
    try:
        before = fingerprint()
        # A new failed check must not leave an older passing receipt usable for the same inputs.
        # Serialize identical-input checks without blocking claims or operator stop controls.
        with (receipts() / (before + ".lock")).open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            path = receipts() / (before + ".json")
            path.unlink(missing_ok=True)
            import cache
            elapsed, modes = {}, {}
            check_id = uuid.uuid4().hex
            env = {**os.environ, "POOLRAD_CHECK_ID": check_id}
            for name, *args in STAGES:
                started = time.monotonic()
                key = cache.golden_key() if name == "golden" else None
                if key and not options.fresh and cache.hit(key):
                    elapsed[name], modes[name] = round(time.monotonic() - started, 3), "cached-original"
                    print("check: original golden inputs unchanged; cached pass %s" % key[:12], flush=True)
                    continue
                if key:
                    cache.invalidate(key)
                result = run_stage(args, env)
                elapsed[name] = round(time.monotonic() - started, 3)
                modes[name] = "fresh"
                if result.returncode:
                    control.event("check-failed", fingerprint=before, stage=name, seconds=elapsed)
                    print("check: %s failed; no receipt written" % name, flush=True)
                    return 1
                if key:
                    if cache.golden_key() != key:
                        raise ValueError("original golden inputs changed during the check")
                    cache.save(key)
            if fingerprint() != before:
                control.event("check-failed", fingerprint=before, stage="inputs-changed", seconds=elapsed)
                raise ValueError("checked inputs changed during make check; rerun after writers finish")
            record = {"fingerprint": before, "stages": [s[0] for s in STAGES], "seconds": elapsed,
                      "commit": common.git("rev-parse", "HEAD"), "check_id": check_id, "stage_modes": modes}
            common.atomic_write(path, json.dumps(record, sort_keys=True) + "\n")
            control.event("check-passed", **record)
            print("check: passed; receipt %s; stages %s" % (before[:12], elapsed), flush=True)
            return 0
    except (ValueError, RuntimeError, OSError) as e:
        print("check: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

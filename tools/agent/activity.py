#!/usr/bin/env python3
"""Attribute bounded CLI activity and proof results to the lock's immutable agent/task identity."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import os
import hashlib
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import control

COMMANDS = {"match": "tools/match/match.py", "tpc": "tools/re/tp_toolchain.py",
            "packet": "tools/agent/packet.py", "readability": "tools/match/readability.py"}


def source_revision(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted((root / "src").glob("*.PAS")):
        digest.update(path.name.encode() + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def results(output: str) -> dict:
    matched = [dict(name=m[1], routine=m[2], code_bytes=int(m[3]), pool_bytes=int(m[4])) for m in
               re.finditer(r"^MATCH\s+(\S+)\s+(\S+)\s+(\d+) bytes code,\s+(\d+) pool", output, re.M)]
    return {"matched": len(matched), "code_bytes": sum(m["code_bytes"] for m in matched),
            "pool_bytes": sum(m["pool_bytes"] for m in matched), "routines": matched,
            "nested": len(re.findall(r"^NESTED\s", output, re.M)),
            "differences": len(re.findall(r"^DIFF\s", output, re.M)),
            "failed": [dict(name=m[1], routine=m[2], detail=m[3]) for m in
                       re.finditer(r"^DIFF\s+(\S+)\s+(\S+)\s+(.+)$", output, re.M)]}


def run(kind: str, args: list[str]) -> int:
    if kind not in COMMANDS:
        raise ValueError("activity only runs the fixed project tools, never arbitrary commands")
    started = time.monotonic()
    unit = args[0] if args and re.fullmatch(r"(?:ovl|res)\d\d", args[0]) else None
    revision = source_revision(common.ROOT) if unit else None
    source = common.ROOT / "src" / (unit.upper() + ".PAS") if unit else None
    draft = source.read_text() if source and source.exists() else None
    try:
        names = {r["id"]: r["name"] for r in common.routines() if r["unit"] == unit} if unit else {}
    except (ValueError, KeyError):
        names = {}
    command = [sys.executable, COMMANDS[kind], *args]
    process = subprocess.Popen(command, cwd=common.ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, bufsize=1)
    output = []
    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            output.append(line)
        rc = process.wait()
    except BaseException:
        process.terminate()
        process.wait()
        raise
    summary = results("".join(output)) if kind == "match" else {}
    trial = None
    if kind == "match" and rc and unit and draft is not None and source_revision(common.ROOT) == revision:
        # Keep the actual failed draft even if its owner later stubs it for a safe hand-off. Advice
        # must not be paid to reconstruct a lost attempt from vague notes or stale main source.
        directory = common.common_dir() / "poolrad-trials"
        directory.mkdir(exist_ok=True)
        trial = unit + "-" + revision
        common.atomic_write(directory / (trial + ".json"), json.dumps(dict(
            unit=unit, revision=revision, source=draft, names=names), sort_keys=True) + "\n")
    control.event("activity", tool=kind, args=args, returncode=rc,
                  unit=unit, revision=revision, trial=trial,
                  check_id=os.environ.get("POOLRAD_CHECK_ID"),
                  seconds=round(time.monotonic() - started, 3), **summary)
    return rc


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("kind", choices=COMMANDS)
    ap.add_argument("args", nargs=argparse.REMAINDER)
    a = ap.parse_args(argv)
    args = a.args[1:] if a.args[:1] == ["--"] else a.args
    try:
        return run(a.kind, args)
    except (ValueError, RuntimeError, OSError) as e:
        print("activity: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

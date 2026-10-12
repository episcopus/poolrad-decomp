"""Content-keyed reuse of the unchanged ORIGINAL golden check, never Pascal matcher verdicts.

Inputs include every project tool, pinned game file, session/golden, state definition, unit map and
runtime/dependency version. symbols.toml is parsed on every lookup; its names/levels/notes are not used
by the original-golden path (trace.load_symbols returns them but no call tracer is installed). Any
oracle/tool change invalidates the cache. FRESH=1 forces reexecution. A hit is not a rebuilt-game test.
"""
from __future__ import annotations

import hashlib
import importlib.metadata
import json
import platform
import sys
import time
import tomllib
from pathlib import Path

import common

SCHEMA = 1
MAX_AGE = 24 * 60 * 60
GOLDEN_INPUTS = ("tools", "poolrad", "tests/sessions", "re/state.toml", "re/inputs.toml",
                 "re/units.toml", "pyproject.toml", "uv.lock")


def golden_key(root: Path | None = None) -> str:
    root = root or common.ROOT
    # Do not hide a broken registry behind a cache hit: the original oracle parses it too.
    tomllib.loads((root / "re/symbols.toml").read_text())
    digest = hashlib.sha256()
    digest.update(json.dumps({"schema": SCHEMA, "python": sys.version, "platform": platform.platform(),
        "packages": {p: importlib.metadata.version(p) for p in ("unicorn", "capstone", "pillow")}},
        sort_keys=True).encode())
    for rel in GOLDEN_INPUTS:
        p = root / rel
        paths = sorted(p.rglob("*")) if p.is_dir() else [p]
        for path in paths:
            # Generated Python bytecode and local vendor tools are not original-oracle inputs.
            if path.is_file() and "__pycache__" not in path.parts and not path.is_relative_to(root / "tools/vendor"):
                digest.update(path.relative_to(root).as_posix().encode() + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def directory() -> Path:
    p = common.common_dir() / "poolrad-cache" / "original-golden"
    p.mkdir(parents=True, exist_ok=True)
    return p


def hit(key: str, now: float | None = None) -> bool:
    p = directory() / (key + ".json")
    try:
        record = json.loads(p.read_text())
        age = (time.time() if now is None else now) - record["time"]
        return record.get("schema") == SCHEMA and record.get("key") == key and \
            record.get("result") == "passed" and 0 <= age < MAX_AGE
    except (OSError, ValueError, KeyError, TypeError):
        return False


def save(key: str) -> None:
    common.atomic_write(directory() / (key + ".json"), json.dumps({
        "schema": SCHEMA, "key": key, "result": "passed", "time": time.time()}) + "\n")


def invalidate(key: str) -> None:
    (directory() / (key + ".json")).unlink(missing_ok=True)

"""common.py: what the agent tools share: the main checkout, the lock directory, unit completion.

Every git worktree of this clone sees the same lock directory: it lives in the clone's common git
directory (`git rev-parse --git-common-dir`), never in a working tree and never in a commit, so agents
working in parallel worktrees on one machine see each other's claims.
"""
from __future__ import annotations

import os
import re
import subprocess
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def git(*args: str, cwd: Path = ROOT) -> str:
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout.strip()


def common_dir() -> Path:
    p = Path(git("rev-parse", "--git-common-dir"))
    return p if p.is_absolute() else (ROOT / p).resolve()


def main_checkout() -> Path:
    """The working tree that owns the clone's .git directory (where build/toolchain lives)."""
    return common_dir().parent


def lock_dir() -> Path:
    d = common_dir() / "poolrad-locks"
    d.mkdir(exist_ok=True)
    return d


def lock_path(unit: str) -> Path:
    return lock_dir() / ("%s.lock" % unit)


def try_lock(unit: str, body: str) -> bool:
    """Create the lock atomically; False when someone holds it."""
    try:
        fd = os.open(lock_path(unit), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        return False
    with os.fdopen(fd, "w") as f:
        f.write(body)
    return True


def routines() -> list[dict]:
    return tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]


def unit_complete(unit: str, rs: list[dict] | None = None) -> bool:
    rs = [r for r in (rs or routines()) if r["unit"] == unit]
    return bool(rs) and all(r.get("level") in ("L2", "L3") for r in rs)


def queue() -> list[dict]:
    return tomllib.loads((ROOT / "work/queue.toml").read_text()).get("unit", [])


def open_must_fix(unit: str) -> list[str]:
    """Open must-fix findings of the unit's review (work/reviews/<unit>.md): `- [ ] must-fix ...`."""
    p = ROOT / "work/reviews" / ("%s.md" % unit)
    if not p.exists():
        return []
    return [l.strip() for l in p.read_text().splitlines() if re.match(r"\s*-\s*\[ \]\s*must-fix\b", l, re.I)]

"""common.py: what the agent tools share: the main checkout, the lock directory, unit completion.

Every git worktree of this clone sees the same lock directory: it lives in the clone's common git
directory (`git rev-parse --git-common-dir`), never in a working tree and never in a commit, so agents
working in parallel worktrees on one machine see each other's claims.
"""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
from functools import lru_cache
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def identifier(value: str, label: str = "identifier") -> str:
    """Coordination keys are names, never paths, options or injected field lines."""
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,79}", value):
        raise ValueError("%s must be 1..80 lowercase letters, digits, underscores or hyphens" % label)
    return value


def fields(text: str) -> dict[str, str]:
    out = {}
    for line in text.splitlines():
        if " = " not in line:
            continue
        key, value = line.split(" = ", 1)
        if key in out:
            raise ValueError("duplicate coordination field: %s" % key)
        out[key] = value
    return out


def single_line(value: str, label: str) -> str:
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("%s must be a single line without control characters" % label)
    return value


def atomic_write(path: Path, text: str) -> None:
    """Readers see the old record or the complete new one, never half a heartbeat."""
    fd, name = tempfile.mkstemp(prefix=".%s." % path.name, dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def git(*args: str, cwd: Path | None = None) -> str:
    r = subprocess.run(["git", *args], cwd=cwd or ROOT, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout.strip()


@lru_cache(maxsize=128)
def _common_dir(root: Path, marker: tuple) -> Path:
    p = Path(git("rev-parse", "--git-common-dir", cwd=root))
    return p if p.is_absolute() else (root / p).resolve()


def common_dir() -> Path:
    # This location is stable during a CLI invocation. Repeated attribution/ledger reads must not
    # spawn dozens of identical git processes. Root/marker changes invalidate it (including tests).
    root = ROOT.resolve()
    path = root / ".git"
    stat = path.stat()
    marker = (stat.st_dev, stat.st_ino, stat.st_mtime_ns if path.is_file() else 0)
    return _common_dir(root, marker)


def main_checkout() -> Path:
    """The working tree that owns the clone's .git directory (where build/toolchain lives)."""
    return common_dir().parent


def lock_dir() -> Path:
    d = common_dir() / "poolrad-locks"
    d.mkdir(exist_ok=True)
    return d


def lock_path(unit: str) -> Path:
    return lock_dir() / ("%s.lock" % identifier(unit, "lock key"))


def pending_handoff(key: str) -> bool:
    return (common_dir() / "poolrad-handoffs" / (identifier(key) + ".md")).exists()


def require_main(operation: str) -> None:
    if ROOT.resolve() != main_checkout().resolve() or git("branch", "--show-current") != "main":
        raise ValueError("%s must run in the main checkout on branch main" % operation)


def require_owner(key: str, agent: str, branch: str) -> None:
    identifier(agent, "agent")
    path = lock_path(key)
    if not path.exists():
        raise ValueError("%s has no lock; claim the work before handing it off" % key)
    record = fields(path.read_text())
    if record.get("agent") != agent or record.get("branch") != branch:
        raise ValueError("%s is not owned by %s on %s" % (key, agent, branch))
    if ROOT.resolve() == main_checkout().resolve():
        raise ValueError("a branch hand-off must run from its claimed worktree, not main")


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

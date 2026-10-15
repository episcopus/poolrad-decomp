"""vfs.py: the virtual DOS filesystem the oracle exposes to the original program.

Reads come from the pinned `poolrad/` directory; every write lands in an in-memory layer, so a run
can never change a pinned input and two runs from the same inputs see the same files (SPEC 8.2,
AGENTS.md rule 4). The game directory is presented as `C:\\POOLRAD` (that is what POOL.CFG names).
"""
from __future__ import annotations

import fnmatch
from pathlib import Path


class VFile:
    """An open file: a bytearray plus a position. Device handles use DevFile."""
    __slots__ = ("path", "data", "pos", "writable", "dirty")

    def __init__(self, path: str, data: bytearray, writable: bool):
        self.path, self.data, self.pos, self.writable, self.dirty = path, data, 0, writable, False

    is_device = False


class DevFile:
    """stdin/stdout/stderr/aux/prn."""
    is_device = True

    def __init__(self, name: str):
        self.path = name
        self.pos = 0
        self.writable = True


def norm(path: str) -> str:
    """Upper-case, backslash form without drive: 'c:\\poolrad\\x.dax' -> '\\POOLRAD\\X.DAX'."""
    p = path.replace("/", "\\").upper()
    if len(p) >= 2 and p[1] == ":":
        p = p[2:]
    return p


class VFS:
    def __init__(self, host_root: Path, mount: str = "\\POOLRAD"):
        self.host_root = Path(host_root)
        self.mount = mount.upper()
        self.layer: dict[str, bytearray] = {}   # normalised path -> files created or opened for write this run
        self.host_cache: dict[str, bytearray] = {}   # read-only copies of pinned files (never written back)
        self.deleted: set[str] = set()
        self.dirs: set[str] = {"\\", self.mount, self.mount + "\\SAVE"}
        self.cwd = self.mount                    # current directory on C:
        self.host_index = {}                     # normalised path -> host Path (lazy)
        for p in sorted(self.host_root.rglob("*")):
            rel = p.relative_to(self.host_root).as_posix().upper().replace("/", "\\")
            full = self.mount + "\\" + rel
            if p.is_dir():
                self.dirs.add(full)
            else:
                self.host_index[full] = p
        self.log: list[tuple] = []               # (op, path, extra), used by trace and tests

    def alias(self, name: str, host_file: Path) -> None:
        """Serve `host_file` (read only, copy on write like every pinned file) as `name` in the game
        directory: the rebuilt program's overlay file `POOL.OVR` appears as GAME.OVR."""
        self.host_index[self.mount + "\\" + name.upper()] = Path(host_file)
        self.host_cache.pop(self.mount + "\\" + name.upper(), None)

    # --- path resolution -------------------------------------------------------------
    def resolve(self, path: str) -> str:
        p = norm(path)
        if not p.startswith("\\"):
            p = (self.cwd.rstrip("\\") + "\\" + p) if p else self.cwd
        out: list[str] = []
        for part in p.split("\\"):
            if part in ("", "."):
                continue
            if part == "..":
                if out:
                    out.pop()
            else:
                out.append(part)
        return "\\" + "\\".join(out)

    def exists(self, full: str) -> bool:
        if full in self.deleted:
            return False
        return full in self.layer or full in self.host_index

    def isdir(self, full: str) -> bool:
        return full in self.dirs

    # --- file operations -------------------------------------------------------------
    def open(self, path: str, write: bool, create: bool = False, truncate: bool = False):
        full = self.resolve(path)
        if create:
            self.layer[full] = bytearray()
            self.deleted.discard(full)
            self.log.append(("create", full, None))
            return VFile(full, self.layer[full], True)
        if not self.exists(full):
            self.log.append(("open-missing", full, None))
            return None
        self.log.append(("open", full, "rw" if write else "r"))
        if full in self.layer:
            data = self.layer[full]
        elif write:                                   # copy on write: the pinned file stays untouched
            data = self.layer[full] = bytearray(self.host_index[full].read_bytes())
        else:
            data = self.host_cache.get(full)
            if data is None:
                data = self.host_cache[full] = bytearray(self.host_index[full].read_bytes())
        f = VFile(full, data, write)
        if truncate:
            f.data.clear()
        return f

    def delete(self, path: str) -> bool:
        full = self.resolve(path)
        if not self.exists(full):
            return False
        self.layer.pop(full, None)
        self.deleted.add(full)
        self.log.append(("delete", full, None))
        return True

    def rename(self, old: str, new: str) -> bool:
        a, b = self.resolve(old), self.resolve(new)
        if not self.exists(a):
            return False
        data = self.layer.get(a)
        if data is None:
            data = bytearray(self.host_index[a].read_bytes())
        self.layer[b] = data
        self.deleted.discard(b)
        self.layer.pop(a, None)
        self.deleted.add(a)
        return True

    def listdir(self, dirpath: str) -> list[str]:
        d = dirpath.rstrip("\\") or "\\"
        names = set()
        for full in list(self.host_index) + list(self.layer):
            if full in self.deleted:
                continue
            head, _, tail = full.rpartition("\\")
            if (head or "\\") == d:
                names.add(tail)
        return sorted(names)

    def size(self, full: str) -> int:
        if full in self.layer:
            return len(self.layer[full])
        return self.host_index[full].stat().st_size

    def find(self, spec: str) -> list[tuple[str, int, int]]:
        """DOS wildcard search: returns [(name, size, attr)] in directory order (sorted)."""
        full = self.resolve(spec)
        head, _, pat = full.rpartition("\\")
        d = head or "\\"
        pat = pat or "*.*"
        if pat == "*.*":
            pat = "*"
        out = []
        for name in self.listdir(d):
            if fnmatch.fnmatchcase(name, pat):
                out.append((name, self.size((d.rstrip("\\") + "\\" + name)), 0x20))
        for dd in sorted(self.dirs):
            head2, _, tail = dd.rpartition("\\")
            if (head2 or "\\") == d and tail and fnmatch.fnmatchcase(tail, pat):
                out.append((tail, 0, 0x10))
        return out

"""trace.py: tracing for the oracle (SPEC 8.2, playbook 25 step 7).

  * interrupts, file I/O and port I/O as one line each;
  * routine calls and returns for every routine in `re/symbols.toml`, resident and overlaid. Overlay
    code moves: the stub header (+10h `LoadSeg`) says where a unit currently sits, so entry points are
    resolved lazily after each read of GAME.OVR;
  * watch points on a memory range (read or write), reported with the writing instruction's address.

Lines are `time cs:ip(load-relative) text`, with time in executed instructions. Everything is text so
two runs can be compared with `diff`.
"""
from __future__ import annotations

import tomllib
from pathlib import Path

from unicorn import UC_HOOK_BLOCK, UC_HOOK_MEM_WRITE, UC_HOOK_MEM_READ

from .machine import LOAD_SEG, ROOT

OVL_LOADSEG_OFF = 0x10        # stub header field: segment the unit is loaded at (0 = not resident)


def load_symbols(root: Path = ROOT):
    """Return (routines, units): routines = [(unit, off, name, size)], units = {id: dict(kind, seg, ...)}."""
    sy = tomllib.loads((root / "re/symbols.toml").read_text())
    un = tomllib.loads((root / "re/units.toml").read_text())
    return sy.get("routine", []), un


class Tracer:
    def __init__(self, m, *, ints=False, calls=False, files=False, ports=False, out=None, max_lines=2_000_000):
        self.m = m
        self.ints, self.calls, self.files, self.ports = ints, calls, files, ports
        self.lines: list[str] = []
        self.out = out
        self.max_lines = max_lines
        self.depth = 0
        self.shadow: list[tuple[int, int, str]] = []      # (return linear, sp at entry, routine id)
        self.entered: dict[str, int] = {}                  # routine id -> call count (coverage)
        self.entry_map: dict[int, str] = {}                # runtime linear address -> routine id
        self.names: dict[str, str] = {}
        self.ovl_epoch = 0
        self._ovl_seen_epoch = -1
        m.tracer = self
        if calls:
            self._prepare_calls()
            m.uc.hook_add(UC_HOOK_BLOCK, self._on_block, begin=0, end=0x9FFFF)

    # ---------------------------------------------------------------- output
    def emit(self, text: str) -> None:
        m = self.m
        line = "%9d %04X:%04X %s" % (m.insns, (m.get("cs") - LOAD_SEG) & 0xFFFF, m.get("ip"), text)
        if len(self.lines) < self.max_lines:
            self.lines.append(line)
        if self.out:
            self.out.write(line + "\n")

    # ---------------------------------------------------------------- m callbacks
    def on_int(self, m, n: int) -> None:
        if self.ints:
            self.emit("INT %02Xh AX=%04X BX=%04X CX=%04X DX=%04X DS=%04X ES=%04X" % (
                n, m.get("ax"), m.get("bx"), m.get("cx"), m.get("dx"), m.get("ds"), m.get("es")))

    def on_file(self, m, op: str, path: str, pos: int, n: int) -> None:
        if path.endswith("GAME.OVR") and op == "read":
            self.ovl_epoch += 1
        if self.files:
            self.emit("FILE %s %s pos=%d n=%d" % (op, path, pos, n))

    def on_port(self, m, d: str, port: int, size: int, val: int) -> None:
        if self.ports:
            self.emit("PORT %s %04X = %X" % (d, port, val))

    # ---------------------------------------------------------------- calls
    def _prepare_calls(self) -> None:
        routines, units = load_symbols()
        self.resident_entries: dict[int, str] = {}
        self.overlay_entries: dict[str, list[tuple[int, str]]] = {}
        for r in routines:
            unit, rid = r["unit"], r["id"]
            self.names[rid] = r.get("name", rid)
            off = int(r["addr"].split(":")[1], 16)
            if unit.startswith("res"):
                seg = int(r["addr"].split(":")[0], 16)
                self.resident_entries[((seg + LOAD_SEG) << 4) + off] = rid
            else:
                self.overlay_entries.setdefault(unit, []).append((off, rid))
        self.entry_map.update(self.resident_entries)
        self.overlay_stub = {}
        for u in units.get("overlay", []):
            seg = u.get("stub_segment") or u.get("segment")
            if seg:
                self.overlay_stub[u["id"]] = int(seg, 16) + LOAD_SEG

    def _rescan_overlays(self) -> None:
        m = self.m
        self.entry_map = dict(self.resident_entries)
        for unit, stub in self.overlay_stub.items():
            seg = m.rw(stub, OVL_LOADSEG_OFF)
            if seg:
                for off, rid in self.overlay_entries.get(unit, ()):
                    self.entry_map[(seg << 4) + off] = rid
        self._ovl_seen_epoch = self.ovl_epoch

    def _on_block(self, uc, addr, size, _ud) -> None:
        if self._ovl_seen_epoch != self.ovl_epoch:
            self._rescan_overlays()
        sh = self.shadow
        if sh and addr == sh[-1][0]:
            ret = sh.pop()
            self.depth = max(0, self.depth - 1)
            self.emit("%sret %s AX=%04X" % ("  " * self.depth, self.names.get(ret[2], ret[2]), self.m.get("ax")))
        rid = self.entry_map.get(addr)
        if rid is None:
            return
        m = self.m
        ss, sp = m.get("ss"), m.get("sp")
        ip, cs = m.rw(ss, sp), m.rw(ss, sp + 2)
        args = " ".join("%04X" % m.rw(ss, sp + 4 + 2 * i) for i in range(4))
        self.entered[rid] = self.entered.get(rid, 0) + 1
        self.emit("%scall %s(%s)" % ("  " * self.depth, self.names.get(rid, rid), args))
        sh.append((((cs << 4) + ip) & 0xFFFFF, sp, rid))
        self.depth += 1

    # ---------------------------------------------------------------- watch points
    def watch(self, seg: int, off: int, length: int, write: bool = True, read: bool = False) -> None:
        lo = (seg << 4) + off
        def cb(uc, access, address, size, value, _ud):
            self.emit("WATCH %s %05X size=%d val=%X" % ("W" if access == 1 else "R", address, size, value))
        mask = (UC_HOOK_MEM_WRITE if write else 0) | (UC_HOOK_MEM_READ if read else 0)
        self.m.uc.hook_add(mask, cb, begin=lo, end=lo + length - 1)


def overlay_stubs(units: dict | None = None) -> dict[str, int]:
    """Overlay unit id -> runtime stub segment (absolute), from re/units.toml."""
    if units is None:
        units = load_symbols()[1]
    out = {}
    for u in units.get("overlay", []):
        seg = u.get("stub_segment") or u.get("segment")
        if seg:
            out[u["id"]] = int(seg, 16) + LOAD_SEG
    return out


_RES_RANGES = None


def _resident_ranges():
    """[(start_linear_rel, end_linear_rel, base_segment, unit_id)] from re/units.toml, load-relative."""
    global _RES_RANGES
    if _RES_RANGES is None:
        _, units = load_symbols()
        out = []
        for u in units.get("resident", []):
            if u.get("code_start") and u.get("code_end"):
                (s0, o0), (s1, o1) = (tuple(int(x, 16) for x in u[k].split(":")) for k in ("code_start", "code_end"))
                out.append((s0 * 16 + o0, s1 * 16 + o1, s0, u["id"]))
        _RES_RANGES = out
    return _RES_RANGES


def locate(m, linear: int, stubs: dict[str, int] | None = None) -> str:
    """Describe a runtime linear address the way the project writes addresses: `ovlNN:OFFS` inside a
    loaded overlay (from the stub's load segment and code size), `SSSS:OOOO` load-relative inside a
    resident unit (the form of whitepaper section 2.2), else the bare load-relative linear address."""
    stubs = stubs or overlay_stubs()
    for unit, stub in stubs.items():
        loadseg = m.rw(stub, OVL_LOADSEG_OFF)
        size = m.rw(stub, 0x08)
        if loadseg and loadseg * 16 <= linear < loadseg * 16 + size:
            return "%s:%04X" % (unit, linear - loadseg * 16)
    rel = linear - LOAD_SEG * 16
    for lo, hi, seg, _uid in _resident_ranges():
        if lo <= rel < hi:
            return "%04X:%04X" % (seg, rel - seg * 16)
    return "rel:%05X" % (rel & 0xFFFFF)

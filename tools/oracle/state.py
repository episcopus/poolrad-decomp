"""state.py: canonical game state digests (SPEC 8.5, `re/state.toml`).

`re/state.toml` says which DGROUP ranges are compared and which bytes are masked (each with a reason).
Changing that file needs a human (AGENTS.md rule 6); this module only reads it. While the file defines
no regions (Phase 2), the canonical state falls back to all of DGROUP plus the video planes, which is a
superset of what any later definition will select.

`heap_root` entries (heap records reachable from a far pointer) need the record types of `re/types/`
and arrive with the first lifted unit; an entry present before that raises, never silently skipped.
"""
from __future__ import annotations

import hashlib
import tomllib
from pathlib import Path

from .machine import LOAD_SEG, ROOT

DGROUP_PARA = 0x0C7C          # whitepaper 3.1: System init does `mov dx,0C7Ch; mov ds,dx`


def dgroup_seg() -> int:
    return LOAD_SEG + DGROUP_PARA


def load_definition(path: Path | None = None) -> dict:
    p = path or ROOT / "re/state.toml"
    return tomllib.loads(p.read_text()) if p.exists() else {}


STACK_SIZE = 0x4000           # whitepaper 3.1: initial SS:SP 14F2:4000 (16 KB stack segment)


def canonical_digest(m, definition: dict | None = None, *, exclude_stack: bool = False) -> str:
    """sha256 of the canonical state. `exclude_stack=True` leaves the stack segment out. A routine
    replaced by C does not push the frames the original pushed (and C locals are never on the guest
    stack), so stack bytes, including stale slots of live frames that nobody has written yet, differ in
    a hybrid run while globals, heap and video are equal (timing.py, whitepaper appendix C). The default
    keeps the stack, so recorded goldens stay valid; whether the project's definition should exclude it
    is a decision for `re/state.toml` (human approval)."""
    d = load_definition() if definition is None else definition
    if d.get("heap_root"):
        raise NotImplementedError("re/state.toml heap_root entries need re/types/ (first lifted unit)")
    ds = dgroup_seg()
    h = hashlib.sha256()
    regions = d.get("region") or [{"name": "DGROUP", "dseg": [0x0000, 0xFFFF]}]
    masks = [tuple(x["dseg"]) for x in d.get("mask", [])]
    for r in regions:
        lo, hi = r["dseg"]
        data = bytearray(m.read(ds, lo, hi - lo))
        if exclude_stack:
            base = (ds << 4) + lo
            dlo, dhi = m.get("ss") << 4, (m.get("ss") << 4) + STACK_SIZE
            a, b = max(base, dlo), min(base + len(data), dhi)
            if a < b:
                data[a - base:b - base] = bytes(b - a)
        for mlo, mhi in masks:
            a, b = max(lo, mlo), min(hi, mhi)
            if a < b:
                data[a - lo:b - lo] = bytes(b - a)
        h.update(r.get("name", "").encode())
        h.update(bytes(data))
    if not d.get("region"):
        h.update(m.ega.planes_digest().encode())
    return h.hexdigest()

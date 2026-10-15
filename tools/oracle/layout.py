"""layout.py: where the program under test keeps what the oracle's tools look for (SPEC 8.4, playbook 50).

The oracle's hooks and digests were written against the original image: System's `Random` at
`0AF8:11C0`, DGROUP at paragraph `0C7C`, the overlay stubs of `re/units.toml`. A rebuild from Pascal
(`make rebuild`, Phase 5) has the same code but different segment addresses and a different data layout.
A `Layout` says where each of those things is in the build being run; `protection.py`, `rng.py`,
`state.py` and `trace.py` ask `current()` instead of using constants.

  original()   the pinned image `poolrad/start-unpack.exe` and `poolrad/GAME.OVR` (what every golden is)
  rebuilt()    `build/rebuild/POOL.EXE` and `POOL.OVR`, with addresses read from its link map

Offsets inside the System unit (Random, the generator step) are the same in every build because the
runtime comes from the same `TURBO.TPL`; `rebuilt()` checks that against the original's bytes and refuses
a build whose System code differs.

Addresses in text a golden digests (the caller of a `Random` call) keep the *original's* form even for
the rebuild, so a digest recorded on the original is comparable with one taken on a rebuild: a resident
address prints as the original unit's paragraph plus the offset inside the unit.
"""
from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from .machine import ROOT

REBUILD_DIR = ROOT / "build/rebuild"
SYSTEM_CHECK = (0x11C0, 0x1250)      # the System code the oracle's hooks sit in (Random and the generator)

SYSTEM_DATA = (0x43EC, 0x8800)       # the original's DS offsets of System's variable blocks (re/dseg.toml)

# Turbo Pascal runtime names the oracle needs, and what they are called in the link map (uppercase).
SYSTEM_VARS = {"randseed": "RANDSEED", "heap_org": "HEAPORG", "heap_ptr": "HEAPPTR"}


@dataclass
class Layout:
    name: str = "original"
    exe: Path = ROOT / "poolrad/start-unpack.exe"
    overlay_file: Path | None = None             # host file served as GAME.OVR; None: the pinned one
    dgroup_para: int = 0x0C7C                    # load-relative paragraph of DGROUP
    system_para: int = 0x0AF8                    # load-relative paragraph of the System unit's code
    randseed: int = 0x4428                       # DS offsets of System variables
    heap_org: int = 0x4400
    heap_ptr: int = 0x4404
    wheel_table: int = 0x0000                    # DS offset of the code wheel table (whitepaper 5.12)
    stubs: dict[str, int] | None = None          # overlay id -> load-relative stub paragraph; None: re/units.toml
    # resident code ranges for `trace.locate`: (lo, hi, out_seg, unit id, base), load-relative linear;
    # printed as `out_seg:(linear - base)`, out_seg being the original's paragraph of the unit
    resident_ranges: list[tuple[int, int, int, str, int]] | None = None
    notes: list[str] = field(default_factory=list)

    @property
    def is_original(self) -> bool:
        return self.name == "original"


def original() -> Layout:
    return Layout()


def _units() -> dict:
    return tomllib.loads((ROOT / "re/units.toml").read_text())


def rebuilt(build_dir: Path | None = None) -> Layout:
    """The layout of the program `make rebuild` linked, from its map (Publics and segments)."""
    import sys
    sys.path.insert(0, str(ROOT / "tools/re"))
    import tp_toolchain as tp

    d = build_dir or REBUILD_DIR
    exe, ovr, mapf = tp.ci(d, "POOL.EXE"), tp.ci(d, "POOL.OVR"), tp.ci(d, "POOL.MAP")
    if exe is None or ovr is None or mapf is None:
        raise FileNotFoundError("no rebuilt program in %s: run `make rebuild` first" % d)
    segs, pubs = tp.read_map(mapf)
    units = _units()
    lay = Layout(name="rebuilt", exe=exe, overlay_file=ovr)

    data = segs.get("DATA")
    if data is None:
        raise ValueError("the link map has no DATA segment")
    lay.dgroup_para = data[0] >> 4
    for attr, pub in SYSTEM_VARS.items():
        if pub not in pubs:
            raise ValueError("the link map has no public %s" % pub)
        setattr(lay, attr, pubs[pub][1])
    # the code wheel table is the program's first typed constant (DS:0002; the original's table base DS:0000
    # is two bytes below it): a `dsXXXX` global named by its original offset
    if "DS0002" in pubs:
        lay.wheel_table = pubs["DS0002"][1] - 2
    elif "DS0000" in pubs:
        lay.wheel_table = pubs["DS0000"][1]
    else:
        lay.notes.append("no DS0002 in the map: the code wheel solver would read the wrong table")

    system = segs.get("SYSTEM")
    if system is None:
        raise ValueError("the link map has no SYSTEM segment")
    lay.system_para = system[0] >> 4
    img, rel = tp.read_mz(exe)
    orig_img, orig_rel = tp.read_mz(tp.EXE)
    lo, hi = SYSTEM_CHECK
    a0, b0 = lay.system_para * 16 + lo, 0x0AF8 * 16 + lo
    ours, orig = img[a0:a0 + hi - lo], orig_img[b0:b0 + hi - lo]
    # the code is the runtime's; only the operands naming System's own variables (the data layout differs)
    # and the relocated words may differ
    hidden = set()
    for i in range(len(orig) - 1):
        if ours[i] != orig[i] or ours[i + 1] != orig[i + 1]:
            w = orig[i] | (orig[i + 1] << 8)
            if SYSTEM_DATA[0] <= w < SYSTEM_DATA[1] or (a0 + i) in rel or (b0 + i) in orig_rel:
                hidden.update((i, i + 1))
    bad = [i for i in range(len(orig)) if ours[i] != orig[i] and i not in hidden]
    if bad:
        raise ValueError("System code of the rebuild differs from the original's at offsets %s: the oracle's "
                         "hooks are not valid for it" % ", ".join("%04X" % (lo + i) for i in bad[:6]))

    stubs = {}
    for u in units.get("overlay", []):
        name = u["id"].upper()
        if name in segs:
            stubs[u["id"]] = segs[name][0] >> 4
    lay.stubs = stubs

    ranges = []
    library = {"res00": "SYSTEM", "res01": "CRT", "res13": "DOS", "res14": "OVERLAY"}
    for u in units.get("resident", []):
        if not (u.get("code_start") and u.get("code_end")):
            continue
        name = library.get(u["id"], u["id"].upper())
        if name not in segs:
            continue
        s0, o0 = (int(x, 16) for x in u["code_start"].split(":"))
        s1, o1 = (int(x, 16) for x in u["code_end"].split(":"))
        start = segs[name][0]
        ranges.append((start, start + (s1 * 16 + o1) - (s0 * 16 + o0), s0, u["id"], start))
    lay.resident_ranges = ranges
    return lay


# --- the active layout -------------------------------------------------------------------------------
_current: Layout = original()


def current() -> Layout:
    return _current


def use(layout: Layout) -> Layout:
    """Make `layout` the one the oracle's tools consult; returns the previous one."""
    global _current
    prev, _current = _current, layout
    from . import trace
    trace._RES_RANGES = None               # the resident range cache is per layout
    return prev

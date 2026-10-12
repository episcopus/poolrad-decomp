#!/usr/bin/env python3
"""forced_starts.py: routine starts `make map` must keep even when its scan cannot find them.

The enumerator (enumerate_routines.py) finds starts from frame prologues and call targets. A leaf
runtime routine with no `push bp; mov bp,sp` that nothing in POOL near- or far-calls from a place
the scan sees is merged into the routine before it (System.Randomize at 0AF8:1247 into
System_RandomStep, escalate-ovl11-20261012040038). Every start listed here is a start, whatever
the scan finds, and the enumerator never merges it away.

Sources, each with its evidence:
  probe    far-call targets into a runtime unit (System, Crt, Dos, Overlay) of the pinned
           compiler's probe build (build/toolchain/probe/<pinned>/sink.exe, `make tp-probe`),
           mapped to POOL's unit by the byte alignment of `make tp-compare` and confirmed by
           tp_toolchain.runtime_entries (the whole routine body votes for that entry, one to one).
           The pinned compiler emitted a far call to that byte, so a routine begins there.
  rtl      the hand-verified runtime entries of tools/re/rtl_ident.py (SYSTEM_NAMED, CRT_NAMED,
           OVERLAY_NAMED).
  manual   committed entries of re/forced_starts.toml with their own evidence.

re/forced_starts.toml holds the manual entries and a copy of the probe entries, so `make map` gives
the same routines on a machine without the proprietary compiler. `--write` (run by `make map`)
recomputes the probe entries when the probe build exists and leaves the file alone otherwise.

Usage:
  python3 tools/re/forced_starts.py [--write] [--list]
"""
from __future__ import annotations

import argparse
import struct
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

TOML = ROOT / "re/forced_starts.toml"
HEADER = """\
# Routine starts `make map` keeps even when its prologue and call scan cannot find them
# (tools/re/forced_starts.py, escalate-ovl11-20261012040038). One [[start]] per routine entry:
#   id        routine id as in re/symbols.toml (resident: unit segment:offset from unit start)
#   name      name for a routine re/symbols.toml does not hold yet ("" keeps the provisional one)
#   source    "manual" (kept as written, needs evidence) or "probe" (rewritten by
#             `forced_starts.py --write` from the pinned compiler's probe build; do not edit)
#   evidence  why a routine begins there
"""


def _q(s: str) -> str:
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def load(path: Path = TOML) -> list[dict]:
    if not path.exists():
        return []
    return tomllib.loads(path.read_text()).get("start", [])


def save(entries: list[dict], path: Path = TOML) -> None:
    lines = [HEADER]
    for e in sorted(entries, key=lambda e: (e["source"] != "manual", e["id"])):
        lines += ["[[start]]", "id = %s" % _q(e["id"]), "name = %s" % _q(e.get("name", "")),
                  "source = %s" % _q(e["source"]), "evidence = %s" % _q(e["evidence"]), ""]
    path.write_text("\n".join(lines))


def rtl_starts() -> dict[str, str]:
    """The hand-verified runtime entries of rtl_ident.py: id -> name."""
    import rtl_ident as rt
    out = {}
    for seg, table in ((0x0AF8, rt.SYSTEM_NAMED), (0x0A40, rt.CRT_NAMED), (0x0AA2, rt.OVERLAY_NAMED)):
        for off, (name, _note) in table.items():
            out["%04X:%04X" % (seg, off)] = name
    return out


def probe_starts() -> dict[str, str] | None:
    """Far-call targets into each runtime unit of the pinned probe build, mapped to POOL and
    confirmed by runtime_entries: id -> evidence. None when the probe build is absent."""
    import tp_toolchain as tc
    ver = tc.pinned_version()
    pdir = tc.TC / "probe" / ver
    exe, mapf = pdir / "sink.exe", pdir / "sink.map"
    if not (exe.exists() and mapf.exists()):
        return None
    img, _ = tc.read_mz(exe)
    segs, pubs = tc.read_map(mapf)
    pub_at = {v: k for k, v in pubs.items()}
    ours, _ = tc.read_mz(tc.EXE)
    units = tomllib.loads((ROOT / "re/units.toml").read_text())["resident"]
    sym = tomllib.loads((ROOT / "re/symbols.toml").read_text()).get("routine", [])
    far = []
    for i in range(len(img) - 5):
        if img[i] == 0x9A:
            far.append(struct.unpack_from("<HH", img, i + 1))
    out: dict[str, str] = {}
    for u in units:
        uname = u.get("name", "").upper()
        if uname not in tc.UNITS or uname not in segs:
            continue
        a = int(u["code_start"].split(":")[0], 16)
        b = int(u["code_end"].split(":")[0], 16)
        rs, rl, _ = segs[uname]
        U, R = ours[a * 16:b * 16], img[rs:rs + rl]
        targets = sorted({off for off, seg in far if seg * 16 == rs and off < rl})
        _, m = tc.align_unit(U, R)
        inv = {v: k for k, v in m.items()}
        known = {int(r["id"][5:], 16) for r in sym if r["id"].startswith("%04X:" % a)}
        cand = {inv[t]: t for t in targets if t in inv}
        found = tc.runtime_entries(U, R, sorted(known | set(cand)))
        for e, t in sorted(cand.items()):
            if found.get(t) != e:
                continue
            pub = pub_at.get((rs >> 4, t))
            out["%04X:%04X" % (a, e)] = (
                "probe %s: sink.exe far-calls %s:%04X%s; aligned by make tp-compare, "
                "confirmed by runtime_entries" % (ver, uname, t, " (public %s)" % pub if pub else ""))
    return out


def refresh(path: Path = TOML) -> tuple[int, int] | None:
    """Rewrite the probe entries of the toml; None when the probe build is absent."""
    probe = probe_starts()
    if probe is None:
        return None
    old = load(path)
    manual = [e for e in old if e.get("source") == "manual"]
    probe = {i: ev for i, ev in probe.items() if i not in {e["id"] for e in manual}}
    names = {e["id"]: e.get("name", "") for e in old}
    probe_entries = [{"id": i, "name": names.get(i, ""), "source": "probe", "evidence": ev}
                     for i, ev in sorted(probe.items())]
    before = {e["id"] for e in old if e.get("source") == "probe"}
    save(manual + probe_entries, path)
    return len(probe_entries), len(set(probe) - before)


def forced(path: Path = TOML) -> dict[str, dict]:
    """Every forced start: id -> {"name", "evidence"} (manual, then probe, then rtl tables)."""
    out: dict[str, dict] = {}
    for e in load(path):
        out.setdefault(e["id"], {"name": e.get("name", ""), "evidence": e["evidence"]})
    for rid, name in rtl_starts().items():
        cur = out.setdefault(rid, {"name": "", "evidence": "rtl: hand-verified entry in tools/re/rtl_ident.py"})
        if not cur["name"]:
            cur["name"] = name
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="recompute the probe entries of re/forced_starts.toml")
    ap.add_argument("--list", action="store_true", help="print every forced start")
    args = ap.parse_args(argv[1:])
    if args.write:
        r = refresh()
        if r is None:
            print("forced_starts: no probe build (make tp-probe); re/forced_starts.toml left as committed")
        else:
            print("forced_starts: %d probe starts (%d new) -> %s" % (r[0], r[1], TOML.relative_to(ROOT)))
    if args.list:
        for rid, e in sorted(forced().items()):
            print("%s  %-24s %s" % (rid, e["name"], e["evidence"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

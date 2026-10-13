#!/usr/bin/env python3
"""status.py: regenerate work/status.md from re/ inventory (SPEC 9.4).

Usage:
  python3 tools/agent/status.py [-o work/status.md]
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def parse_routines(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out, cur = [], None
    for line in path.read_text().splitlines():
        s = line.strip()
        if s == "[[routine]]":
            if cur:
                out.append(cur)
            cur = {}
            continue
        if cur is None or not s or s.startswith("#"):
            continue
        m = re.match(r'^([A-Za-z0-9_]+)\s*=\s*(.+)$', s)
        if not m:
            continue
        k, raw = m.group(1), m.group(2).strip()
        if raw.startswith('"') and raw.endswith('"'):
            cur[k] = raw[1:-1]
        else:
            try:
                cur[k] = int(raw, 0)
            except ValueError:
                cur[k] = raw
    if cur:
        out.append(cur)
    return out


def parse_units(path: Path) -> tuple[list[dict], list[dict]]:
    res, ovl, cur, kind = [], [], None, None
    if not path.exists():
        return res, ovl
    for line in path.read_text().splitlines():
        s = line.strip()
        if s == "[[resident]]":
            if cur:
                (res if kind == "resident" else ovl).append(cur)
            cur, kind = {}, "resident"
            continue
        if s == "[[overlay]]":
            if cur:
                (res if kind == "resident" else ovl).append(cur)
            cur, kind = {}, "overlay"
            continue
        if cur is None or not s or s.startswith("#"):
            continue
        m = re.match(r'^([A-Za-z0-9_]+)\s*=\s*(.+)$', s)
        if not m:
            continue
        k, raw = m.group(1), m.group(2).strip()
        if raw.startswith('"') and raw.endswith('"'):
            cur[k] = raw[1:-1]
        else:
            try:
                cur[k] = int(raw, 0)
            except ValueError:
                cur[k] = raw
    if cur:
        (res if kind == "resident" else ovl).append(cur)
    return res, ovl


def readable(uid: str) -> str:
    """`clean`, or the number of findings of tools/match/readability.py for the unit."""
    try:
        sys.path.insert(0, str(ROOT / "tools/match"))
        import readability
        f = readability.check(uid)
    except Exception as e:                       # the status must not fail on a tool problem
        return "? (%s)" % e.__class__.__name__
    return "clean" if not f else "%d findings" % len(f)


FIXED_DECISIONS = [
    "- Approach (decided 2026-10-11, SPEC 4): Pascal first, matched by the pinned compiler; C later by translation (Phase 7, branch `track-c-hybrid`).",
    "- Canonical state (decided 2026-10-10 and 2026-10-11): `re/state.toml` has `stack = \"diagnostic\"` and `heap = \"compared\"`; goldens carry recordings of the outside world (`tools/oracle/replay.py`) for the rebuild and the C translation.",
    "- Shared files (SPEC 9.6): `src/POOLVARS.PAS` and stub declarations take additive edits; the orchestrator merges.",
    "- `re/units.toml` lists units found through the init chain plus the two runtime units without init; game units without an initialisation part are still invisible (WHITEPAPER 2.2).",
]


def blocker_lines(path: Path) -> list[str]:
    """The orchestrator's blockers from work/blockers.md (playbook 90), without its title and comments."""
    if not path.exists():
        return []
    text = re.sub(r"<!--.*?-->", "", path.read_text(), flags=re.S)
    out = [l.rstrip() for l in text.splitlines() if not l.startswith("# ")]
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-o", "--output", default=str(ROOT / "work/status.md"))
    ap.add_argument("--blockers", default=str(ROOT / "work/blockers.md"),
                    help="the orchestrator's blockers, copied into the status (default work/blockers.md)")
    args = ap.parse_args(argv[1:])

    routines = parse_routines(ROOT / "re/symbols.toml")
    residents, overlays = parse_units(ROOT / "re/units.toml")
    # drop accidental comment-only "resident" ghosts (no id)
    residents = [r for r in residents if r.get("id")]
    overlays = [o for o in overlays if o.get("id")]
    levels = Counter(str(r.get("level", "none")) for r in routines)
    by_unit = Counter(str(r.get("unit", "?")) for r in routines)
    named = sum(
        1
        for r in routines
        if r.get("name")
        and not re.search(r"_fn_[0-9A-Fa-f]{4}$", str(r.get("name")))
        and not re.search(r"_e\d+$", str(r.get("name")))
    )
    named_rtl = sum(
        1
        for r in routines
        if str(r.get("name", "")).startswith(("System_", "Crt_", "Overlay_", "Dos_"))
    )
    res_init = [r for r in residents if r.get("init")]
    code_bytes = sum(int(u.get("code_bytes") or 0) for u in residents + overlays)
    routine_bytes = sum(int(r.get("size") or 0) for r in routines)

    library = {u["id"] for u in residents if u.get("name") in ("System", "Crt", "Dos", "Overlay")}
    external = [r for r in routines if r.get("unit") not in library and r.get("external")]
    game = [r for r in routines if r.get("unit") not in library and not r.get("external")]
    game_units = [u for u in residents + overlays if u["id"] not in library]
    sources = {f.stem.lower() for f in (ROOT / "src").glob("*.PAS")}
    p4 = {"routines": len(game), "bytes": sum(int(r.get("size") or 0) for r in game),
          "matched": sum(1 for r in game if r.get("level") in ("L2", "L3")),
          "matched_bytes": sum(int(r.get("size") or 0) for r in game if r.get("level") in ("L2", "L3")),
          "units": len(game_units), "complete": 0, "reviewed": 0, "rows": [],
          "external": len(external), "external_bytes": sum(int(r.get("size") or 0) for r in external)}
    for u in sorted(game_units, key=lambda u: u["id"]):
        rs = [r for r in game if r.get("unit") == u["id"]]
        ok = [r for r in rs if r.get("level") in ("L2", "L3")]
        reviewed = rs and all(str(r.get("review", "")).startswith("passed") for r in rs)
        if rs and len(ok) == len(rs):
            p4["complete"] += 1
            p4["reviewed"] += bool(reviewed)
        if u["id"] in sources and ok:
            p4["rows"].append((u["id"], u.get("name", ""), len(rs), len(ok), sum(int(r.get("size") or 0) for r in ok),
                               readable(u["id"]),
                               "yes" if reviewed else ("complete" if len(ok) == len(rs) else "in progress")))
    scripts = sorted(p.stem for p in (ROOT / "tests/sessions").glob("*.keys"))
    goldens = [n for n in scripts if (ROOT / "tests/sessions/golden" / n / "golden.json").exists()]
    today = dt.date.today().isoformat()
    lines = [
        "# Project status",
        "",
        "Generated by `make status` (%s)." % today,
        "",
        "## Phase",
        "",
        "Approach: ADR-002 (SPEC 4), Pascal-first matching decompilation; the C track (ADR-001) is on branch `track-c-hybrid`.",
        "",
        "| Phase | State |",
        "|---|---|",
        "| P0 Bootstrap | done (`make doctor`, `make inputs`) |",
        "| P1 Map | done (`make p1-check`): %d units, %d routines, TP 6.0 June 1991 pinned |" % (len(residents) + len(overlays), len(routines)),
        "| P2 Oracle and data | done: goldens with recordings for %d of %d session scripts (%s); `make golden CHECK=1` |" % (len(goldens), len(scripts), ", ".join(goldens) or "none"),
        "| P3 Match harness | done: `make match` (tools/match/match.py, tests/unit/test_match.py); gate `make check` |",
        "| P4 Match | %d of %d game routines at L2 (%d of %d bytes by re/symbols.toml sizes); %d of %d game units complete, %d reviewed; %d routines (%d bytes) inside external object files are not Pascal and are matched by bytes; main program `src/POOL.PAS` matched by `make match UNIT=main` |" % (
            p4["matched"], p4["routines"], p4["matched_bytes"], p4["bytes"], p4["complete"], p4["units"], p4["reviewed"],
            p4["external"], p4["external_bytes"]),
        "| P5 Rebuild | `make rebuild` links the whole game from `src/` (every unit has source: decompiled or skeleton) and reports identical segments |",
        "",
        "### P4 units with matched routines",
        "",
        "| Unit | Name | Routines | L2 | Bytes at L2 | Readable (`make readability`) | Reviewed |",
        "|---|---|---:|---:|---:|---|---|",
    ] + [
        "| %s | %s | %d | %d | %d | %s | %s |" % row for row in p4["rows"]
    ] + [
        "",
        "Locks (agents at work): `make locks`. Next unit: `make next`.",
        "",
        "## Inventory",
        "",
        "| | Count |",
        "|---|---:|",
        "| Units | %d |" % (len(residents) + len(overlays)),
        "| Routines | %d |" % len(routines),
        "| Routines with non-provisional names | %d |" % named,
        "| RTL-prefixed routine names | %d |" % named_rtl,
        "| Unit code_bytes (declared) | %d |" % code_bytes,
        "| Sum of routine sizes | %d |" % routine_bytes,
        "",
        "### Routines by level",
        "",
        "| Level | Count |",
        "|---|---:|",
    ]
    for lv in ("none", "L0", "L1", "L2", "L3", "M"):
        if levels.get(lv):
            lines.append("| %s | %d |" % (lv, levels[lv]))
    for lv, n in sorted(levels.items()):
        if lv not in ("none", "L0", "L1", "L2", "L3", "M"):
            lines.append("| %s | %d |" % (lv, n))

    lines += [
        "",
        "### Top units by routine count",
        "",
        "| Unit | Routines |",
        "|---|---:|",
    ]
    for uid, n in by_unit.most_common(15):
        lines.append("| %s | %d |" % (uid, n))

    lifted = [r for r in routines if str(r.get("level", "none")) not in ("", "none")]
    if not lifted:
        verification = "No routines matched yet (all levels `none`)."
    else:
        shown = ", ".join("%s %s (%s)" % (r.get("name", r.get("id")), r.get("level"), r.get("id"))
                          for r in sorted(lifted, key=lambda r: str(r.get("id"))))
        verification = "%d routines above `none`: %s." % (len(lifted), shown)
    blockers = blocker_lines(Path(args.blockers))
    if blockers:
        blockers.append("")
    lines += [
        "",
        "## Verification",
        "",
        verification,
        "",
        "## Blockers and decisions waiting for the human",
        "",
        "Blockers are kept in `work/blockers.md` (the orchestrator's, playbook 90) and copied here by `make status`.",
        "",
    ] + blockers + FIXED_DECISIONS + [
        "",
        "## Toolchain",
        "",
        "| Tool | Pin | Command |",
        "|---|---|---|",
        "| Turbo Pascal compiler (critical path, never committed) | 6.0, June 1991 release (`tools/re/tp_toolchain.toml`) | `make tp-pin`, `make match`, `make tpc SRC=...` |",
        "| Runtime byte comparison | System/Crt/Dos/Overlay match | `make tp-compare` |",
        "| Headless DOS emulator | emu2 (commit in `tools/setup/build-emu2.sh`) | `make emu2` |",
        "",
    ]
    Path(args.output).write_text("\n".join(lines))
    print("status: %d routines, %d units -> %s" % (len(routines), len(residents) + len(overlays), args.output))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

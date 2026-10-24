#!/usr/bin/env python3
"""codeprof.py: the routines of the banked units with their code sizes, as the compiler made them (step 8.11).

For every unit that lives in banks (not the core, not the runtime or the sound bank) it reads the unit's translated C
(build/game/src/<unit>.c, after the patches) and the compiled object of the whole unit (build/game/obj/<unit>.o, which mkgame builds
before it splits a unit), and writes build/profile/code.json:

  { "units": { "ovl03": { "groups": [ {"name": "ScanParty", "funcs": ["Helper", "ScanParty"], "size": 812}, ...],
                          "rodata": 174, "code": 19300 } },
    "bank_of": { "ScanParty": "ovl03_1", ... }        the banks of the last build (build/game/banks.json)
    "calls": { "ScanParty": ["Other", ...] }           the static call graph between routine groups
  }

A group is a routine with the static helpers in front of it (the unit is split between groups only, never inside one).
Needs the toolchain (lwobjdump): run it through `make code-profile` or scripts/lib.sh run_toolchain."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import mkgame                      # noqa: E402  (parse_items, objinfo)

CORE = set(mkgame.CORE_UNITS) | {"proc_table", "image", "poolvars", "vmlayout"}


def main() -> int:
    game = ROOT / "build/game"
    banks = json.loads((game / "banks.json").read_text())["banks"]
    bank_of = {}
    for b in banks:
        for o in b["objs"]:
            bank_of[Path(o).stem] = b["name"]
    units = {}
    for src in sorted((game / "src").glob("*.c")):
        u = src.stem
        if u in CORE or re.search(r"_\d+$", u) and (game / "src" / (re.sub(r"_\d+$", "", u) + ".c")).exists():
            continue
        obj = game / "obj" / (u + ".o")
        if not obj.exists() or u not in bank_of and not any(p.startswith(u + "_") for p in bank_of):
            continue
        inf = mkgame.objinfo(str(obj))
        groups, cur = [], []
        for it in mkgame.parse_items(src.read_text()):
            if it[0] != "fn":
                continue
            cur.append(it)
            if not it[2]:
                groups.append(cur)
                cur = []
        if cur:
            groups.append(cur)
        units[u] = {"code": inf["code"], "rodata": inf["rodata"],
                    "groups": [{"name": g[-1][1], "funcs": [it[1] for it in g], "size": sum(inf["funcs"].get(it[1], 0) for it in g)} for g in groups]}
    out = ROOT / "build/profile"
    out.mkdir(parents=True, exist_ok=True)
    where = {}                                       # routine -> bank of the last build (a split unit: the part that holds the routine)
    for u, v in units.items():
        parts = [(game / "src" / ("%s_%d.c" % (u, k))) for k in range(1, 8)]
        parts = [p for p in parts if p.exists() and p.stem in bank_of]      # the directory keeps the parts of older builds
        if not parts:
            for g in v["groups"]:
                where[g["name"]] = bank_of.get(u)
            continue
        for p in parts:
            for it in mkgame.parse_items(p.read_text()):
                if it[0] == "fn" and not it[2]:
                    where[it[1]] = bank_of.get(p.stem)
    # the static call graph: which routine groups name which others (calls, and routine addresses taken)
    owner = {f: g["name"] for v in units.values() for g in v["groups"] for f in g["funcs"]}
    calls = {}
    for u, v in units.items():
        text = {it[1]: it[3] for it in mkgame.parse_items((game / "src" / (u + ".c")).read_text()) if it[0] == "fn"}
        for g in v["groups"]:
            used = set()
            for f in g["funcs"]:
                used |= {owner[w] for w in re.findall(r"[A-Za-z_]\w*", text.get(f, "")) if w in owner}
            used.discard(g["name"])
            calls[g["name"]] = sorted(used)
    (out / "code.json").write_text(json.dumps({"units": units, "bank_of": where, "calls": calls}, indent=0))
    tot = sum(g["size"] for v in units.values() for g in v["groups"])
    print("%d units, %d routines, %d bytes of code in groups (%d in the objects)" % (
        len(units), sum(len(v["groups"]) for v in units.values()), tot, sum(v["code"] for v in units.values())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

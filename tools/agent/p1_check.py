#!/usr/bin/env python3
"""p1_check.py: verify Phase 1 exit criteria (SPEC section 10).

Exit 0 only when every required check passes.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def ok(msg: str) -> None:
    print("ok       %s" % msg)


def bad(msg: str) -> None:
    print("FAIL     %s" % msg)


def main() -> int:
    fails = 0

    # 1. Ghidra project rebuildable (tools present; project may be regenerated)
    if (ROOT / "tools/ghidra/import_tp.py").exists():
        ok("tools/ghidra/import_tp.py present (make ghidra)")
    else:
        bad("missing tools/ghidra/import_tp.py")
        fails += 1
    # project dir from last run is optional if tools work; require script + env docs
    if (ROOT / "build/ghidra").exists():
        ok("build/ghidra/ exists from a prior make ghidra")
    else:
        bad("build/ghidra/ missing; run: . tools/setup/env.local.sh && make ghidra")
        fails += 1

    # 2. units with code ranges: 48 from the init chain (13 resident + 35 overlay)
    #    plus the Borland runtime units without an initialisation part (Dos, Overlay;
    #    WHITEPAPER 2.2), which the init chain cannot see.
    units = (ROOT / "re/units.toml").read_text()
    blocks = re.split(r"(?=^\[\[resident\]\]$|^\[\[overlay\]\]$)", units, flags=re.M)
    res_blocks = [b for b in blocks if b.startswith("[[resident]]")]
    res_init = [b for b in res_blocks if re.search(r'^init = "[0-9A-F]{4}:[0-9A-F]{4}"', b, re.M)]
    res_noinit = [b for b in res_blocks if re.search(r'^init = ""', b, re.M)]
    ovl_ids = re.findall(r'^id = "(ovl\d+)"', units, re.M)
    starts = sum(1 for b in res_blocks if re.search(r'^code_start = "', b, re.M))
    if len(res_init) == 13 and len(ovl_ids) == 35 and starts == len(res_blocks):
        ok("48 init-chain units (13 resident + 35 overlay) + %d runtime units without init, all with code ranges"
           % len(res_noinit))
    else:
        bad(
            "units.toml expected 13 init-chain residents + 35 overlays with ranges; got res=%d (+%d no init) ovl=%d code_start=%d"
            % (len(res_init), len(res_noinit), len(ovl_ids), starts)
        )
        fails += 1
    for need in ("System", "Crt", "Dos", "Overlay"):
        if 'name = "%s"' % need in units:
            ok("runtime unit named %s" % need)
        else:
            bad("runtime unit %s not named" % need)
            fails += 1

    # 3. routines listed with size
    sym = (ROOT / "re/symbols.toml").read_text()
    nrout = sym.count("[[routine]]")
    sizes = len(re.findall(r"^size = \d+", sym, re.M))
    if nrout >= 400 and sizes == nrout:
        ok("%d routines each with size" % nrout)
    else:
        bad("routines=%d sizes=%d (need many routines all with size)" % (nrout, sizes))
        fails += 1

    # 4. RTL named: require hand-verified System names present
    rtl_need = [
        "System_StrCopy",
        "System_StrConcat",
        "System_Move",
        "System_FillChar",
        "System_Assign",
        "System_Reset",
        "System_Close",
        "System_BlockRead",
        "System_IOResult",
        "System_init",
        "Crt_init",
    ]
    missing = [n for n in rtl_need if ('name = "%s"' % n) not in sym]
    # Dos and Overlay have no init; require at least one named entry each (res13, res14)
    for prefix in ("Dos_", "Overlay_"):
        if not re.search(r'^name = "%s' % prefix, sym, re.M):
            missing.append(prefix + "*")
    if not missing:
        ok("core RTL routine names present (%d)" % len(rtl_need))
    else:
        bad("missing RTL names: %s" % ", ".join(missing))
        fails += 1

    # 5. version pinned (or at least bounded) in the whitepaper
    wp = (ROOT / "docs/design/WHITEPAPER.md").read_text()
    if "Pinned: Turbo Pascal 6.0" in wp:
        ok("TP version pinned in whitepaper (Turbo Pascal 6.0, June 1991)")
    elif "6.0 or 7.0" in wp or "6.0 or 7" in wp:
        ok("TP version bounded in whitepaper")
    else:
        bad("whitepaper missing TP version pin or bound")
        fails += 1

    # 6. dseg started
    dseg = (ROOT / "re/dseg.toml").read_text()
    ng = dseg.count("[[global]]")
    if ng >= 5:
        ok("dseg.toml started (%d globals)" % ng)
    else:
        bad("dseg.toml needs globals; got %d" % ng)
        fails += 1

    # 7. calling convention samples
    if "retf 6" in wp and "0AF8:0254" in wp:
        ok("calling convention samples in whitepaper")
    else:
        bad("whitepaper missing CC sample evidence")
        fails += 1

    # 8. initial names from strings / prior art: some overlays renamed
    named_ovl = [
        m
        for m in re.finditer(r'^id = "(ovl\d+)"\nname = "([^"]+)"', units, re.M)
        if m.group(2) != m.group(1)
    ]
    if len(named_ovl) >= 10:
        ok("%d overlays named from strings/prior-art leads" % len(named_ovl))
    else:
        bad("need >=10 overlays named from evidence; got %d" % len(named_ovl))
        fails += 1

    # 9. agent tooling for P1 workflow
    for rel in (
        "tools/agent/status.py",
        "tools/agent/next.py",
        "tools/agent/lock.py",
        "tools/agent/unlock.py",
        "tools/agent/packet.py",
        "work/queue.toml",
    ):
        if (ROOT / rel).exists():
            ok(rel)
        else:
            bad("missing %s" % rel)
            fails += 1

    print()
    if fails:
        print("p1_check: %d FAILURES" % fails)
        return 1
    print("p1_check: all Phase 1 exit criteria PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""timing_scan.py: which routines are time sensitive (hybrid runs, SPEC 8.4, whitepaper appendix C).

A routine replaced by C runs instantly, and in a session replay every read of the outside world is
answered from the original's recording (`tools/oracle/replay.py`). That is right for routines that
compute. It is wrong for a literal transliteration of a routine that *waits*: a loop that spins until a
tick counter changes, until the vertical retrace, until a key arrives must go through a platform wait
(`src/platform/platform.h`). This tool finds them before a lifter does.

Static pass (every routine of re/symbols.toml, Capstone on the pinned bytes):
  features    int 16h / 21h key and time calls, int 1Ah, int 15h AH=86, hlt, ports (retrace 3DA, PIT,
              keyboard 60/64, speaker 61, joystick 201), BIOS tick counter 0040:006C, and DGROUP words the
              game's own timer interrupt writes (needs --dynamic);
  loops       a backward branch makes the instructions between target and branch a loop;
  call graph  near and far calls resolved to routines (overlay entries through their stubs).
Classes:
  waits       a loop contains a time or input feature, or a call to a routine that has one
              (wait or poll loop: needs a platform wait, or stays in the original);
  uses        has such a feature or such a callee outside any loop (reads the clock once);
  none        neither.
`direct` marks routines whose own bytes hold the feature (as opposed to reaching it through callees).

Dynamic pass (--dynamic SESSION ...): runs the sessions in the oracle with a profiler on every
routine (`oracle.routines.Profiler`); reports calls, total and longest own-code run per routine (a call spinning for a whole timer
period or more, 54,925 instructions, is a candidate whatever the static pass says), and the DGROUP bytes
written while the timer interrupt is in service (the game's tick-driven variables).

  .venv/bin/python tools/re/timing_scan.py [--dynamic boot-title --dynamic create-character]
        [--out build/re/timing-scan.json] [--report build/re/timing-scan.md]
"""
from __future__ import annotations

import argparse
import json
import sys
import tomllib
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/re"))

from mzutil import read_mz  # noqa: E402

try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_16
    from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_OP_REG
except ImportError:                                             # pragma: no cover
    Cs = None

PERIOD = 54_925            # instructions per timer tick at 1,000,000 per virtual second (65536 / 1193182 s)
KEY_21 = {0x01, 0x07, 0x08, 0x0A, 0x0B, 0x0C}      # not 06h: with DL != FFh it is console output
TIME_21 = {0x2A, 0x2C}
PORT_CLASS = {0x3DA: "retrace", 0x3BA: "retrace", 0x40: "pit", 0x41: "pit", 0x42: "pit", 0x43: "pit",
              0x60: "kbd-port", 0x64: "kbd-port", 0x61: "speaker", 0x201: "joystick"}
LOOPING = {"loop", "loope", "loopne", "loopz", "loopnz", "jcxz", "jecxz"}


def load_bytes():
    """(resident image, {overlay unit: code bytes}) from the pinned inputs and the extracted overlays."""
    _hdr, image = read_mz(ROOT / "poolrad/start-unpack.exe")
    ovl = {}
    for p in sorted((ROOT / "build/re/overlays").glob("ovl*.bin")):
        ovl[p.stem] = p.read_bytes()
    if not ovl:
        raise SystemExit("build/re/overlays/*.bin missing; run `make overlays`")
    return image, ovl


def routine_bytes(r, image, ovl) -> tuple[bytes, int, str]:
    """(code, base offset, segment text) of one routine."""
    seg, off = r["addr"].split(":")
    off = int(off, 16)
    if r["unit"].startswith("res"):
        lin = int(seg, 16) * 16 + off
        return image[lin:lin + r["size"]], off, seg.upper()
    return ovl[r["unit"]][off:off + r["size"]], off, r["unit"]


class Scanner:
    def __init__(self, tick_vars: set[int] | None = None):
        if Cs is None:
            raise SystemExit("capstone is required (pip install capstone)")
        self.md = Cs(CS_ARCH_X86, CS_MODE_16)
        self.md.detail = True
        self.tick_vars = tick_vars or set()
        self.routines = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
        units = tomllib.loads((ROOT / "re/units.toml").read_text())
        manifest = json.loads((ROOT / "build/re/overlays.json").read_text())
        # (stub segment, stub offset) -> routine id of the overlay entry
        self.entry_of: dict[tuple[int, int], str] = {}
        stub_seg = {u["id"]: int(u["stub_segment"], 16) for u in units["overlay"]}
        for i, o in enumerate(manifest["overlays"]):
            uid = "ovl%02d" % o["overlay"]
            for e in o["entries"]:
                self.entry_of[(stub_seg[uid], e["stub_offset"])] = "%s:%04X" % (uid, e["code_offset"])
        self.ids = {r["id"] for r in self.routines}

    def scan(self, r, image, ovl) -> dict:
        code, base, segtext = routine_bytes(r, image, ovl)
        insns = list(self.md.disasm(code, base))
        dx = ah = None
        feats: list[tuple[int, str]] = []          # (instruction index, feature)
        calls: list[tuple[int, str]] = []          # (instruction index, callee routine id)
        loops: list[tuple[int, int]] = []          # (first index, last index) of backward branches
        addr_index = {i.address: n for n, i in enumerate(insns)}
        seg40 = False
        reg_imm: dict[str, int] = {}               # 16-bit registers last loaded with an immediate
        for n, i in enumerate(insns):
            mn, ops = i.mnemonic, i.operands
            if mn == "mov" and len(ops) == 2 and ops[1].type == X86_OP_IMM and ops[0].type == X86_OP_REG:
                reg = i.reg_name(ops[0].reg)
                reg_imm[reg] = ops[1].imm & 0xFFFF
                if reg == "ah":
                    ah = ops[1].imm & 0xFF
                elif reg == "ax":
                    ah = (ops[1].imm >> 8) & 0xFF
                elif reg == "dx":
                    dx = ops[1].imm & 0xFFFF
                if ops[1].imm == 0x40 and reg in ("ax", "bx", "cx", "dx", "si", "di"):
                    seg40 = True
            if mn == "int" and ops and ops[0].type == X86_OP_IMM:
                v = ops[0].imm & 0xFF
                if v == 0x16:
                    feats.append((n, "kbd-int16"))
                elif v == 0x1A:
                    feats.append((n, "time-int1A"))
                elif v == 0x15 and ah == 0x86:
                    feats.append((n, "wait-int15"))
                elif v == 0x21 and ah in KEY_21:
                    feats.append((n, "kbd-int21"))
                elif v == 0x21 and ah in TIME_21:
                    feats.append((n, "time-int21"))
            elif mn == "hlt":
                feats.append((n, "hlt"))
            elif mn in ("in", "out"):
                port = None
                for o in ops:
                    if o.type == X86_OP_IMM:
                        port = o.imm & 0xFFFF
                if port is None and dx is not None:
                    port = dx
                cls = PORT_CLASS.get(port)
                if cls:
                    feats.append((n, "port-" + cls))
            for o in ops:
                if o.type == X86_OP_MEM:
                    d = o.mem.disp & 0xFFFF
                    if o.mem.base:                  # [di], [bx+2]: the register may hold the tick counter's offset
                        d = (reg_imm.get(i.reg_name(o.mem.base), -0x10000) + d) & 0xFFFF
                    if seg40 and d in (0x6C, 0x6E) and o.mem.index == 0:
                        feats.append((n, "bios-tick-0040"))
                    elif d in (0x46C, 0x46E) and o.mem.index == 0:
                        feats.append((n, "bios-tick-0000"))
                    elif o.mem.base:
                        continue
                    elif d in self.tick_vars and o.mem.base == 0 and o.mem.index == 0 and mn != "lea":
                        feats.append((n, "tick-var-%04X" % d))
            if mn.startswith("j") or mn in LOOPING:
                if ops and ops[0].type == X86_OP_IMM:
                    t = ops[0].imm
                    if t <= i.address and t in addr_index:
                        loops.append((addr_index[t], n))
            elif mn in ("call", "lcall"):
                callee = None
                if mn == "lcall" and len(ops) == 2 and ops[0].type == X86_OP_IMM and ops[1].type == X86_OP_IMM:
                    s, o = ops[0].imm & 0xFFFF, ops[1].imm & 0xFFFF      # far call seg, off (capstone order)
                    callee = self.entry_of.get((s, o)) or ("%04X:%04X" % (s, o))
                elif ops and ops[0].type == X86_OP_IMM:            # near call within the unit
                    t = ops[0].imm & 0xFFFF
                    callee = "%s:%04X" % (segtext, t)
                if callee in self.ids:
                    calls.append((n, callee))
        in_loop = [False] * len(insns)
        for a, b in loops:
            for k in range(a, b + 1):
                in_loop[k] = True
        return {
            "feats": sorted({f for _, f in feats}),
            "loop_feats": sorted({f for n, f in feats if in_loop[n]}),
            "calls": sorted({c for _, c in calls}),
            "loop_calls": sorted({c for n, c in calls if in_loop[n]}),
            "loops": len(loops),
        }


def family(feat: str) -> str:
    """input: keyboard and joystick; time: clock, tick counters, waits; sound: PIT and speaker; video: retrace."""
    if feat.startswith(("kbd", "port-kbd", "port-joystick")):
        return "input"
    if feat.startswith("port-retrace"):
        return "retrace"
    if feat.startswith(("port-pit", "port-speaker")):
        return "sound"
    return "time"


def classify(scan: dict[str, dict]) -> dict[str, dict]:
    """Propagate through the call graph: a routine is `sensitive` when it has a feature itself or calls a
    sensitive routine. `waits` = a loop holds a feature or a call to a sensitive routine."""
    sensitive: dict[str, bool] = {}

    def is_sensitive(rid: str, stack=()) -> bool:
        if rid in sensitive:
            return sensitive[rid]
        if rid in stack:
            return False
        s = scan.get(rid)
        if s is None:
            return False
        v = bool(s["feats"]) or any(is_sensitive(c, stack + (rid,)) for c in s["calls"])
        sensitive[rid] = v
        return v

    fam_cache: dict[str, set] = {}

    def families(rid: str, stack=()) -> set:
        if rid in fam_cache:
            return fam_cache[rid]
        if rid in stack or rid not in scan:
            return set()
        f = {family(x) for x in scan[rid]["feats"]}
        for c in scan[rid]["calls"]:
            f |= families(c, stack + (rid,))
        fam_cache[rid] = f
        return f

    sys.setrecursionlimit(10_000)
    out = {}
    for rid, s in scan.items():
        direct_wait = bool(s["loop_feats"])
        indirect_wait = any(is_sensitive(c) for c in s["loop_calls"])
        sens = is_sensitive(rid)
        if direct_wait:
            cls = "waits"
        elif indirect_wait:
            cls = "waits"
        elif sens:
            cls = "uses"
        else:
            cls = "none"
        fam = set()
        if cls == "waits":
            fam = {family(x) for x in s["loop_feats"]}
            for c in s["loop_calls"]:
                fam |= families(c)
        elif cls == "uses":
            fam = families(rid)
        out[rid] = {"class": cls, "direct": bool(s["feats"]), "waits_via_calls": indirect_wait and not direct_wait,
                    "families": sorted(fam),
                    "feats": s["feats"], "loop_feats": s["loop_feats"],
                    "loop_callees": [c for c in s["loop_calls"] if is_sensitive(c)]}
    return out


def dynamic(sessions: list[str]) -> tuple[dict[str, dict], dict[int, int]]:
    """Run sessions with a profiler on every routine and a write watch on the timer handler."""
    from oracle import routines
    from oracle.run import run_session
    from oracle.state import dgroup_seg
    from oracle.machine import LOAD_SEG
    from unicorn import UC_HOOK_MEM_WRITE
    ids = [r["id"] for r in tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]]
    stats: dict[str, dict] = {}
    tick_writes: Counter = Counter()
    for name in sessions:
        text = (ROOT / "tests/sessions" / (name + ".keys")).read_text()
        holder = {}

        def prepare(m, holder=holder):
            holder["rec"] = routines.Profiler(m, ids)
            base = dgroup_seg() << 4
            stack_lo = (m.get("ss") << 4) - base                  # the stack segment lies inside the DS window
            stack_hi = stack_lo + 0x4000

            def on_write(uc, access, address, size, value, _ud):
                if m.irq0_in_service:
                    o = (address - base) & 0xFFFF
                    if not (stack_lo <= o < stack_hi):            # frames and pushes of the handler are not state
                        tick_writes[o] += 1
            m.uc.hook_add(UC_HOOK_MEM_WRITE, on_write, begin=base, end=base + 0xFFFF)

        s = run_session(text, max_insns=400_000_000, quiet=True, prepare=prepare)
        print("[dynamic] %s: %s after %d instructions" % (name, s["reason"], s["insns"]), file=sys.stderr)
        for rid, rows in holder["rec"].rows.items():
            if not rows:
                continue
            st = stats.setdefault(rid, {"calls": 0, "total": 0, "max": 0})
            st["calls"] += len(rows)
            st["total"] += sum(rows)
            st["max"] = max(st["max"], max(rows))
    return stats, dict(tick_writes)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dynamic", action="append", default=[], help="session name to run (repeatable)")
    ap.add_argument("--out", default=str(ROOT / "build/re/timing-scan.json"))
    ap.add_argument("--report", default=str(ROOT / "build/re/timing-scan.md"))
    a = ap.parse_args(argv)

    dyn, tick_writes = ({}, {})
    if a.dynamic:
        dyn, tick_writes = dynamic(a.dynamic)
    # DGROUP words the timer interrupt writes (offsets with at least one write; word granularity)
    tick_vars = {o & ~1 for o in tick_writes} | {o & ~1 for o in tick_writes if o & 1} if tick_writes else set()

    sc = Scanner(tick_vars)
    image, ovl = load_bytes()
    raw = {r["id"]: sc.scan(r, image, ovl) for r in sc.routines}
    cls = classify(raw)
    meta = {r["id"]: r for r in sc.routines}
    result = {}
    for rid, c in cls.items():
        row = dict(c, unit=meta[rid]["unit"], name=meta[rid].get("name", rid), size=meta[rid]["size"])
        if rid in dyn:
            row["dynamic"] = dyn[rid]
            row["spins_a_period"] = dyn[rid]["max"] >= PERIOD
        result[rid] = row
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps({"tick_vars": sorted(tick_vars), "tick_writes": {"%04X" % k: v for k, v in sorted(tick_writes.items())},
                                       "routines": result}, indent=1) + "\n")

    counts = Counter(r["class"] for r in result.values())
    fam_waits = Counter("+".join(r["families"]) or "-" for r in result.values() if r["class"] == "waits")
    lines = ["# Timing scan", "",
             "Routines: %d. waits: %d, uses: %d, none: %d." % (len(result), counts["waits"], counts["uses"], counts["none"]), "",
             "Wait loops by what they wait on: " + ", ".join("%s %d" % kv for kv in sorted(fam_waits.items())), ""]
    if a.dynamic:
        lines += ["The game's timer interrupt writes no DGROUP globals outside its own stack frames: %s." % (
            "none seen in %s" % ", ".join(a.dynamic) if not tick_writes else
            "these word offsets: " + ", ".join("%04X" % o for o in sorted(tick_vars))), ""]
    spinners = [(rid, r) for rid, r in result.items() if r.get("spins_a_period")]
    lines += ["## Dynamic: calls that spun for a whole timer period or more (%d)" % len(spinners), "",
              "Own-code instructions in one call, callees and interrupt handlers excluded. A routine that "
              "computes for that long is listed too; `static class none` means no time or input feature was "
              "found anywhere below it, so it is probably computation (check before assuming).", "",
              "| routine | name | longest own-code run | calls | static class | waits on |", "|---|---|---:|---:|---|---|"]
    for rid, r in sorted(spinners, key=lambda x: -x[1]["dynamic"]["max"]):
        lines.append("| %s | %s | %d | %d | %s | %s |" % (rid, r["name"], r["dynamic"]["max"], r["dynamic"]["calls"],
                                                          r["class"], "+".join(r["families"]) or "-"))
    lines += ["", "## Static: wait or poll loops (class waits)", "",
              "| routine | name | size | via | waits on | features in loops | loop callees |", "|---|---|---:|---|---|---|---|"]
    for rid, r in sorted(result.items()):
        if r["class"] == "waits":
            lines.append("| %s | %s | %d | %s | %s | %s | %s |" % (
                rid, r["name"], r["size"], "callee" if r["waits_via_calls"] else "own bytes",
                "+".join(r["families"]) or "-", ", ".join(r["loop_feats"]) or "-", ", ".join(r["loop_callees"][:4]) or "-"))
    Path(a.report).write_text("\n".join(lines) + "\n")
    direct_waits = [rid for rid, r in result.items() if r["class"] == "waits" and not r["waits_via_calls"]]
    print("routines %d: waits %d (own loop %d, via callee %d), uses %d, none %d" % (
        len(result), counts["waits"], len(direct_waits), counts["waits"] - len(direct_waits), counts["uses"], counts["none"]))
    if dyn:
        print("dynamic: %d routines executed, %d spun a whole timer period or more" % (len(dyn), len(spinners)))
    print("wrote", a.out, "and", a.report)
    return 0


if __name__ == "__main__":
    sys.exit(main())

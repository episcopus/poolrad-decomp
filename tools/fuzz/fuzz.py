#!/usr/bin/env python3
"""fuzz.py: differential test of one lifted routine, L2 (SPEC 8.3).

  .venv/bin/python tools/fuzz/fuzz.py --routine 0AF8:1685 [--cases N] [--seed S]
  make fuzz FN=<id or c_name> [CASES=N] [SEED=S]

For a routine, runs the ORIGINAL bytes in the oracle (a freshly loaded
Machine, no boot: resident code is already in memory) and the C function in
the hybrid library on identical inputs, and compares every byte written plus
the result register and the RNG state. Minimum 200 random cases plus every
edge case for that routine. On success the tool writes level L2 for the
routine in re/symbols.toml (tools write verdicts, AGENTS.md rule 2); on the
first difference it reports the case and exits 1 without touching levels.

P3 spike routines: System_Move (0AF8:1685), System_FillChar (0AF8:16A8),
System_Random (0AF8:11C0, with its step 0AF8:120F).
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle.hybrid import HybridLib  # noqa: E402
from oracle.machine import LOAD_SEG, Machine, Stop  # noqa: E402
from oracle.run import EXE, GAME  # noqa: E402
from oracle.state import dgroup_seg  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/fuzz"

ROUTINES = {
    "0AF8:1685": {"size": 35, "ret_bytes": 10, "names": ("System_Move", "0AF8:1685")},
    "0AF8:16A8": {"size": 20, "ret_bytes": 8, "names": ("System_FillChar", "0AF8:16A8")},
    "0AF8:11C0": {"size": 79, "ret_bytes": 2, "names": ("System_Random", "0AF8:11C0")},
}

SCRATCH_STACK = (0x4000, 0x1000)
SRC_SEG, DST_SEG = 0x5000, 0x6000
TRAP = (0x4200, 0x0000)


def resolve(fn: str) -> str:
    for rid, r in ROUTINES.items():
        if fn in r["names"] or fn == rid:
            return rid
    raise KeyError("fuzz: no spike routine %r (have %s)" % (fn, sorted(ROUTINES)))


def fresh_machine() -> Machine:
    m = Machine(EXE, GAME, strict=True)
    # Trap for isolated calls: install once, before any test writes, so the
    # two NOP bytes are part of every snapshot taken later.
    tseg, toff = TRAP[0] + LOAD_SEG, TRAP[1]
    m.write(tseg, toff, b"\x90\x90")

    def done(mm):
        raise Stop("fuzz-done")

    m.add_breakpoint(tseg, toff, done)
    return m


def call_original(m: Machine, rid: str, stack_words: list[int], setup=None) -> None:
    """Set guest state, run the original bytes, stop at the trap return."""
    seg = int(rid.split(":")[0], 16) + LOAD_SEG
    off = int(rid.split(":")[1], 16)
    sseg, soff = SCRATCH_STACK
    sp = soff - 2 * (2 + len(stack_words))
    # The trap return address is an absolute segment (the CPU reads it raw).
    words = [TRAP[1], TRAP[0] + LOAD_SEG] + list(stack_words)
    for i, w in enumerate(words):
        m.ww(sseg, sp + 2 * i, w)
    if setup is not None:
        setup(m)
    for r, v in (("ss", sseg), ("sp", sp), ("cs", seg), ("ip", off),
                 ("ds", dgroup_seg()), ("es", SRC_SEG)):
        m.set(r, v)
    reason = m.run(4_000_000)
    if reason != "fuzz-done":
        raise RuntimeError("fuzz: %s did not return (stop %s)" % (rid, reason))


def linear(seg: int, off: int) -> int:
    return ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF


def check_move(hyb: HybridLib, rng: random.Random, cases: int) -> list[str]:
    fails = []
    m = fresh_machine()
    ds = SRC_SEG
    scenarios = []
    for _ in range(cases):
        count = rng.choice([0, 1, 2, 3, 7, 8, 15, 16, 31, 64, 127, 128, 255, 256,
                            1024, 4096, rng.randrange(0, 3000)])
        src_off = rng.randrange(0, 8192)
        # dst: separate, or overlapping either way (the std/cld choice)
        mode = rng.randrange(4)
        if mode == 0:
            dst_seg, dst_off = DST_SEG, rng.randrange(0, 8192)
        elif mode == 1:
            dst_seg, dst_off = ds, (src_off + rng.choice([-16, -8, -1, 1, 8, 16])) % 12288
        elif mode == 2:
            dst_seg, dst_off = ds, src_off
        else:
            dst_seg, dst_off = ds, rng.randrange(0, 8192)
        scenarios.append((count, src_off, dst_seg, dst_off))
    scenarios += [(65535, 0, DST_SEG, 0), (0, 100, DST_SEG, 100), (1, 0, ds, 0)]
    for i, (count, src_off, dst_seg, dst_off) in enumerate(scenarios):
        if linear(ds, src_off) + count > 0xA0000 or linear(dst_seg, dst_off) + count > 0xA0000:
            continue
        data = bytes(rng.randrange(256) for _ in range(count))
        # Poison dst first, then src data: where they overlap the src bytes
        # win, which is exactly the pre-call memory both sides must see.
        m.write(dst_seg, dst_off, bytes(0x5A for _ in range(count)))
        m.write(ds, src_off, data)
        src_actual = bytes(m.read(ds, src_off, count))
        s_lin, d_lin = linear(ds, src_off), linear(dst_seg, dst_off)
        hyb._put(d_lin, bytes(0xA5 for _ in range(count)))
        hyb._put(s_lin, src_actual)
        # Expected result: the original's destructive rep movsb with the
        # original's direction rule (offsets only: forward when src_off >=
        # dst_off, the jae at 0AF8:1698). Simulate on the pre-call bytes.
        mem = bytearray(m.read(ds, 0, 16384)) if dst_seg == ds else None
        if dst_seg == ds:
            if (src_off & 0xFFFF) >= (dst_off & 0xFFFF):
                for k in range(count):
                    mem[dst_off + k] = mem[src_off + k]
            else:
                for k in range(count - 1, -1, -1):
                    mem[dst_off + k] = mem[src_off + k]
            want = bytes(mem[dst_off:dst_off + count])
        else:
            want = src_actual
        call_original(m, "0AF8:1685",
                      [count, dst_off, dst_seg, src_off, ds])
        if m.get("sp") != SCRATCH_STACK[1]:
            fails.append("case %d: SP not restored (want retf 10 behaviour)" % i)
            break
        got_orig = m.read(dst_seg, dst_off, count)
        hyb.lib.hybrid_System_Move((ds << 16) | src_off, (dst_seg << 16) | dst_off, count)
        got_c = hyb._get(d_lin, count)
        if got_orig != want:
            fails.append("case %d: original disagrees with rep-movsb model (count=%d src=%04X:%04X dst=%04X:%04X)" % (
                i, count, ds, src_off, dst_seg, dst_off))
            break
        if got_c != want:
            fails.append("case %d: C disagrees (count=%d src=%04X:%04X dst=%04X:%04X)" % (
                i, count, ds, src_off, dst_seg, dst_off))
            (BUILD / "move-fail-%d.bin" % i).write_bytes(got_c)
            break
        if dst_seg == ds:
            # Destructive side effects on the source must match as well.
            if hyb._get(s_lin, count) != m.read(ds, src_off, count):
                fails.append("case %d: source side effects differ" % i)
                break
    return fails


def check_fill(hyb: HybridLib, rng: random.Random, cases: int) -> list[str]:
    fails = []
    m = fresh_machine()
    for i in range(cases + 3):
        if i < cases:
            count = rng.choice([0, 1, 2, 15, 16, 255, 256, 1000, rng.randrange(0, 2000)])
            dst_off = rng.randrange(0, 8192)
            value = rng.randrange(256)
        else:
            count, dst_off, value = [(65535, 0, 0x41), (0, 50, 7), (1, 8191, 0xFF)][i - cases]
        if linear(DST_SEG, dst_off) + count > 0xA0000:
            continue
        m.write(DST_SEG, dst_off, bytes(0x5A for _ in range(count)))
        d_lin = linear(DST_SEG, dst_off)
        hyb._put(d_lin, bytes(0xA5 for _ in range(count)))
        call_original(m, "0AF8:16A8", [value, count, dst_off, DST_SEG])
        got_orig = m.read(DST_SEG, dst_off, count)
        hyb.lib.hybrid_System_FillChar((DST_SEG << 16) | dst_off, count, value)
        got_c = hyb._get(d_lin, count)
        want = bytes(value for _ in range(count))
        if got_orig != want or got_c != want:
            fails.append("case %d: count=%d value=%02X differ" % (i, count, value))
            break
    return fails


def check_random(hyb: HybridLib, rng: random.Random, cases: int) -> list[str]:
    fails = []
    m = fresh_machine()
    ds = dgroup_seg()
    for i in range(cases + 2):
        seed = rng.randrange(0, 0x100000000) if i < cases else [0, 0xFFFFFFFF][i - cases]
        rnge = rng.choice([0, 1, 2, 3, 4, 5, 13, 100, 256, 1000, 32767, 65535,
                           rng.randrange(0, 65536)])
        m.write(ds, 0x4428, seed.to_bytes(4, "little"))
        call_original(m, "0AF8:11C0", [rnge])
        ax_orig = m.get("ax")
        seed_orig = int.from_bytes(m.read(ds, 0x4428, 4), "little")
        hyb._put_seed(seed)
        ax_c = hyb.lib.hybrid_System_Random(rnge)
        seed_c = hyb._get_seed()
        if ax_orig != ax_c or seed_orig != seed_c:
            fails.append("case %d: seed=%08X range=%d: orig AX=%04X seed=%08X, C AX=%04X seed=%08X" % (
                i, seed, rnge, ax_orig, seed_orig, ax_c, seed_c))
            break
    return fails


CHECKS = {"0AF8:1685": check_move, "0AF8:16A8": check_fill, "0AF8:11C0": check_random}


def set_level(rid: str, verdict: str, note: str) -> None:
    p = ROOT / "re/symbols.toml"
    text = p.read_text()
    pat = re.compile(r"\[\[routine\]\]\nid = \"%s\"\n(?:.*\n)*?notes = \"[^\"]*\"" % re.escape(rid))
    m = pat.search(text)
    if not m:
        raise KeyError("no routine block %s in symbols.toml" % rid)
    block = m.group(0)
    new = re.sub(r'level = "[^"]*"', 'level = "%s"' % verdict, block)
    if note and "fuzz:" not in new:
        new = re.sub(r'notes = "([^"]*)"',
                      lambda mm: 'notes = "%s; fuzz:%s"' % (mm.group(1), note), new, count=1)
    p.write_text(text[:m.start()] + new + text[m.end():])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--routine", "--fn", dest="fn", required=True)
    ap.add_argument("--cases", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--no-verdict", action="store_true")
    a = ap.parse_args(argv)
    rid = resolve(a.fn)
    rng = random.Random(a.seed)
    hyb = HybridLib()
    BUILD.mkdir(parents=True, exist_ok=True)
    fails = CHECKS[rid](hyb, rng, max(200, a.cases))
    total = max(200, a.cases) + (3 if rid != "0AF8:11C0" else 2)
    report = {"routine": rid, "cases": total, "seed": a.seed, "failed": fails[:3]}
    (BUILD / ("%s.json" % rid.replace(":", "-"))).write_text(json.dumps(report, indent=1) + "\n")
    if fails:
        print("FAIL %s: %d/%d cases failed; first: %s" % (rid, len(fails), total, fails[0]))
        return 1
    print("PASS %s: %d cases, original and C agree on every byte" % (rid, total))
    if not a.no_verdict:
        set_level(rid, "L2", "%dcases-seed%d" % (total, a.seed))
        print("verdict: %s -> L2 in re/symbols.toml" % rid)
    return 0


if __name__ == "__main__":
    sys.exit(main())

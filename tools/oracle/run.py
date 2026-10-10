#!/usr/bin/env python3
"""run.py: run the original Pool of Radiance in the oracle (SPEC 8.2, `make oracle-run`).

  .venv/bin/python tools/oracle/run.py [--script tests/sessions/x.keys] [--max-insns N]
        [--out DIR] [--shot-final] [--trace ints,calls,files,ports] [--digest-every-read]

Writes into --out (default build/oracle/run): console.txt, trace.txt (when tracing), shots/*.png and
summary.json (stop reason, instruction count, state digest). Exit code 0 when the run stopped for an
expected reason (script end, quit, program exit), 3 on an unimplemented service, 4 on a guest fault.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from oracle.machine import Machine, OracleError, Unimplemented, GuestCrash, ROOT, Stop  # noqa: E402
from oracle.keys import KeyScript  # noqa: E402
from oracle.trace import Tracer  # noqa: E402
from oracle.protection import install_wheel_solver  # noqa: E402
from oracle.state import canonical_digest  # noqa: E402

EXE = ROOT / "poolrad/start-unpack.exe"
GAME = ROOT / "poolrad"


def build_machine(script: KeyScript | None, *, strict: bool = True) -> Machine:
    m = Machine(EXE, GAME, strict=strict)
    m.keys = script
    install_wheel_solver(m)
    return m


def run_session(script_text: str | None, *, max_insns: int, out_dir: Path | None = None,
                trace: str = "", shot_final: bool = True, digests: bool = True,
                strict: bool = True, quiet: bool = False, shot_every: int = 0) -> dict:
    """Run one session and return its summary (also used by tests and the golden recorder)."""
    script = KeyScript.parse(script_text) if script_text is not None else KeyScript([])
    m = build_machine(script, strict=strict)
    shots_dir = None
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)
        shots_dir = out_dir / "shots"
        shots_dir.mkdir(exist_ok=True)
    tracer = None
    tfile = None
    flags = {t for t in trace.split(",") if t}
    if flags:
        tfile = open(out_dir / "trace.txt", "w") if out_dir else None
        tracer = Tracer(m, ints="ints" in flags, calls="calls" in flags, files="files" in flags,
                        ports="ports" in flags, out=tfile)
    checkpoints: list[dict] = []

    def on_op(op, mach):
        kind, arg = op
        if kind == "shot" and shots_dir:
            mach.ega.screenshot(shots_dir / (arg + ".png"))
        if kind in ("shot", "digest"):
            checkpoints.append({"label": arg, "time": mach.now(), "digest": mach.state_digest(),
                                "canonical": canonical_digest(mach), "screen": mach.ega.planes_digest()})
        if kind == "quit":
            raise Stop("quit")

    script.on_op = on_op
    if digests:
        reads = []

        def on_key(mach, k):
            reads.append(mach.state_digest()[:16])
        m.on_key_read = on_key
    else:
        reads = []
    reason, err = None, None
    on_chunk = None
    if shot_every and shots_dir:
        nxt = [shot_every]

        def on_chunk(mach):
            if mach.insns >= nxt[0]:
                mach.ega.screenshot(shots_dir / ("t%010d.png" % mach.insns))
                nxt[0] = mach.insns + shot_every
    try:
        reason = m.run(max_insns, on_chunk=on_chunk)
    except Unimplemented as e:
        reason, err = "unimplemented", str(e)
    except GuestCrash as e:
        reason, err = "guest-fault", str(e)
    finally:
        if tfile:
            tfile.close()
    if out_dir:
        (out_dir / "console.txt").write_bytes(bytes(m.dos.console))
        if shot_final:
            m.ega.screenshot(out_dir / "final.png")
    summary = {
        "reason": reason, "error": err, "insns": m.insns, "virtual_seconds": round(m.seconds(), 3),
        "mode": m.ega.mode, "key_reads": m.bios.key_reads, "blocked_reads": m.bios.blocked_reads,
        "state_digest": m.state_digest(), "canonical_digest": canonical_digest(m),
        "checkpoints": checkpoints, "read_digests": reads,
        "int_counts": {"%02X" % k: v for k, v in sorted(m.int_counts.items())},
        "service_counts": {"%02X" % k: v for k, v in sorted(m.service_counts.items())},
        "files_opened": [p for (op, p, _x) in m.vfs.log if op == "open"],
        "missing_opens": [p for (op, p, _x) in m.vfs.log if op == "open-missing"],
        "routines_entered": len(tracer.entered) if tracer and tracer.calls else None,
    }
    if out_dir:
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=1))
    if not quiet:
        print("stop: %s after %d instructions (%.2f virtual s), mode %02Xh, %d key reads" % (
            reason, m.insns, m.seconds(), m.ega.mode, m.bios.key_reads))
        if err:
            print(err, file=sys.stderr)
    summary["_machine"] = m
    return summary


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--script", help="key script (.keys); omitted: no input, run until it blocks")
    ap.add_argument("--max-insns", type=int, default=200_000_000)
    ap.add_argument("--out", default=str(ROOT / "build/oracle/run"))
    ap.add_argument("--trace", default="", help="comma list of: ints calls files ports")
    ap.add_argument("--no-final-shot", action="store_true")
    ap.add_argument("--shot-every", type=int, default=0, help="screenshot every N instructions (debug)")
    ap.add_argument("--lenient", action="store_true", help="log unimplemented services instead of stopping")
    a = ap.parse_args(argv)
    text = Path(a.script).read_text() if a.script else None
    s = run_session(text, max_insns=a.max_insns, out_dir=Path(a.out), trace=a.trace,
                    shot_final=not a.no_final_shot, strict=not a.lenient, shot_every=a.shot_every)
    if s["reason"] == "unimplemented":
        return 3
    if s["reason"] == "guest-fault":
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())

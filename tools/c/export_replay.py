#!/usr/bin/env python3
"""export_replay.py: run a session script on the original in the oracle and write what the C translation is
replayed against (SPEC 8.5, Phase 7).

  .venv/bin/python tools/c/export_replay.py SESSION [--out build/c/replay/SESSION.rpl]

The oracle's recording (tools/oracle/replay.py) keeps one stream per kind of read, which is enough to replay the
original or the rebuild. The C translation also needs the order in which the reads came and where the checkpoints
fall in it, so this runs the same recorder with an order log, checks that the recording is the one the golden holds
(when there is one) and writes a text file the C replay driver (c/platform/replay.c) reads:

  RPL 1
  H <reads>                                         the number of reads of the outside world in the run
  R <kind> <ax> <bx> <cx> <dx> <flags> <irq> <n>    n identical reads in a row; irq: timer interrupts raised by then
  C <after-read> <label> <screen> <canonical> <random-calls>
  F <random-calls>
  W <dos-name> <sha256>                             files the run wrote

Kinds: 0 INT 16h AH=0 (key wait), 1 INT 16h AH=1 (key peek), 2 INT 21h AH=2Ch (time), 3 INT 21h AH=2Ah (date),
4 IN 40h (PIT), 5 IN 3DAh (retrace), 9 anything the C runtime does not make (the BIOS tick word the original's
Crt unit polls).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from oracle import golden, replay  # noqa: E402

KINDS = {"int16.00": 0, "int16.01": 1, "int21.2C": 2, "int21.2A": 3, "in040": 4, "in3DA": 5}


# DGROUP bytes that are the runtime's own bookkeeping, not game state: the overlay manager's variables, the exit and
# error variables, the stack segment inside DGROUP and the Crt/System tail (saved vectors, Input and Output); the
# Flags word of the Regs variable (what an INT returns there is the caller's own flags), and the
# file records (handle numbers and buffers differ) are masked too, from c/game/globals.txt. The C replay applies
# the same ranges (c/platform/replay.c).
STATIC_MASKS = [(0x43DC, 0x4400), (0x4418, 0x4428), (0x8760, 0xC760), (0x84F0, 0x10000),
                (0x4A14, 0x4A16)]      # Regs.Flags: the caller's flags at the INT instruction, left by compiled code


def file_masks() -> list[tuple[int, int]]:
    out = []
    for line in (ROOT / "c/game/globals.txt").read_text().splitlines():
        f = line.split()
        if len(f) >= 4 and f[3] == "file":
            out.append((int(f[0], 16), int(f[0], 16) + int(f[1])))
    return out


def masked_digest(m, ranges) -> str:
    import hashlib
    from oracle import state
    ds = state.dgroup_seg()
    data = bytearray(m.read(ds, 0, 0x10000))
    for lo, hi in ranges:
        data[lo:hi] = bytes(hi - lo)
    h = hashlib.sha256()
    h.update(b"MASKED")
    h.update(bytes(data))
    h.update(b"heap")
    h.update(state.heap_bytes(m, ds))
    h.update(m.ega.planes_digest().encode())
    return h.hexdigest()


class OrderedRecorder(replay.Recorder):
    """The recorder of the oracle, plus the order of all reads and a digest of the game's state at each checkpoint."""

    def __init__(self, m):
        self.order = []
        self.masked = {}
        self.ranges = STATIC_MASKS + file_masks()
        super().__init__(m)

    def _checkpoint(self, label, at=None):
        super()._checkpoint(label, at)
        at = self.streams.total if at is None else at
        self.masked[(at, label)] = masked_digest(self.m, self.ranges)

    def note(self, kind, value):
        self.order.append((kind, value, self.m.irq0_raised))
        super().note(kind, value)


def record_ordered(script_text: str):
    from oracle.run import run_session
    holder = {}

    def prepare(m):
        holder["rec"] = OrderedRecorder(m)

    s = run_session(script_text, max_insns=golden.MAX_INSNS, quiet=True, prepare=prepare,
                    insn_per_sec=golden.INSN_PER_SEC)
    return s, replay.Recording.of(s, holder["rec"]), holder["rec"]


def pinned_digest(dos_path: str):
    """The sha256 of the pinned file a DOS name (\\POOLRAD\\X) stands for, or None."""
    import hashlib
    rel = dos_path.upper().split("\\")[2:]
    here = ROOT / "poolrad"
    for part in rel:
        match = next((p for p in here.iterdir() if p.name.upper() == part), None) if here.is_dir() else None
        if match is None:
            return None
        here = match
    return hashlib.sha256(here.read_bytes()).hexdigest() if here.is_file() else None


def known_differences() -> dict:
    import tomllib
    d = tomllib.loads((ROOT / "tools/c/known_differences.toml").read_text())
    return {f["name"].upper(): [tuple(r) for r in f["ranges"]] for f in d.get("file", [])}


# Heap pointers inside the records the game saves (CoCo port, step 8.2): with the placement model the blocks are
# elsewhere, so the pointer fields of a saved record differ from the original's although the game did the same. Offsets
# from the record types (TCharacter 285 bytes: Affects 127, Items 200, SlotItems 204 (13), Next 260, Combat 264;
# TMenuLine 63: Next 42; TAffect 9: Next 5).
POINTER_FIELDS = {
    (".ITM", 63): [(42, 46)],
    (".SPC", 9): [(5, 9)],
    (".SAV", 285): [(127, 131), (200, 204), (204, 256), (260, 264), (264, 268)],
    (".CHA", 285): [(127, 131), (200, 204), (204, 256), (260, 264), (264, 268)],
}


def pointer_ranges(path: str, size: int) -> list[tuple[int, int]]:
    ext = path.upper()[-4:]
    out = []
    for (e, rec), fields in POINTER_FIELDS.items():
        if e == ext and size % rec == 0:
            for base in range(0, size, rec):
                out += [(base + lo, base + hi) for lo, hi in fields]
    return out


def lines(summary, recording, rec, pointer_masks=False) -> list[str]:
    out = ["RPL 1", "H %d" % len(rec.order)]
    for lo, hi in rec.ranges:
        out.append("M %d %d" % (lo, hi))
    run = None
    for kind, value, irq in rec.order:
        k = KINDS.get(kind, 9)
        if k <= 3:
            ax, bx, cx, dx, fl = value
            key = (k, ax, bx, cx, dx, fl, irq)
        elif k <= 5:
            key = (k, int(value), 0, 0, 0, 0, irq)
        else:
            key = (9, 0, 0, 0, 0, 0, irq)
        if run is not None and run[0] == key:
            run[1] += 1
        else:
            if run is not None:
                out.append("R %d %d %d %d %d %d %d %d" % (*run[0], run[1]))
            run = [key, 1]
    if run is not None:
        out.append("R %d %d %d %d %d %d %d %d" % (*run[0], run[1]))
    for at, cps in sorted(recording.checkpoints.items()):
        for c in cps:
            out.append("C %d %s %s %s %d" % (at, c["label"], c["screen"], rec.masked[(at, c["label"])], c["random_calls"]))
    out.append("F %d" % recording.final["random_calls"])
    known = known_differences()
    layer = summary["_machine"].vfs.layer
    if pointer_masks:
        for path in recording.final["written_files"]:
            r = pointer_ranges(path, len(layer[path])) if path in layer else []
            if r:
                known[path] = sorted(set(known.get(path, []) + r))
    for path, digest in sorted(recording.final["written_files"].items()):
        if digest == pinned_digest(path):
            continue                          # opened for update but not changed: nothing was written
        if path in known:
            import hashlib
            data = bytearray(layer[path])
            for lo, hi in known[path]:
                data[lo:hi] = bytes(len(data[lo:hi]))
            out.append("Z %s %s" % (path, " ".join("%d %d" % r for r in known[path])))
            out.append("W %s %s" % (path, hashlib.sha256(bytes(data)).hexdigest()))
            continue
        if digest == pinned_digest(path):
            continue                          # opened for update but not changed: nothing was written
        out.append("W %s %s" % (path, digest))
    return out


def export(session: str, out: Path, check_golden: bool = True, pointer_masks: bool = False) -> int:
    text = (golden.SESSIONS / (session + ".keys")).read_text()
    s, recording, rec = record_ordered(text)
    if s["reason"] not in ("input-exhausted", "quit"):
        print("[%s] the oracle stopped: %s %s" % (session, s["reason"], s["error"] or ""), file=sys.stderr)
        return 1
    gp = golden.GOLDEN / session / golden.RECORDING
    if check_golden and gp.exists():
        want = replay.Recording.load(gp)
        if want.digest() != recording.digest():
            print("[%s] the recording differs from the golden's: re-record the golden or fix the session" % session,
                  file=sys.stderr)
            return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines(s, recording, rec, pointer_masks)) + "\n")
    print("[%s] %s: %d reads, %d checkpoints" % (session, out, len(rec.order),
                                                  sum(len(v) for v in recording.checkpoints.values())))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("session", nargs="+")
    ap.add_argument("--out-dir", default=str(ROOT / "build/c/replay"))
    ap.add_argument("--no-golden-check", action="store_true")
    ap.add_argument("--pointer-masks", action="store_true",
                    help="mask the heap pointer fields of saved records (for builds whose heap is not the original's)")
    a = ap.parse_args(argv)
    rc = 0
    for s in a.session:
        rc |= export(s, Path(a.out_dir) / (s + ".rpl"), not a.no_golden_check, a.pointer_masks)
    return rc


if __name__ == "__main__":
    sys.exit(main())

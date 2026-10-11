#!/usr/bin/env python3
"""replay.py: record every read of the outside world, then replay it (SPEC 7.5, 8.4, 8.5).

Exhume's port method (docs/dos-decomp-projects/UW1Decomp/docs/BUILDING.md, UW2Decomp's PORT.md "The
differential test") applied to hybrid runs: a session is the sequence of values the game read from the
outside world. Replayed, the game reads the same values in the same order, so it does what it did
however many instructions its code takes. A routine replaced by C needs no time charged.

What the game reads from the outside world (survey of boot-title and create-character, 2026-10-11):
keyboard (INT 16h, peeks and reads), the time of day (INT 21h AH=2Ch, also what Randomize uses) and the
BIOS tick word 0040:006C (Crt init and Crt.Delay read it directly). Also covered though unused by these
sessions: INT 16h's other functions, INT 21h AH=2Ah, INT 1Ah AH=00h/02h/04h, the PIT counters (40h,
42h) and the retrace status (3DAh, 3BAh).

  record   run the original with the key script, as the golden recorder does (the same run: its
           summary still matches golden.json). Each read is noted as (value, timer interrupts raised so
           far) in a stream of its kind, run-length coded. Checkpoints are taken right after a read: after
           each completed key read, and after the first read that follows a script `shot`/`digest`. A
           checkpoint is the no-stack canonical state, the screen, the Random count and the interrupt count.
  replay   run with no script: each read returns the next value of its stream instead of asking the
           script or the clock, the timer interrupt is raised as many times as the recording had raised it
           by that read (game code the timer runs therefore runs, at reads instead of mid-computation;
           its only writes are stack frames and the BIOS tick, whitepaper appendix C), and the
           checkpoints are taken at the same read numbers and compared.

A read of another kind than the recording's next one, a value C asked for that differs, or a stream that
runs out early is a divergence and names the read. No instruction counting, no per-call costs: the run
goes at the emulator's full speed.

The recording is saved with the golden (`make golden`, `tests/sessions/golden/<name>/replay.json.gz`)
and verified by `make golden CHECK=1`; `make sessions` replays it with the lifted routines in C.

  .venv/bin/python tools/oracle/replay.py --session boot-title [--routine 0AF8:1685 ...] [--fresh]
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from unicorn import UC_HOOK_MEM_READ  # noqa: E402

from oracle.machine import FLAG_CF, FLAG_ZF, Stop  # noqa: E402
from oracle.state import canonical_digest  # noqa: E402

TICK_LO, TICK_HI = 0x46C, 0x46F           # BIOS tick count, 0040:006C (dword)
ROM_LO = 0xF0000                          # our BIOS's own code (the INT 8 stub increments the tick)
OBS_PORTS = (0x40, 0x42, 0x3DA, 0x3BA)
PERIOD = 20_000                           # also a checkpoint every this many reads (narrows a divergence)
END = -1                                  # checkpoint key: where the recording stopped (a last `shot`)
FLAGS_KEPT = FLAG_CF | FLAG_ZF            # what our services return in FLAGS


def observed(n: int, ah: int) -> bool:
    """Service calls whose answer comes from the outside world (keyboard, clock)."""
    if n == 0x16:
        return True
    if n == 0x1A:
        return ah in (0x00, 0x02, 0x04)
    if n == 0x21:
        return ah in (0x2A, 0x2C)
    return False


class Streams:
    """One run-length coded stream per kind of read: kind -> [[value, irq0_raised, count], ...]."""

    def __init__(self):
        self.runs: dict[str, list] = {}
        self.total = 0

    def add(self, kind: str, value, irq: int) -> None:
        runs = self.runs.setdefault(kind, [])
        if runs and runs[-1][0] == value and runs[-1][1] == irq:
            runs[-1][2] += 1
        else:
            runs.append([value, irq, 1])
        self.total += 1

    def summary(self) -> dict:
        return {k: (sum(r[2] for r in v), len(v)) for k, v in sorted(self.runs.items())}


class Cursor:
    def __init__(self, streams: Streams):
        self.streams = streams
        self.pos = {k: [0, 0] for k in streams.runs}      # kind -> [run index, used in that run]
        self.read = {k: 0 for k in streams.runs}          # kind -> reads consumed

    def take(self, kind: str):
        p = self.pos.get(kind)
        runs = self.streams.runs.get(kind)
        if p is None or p[0] >= len(runs):
            return None
        run = runs[p[0]]
        p[1] += 1
        if p[1] >= run[2]:
            p[0], p[1] = p[0] + 1, 0
        self.read[kind] += 1
        return run


def memory_nostack(m) -> str:
    """Every byte of conventional memory above the BIOS data area except the stack segment, with the
    video planes. Wider than canonical_nostack (DGROUP and video) until re/state.toml names the heap
    roots: a heap record (the party) is game state too. The interrupt vectors and the BIOS data area are
    machinery (the tick word, the timer's frames)."""
    from oracle.state import STACK_SIZE
    data = bytearray(m.uc.mem_read(0x500, 0xA0000 - 0x500))
    lo = (m.get("ss") << 4) - 0x500
    data[lo:lo + STACK_SIZE] = bytes(STACK_SIZE)
    h = hashlib.sha256(bytes(data))
    h.update(m.ega.planes_digest().encode())
    return h.hexdigest()


def written_files(m) -> dict:
    return {k: hashlib.sha256(bytes(v)).hexdigest() for k, v in sorted(m.vfs.layer.items())}


def checkpoint(m, label: str) -> dict:
    return {"label": label, "canonical_nostack": canonical_digest(m, exclude_stack=True),
            "memory_nostack": memory_nostack(m), "screen": m.ega.planes_digest(),
            "random_calls": len(m.random_log), "irq0": m.irq0_raised}


class Recorder:
    """Attached to an original run (with its key script)."""

    def __init__(self, m):
        self.m = m
        self.streams = Streams()
        self.checkpoints: dict[int, list] = {}     # read number (1-based, after the read) -> checkpoints
        self._fired = 0
        self.end: dict | None = None
        self.max_gap = 0                            # most instructions the run went without a read
        self._last = 0
        _attach(m, self)

    def service(self, m, n, ah, fn):
        ss, sp = m.get("ss"), m.get("sp")
        ret = m.rw(ss, sp)
        try:
            fn(m)
        except Stop:
            self.end = {"reads": self.streams.total, "kind": "%02X.%02X" % (n, ah)}
            self._shots(END)                        # a shot that fired as the script ran out
            raise
        if m.rw(ss, sp) != ret:
            return                                  # a blocked read: the INT is retried, not answered
        value = (m.get("ax"), m.get("bx"), m.get("cx"), m.get("dx"), m.rw(ss, sp + 4) & FLAGS_KEPT)
        self.note("int%02X.%02X" % (n, ah), value)
        if n == 0x16 and ah in (0x00, 0x10):
            self._checkpoint("key%d" % m.bios.key_reads)

    def port(self, port, size, v):
        self.note("in%03X" % port, v)
        return v

    def memory(self, addr, size):
        v = bytes(self.m.uc.mem_read(addr, size))
        self.note("mem%03X.%d" % (addr, size), v.hex())

    def note(self, kind, value):
        self.streams.add(kind, value, self.m.irq0_raised)
        self.max_gap = max(self.max_gap, self.m.insns - self._last)
        self._last = self.m.insns
        self._shots(self.streams.total)
        if self.streams.total % PERIOD == 0:
            self._checkpoint("read%d" % self.streams.total)

    def _shots(self, at):
        keys = getattr(self.m, "keys", None)
        if keys is not None and len(keys.fired) > self._fired:
            for op in keys.fired[self._fired:]:
                if op[0] in ("shot", "digest"):
                    self._checkpoint(op[1], at)
            self._fired = len(keys.fired)

    def _checkpoint(self, label, at=None):
        at = self.streams.total if at is None else at
        self.checkpoints.setdefault(at, []).append(checkpoint(self.m, label))


class Player:
    """Attached to a run with no script: answers every read from a recording."""

    def __init__(self, m, rec: "Recording"):
        self.m = m
        self.rec = rec
        self.cursor = Cursor(rec.streams)
        self.reads = 0
        self.checkpoints: dict[int, list] = {}
        self.first_difference: str | None = None
        self.stop_reason: str | None = None
        m.irq0_owed = 0
        _attach(m, self)
        # A replay that stops reading the outside world has gone off the rails (an endless loop): stop
        # it well before max_insns. The bound is generous against the recording's longest quiet stretch.
        self._last = 0
        limit = 4 * rec.max_gap + 20_000_000
        service = m.keys.service

        def watch(mm):
            service(mm)
            if mm.insns - self._last > limit:
                self._fail("no read for %d instructions after read %d (the recording's longest gap is %d): "
                           "the replay has left the recorded path" % (mm.insns - self._last, self.reads,
                                                                      rec.max_gap))
        m.keys.service = watch

    def _fail(self, msg):
        if self.first_difference is None:
            self.first_difference = msg
        raise Stop("diverged")

    def _next(self, kind):
        if self.rec.end is not None and self.reads == self.rec.end["reads"]:
            self._compare(END)
            raise Stop("input-exhausted")             # where the recording ended
        run = self.cursor.take(kind)
        if run is None:
            self._fail("read %d: the game asks %s, but the recording has no more of those (reads of each "
                       "kind so far: %s)" % (self.reads + 1, kind, self.cursor.read))
        value, irq, _n = run
        owed = irq - self.m.irq0_raised - self.m.irq0_owed
        if owed > 0:
            self.m.irq0_owed += owed
        return value

    def _after(self):
        self.reads += 1
        self._last = self.m.insns
        self._compare(self.reads)

    def _compare(self, at):
        want = self.rec.checkpoints.get(at)
        if want is None:
            return
        got = [dict(checkpoint(self.m, w["label"]), irq0=self._irq_now()) for w in want]
        self.checkpoints[at] = got
        where = "the end" if at == END else "read %d" % at
        for w, g in zip(want, got):
            if w != g and self.first_difference is None:
                self.first_difference = "%s (%s): %s" % (
                    where, w["label"], {k: (w[k], g[k]) for k in w if w[k] != g[k]})

    def _irq_now(self):
        # interrupts raised by this read in the recording: those delivered plus those owed
        return self.m.irq0_raised + self.m.irq0_owed

    def service(self, m, n, ah, fn):
        value = self._next("int%02X.%02X" % (n, ah))
        ax, bx, cx, dx, fl = value
        for r, v in (("ax", ax), ("bx", bx), ("cx", cx), ("dx", dx)):
            m.set(r, v)
        m.ret_flags(set_mask=fl, clear_mask=FLAGS_KEPT & ~fl)
        if n == 0x16 and ah in (0x00, 0x10):
            m.bios.key_reads += 1
        self._after()

    def port(self, port, size, v):
        value = self._next("in%03X" % port)
        self._after()
        return value

    def memory(self, addr, size):
        value = self._next("mem%03X.%d" % (addr, size))
        self.m.uc.mem_write(addr, bytes.fromhex(value))
        self._after()


def _attach(m, obs) -> None:
    """Route the observed services, ports and the tick word through `obs`."""
    for n in (0x16, 0x1A, 0x21):
        fn = m.services.get(n)
        if fn is None:
            continue

        def wrapped(mm, n=n, fn=fn):
            ah = mm.get("ax") >> 8
            if not observed(n, ah):
                return fn(mm)
            return obs.service(mm, n, ah, fn)
        m.services[n] = wrapped
    port_read = m.port_read

    def port(p, size):
        if p not in OBS_PORTS:
            return port_read(p, size)
        v = port_read(p, size)                         # keeps side effects (3DAh resets the flip-flop)
        return obs.port(p, size, v)
    m.port_read = port

    def mem(uc, access, addr, size, value, _ud):
        if m.linear(m.get("cs"), m.get("ip")) >= ROM_LO:
            return                                     # our BIOS's INT 8 stub counting the tick
        obs.memory(addr, size)
    m.uc.hook_add(UC_HOOK_MEM_READ, mem, begin=TICK_LO, end=TICK_HI)


# ----------------------------------------------------------------------------- recordings
FORMAT = 1
FINAL_FIELDS = ("reason", "canonical_nostack_digest", "random_calls", "random_digest", "files_opened", "mode")


class Recording:
    """What a replay needs from a recorded run, and what it is compared against. Saved with the golden
    (`tests/sessions/golden/<name>/replay.json.gz`), so a replay needs no recording run."""

    def __init__(self, streams: Streams, checkpoints: dict, end, max_gap: int, final: dict):
        self.streams, self.checkpoints, self.end, self.max_gap, self.final = (
            streams, checkpoints, end, max_gap, final)

    @classmethod
    def of(cls, summary: dict, rec: Recorder) -> "Recording":
        m = summary["_machine"]
        final = {k: summary[k] for k in FINAL_FIELDS}
        final["memory_nostack"] = memory_nostack(m)
        final["written_files"] = written_files(m)
        return cls(rec.streams, rec.checkpoints, rec.end, rec.max_gap, final)

    def to_json(self) -> str:
        return json.dumps({"format": FORMAT, "reads": self.streams.total, "end": self.end,
                           "max_gap": self.max_gap, "final": self.final,
                           "checkpoints": {str(k): v for k, v in sorted(self.checkpoints.items())},
                           "streams": self.streams.runs}, sort_keys=True, separators=(",", ":"))

    @classmethod
    def from_json(cls, text: str) -> "Recording":
        d = json.loads(text)
        if d.get("format") != FORMAT:
            raise ValueError("recording format %r, the tool reads %d: re-record (make golden)" % (
                d.get("format"), FORMAT))
        st = Streams()
        st.runs, st.total = d["streams"], d["reads"]
        return cls(st, {int(k): v for k, v in d["checkpoints"].items()}, d["end"], d["max_gap"], d["final"])

    def save(self, path: Path) -> None:
        Path(path).write_bytes(gzip.compress(self.to_json().encode(), compresslevel=9, mtime=0))

    @classmethod
    def load(cls, path: Path) -> "Recording":
        return cls.from_json(gzip.decompress(Path(path).read_bytes()).decode())

    def digest(self) -> str:
        return hashlib.sha256(self.to_json().encode()).hexdigest()


# ----------------------------------------------------------------------------- sessions
def record(script_text: str, max_insns: int = 400_000_000, out_dir: Path | None = None,
           insn_per_sec: int = 1_000_000):
    """Run the original with its script (the golden run); returns (summary, Recording)."""
    from oracle.run import run_session
    holder = {}

    def prepare(m):
        holder["rec"] = Recorder(m)

    s = run_session(script_text, max_insns=max_insns, quiet=True, prepare=prepare, out_dir=out_dir,
                    insn_per_sec=insn_per_sec)
    return s, Recording.of(s, holder["rec"])


def replay(rec: Recording, prepare=None, max_insns: int = 400_000_000):
    """Replay a recording, optionally with routines replaced (prepare(machine)); returns (summary, Player)."""
    from oracle.run import run_session
    holder = {}

    def prep(m):
        holder["player"] = Player(m, rec)
        if prepare is not None:
            prepare(m)

    s = run_session(None, max_insns=max_insns, quiet=True, digests=False, prepare=prep)
    return s, holder["player"]


def difference(rec: Recording, got: dict, player: Player) -> str | None:
    """First difference between a recording and its replay (None when they match)."""
    if got["reason"] != rec.final["reason"] or got["error"]:
        return "replay stopped (%s): %s" % (got["reason"], player.first_difference or got["error"] or "")
    if player.reads != rec.streams.total:
        return "replay made %d reads, the recording %d" % (player.reads, rec.streams.total)
    if player.first_difference:
        return player.first_difference
    missing = set(rec.checkpoints) - set(player.checkpoints)
    if missing:
        return "checkpoints at reads %s never reached" % sorted(missing)[:5]
    for k in FINAL_FIELDS:
        if rec.final[k] != got[k]:
            return "final %s: %r != %r" % (k, rec.final[k], got[k])
    m = got["_machine"]
    if rec.final["memory_nostack"] != memory_nostack(m):
        return "final memory (outside the stack segment) differs"
    files = written_files(m)
    if rec.final["written_files"] != files:
        return "files written differ: %s" % sorted(set(rec.final["written_files"].items()) ^ set(files.items()))
    return None


def describe(rec: Recording) -> str:
    parts = ["%s %d reads in %d runs" % (k, sum(r[2] for r in v), len(v)) for k, v in sorted(rec.streams.runs.items())]
    return "%d reads (%s), %d checkpoints" % (rec.streams.total, "; ".join(parts),
                                               sum(len(v) for v in rec.checkpoints.values()))


def main(argv=None) -> int:
    from oracle import golden
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--session", required=True)
    ap.add_argument("--routine", action="append", default=[], help="replace with the C lift (hybrid.py)")
    ap.add_argument("--fresh", action="store_true", help="record now instead of using the golden's recording")
    a = ap.parse_args(argv)
    t = time.time()
    if a.fresh:
        _s, rec = record((golden.SESSIONS / (a.session + ".keys")).read_text())
        print("recorded in %.1fs: %s" % (time.time() - t, describe(rec)))
    else:
        rec = Recording.load(golden.GOLDEN / a.session / golden.RECORDING)
    prepare = None
    if a.routine:
        from oracle.hybrid import install
        prepare = install(set(a.routine))
    t = time.time()
    got, player = replay(rec, prepare)
    diff = difference(rec, got, player)
    print("replay: %s, %.1fs: %s" % (got["reason"], time.time() - t, diff or "matches the recording"))
    return 1 if diff else 0


if __name__ == "__main__":
    sys.exit(main())

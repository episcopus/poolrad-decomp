#!/usr/bin/env python3
"""sessions.py: show, in the oracle, that the port's reference build (the series without speed patches,
`build.py --ref`, build/ref) plays the same game as the original on every session of tests/sessions, apart from what
its patches change on purpose. The speed patches are compared with that reference by func.py.

  .venv/bin/python ports/dos/tools/sessions.py [--session NAME ...] [--sound T|P|S]
  make -C ports/dos sessions [SESSION=name] [SOUND=P]

The comparison is the project's replay method (tools/oracle/replay.py), which does not depend on speed:

  1. The original runs the session's key script, with the sound device --sound names (default T, the Tandy
     chip). Every value it reads from the outside world (keys, time of day, BIOS tick, timer ports) is
     recorded in order, with the number of timer interrupts raised so far; a checkpoint is taken after
     every key read, at every `shot` and every 20,000 reads.
  2. The reads the code wheel made are cut out: from the wheel routine's random draw (it draws before it
     reads anything) up to and including the read of the ENTER after the code word. The port's wheel
     routine makes none of them. Checkpoints after the cut are renumbered, and the timer interrupts the
     original raised during the cut stretch are taken off every later count: the port spends no time on
     the wheel. (Left owed, they would come one per execution chunk of the replay, as a backlog that
     shifts the sound driver's steps for a while: council-guards, 55 writes.)
  3. The port replays that recording: each read returns the recorded value, the timer interrupts the
     recording had raised by then are raised (the wheel's are owed at the first read after the cut), and
     the checkpoints are compared at the same read numbers. However many instructions the port's code
     takes, it must ask for the same things in the same order and be in the same state.

A checkpoint is the game state (DGROUP's data with the overlay manager's own variables masked, the Turbo Pascal
heap, the video planes; offsets from the port's link map, so a patch that moves a global needs a comparison by
name first), the screen, the number of Random calls and of timer interrupts. The stack and the overlay buffer
are left out (stale frames; the overlay code itself, which the port's patches change). At the end also:

  random     every Random call: kind, range and result; the caller too, except the draw of the code wheel
             routine (ovl02), which the port makes at another offset of a shorter routine
  files      the files opened, and the bytes of the files written (saved games), GAME.OVR (the port's own)
             excepted and the ranges of tools/c/known_differences.toml masked (SaveGame writes stale stack
             bytes, whitepaper appendix C; the port's stack history differs where the wheel was)
  sound      every call of PlaySound and SetSoundDriverIdle (res03's Pascal front end) with its argument,
             in order: what the game asks the sound driver to do. Not the chip writes: in a replay the timer
             interrupts that step the driver are raised at chunk boundaries of the emulator (every 50,000
             instructions at most), so how many steps fit in PlaySound's 0.1 s wait depends on the code's
             length before it (council-guards: 11,238 writes replaying the original, 11,183 the port). The
             driver itself is checked by build.py: res03's code is the original's

A recording whose script stops between two reads (`quit`, the last `shot`) has no end marker: a replay that has
used every recorded read and asks for one more has reached the end, not left the path.

Exit status 0 when every session agrees. The oracle emulates an EGA PC: Tandy video is checked by tandy.py.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
import time
import tomllib
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
ROOT = PORT.parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/re"))

from oracle import golden, layout, replay, state  # noqa: E402
from oracle.keys import KeyScript  # noqa: E402
from oracle.run import run_session  # noqa: E402
import tp_toolchain as tp  # noqa: E402

LINK = PORT / "build/ref"           # the reference: behaviour patches only (func.py checks the speed patches against it)
SESSIONS = ROOT / "tests/sessions"
WHEEL_UNIT = "ovl02"            # the code wheel routine's overlay (CheckCodeWheel)
OWN_FILES = ("\\POOLRAD\\GAME.OVR",)
MASKED = (0, 0)                 # DS offsets [lo, hi) of the overlay manager's variables (main sets it)


def overlay_vars() -> tuple[int, int]:
    """OvrResult up to HeapOrg, the next System variable, from the port's link map."""
    _segs, pubs = tp.read_map(tp.ci(LINK, "POOL.MAP"))
    return pubs["OVRRESULT"][1], pubs["HEAPORG"][1]


def game_state(m) -> str:
    ds = state.dgroup_seg()
    end = min(0x10000, max(0, (m.get("ss") - ds) << 4))       # the data segment ends where the stack begins
    data = bytearray(m.read(ds, 0, end))
    lo, hi = MASKED
    data[lo:hi] = bytes(hi - lo)
    h = hashlib.sha256(bytes(data))
    h.update(b"heap" + state.heap_bytes(m, ds))
    h.update(m.ega.planes_digest().encode())
    return h.hexdigest()


def checkpoint(m, label: str) -> dict:
    """replay.checkpoint for this comparison: the game state instead of the whole memory."""
    return {"label": label, "state": game_state(m), "screen": m.ega.planes_digest(),
            "random_calls": len(m.random_log), "irq0": m.irq0_raised}


replay.checkpoint = checkpoint  # the Recorder and the Player both call it by this name


SOUND_ROUTINES = ("PlaySound", "SetSoundDriverIdle")


def sound_entries(port: bool) -> dict[str, tuple[int, int]]:
    """Name -> (unit segment, offset) of the sound front end: the port's link map, or re/symbols.toml."""
    if port:
        _segs, pubs = tp.read_map(tp.ci(LINK, "POOL.MAP"))
        return {n: pubs[n.upper()] for n in SOUND_ROUTINES}
    syms = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
    out = {}
    for r in syms:
        if r.get("name") in SOUND_ROUTINES:
            seg, off = r["addr"].split(":")
            out[r["name"]] = (int(seg, 16), int(off, 16))
    return out


def log_sound_calls(m, entries: dict) -> list:
    """Every call of the sound front end: (routine, argument). The argument is the word above the far return."""
    from oracle.machine import LOAD_SEG
    calls = []
    for name, (seg, off) in entries.items():
        m.add_breakpoint(LOAD_SEG + seg, off,
                         lambda mm, name=name: calls.append((name, mm.rw(mm.get("ss"), mm.get("sp") + 4))))
    return calls


def wheel_drawn(m, start: int) -> bool:
    return any(str(c.caller).startswith(WHEEL_UNIT) for c in m.random_log[start:])


class WheelKeys(KeyScript):
    """The original's key script, noting when its `wheel` answer (code word, then ENTER) has been taken."""

    wheel_end = None                # op index after the expanded answer
    answered = False

    def _advance(self, m, at_poll: bool = True):
        if self.i < len(self.ops) and self.ops[self.i][0] == "wheel" and getattr(m, "wheel_answer", None):
            self.wheel_end = self.i + len(m.wheel_answer) + 1
        return super()._advance(m, at_poll)

    def take(self, m):
        k = super().take(m)
        if k is not None and self.i == self.wheel_end:
            self.answered = True
        return k


class Recorder(replay.Recorder):
    """replay.Recorder that also keeps every read in order and marks those the code wheel made."""

    def __init__(self, m):
        super().__init__(m)
        self.flat: list[tuple[str, object, int, bool]] = []     # (kind, value, irq0, made by the wheel)
        self.phase = "before"                                   # before, wheel, after
        self.seen = 0

    def note(self, kind, value):
        m = self.m
        if self.phase == "before" and wheel_drawn(m, self.seen):
            self.phase = "wheel"
        self.seen = len(m.random_log)
        self.flat.append((kind, value, m.irq0_raised, self.phase == "wheel"))
        if self.phase == "wheel" and m.keys.answered:
            self.phase = "after"                                # this read was the ENTER
        super().note(kind, value)


def record(text: str):
    """The original's run of the script: (summary, its Recording, Recorder, machine)."""
    layout.use(layout.original())
    holder = {}

    def prepare(m):
        m.keys.__class__ = WheelKeys
        holder["rec"] = Recorder(m)
        m.sound_calls = log_sound_calls(m, sound_entries(False))

    s = run_session(text, max_insns=golden.session_limit(text), quiet=True, prepare=prepare,
                    insn_per_sec=golden.INSN_PER_SEC)
    rec = replay.Recording.of(s, holder["rec"])
    return s, rec, holder["rec"], s.pop("_machine")


def without_wheel(rec: replay.Recording, recorder: Recorder) -> tuple[replay.Recording, int, int]:
    """The recording with the wheel's reads cut out: (recording, first cut read, reads cut)."""
    cut = [i for i, r in enumerate(recorder.flat) if r[3]]
    if not cut:
        cut_end = {at: cp for at, cp in rec.checkpoints.items()}
        if replay.END in cut_end and recorder.flat:
            cut_end[replay.END] = [dict(c, irq0=recorder.flat[-1][2]) for c in cut_end[replay.END]]
        return replay.Recording(rec.streams, cut_end, rec.end, rec.max_gap, rec.final), 0, 0
    first, n = cut[0] + 1, len(cut)                             # read numbers are 1-based, after the read
    if cut != list(range(cut[0], cut[0] + n)):
        raise ValueError("the wheel's reads are not one stretch")
    flat = recorder.flat
    before = flat[cut[0] - 1][2] if cut[0] else 0
    k = flat[cut[-1]][2] - before                               # timer interrupts raised during the cut
    streams = replay.Streams()
    for i, (kind, value, irq, wheel) in enumerate(flat):
        if not wheel:
            streams.add(kind, value, irq - k if i > cut[-1] else irq)
    cps = {}
    for at, cp in rec.checkpoints.items():
        if at == replay.END:
            # a replay stops in the recording's last read before the interrupts raised since the read
            # before it are owed (replay.Player._next), so it ends with the count of the last noted read:
            # the original replayed against itself is one short at the end of camp-rest-combat
            cps[at] = [dict(c, irq0=flat[-1][2] - k) for c in cp]
        elif at < first:
            cps[at] = cp
        elif at >= first + n:
            cps[at - n] = cps.get(at - n, []) + [dict(c, irq0=c["irq0"] - k) for c in cp]
    end = dict(rec.end, reads=rec.end["reads"] - n) if rec.end else None
    return replay.Recording(streams, cps, end, rec.max_gap, rec.final), first, n


def known_differences() -> dict[str, list[tuple[int, int]]]:
    """File name -> byte ranges [lo, hi) that hold no game state (tools/c/known_differences.toml)."""
    d = tomllib.loads((ROOT / "tools/c/known_differences.toml").read_text())
    return {f["name"]: [tuple(r) for r in f["ranges"]] for f in d.get("file", [])}


def written(m, known: dict) -> dict[str, str]:
    """The files the run wrote, masked, as hashes (GAME.OVR, the port's own, left out)."""
    out = {}
    for name, data in sorted(m.vfs.layer.items()):
        if name in OWN_FILES:
            continue
        b = bytearray(data)
        for lo, hi in known.get(name, ()):
            b[lo:hi] = bytes(max(0, min(hi, len(b)) - lo))
        out[name] = hashlib.sha256(bytes(b)).hexdigest()
    return out


def ran_to_end(player, rec) -> bool:
    """The replay used every read of a recording that has no end marker and asked for one more."""
    return (rec.end is None and player.reads == rec.streams.total and player.first_difference is not None
            and "the recording has no more of those" in player.first_difference)


def compare(os_, om, ps, pm, player, prec) -> tuple[list[str], list[str]]:
    """(differences, notes) between the original's run and the port's replay."""
    diffs, notes = [], []
    if player.first_difference and not ran_to_end(player, prec):
        diffs.append("replay: %s" % player.first_difference)
    elif not player.first_difference and (ps["error"] or ps["reason"] not in ("input-exhausted", os_["reason"])):
        diffs.append("replay stopped: %s %s" % (ps["reason"], ps["error"] or ""))
    missing = set(prec.checkpoints) - set(player.checkpoints)
    if missing and not player.first_difference:
        diffs.append("checkpoints at reads %s never reached" % sorted(missing)[:5])
    notes.append("%d reads, %d checkpoints equal" % (player.reads, sum(len(v) for v in player.checkpoints.values())))
    ol, pl = om.random_log, pm.random_log
    if len(ol) != len(pl):
        diffs.append("random calls: original %d, port %d" % (len(ol), len(pl)))
    for i, (a, b) in enumerate(zip(ol, pl)):
        if (a.kind, a.range, a.result) != (b.kind, b.range, b.result):
            diffs.append("random call %d: original %s %s -> %s from %s, port %s %s -> %s from %s" % (
                i, a.kind, a.range, a.result, a.caller, b.kind, b.range, b.result, b.caller))
            break
        if a.caller != b.caller and not (str(a.caller).startswith(WHEEL_UNIT) and str(b.caller).startswith(WHEEL_UNIT)):
            diffs.append("random call %d: caller original %s, port %s" % (i, a.caller, b.caller))
            break
    notes.append("%d random calls equal" % min(len(ol), len(pl)))
    if os_["files_opened"] != ps["files_opened"]:
        diffs.append("files opened: original %s, port %s" % (os_["files_opened"], ps["files_opened"]))
    known = known_differences()
    ow, pw = written(om, known), written(pm, known)
    if ow != pw:
        diffs.append("files written differ: %s" % sorted(k for k in set(ow) | set(pw) if ow.get(k) != pw.get(k)))
    if om.sound_calls != pm.sound_calls:
        i = next((i for i, (a, b) in enumerate(zip(om.sound_calls, pm.sound_calls)) if a != b),
                 min(len(om.sound_calls), len(pm.sound_calls)))
        diffs.append("sound calls: original %d, port %d; first difference at %d: %s, %s" % (
            len(om.sound_calls), len(pm.sound_calls), i, om.sound_calls[i:i + 1], pm.sound_calls[i:i + 1]))
    notes.append("%d sound calls equal" % len(om.sound_calls))
    return diffs, notes


def with_sound(text: str, device: str) -> str:
    """The script with its `sound` setting replaced by (or given) `device`."""
    lines = [l for l in text.splitlines() if not l.strip().startswith("sound ")]
    return "sound %s\n%s\n" % (device, "\n".join(lines))


def main(argv=None) -> int:
    global MASKED
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--session", action="append", help="tests/sessions/NAME.keys (default: every session)")
    ap.add_argument("--sound", default="T", choices=("T", "P", "S"), help="POOL.CFG sound device (default T)")
    a = ap.parse_args(argv)
    try:
        port = layout.rebuilt(LINK)
        MASKED = overlay_vars()
    except (FileNotFoundError, ValueError, KeyError, TypeError) as e:
        print("sessions: no usable reference build in %s (%s): make -C ports/dos ref" % (LINK, e))
        return 1
    port.name = "ports/dos"
    names = a.session or sorted(p.stem for p in SESSIONS.glob("*.keys"))
    failed = []
    for name in names:
        t0 = time.time()
        text = with_sound((SESSIONS / (name + ".keys")).read_text(), a.sound)
        os_, rec, recorder, om = record(text)
        try:
            prec, first, n = without_wheel(rec, recorder)
        except ValueError as e:
            print("[%s] DIFFERS: %s" % (name, e))
            failed.append(name)
            continue
        cfg = {k: bytearray(v) for k, v in om.vfs.layer.items() if k.endswith("\\POOL.CFG")}

        def prepare(m):
            m.vfs.layer.update(cfg)               # the sound device the script set (oracle.run.build_machine)
            m.sound_calls = log_sound_calls(m, sound_entries(True))

        layout.use(port)
        ps, player = replay.replay(prec, prepare=prepare, max_insns=golden.session_limit(text))
        pm = ps.pop("_machine")
        diffs, notes = compare(os_, om, ps, pm, player, prec)
        notes.insert(0, "wheel: %d reads cut after read %d" % (n, first - 1) if n else "no wheel")
        print("[%s] %s (%.0f s): %s" % (name, "ok" if not diffs else "DIFFERS", time.time() - t0, "; ".join(notes)),
              flush=True)
        for d in diffs[:12]:
            print("    " + d)
        if diffs:
            failed.append(name)
    print("sessions: %d of %d play the same game on the port (sound %s)%s" % (
        len(names) - len(failed), len(names), a.sound, (" (differ: %s)" % ", ".join(failed)) if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

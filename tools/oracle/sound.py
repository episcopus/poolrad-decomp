"""sound.py: what the game sent to its sound hardware, as a trace (SPEC 8.5, playbook 50).

The driver of res03 programs three things; the oracle logs each write with the virtual time:

  P  PIT channel 0 reload    the driver's timer: starts at 236.7 Hz, stops at 65536 (whitepaper 5.14)
  S  PC speaker              PIT channel 2 divisor (written low then high) and the gate bits of port 61h
  T  Tandy 3-voice chip      every byte written to port C0h (frequency, latch and attenuation bytes)

A golden keeps the trace's digest twice: with the times (what a build with the same instruction count must
reproduce) and without (the sequence of sounds, which a build of another speed, the C translation, must
reproduce). The full trace is stored gzipped next to the golden so a divergence names its first event.
"""
from __future__ import annotations

import gzip
import hashlib


def events(m) -> list[tuple]:
    """The machine's sound writes in time order: (time, 'P'|'S'|'T', a, b)."""
    out = []
    for t, reload in m.pit0_log:
        out.append((t, "P", reload, 0))
    for t, divisor, on in m.speaker_log:
        out.append((t, "S", divisor, int(on)))
    for t, byte in m.tandy_log:
        out.append((t, "T", byte, 0))
    out.sort(key=lambda e: (e[0], "PST".index(e[1])))
    return out


def format_trace(ev: list[tuple]) -> str:
    return "".join("%10d %s %5d %d\n" % e for e in ev)


def digest(ev: list[tuple], with_time: bool = True) -> str:
    h = hashlib.sha256()
    for t, kind, a, b in ev:
        h.update(("%s %s %d %d\n" % (("%d" % t) if with_time else "", kind, a, b)).encode())
    return h.hexdigest()


def save(path, ev: list[tuple]) -> None:
    from pathlib import Path
    Path(path).write_bytes(gzip.compress(format_trace(ev).encode(), compresslevel=9, mtime=0))


def summary(ev: list[tuple]) -> dict:
    kinds = {k: sum(1 for e in ev if e[1] == k) for k in "PST"}
    return {"sound_events": len(ev), "sound_pit0": kinds["P"], "sound_speaker": kinds["S"],
            "sound_tandy": kinds["T"], "sound_digest": digest(ev), "sound_sequence_digest": digest(ev, False)}

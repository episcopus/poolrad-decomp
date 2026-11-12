#!/usr/bin/env python3
"""build.py: render the original's Tandy sound and the designs, and write the comparison page (README.md).

  python3 ports/dos/sound/build.py          after capture.py; writes ports/dos/build/sound/

Every clip goes through snrender (the chip emulator) at one scale, so the level of a designed sound against the
original's is the level the chip gives them. The page (index.html) embeds every clip as MP3 (lame) and draws its
spectrogram in the browser.
"""
from __future__ import annotations

import base64
import json
import math
import subprocess
import sys
import wave
from array import array
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "ports/dos/build/sound"
SNRENDER = OUT / "snrender"
sys.path.insert(0, str(HERE))

import designs  # noqa: E402

TICK = 1193182 / 5041            # the driver's timer
IDLE_CUT = 0.10                  # WaitHundredths(10) while the driver is idle
IDLE_SOUNDS = {7, 9, 10}         # played while the driver is idle (see designs.IDLE): the page plays them cut

# What the original's Tandy tune does, read from the capture (tune = sound - 1; describe.py-style decoding)
CURRENT = {
    2: "Three detuned tones near 430, 490 and 860 Hz on a fast vibrato, fading together over 0.8 s: a warbling chord.",
    3: "White noise at the fast rate, swelling in and out over 0.2 s.",
    4: "Three tones gliding up from 185 Hz to 1.6 to 1.9 kHz, each starting a little after the last, fading over 1 s.",
    5: "A low tone wandering between 113 and 167 Hz over white noise clocked by tone 2 (1.1 to 1.6 kHz), 1.6 s.",
    6: "One thin tone at 2.9 kHz creeping up to 3.6 kHz at a constant level for 1 s: a whistle.",
    7: "White noise clocked by tone 2 for two ticks, fading: 90 ms.",
    8: "Two tones climbing from 120 Hz to 3 kHz in random steps while they fade, over 2.1 s, then a quiet low pair.",
    9: "White noise at the fast rate, a 0.26 s swell and fade, of which the game plays the first 0.1 s.",
    10: "White noise at the slow rate, 70 ms.",
    11: "White noise clocked by tone 2: high for 0.15 s, then rising from 460 Hz to 1.2 kHz while it fades, 1.8 s.",
    12: "A three-note stab of 218, 530 and 1,203 Hz fading in 0.13 s.",
}

TITLES = {
    2: "Spell cast", 3: "Spell damage lands", 4: "An effect takes hold", 5: "A combatant dies",
    6: "A missile flies", 7: "A blow lands", 8: "Lightning Bolt", 9: "An attack misses", 10: "A step",
    11: "Fireball", 12: "The missile strikes",
}
ORDER = [10, 7, 9, 6, 12, 2, 3, 4, 8, 11, 5]     # by how often a player hears them


def chip_state(log):
    """(seconds, vol[4]) after each write: to find where a log sounds."""
    vol, latch, out = [15] * 4, 0, []
    for t, b in log:
        if b & 0x80:
            latch = (b >> 4) & 7
            if latch & 1:
                vol[latch >> 1] = b & 15
        out.append((t, list(vol)))
    return out


def sounding_end(log):
    end = 0.0
    for t, vol in chip_state(log):
        if any(v < 15 for v in vol):
            end = t
    return end


def render(kind, log, seconds, path, gain=None):
    text = "".join("%.7f %d %d\n" % ((e[0], e[1], e[2]) if len(e) > 2 else (e[0], e[1], 0)) for e in log)
    args = [str(SNRENDER), kind, "%.4f" % seconds, str(path)] + ([str(gain)] if gain else [])
    subprocess.run(args, input=text.encode(), check=True)


def noise_fixed(log):
    """The log as the driver would write it if it wrote the noise register only when its value changes: every write
    of that register resets the chip's shift register, and the driver writes it every tick."""
    out, latch, last = [], 0, None
    for t, b in log:
        if b & 0x80:
            latch = (b >> 4) & 7
            if latch == 6:
                if (b & 7) == last:
                    continue
                last = b & 7
        out.append((t, b))
    return out


def cut_at(log, t1):
    """The log as the game plays it while the driver is idle: silenced after WaitHundredths(10)."""
    return [e for e in log if e[0] < t1] + silence_at(t1)


def silence_at(t):
    return [(t, 0x9F), (t, 0xBF), (t, 0xDF), (t, 0xFF)]


def mp3(wav: Path) -> str:
    out = wav.with_suffix(".mp3")
    subprocess.run(["lame", "--quiet", "-V", "2", "-m", "m", str(wav), str(out)], check=True)
    return "data:audio/mpeg;base64," + base64.b64encode(out.read_bytes()).decode()


def levels(wav: Path):
    """Peak and RMS of the clip (dBFS), and the RMS of its loudest 100 ms."""
    with wave.open(str(wav)) as w:
        a = array("h", w.readframes(w.getnframes()))
    if not a:
        return {"peak": -99.0, "rms": -99.0}
    peak = max(abs(x) for x in a) / 32768
    n = 4410
    best = 0.0
    for i in range(0, max(1, len(a) - n), n // 2):
        seg = a[i:i + n]
        r = math.sqrt(sum(x * x for x in seg) / max(1, len(seg))) / 32768
        best = max(best, r)
    db = lambda v: round(20 * math.log10(v), 1) if v > 0 else -99.0
    return {"peak": db(peak), "loud": db(best)}


def goertzel(wav: Path, hz: float, t0: float, t1: float) -> float:
    with wave.open(str(wav)) as w:
        a = array("h", w.readframes(w.getnframes()))
    seg = a[int(t0 * 44100):int(t1 * 44100)]
    k = 2 * math.cos(2 * math.pi * hz / 44100)
    s1 = s2 = 0.0
    for x in seg:
        s1, s2 = x + k * s1 - s2, s1
    return math.sqrt(max(0.0, s1 * s1 + s2 * s2 - k * s1 * s2)) / max(1, len(seg))


def main() -> int:
    cap = json.loads((OUT / "capture.json").read_text())
    clips = OUT / "clips"
    clips.mkdir(parents=True, exist_ok=True)
    sounds = []
    for sound in ORDER:
        tune = str(sound - 1)
        rec = cap["tunes"][tune]
        d = designs.DESIGNS[sound]
        cdir = clips / ("sound%02d" % sound)
        cdir.mkdir(exist_ok=True)
        cur = [tuple(e) for e in rec["tandy"]]
        spk = [tuple(e) for e in rec["speaker"]]
        idle = sound in IDLE_SOUNDS
        full_end = sounding_end(cur)
        if idle:
            cur = cut_at(cur, IDLE_CUT)
            spk = [e for e in spk if e[0] < IDLE_CUT] + [(IDLE_CUT, 0, 0)]
        cur_end = sounding_end(cur)
        fix = noise_fixed(cur)
        render("T", cur, cur_end + 0.15, cdir / "tandy-now.wav")
        render("T", fix, cur_end + 0.15, cdir / "tandy-fixed.wav")
        spk_end = max([t for t, dv, on in spk if on] + [0.0])
        render("S", spk, spk_end + 0.15, cdir / "speaker.wav", 3000)
        dw = d.script().writes()
        dlen = max(t for t, b in dw)
        render("T", dw, dlen + 0.15, cdir / "designed.wav")
        entry = {
            "sound": sound, "tune": sound - 1, "name": d.name, "title": TITLES[sound], "use": d.use,
            "budget": d.budget, "what": d.what, "current": CURRENT[sound], "idle": idle,
            "full_length": round(full_end, 2),
            "now": {"src": mp3(cdir / "tandy-now.wav"), "length": round(cur_end, 2),
                    "writes": sum(1 for t, b in cur if t <= cur_end), **levels(cdir / "tandy-now.wav")},
            "fixed": {"src": mp3(cdir / "tandy-fixed.wav"), "length": round(cur_end, 2),
                      "writes": sum(1 for t, b in fix if t <= cur_end), **levels(cdir / "tandy-fixed.wav")},
            "designed": {"src": mp3(cdir / "designed.wav"), "length": round(dlen, 2), "writes": len(dw),
                         **levels(cdir / "designed.wav")},
            "speaker": {"src": mp3(cdir / "speaker.wav"), "length": round(spk_end, 2)},
            "noise": any((b & 0xF0) == 0xF0 and (b & 15) < 15 for t, b in cur),
        }
        sounds.append(entry)
        print("sound %2d %-22s now %.2f s %5.1f dB | fixed %5.1f dB | designed %.2f s %4d writes %5.1f dB" % (
            sound, TITLES[sound], cur_end, entry["now"]["loud"], entry["fixed"]["loud"], dlen, len(dw),
            entry["designed"]["loud"]))
    # the tunes nothing plays
    unused = []
    for tune in range(12, 21):
        rec = cap["tunes"][str(tune)]
        cur = [tuple(e) for e in rec["tandy"]]
        end = sounding_end(cur)
        if end <= 0:
            unused.append({"tune": tune, "length": 0, "src": None})
            continue
        cdir = clips / ("tune%02d" % tune)
        cdir.mkdir(exist_ok=True)
        render("T", cur, min(end, 3.0) + 0.15, cdir / "tandy-now.wav")
        unused.append({"tune": tune, "length": round(end, 2), "src": mp3(cdir / "tandy-now.wav")})
    # the buzz: the original writes the noise register every tick, which resets the shift register
    buzz = {}
    for sound in (3, 9, 10):
        w = clips / ("sound%02d" % sound) / "tandy-now.wav"
        on = goertzel(w, TICK, 0.0, 0.07)
        off = sum(goertzel(w, TICK * f, 0.0, 0.07) for f in (0.83, 1.17)) / 2
        buzz[sound] = round(20 * math.log10(max(on, 1e-9) / max(off, 1e-9)), 1)
    print("237 Hz line over its neighbours (dB):", buzz)
    data = {"sounds": sounds, "unused": unused, "buzz": buzz,
            "design_bytes": sum(s["designed"]["writes"] for s in sounds)}
    (OUT / "page.json").write_text(json.dumps(data))
    template = (HERE / "page.html").read_text()
    (OUT / "index.html").write_text(template.replace("/*DATA*/null", json.dumps(data)))
    print("wrote %s (%d KB)" % (OUT / "index.html", (OUT / "index.html").stat().st_size // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())

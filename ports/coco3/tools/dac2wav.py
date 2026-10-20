#!/usr/bin/env python3
"""dac2wav.py: render a DAC capture as a WAV (step 8.8).

  dac2wav.py IN.dac OUT.wav [--rate 44100] [--units] [--squeeze]

IN.dac has one line per change of the CoCo's 6 bit DAC register: `time value`, the time in emulated seconds (MAME, lua/mailbox.lua and
watch.lua with MB_DAC=1) or, with --units, in 279.365 ns GIME fast clock units (probes/snd_ref.c --dac). The value is the byte written to
$FF20 (the DAC in bits 7 to 2); the middle of the range, $80, is silence. The output is 16 bit mono: each sample is the average of the
DAC over the sample's time (a box filter, so a square wave of high frequency does not alias into noise as hard as point sampling would).
Silence before the first line and after the last is not written; --squeeze shortens every gap over half a second to 0.3 s (a session's waits)."""
import struct
import sys
import wave


def load(path, units):
    ev = []
    for line in open(path):
        t, v = line.split()
        ev.append((float(t) * (279.365e-9 if units else 1.0), int(v)))
    return ev


def squeeze(ev, longest=0.5, keep=0.3):
    """A game session is minutes of waiting round a few seconds of sound: a gap longer than `longest` seconds is shortened to `keep`."""
    out, shift, prev = [], 0.0, None
    for t, v in ev:
        if prev is not None and t - prev > longest:
            shift += (t - prev) - keep
        out.append((t - shift, v))
        prev = t
    return out


def render(ev, rate):
    if not ev:
        return []
    t0 = ev[0][0]
    n = int((ev[-1][0] - t0) * rate) + 2
    out = []
    j = 0
    level = ev[0][1]
    for i in range(n):
        a, b = t0 + i / rate, t0 + (i + 1) / rate
        acc, t = 0.0, a
        while j < len(ev) and ev[j][0] <= b:
            acc += level * (max(ev[j][0], a) - t) if ev[j][0] > a else 0.0
            t = max(ev[j][0], a)
            level = ev[j][1]
            j += 1
        acc += level * (b - t)
        out.append(acc / (b - a))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    rate = 44100
    if "--rate" in sys.argv:
        rate = int(sys.argv[sys.argv.index("--rate") + 1])
        args = [a for a in args if a != str(rate)]
    ev = load(args[0], "--units" in sys.argv)
    if "--squeeze" in sys.argv:
        ev = squeeze(ev)
    smp = render(ev, rate)
    w = wave.open(args[1], "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, int((s - 128) * 200)))) for s in smp))
    w.close()
    print("%s: %d samples, %.2f s" % (args[1], len(smp), len(smp) / rate))


if __name__ == "__main__":
    main()

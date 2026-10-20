#!/usr/bin/env python3
"""snd_compare.py: the DAC the emulated CoCo wrote while t_snd played its twenty tunes, against the host model's (step 8.8).

  snd_compare.py build/run/t_snd-mame        (reads .dac and .cp; build/snd/ideal.ticks from `make snd-check`)

The capture's clock and the script's differ by a constant (the script's start); it is found by the best fit of the tunes' toggle counts.
Prints, per tune, the toggles in the host model and on the CoCo, and the share of the length of the tune's window both agree on."""
import sys

pre = sys.argv[1]
cp = {c[0]: float(c[1]) for c in (l.split() for l in open(pre + ".cp"))}
ev = [tuple(map(float, l.split())) for l in open(pre + ".dac")]
host = [tuple(map(int, l.split()[0:2])) for l in open("build/snd/ideal.ticks")]
ht = [sum(n for d, n in host[i * 261:(i + 1) * 261]) for i in range(20)]
WIN = 66 / 59.92
tog = [t for t, v in ev if v in (0x40, 0xC0)]


def starts(off):
    """The first tone write of each tune. The harness' checkpoint stamps are late by a variable few tens of ms, the DAC's stamps are exact."""
    out, lo = [], cp["11"] + off - 0.05
    for i in range(20):
        nxt = [t for t, v in ev if t >= lo and v == 0x40]
        s = nxt[0] if nxt else lo + 1.1
        out.append(s)
        lo = s + 1.03
    return out


off = {}
first128 = [t for t, v in ev if v == 128][0]
off = first128 - cp["1"]                                  # the DAC is set to rest by snd_begin just before checkpoint 1
st = starts(off)
mt = []
for i in range(20):
    a = st[i] - 0.00475                                    # (the host model's first tone write is 4.75 ms into the tune)
    b = a + WIN
    mt.append(sum(1 for t in tog if a <= t < b))
print("offset %.3f s" % off)
for i in range(20):
    print("tune %2d  host %5d  coco %5d  %+6.1f %%" % (i + 1, ht[i], mt[i], 100.0 * (mt[i] - ht[i]) / ht[i] if ht[i] else 0))
print("all     host %5d  coco %5d  %+6.1f %%" % (sum(ht), sum(mt), 100.0 * (sum(mt) - sum(ht)) / sum(ht)))

#!/usr/bin/env python3
"""designs.py: Pool of Radiance's game sounds made for the Tandy 1000's chip from what each is for (README.md).

The game plays 11 sounds (PlaySound 2 to 12, the driver's tunes 1 to 11; tunes 12 to 20 have no caller). Each
design here is a script of the chip's own registers, one state a tick, written from the sound's use in the game
(cited from src/ in `use`) and from how long the game lets it sound (`budget`): a sound played while the driver is
idle (SoundDriverIdle nonzero, the default) is silenced after WaitHundredths(10), about a tenth of a second, so the
step, the hit and the miss are made to say everything in 0.1 s; a sound played inside SetSoundDriverIdle(0) and
SetSoundDriverIdle(10) lasts as long as its animation, so it starts with its character and holds a tail that can
be cut anywhere.

The tick is 118.3 Hz, every second call of the driver's timer (236.7 Hz, whitepaper 5.14). The techniques are the
chip's usual ones, the same as the Eye of the Beholder study's (eob-decomp ports/dos/sound/designs.py), from which
the Script class and the envelopes are taken:
- a volume envelope in software, 2 dB a step;
- a pitch sweep on a tone, and white noise clocked by tone 2 swept with it (whooshes, roars);
- one tick of white noise for an attack (a click);
- periodic noise clocked by tone 2 for a pitch under the chip's 109 Hz floor (a thud, a growl);
- vibrato after the attack, a detuned or delayed second tone (an echo), a fast arpeggio for a chord;
- the noise register written only when it changes: every write resets the chip's shift register, which is why
  the original driver's noise (written every tick) comes out as a 237 Hz buzz.
"""
from __future__ import annotations

import math

TICK = 1193182 / 5041 / 2            # every second tick of the driver's timer: 118.3 Hz
SN_TONE = 3579545 / 32
FLOOR = SN_TONE / 1023


def period(f: float) -> int:
    return max(1, min(1023, round(SN_TONE / f)))


def att(db: float) -> int:
    """The chip's volume for an attenuation in dB (2 dB a step, 15 off)."""
    return max(0, min(15, round(db / 2)))


class Script:
    """A sound as one state of the chip a tick: three tone periods, four volumes, the noise control."""

    def __init__(self, seconds: float):
        self.n = int(seconds * TICK) + 1
        self.p = [[None] * 3 for _ in range(self.n)]
        self.v = [[15] * 4 for _ in range(self.n)]
        self.nz = [None] * self.n

    def ticks(self, t0: float, t1: float):
        return range(max(0, int(round(t0 * TICK))), min(self.n, int(round(t1 * TICK))))

    def tone(self, ch, t0, t1, hz, db, vib=0.0, vib_hz=6.0, vib_after=0.08):
        """Tone channel ch from t0 to t1 seconds; hz(x) and db(x) of x, the time into the note (seconds)."""
        for i in self.ticks(t0, t1):
            x = max(0.0, i / TICK - t0)
            f = hz(x)
            if vib and x > vib_after:
                depth = vib * min(1.0, (x - vib_after) / max(vib_after, 0.02))
                f *= 2 ** (depth / 1200 * math.sin(2 * math.pi * vib_hz * (x - vib_after)))
            self.p[i][ch] = period(f)
            self.v[i][ch] = att(db(x))

    def noise(self, t0, t1, db, white=True, rate=None, clock_hz=None):
        """The noise channel from t0 to t1: white or periodic, at a fixed rate (0 fast to 2 slow) or clocked by tone 2
        at clock_hz(x) (then tone 2 is silent: it only drives the noise)."""
        for i in self.ticks(t0, t1):
            x = max(0.0, i / TICK - t0)
            if clock_hz is not None:
                self.nz[i] = (4 if white else 0) | 3
                self.p[i][2] = period(clock_hz(x))
                self.v[i][2] = 15
            else:
                self.nz[i] = (4 if white else 0) | rate
            self.v[i][3] = att(db(x))

    def writes(self):
        """The chip writes, (seconds, byte): only what changed, the noise register only when it changes."""
        out = []
        sp, sv, sn = [None] * 3, [15] * 4, None
        for i in range(self.n):
            t = i / TICK
            for ch in range(3):
                p = self.p[i][ch]
                if p is not None and p != sp[ch]:
                    out += [(t, 0x80 | ch << 5 | (p & 15)), (t, (p >> 4) & 0x3F)]
                    sp[ch] = p
            if self.nz[i] is not None and self.nz[i] != sn:
                out.append((t, 0xE0 | self.nz[i]))
                sn = self.nz[i]
            for ch in range(4):
                if self.v[i][ch] != sv[ch]:
                    out.append((t, 0x90 | ch << 5 | self.v[i][ch]))
                    sv[ch] = self.v[i][ch]
        for ch in range(4):
            if sv[ch] != 15:
                out.append((self.n / TICK, 0x90 | ch << 5 | 15))
        return out


# envelopes, in dB of attenuation over x seconds into the note
def decay(start, per_s, attack=0.0):
    """Up from silence in `attack` seconds, then down `per_s` dB a second."""
    def f(x):
        if attack and x < attack:
            return start + 30 * (1 - x / attack)
        return start + per_s * (x - attack)
    return f


def hold_fade(start, hold, per_s, attack=0.0):
    def f(x):
        if attack and x < attack:
            return start + 30 * (1 - x / attack)
        return start if x < hold else start + per_s * (x - hold)
    return f


def sweep(f0, f1, secs, curve=1.0):
    """f0 to f1 over secs, exponential in pitch (curve > 1: fast first), then held."""
    def f(x):
        u = min(1.0, x / secs) ** (1 / curve)
        return f0 * (f1 / f0) ** u
    return f


def const(f0):
    return lambda x: f0


def seq(*steps):
    """Pitch steps: (seconds, hz) pairs, each held until the next."""
    def f(x):
        hz = steps[0][1]
        for t, h in steps:
            if x >= t:
                hz = h
        return hz
    return f


class Rand:
    """A small LCG, so a design is the same every run (and an 8086 version can do the same)."""

    def __init__(self, seed):
        self.s = seed

    def __call__(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s / 0x7FFFFFFF


def click(s, t0, db=0, rate=0, dur=1 / TICK):
    """One tick of white noise: a click, a tap (rate 0 bright, 2 dull)."""
    s.noise(t0, t0 + dur, const(db), white=True, rate=rate)


class Design:
    def __init__(self, fn, sound, name, what, use, budget, length):
        self.fn, self.sound, self.name, self.what, self.use = fn, sound, name, what, use
        self.budget, self.length = budget, length

    def script(self) -> Script:
        s = Script(self.length)
        self.fn(s)
        return s


DESIGNS: dict[int, Design] = {}


def design(sound, name, length, what, use, budget):
    """Register the design of PlaySound(sound) (the driver's tune sound - 1)."""
    def reg(fn):
        assert sound not in DESIGNS
        DESIGNS[sound] = Design(fn, sound, name, what, use, budget, length)
        return fn
    return reg


IDLE = "about 0.1 s: played while the driver is idle, then silenced (WaitHundredths(10), src/RES03.PAS:83)"


@design(10, "SoundStep", 0.1,
        what="a soft footfall: a dull tap, a low thump under it, gone in 80 ms",
        use="every step and quarter turn of the party in the 3D view and the wilderness (src/OVL14.PAS:278, 400, "
            "407; src/OVL03.PAS:2377), every step of a combatant (src/OVL13.PAS:393), script sound 8 "
            "(src/OVL03.PAS:2055). The most frequent sound of the game: it must not tire the ear",
        budget=IDLE)
def step(s):
    click(s, 0.0, db=6, rate=2)
    s.noise(1 / TICK, 0.075, decay(8, 160), white=False, clock_hz=lambda x: 15 * sweep(70, 45, 0.05)(x))
    s.tone(0, 0.0, 0.06, sweep(150, 112, 0.03), decay(12, 180))


@design(7, "SoundNoAction (a blow lands)", 0.1,
        what="a blow landing: a sharp crack, a punch of low noise and a falling thump",
        use="every attack roll that hits, and the auto-hit on a helpless target (src/OVL13.PAS:826, 880); "
            "also a move the 3D view refuses, a bump into a wall (src/OVL14.PAS:557). The registry's name "
            "SoundNoAction undersells it: this is the game's hit sound",
        budget=IDLE)
def blow(s):
    click(s, 0.0, db=0, rate=0)
    s.noise(1 / TICK, 0.09, decay(2, 170), white=True, clock_hz=sweep(2200, 500, 0.07))
    s.tone(0, 0.0, 0.08, sweep(240, 110, 0.05, 2), decay(2, 150))
    s.tone(1, 0.0, 0.05, sweep(480, 220, 0.04, 2), decay(10, 200))


@design(9, "SoundAttackMissed", 0.1,
        what="a whiff: a quick airy swish that rises and falls away, no impact",
        use="an attack whose rolls all missed (src/OVL13.PAS:892)",
        budget=IDLE)
def whiff(s):
    up = 0.035
    s.noise(0.0, 0.095, lambda x: 4 + (14 * (1 - x / up) if x < up else 140 * (x - up)),
            white=True, clock_hz=lambda x: sweep(900, 4200, up)(x) if x < up else sweep(4200, 1500, 0.06)(x - up))


@design(6, "SoundAttackLeaves", 1.4,
        what="a missile let fly: a bowstring's twang, then a thin whistle of air that carries the flight",
        use="a missile or thrown weapon leaves the attacker (ShowAttackAnimation, src/OVL13.PAS:1493): it sounds "
            "while the missile crosses the map (WalkCombatLine) and is replaced by SoundAttackArrives",
        budget="the missile's flight: SetSoundDriverIdle(0) to the next sound (src/OVL13.PAS:1492)")
def leaves(s):
    s.tone(0, 0.0, 0.16, sweep(330, 196, 0.12, 2), decay(0, 90), vib=60, vib_hz=28, vib_after=0.01)
    s.tone(1, 0.0, 0.12, sweep(660, 392, 0.1, 2), decay(8, 120))
    s.noise(0.0, 0.02, const(4), white=True, rate=0)
    s.noise(0.06, 1.4, hold_fade(12, 0.4, 16, attack=0.12), white=True,
            clock_hz=lambda x: 2600 * 2 ** (0.15 * math.sin(2 * math.pi * 3 * x)))


@design(12, "SoundAttackArrives", 0.12,
        what="the missile strikes: a short wooden thock",
        use="the missile reaches its target (src/OVL13.PAS:1496); the hit or miss sound follows. In the original "
            "it is silenced at once: SetSoundDriverIdle(10) right after it stops the timer and quiets the chip, "
            "so at most one tick of it is ever heard",
        budget="none in the original (stopped by the next line); 0.1 s if the port lets it finish")
def arrives(s):
    click(s, 0.0, db=2, rate=1)
    s.tone(0, 0.0, 0.09, sweep(700, 420, 0.03, 2), decay(2, 220))
    s.tone(1, 0.0, 0.06, const(1180), decay(10, 260))


@design(2, "SoundSpellDefault", 1.2,
        what="a spell cast: a quick rising run of three notes that sparkles and rings on with vibrato",
        use="every spell cast in combat but Fireball and Lightning Bolt, while its line crosses to the aim point "
            "(CastChosenSpell, src/OVL22.PAS:572), and again for every further target of a many-target spell "
            "(src/OVL22.PAS:934)",
        budget="the cast's line animation: SetSoundDriverIdle(0) to (10) (src/OVL22.PAS:567, 575)")
def spell(s):
    notes = (659, 988, 1319)
    s.tone(0, 0.0, 1.2, seq((0, notes[0]), (0.06, notes[1]), (0.12, notes[2])), hold_fade(0, 0.3, 22, attack=0.01),
           vib=25, vib_hz=6, vib_after=0.25)
    s.tone(1, 0.09, 1.2, seq((0, notes[0]), (0.06, notes[1]), (0.12, notes[2])), hold_fade(10, 0.3, 22, attack=0.01),
           vib=25, vib_hz=7, vib_after=0.2)
    s.noise(0.0, 0.8, decay(16, 22, attack=0.08), white=True, clock_hz=lambda x: sweep(2500, 5000, 0.4)(x))


@design(3, "SoundDamageMessage (spell damage)", 0.4,
        what="magic that hurts: a bright crack and a falling zap with a burst of noise",
        use="a target takes damage from a spell, 'takes N points of damage from Fire / Cold / Electricity / "
            "Acid / Magic' (ShowHitMessage with a damage message, src/OVL24.PAS:669; src/RES12.PAS:1317), "
            "while the hit icon flashes",
        budget="the flash: four frames of FlashDelay (src/RES12.PAS:1306 to 1333)")
def spell_damage(s):
    click(s, 0.0, db=0, rate=0)
    s.tone(0, 0.0, 0.3, sweep(1600, 180, 0.25, 1.6), decay(0, 50))
    s.tone(1, 0.0, 0.3, lambda x: sweep(1600, 180, 0.25, 1.6)(x) * 1.03, decay(8, 50))
    s.noise(1 / TICK, 0.35, decay(2, 55), white=True, clock_hz=sweep(3000, 400, 0.3))


@design(4, "SoundAffectMessage (an effect takes hold)", 1.2,
        what="magic settling on someone: three soft struck notes, a suspended chord that rings and fades",
        use="an effect takes hold of a combatant: 'is Healed', 'is Paralyzed', 'is turned', 'is affected', "
            "'can see', 'is un-cursed' (ShowHitMessage with an affect message, src/RES12.PAS:1315; src/OVL22.PAS, "
            "src/OVL12.PAS:1252, src/OVL13.PAS:728, src/OVL24.PAS:728). Good and bad alike, so neutral",
        budget="the flash, repeated GameSpeed times (src/RES12.PAS:1319 to 1333)")
def affect(s):
    for ch, (t0, hz, db) in enumerate(((0.0, 587, 0), (0.1, 784, 4), (0.2, 880, 6))):
        s.tone(ch, t0, 1.2, const(hz), decay(db, 16, attack=0.01), vib=12, vib_hz=5 + ch, vib_after=0.2)


@design(5, "SoundCombatantDies", 1.3,
        what="a death: a falling groan over a low growl, and the body's thud as it drops",
        use="a combatant dies in combat (RemoveCombatant, src/OVL31.PAS:500), or a party member outside it "
            "(src/OVL31.PAS:470), while the dying picture shows",
        budget="DelayByGameSpeed, GameSpeed x 225 ms (src/OVL31.PAS:471, 501)")
def death(s):
    s.tone(0, 0.0, 0.75, lambda x: sweep(220, 116, 0.7)(x), hold_fade(2, 0.15, 24, attack=0.06), vib=40, vib_hz=5,
           vib_after=0.12)
    s.tone(1, 0.02, 0.75, lambda x: sweep(220, 116, 0.7)(x) * 1.06, hold_fade(10, 0.15, 24, attack=0.08))
    s.noise(0.0, 0.7, hold_fade(6, 0.2, 16, attack=0.08), white=False, clock_hz=lambda x: 15 * sweep(70, 38, 0.7)(x))
    # the fall: a dull click and a short thump
    s.noise(0.72, 0.74, const(0), white=True, rate=2)
    s.noise(0.74, 1.3, decay(2, 55), white=False, clock_hz=lambda x: 15 * sweep(55, 30, 0.3, 2)(x))
    s.tone(0, 0.72, 1.0, sweep(160, 110, 0.06, 2), decay(4, 90))


@design(8, "SoundLightningBolt", 1.6,
        what="a lightning bolt: a crackling arc that spits and buzzes, a high zap jumping about, thunder under it",
        use="the spell Lightning Bolt, while the bolt crosses to the aim point (CastChosenSpell, "
            "src/OVL22.PAS:570)",
        budget="the bolt's line animation (src/OVL22.PAS:567, 575)")
def lightning(s):
    r = Rand(8)
    jumps = [r() for _ in range(400)]
    crack = [r() for _ in range(400)]
    tick = lambda x: int(x * TICK)
    s.tone(0, 0.0, 1.6, lambda x: 900 * 2 ** (2.2 * jumps[tick(x) // 2]),
           lambda x: decay(0, 9)(x) + (10 if crack[tick(x)] < 0.25 else 0))
    s.tone(1, 0.0, 1.6, lambda x: 125 + 40 * jumps[tick(x) // 3 + 100], lambda x: decay(10, 6)(x) + 6 * crack[tick(x) + 50])
    s.noise(0.0, 1.6, lambda x: decay(0, 9)(x) + (14 if crack[tick(x) + 200] < 0.35 else 0), white=True,
            clock_hz=lambda x: 5000 if crack[tick(x) + 100] < 0.5 else 2200)


@design(11, "SoundFireball", 1.8,
        what="a fireball: a sharp ignition, then a roaring rush of flame that swells as it flies",
        use="the spell Fireball, while the ball crosses to the aim point (CastChosenSpell, src/OVL22.PAS:569), "
            "and script sound 10 (src/OVL03.PAS:2056)",
        budget="the ball's line animation; 0.1 s as a script sound (the driver idle)")
def fireball(s):
    r = Rand(11)
    flick = [r() for _ in range(800)]
    tick = lambda x: int(x * TICK)
    click(s, 0.0, db=0, rate=0)
    s.noise(1 / TICK, 0.25, decay(0, 20), white=True, clock_hz=sweep(600, 3800, 0.2, 2))
    s.noise(0.25, 1.8, lambda x: 4 - 4 * min(1.0, x / 1.0) + 5 * flick[tick(x)], white=True,
            clock_hz=lambda x: 1400 + 900 * flick[tick(x) + 100])
    s.tone(0, 0.0, 1.8, lambda x: 112 + 14 * flick[tick(x) // 2 + 200], lambda x: decay(8, -4)(x) + 4 * flick[tick(x) + 300])
    s.tone(1, 0.15, 1.8, sweep(230, 300, 1.5), lambda x: 14 + 4 * flick[tick(x) + 50])


if __name__ == "__main__":
    for k, d in sorted(DESIGNS.items()):
        w = d.script().writes()
        print("%2d %-40s %5.2f s %5d bytes" % (k, d.name, d.length, len(w)))

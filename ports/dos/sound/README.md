# ports/dos/sound: the Tandy sound study

Pool of Radiance's sounds on the Tandy 1000's SN76489: what the game's own driver (`src/RES03.ASM`) plays, the same
tunes with one driver fault fixed, and new sounds designed for the chip from what each is for. The method follows the
Eye of the Beholder study (eob-decomp `ports/dos/sound/`), whose listening passes kept the designed sounds for 110 of
117 clips. The first listening pass (`picks.json`) is in the DOS build: `port.py` turns it into the port's
`patches/tandy-sound.patch` and `patches/tandy-strike.patch` (below).

```bash
.venv/bin/python ports/dos/sound/capture.py      # the original's 20 tunes, Tandy and speaker (oracle, 3 s)
cc -O2 -o ports/dos/build/sound/snrender ports/dos/sound/snrender.c -lm
python3 ports/dos/sound/build.py                 # render, encode (lame), write ports/dos/build/sound/index.html
python3 ports/dos/sound/port.py                  # the port's patches from picks.json; then make -C ports/dos game
.venv/bin/python ports/dos/sound/capture.py --build ports/dos/build/link --out port.json
python3 ports/dos/sound/check.py                 # every tune of the port's build against what the page played
```

| File | What |
|---|---|
| `capture.py` | Boots the original in the oracle (as `tools/oracle/soundprobe.py` does) and plays each tune 1..20 for 4 s on each device, keeping every port C0h write and the speaker events with their virtual times. |
| `snrender.c` | The chip (the EOB study's model: 3.579545 MHz, 15-bit noise register with taps on bits 0 and 4, reset by every write of the noise register, 2 dB a step, 12 kHz and 20 Hz filters) and the PC speaker, to WAV. Every Tandy clip at one scale. |
| `designs.py` | The 11 designs, register scripts at 118.3 Hz (every second tick of the driver's 236.7 Hz timer), each with its use cited from `src/` and the time the game gives it. |
| `build.py` | Renders the original (cut at 0.1 s where the game cuts it), the original with the noise fix, the design and the speaker original; writes the page. |
| `page.html` | The page template: three lanes per sound with spectrograms, a pick and a note per sound, the picks as JSON. |
| `picks.json` | The listening pass the page exported: per sound `designed`, `fixed` or `now`. |
| `port.py` | Writes the port's two patches from the picks: the driver's noise fix and script player with the designed scripts, and the strike's wait. |
| `check.py` | The port's capture against the expectation: a designed tune writes its script byte for byte, a frame every second tick, then quiet; every other tune writes the original's bytes with the noise fix, tick for tick. |

## What the capture showed

- The game plays 11 sounds: `PlaySound` 2 to 12, tunes 1 to 11 (`re/dseg.toml` `Sound*`). Tunes 12 to 20 have no
  caller; tune 20 is silent on the Tandy chip.
- `TandyStep` writes all four channels every tick (11 bytes, 236.7 times a second), the noise control included. In
  the chip model MAME and DOSBox use, each write of the noise register resets the shift register, so fast noise
  becomes a 237 Hz buzz (`build.py` measures the line: 15 dB over its neighbours in sound 3, 21 dB in sound 9) and
  slow noise never leaves its reset state: the step and the hit are clicks, Fireball is near silence (loudest 100 ms
  at -27.8 dBFS, -15.5 with the fix). Not yet confirmed on an EX.
- While the driver is idle (the default) `PlaySound` silences a sound after `WaitHundredths(10)`: the step (10), the
  hit (7) and the miss (9) get about 0.1 s, and the game waits for them.
- `SoundAttackArrives` (12) is stopped by the next line, `SetSoundDriverIdle(10)` (`src/OVL13.PAS:1496`), so at most
  one tick of it sounds.
- `SoundNoAction` (7) is the hit sound: `ResolveCombatantAttacks` plays it for every attack roll that hits
  (`src/OVL13.PAS:880`), besides the helpless target and the refused move in the 3D view.

## In the port (pass por-tandy-1)

Designed: the spell cast (2), an effect (4), a death (5), the missile's flight (6) and strike (12), a blow (7),
Lightning Bolt (8), the step (10). The original with the noise fix: spell damage (3), the miss (9), Fireball (11).

1. The noise fix in `TandyStep`: the noise control is written when its low three bits change (`LastNoise`,
   forgotten by `SetTandyTune`). It covers every tune that is not designed, the unused ones too.
2. The script player: `SetTandyTune` takes the tune's script from `DesignTunes` (0: the voices as before);
   `ScriptStep` plays a frame every second tick (n bytes for port C0h, or a run of empty frames, or the end, after
   which the chip is quiet). 2,925 bytes of scripts; the driver grows from 5,721 to 8,825 bytes, resident.
3. The strike: `SetSoundDriverIdle(10)` right after `PlaySound(SoundAttackArrives)` silenced it at once; a Tandy
   game now waits `WaitHundredths(10)` (the script's length) in between. It is the one change of timing.

`check.py` passes on every tune (oracle). Not heard on a real EX yet.

## Toward the port (the options this study weighed)

1. The noise fix: `TandyStep` keeps the last noise byte and skips an unchanged write. Small, resident, every tune
   kept.
2. The designs: a register-script player like EOB's `SNPLAY.ASM`, called on every second timer tick, and the
   scripts (3,682 bytes of chip writes before packing). Most designs are sweeps, envelopes and vibrato, which the
   driver's own stream language has, so compiling them to its streams is the smaller alternative.
3. Optional, a timing change: run the timer for good so short sounds finish (the strike would be heard, and the
   0.1 s wait at every step would go). The designs fit 0.1 s either way.


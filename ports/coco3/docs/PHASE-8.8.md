# Step 8.8: sound, the PC speaker's effects on the CoCo's DAC (report)

Date: 2026-10-19. Scope, by the human's decision of the day: **the PC speaker driver only, on the CoCo 3's 6 bit DAC.** No Tandy/GMC backend (the plan's "GMC backend" is dropped
for this step, nothing in the design prevents it later). Tags: **[V]** verified by running something, **[E]** estimate, **[?]** open.

## 0. Result

* **The game plays its sound effects on the CoCo** [V]: the 20 tunes of the original's driver (steps, attacks, spells, deaths, messages) come out of the DAC. `make game-wav S=combat-spells` renders a session's sound as a WAV
  (24 effects in that session, 0.14 s to 0.8 s each, from the DAC writes MAME makes), `make snd-wav` renders the twenty tunes alone.
* **The driver is the proven one.** `src/snd/snd_driver.c` is *generated* (`tools/mksnd.py`) from the host's `c/driver/res03_driver.c` (a port of the original's RES03.ASM, proven against the oracle at step 7): the tune
  table, the streams and the voice stepper are that file's text; the script's edits are asserted and listed in the generated file's header (no Tandy, the speaker calls go to the backend, the interrupt body is `DriverTick`, the
  variables are a block). A unit test (`tests/unit/test_snd.py`) fails if the file is not what the script writes.
* **Same calls as the original** [V]: the driver's speaker calls over the first 237 ticks of each of the 20 tunes, as a checksum, are the host's on the 6809 in MAME and XRoar (`t_snd`, `check_driver`); and the host model
  (the driver, the backend and a model of the GIME timer, `probes/snd_ref.c`) makes the **7,045 speaker events of the golden `sound-driver`'s PC speaker half, event for event** (`make snd-check`).
* **The clock is exact** [V]: the driver's 236.7 Hz ticks come out as 237 per 60 frames (474 per 120) in MAME for silence, for the slowest tone, for the clamped fastest tone and for the real tunes (the 16 sessions play the
  tunes through the same pump). XRoar agrees.
* **16 of 16 sessions still match** [V] (`make baseline`, table in 3), with the sound on: `SoundMode`, `SoundModeBeforePause` and `SoundDriverIdle` are no longer different from the original's (three lines left `data/state_ignore.txt`).

## 1. How it works

The PC speaker is one square wave: the driver sets PIT channel 2's divisor D and the gate bits (a tone when both are set); every 236.7 Hz tick it asks again. The CoCo's DAC has no oscillator, the wave is made by the CPU:

| Piece | Where | What it does |
|---|---|---|
| the interrupt | `src/engine/snd.asm` (code at `$FE00` in the constant page) | the GIME timer's FIRQ, once per part of a half period: counts itself (`snd_n`), toggles the DAC (`ISR_A`: every interrupt; `ISR_B`: every `snd_k`-th, for half periods longer than the timer's 12 bits), loads a new reload if the main line left one, and notes how many interrupts there had been then (`snd_cn`). 59 and 70 bytes, about 71 cycles |
| the clock | `src/snd/snd_core.c` (the pump) | 15,123 timer units (279.365 ns) are one tick of the driver (3 * 5041). The pump counts the interrupts since it last looked, multiplies by the length of one, and runs `DriverTick` for every tick passed (at most 24 at a time: after a long computation the sound goes on from now) |
| the tone | `snd_core.c` | the half period is 1.5 D units; one interrupt is at most 4,097 of them (reload 4,095); a longer one takes k = 2, 4, 8, 16 or 32 interrupts. A rest is the same timer without the toggle. A new tone is **loaded by the interrupt at its next expiry**, never by restarting the timer (the timer cannot be read, a restart loses part of an interval) |
| the state | `SndState` (`snd.h`), 674 bytes | in the mapped heap, allocated by the first call into the driver (a bank has no variables); the interrupt's variables are 19 bytes in the engine's shared data (`$07C0`) |
| the hooks | `src/game/rtl_sys.c` | `frames32` (the clock the game waits on: `GetTime`, `Delay`) and `rtl_KeyPressed` check `snd_n >= snd_thresh` and call `snd_run` (a far call into the sound bank): the game waits by polling those two, so the driver runs wherever the game waits |
| the bank | `mkgame.py` | `snd_driver.c` and `snd_core.c` are one bank (6,786 bytes, 5 entries: the five routines RES03 calls, and `snd_run`); the translated `PlaySound`, `SilenceSound` and `SetSoundDriverIdle` (bank `res03`) are unchanged |

Hardware facts used or found [V]: the GIME timer counts `reload + 2` units, on the 279.365 ns clock when `TINS` ($FF91 bit 5) is set (every write of `$FF91`, in `engcall.asm`, `mmu.asm` and the sound code, carries the shadow
`_tins`); the DAC is `$FF20` bits 7 to 2, the mux select bits (`$FF01`, `$FF03` bit 3) 0 and sound enable (`$FF23` bit 3) 1; the wave is $40/$C0 around the middle $80 (16 of 64 steps either side).

## 2. What was found on the way

1. **`gfx_init` switches the GIME's FIRQ off** [V]: the engine's graphics reset `$FF90` to `$4C` (no IRQ/FIRQ bits) when the game sets its video mode, after `irq_start` set them. The frame interrupt does not need the bit (the PIA's
   IRQ reaches the CPU without it), the timer's FIRQ does. `snd_begin` asks for it again (`eng_init0 |= $10`). The first game build with the sound had every tune loaded and nothing ever played; the engine test passed because it calls `irq_start` last.
2. **Reading `$FFF6` returns the stub's address, not the handler's** [V] (`$FEF4`); `snd_end` first put that back as the vector and left the FIRQ a jump to itself. The engine's handler is exported now (`_firq_isr`) and put back by name.
3. **`eng_back` (the return of an engine call) must keep D** [V]: it is where the engine's result is; the first version loaded A with the timer's clock. The sessions stopped at the first engine call that returns a value.
4. **CMOC**: a byte shifted by 8 is zero (`DataWord`'s high byte, the vibrato's table byte: the generator widens them), a product of two bytes is a byte (`NoteEvent`), 32 bit arithmetic is slow (a 16 bit division costs 0.6 ms, a 32 bit multiplication 0.36 ms:
   the tone's arithmetic is 16 bit with shifts, the pump's division is a 6 step loop), `volatile` is ignored, `static` data in a bank is read only.
5. **Two requests in one pump spoil the accounting** [V]: the pump ran two ticks in one call when the CPU was busy, each asked the timer for a new reload, and the second overwrote the first before the pump knew which interrupts ended intervals of
   the old length: tune 13 ran 12 % fast. The driver now only *wants* a tone (`snd_want_tone`); the pump sets it once, after all its ticks and after settling the interrupts that came meanwhile (`snd_apply`). The host model has a `--busy` mode (the driver
   taking CPU time while interrupts arrive) that shows this and is part of `make snd-check`.
6. **The make rule for `t_snd` did not know the three C files it includes** [V]: edits did not rebuild it and two "results" were stale; the rule has them now.
7. **The shared image no longer fits under `$7C00` if the engine grows 12 bytes**: the sound's code (173 bytes of interrupt in the engine image, 14 of install, the TINS patches) took the engine from `$7AAA` to `$7BEA`; the layout of the blob is packed
   (no padding) and `snd.asm` stops the assembly if a routine is not where `snd_core.c` expects it. `$7E00` is not a way out: BASIC's stack is there while `LOADM` runs. 22 bytes are left; the next engine routine needs the image moved
   (down, with the engine's data) or something else out.

## 3. Verification

| Check | How | Result |
|---|---|---|
| the generated driver is the generator's output | `tests/unit/test_snd.py` | pass |
| the driver's speaker events are the oracle's | `make snd-check`: the first part of the golden `sound-driver` (PC speaker half), `probes/snd_ref.c ideal`, `tools/snd_check.py` | **7,045 of 7,045 events equal** |
| the DAC makes the pitch | the same, per 4.2 ms tick window: toggles = 15,123 / (1.5 D) within 2 (clamped half periods excepted) | 1,820 of 1,822 tone ticks, the 2 are tone changes |
| the clock | the same with the real pump, polled every 1,000 / 3,000 / 15,123 / 20,000 units, the driver busy 0 / 5,000 / 12,000 units a tick | 5,219 to 5,235 ticks for 5,220 to 5,256 expected |
| the driver on the 6809 | `make eng-test T=t_snd` (MAME and XRoar): the speaker calls of each tune, as a checksum, against the host's | 20 of 20 |
| the backend's arithmetic on the 6809 | the same: k and the interrupt length for 20 divisors at the edges of its cases | 20 of 20 |
| the interrupts | the same: interrupts in 60 frames of the rest clock (875 expected), of 1,193 Hz (2,389) and of 298 Hz (1,192, `ISR_B`); the DAC read back $C0/$40 | MAME 863 to 873, 2,367 to 2,372, 1,176 to 1,194 (MAME's timer runs about 1 % slow, as at 8.3d); XRoar 873, 2,378, 1,198 |
| the pump | the same: ticks in 120 frames of silence, with a held tone at the clamp, at the slowest and at 3,000, and with tune 8 | 472 to 478 of 474 |
| the sound of the game | `make snd-wav`: the DAC of the twenty tunes in MAME against the host model, toggles per tune (`tools/snd_compare.py`) | 15 of the 19 tunes with sound within 5 % of the model's toggles; tunes 13 and 18 +8 %, 16 and 17 +15 % and +34 % of counts of 20 and 59: the high pitched chirps at their ends last longer (below) |
| the sessions | `make baseline` | **16 of 16 as before, and 0 DGROUP places open in every session** (one was open before: `SoundModeBeforePause`, now the original's). The sessions that fight play 18 to 41 effects each (4,200 to 12,900 DAC toggles: `battle-aftermath`, `parley-combat`, `temple-heal` 18, `combat-spells` 24, `council-guards` 41); the others play none |

Costs on the 1.79 MHz machine [V, MAME]: a tick of the driver is 1.2 ms typical (0.36 ms when no voice sounds, 1.9 ms for tune 1, 6 ms for the first tick of a tune), applying a tone 0.4 ms, the pump's own work 0.3 ms. The interrupt takes
5 % of the CPU at 1 kHz, 28 % at the highest pitch the port makes (3.6 kHz). A sound effect therefore takes 40 to 70 % of the machine for its second; the game waits for the sound with `WaitHundredths` anyway.

## 4. What is not done or not as the original

* **No Tandy / GMC.** `SetTandyTune` only keeps the tune number, as the original's `PlaySound(0)` and `SoundQuiet` need; `SoundMode` 0 (T) plays nothing. The tune table's Tandy rows and the Tandy note table are not in the bank.
* **Pitches above 3.6 kHz are lowered to it** (half period at least 500 units): the interrupt cannot go faster and leave the main line the CPU. 9 of the 1,822 tone ticks of the 20 tunes are higher (the ends of the zaps of tunes 13 and 18). Tones above that are
  the PC speaker's shrill end; they sound as a plateau.
* **The high pitched chirps last longer than the host model's** (tunes 13, 16, 17, 18: +8 to +34 % toggles): the tone the driver asks for is set after the pump's call, which takes 2 to 5 ms with the interrupt at 28 % of the CPU. Faster `DriverTick` (8.9) shortens it.
* **The sound is as steady as the game polls.** The driver runs when the game polls the clock or the keyboard; a long computation (a screen being drawn, a combat scan of seconds) lets the tone go on and holds the tunes' progress (the pump then catches up to 100 ms, the rest is dropped).
  A disk read masks the interrupt for its length: the wave stops for it.
* **The amplitude is fixed** (±16 of 64 DAC steps, `DAC_LO` in `snd_core.c`); the game has no volume control, the TV or the amplifier does.
* **The sound bank loads at start** (`SilenceSound` in `init_RES08`, as RES08's initialisation does) and is used from the pump every 4 ms while a sound plays, so it stays in the pool; between sounds the pump does not call it (thresh 0) and it can be evicted
  like any bank: the next effect then waits for the disk (the bank loads in about as long as any other overlay's).
* Not heard on a real machine or through a real speaker: the WAV is rendered from the DAC writes.

## 5. How to run and listen

```
make snd-check             # the host model against the oracle's golden (clang, 2 s)
make eng-test T=t_snd      # the interrupt, the pump and the driver on the emulated CoCo, MAME and XRoar
make snd-wav               # build/snd/host-reference.wav and build/run/t_snd-mame.wav (the twenty tunes, one second each) and the comparison table
make game-wav S=combat-spells    # a session of the game with its sound: build/run/game-combat-spells.wav (waits shortened)
```
`MB_DAC=1` in front of any `make game-run` / `eng-test` writes `<out>.dac` (every DAC write with its emulated time); `tools/dac2wav.py` renders it, `--squeeze` shortens the waits. `MB_WTAP=07C1` records the time of every
interrupt's increment of `snd_n`.

## 6. Files

New: `src/snd/{snd.h, snd_driver.c (generated), snd_core.c}`, `src/engine/snd.asm`, `src/engtest/t_snd.c`, `tools/{mksnd.py, snd_check.sh, snd_check.py, snd_compare.py, dac2wav.py}`, `probes/snd_ref.c`, `tests/unit/test_snd.py`.
Changed: `src/engine/{engcall.asm, mmu.asm, irq.asm (_firq_isr exported), gameboot.c (snd_install), eng.h}`, `src/game/{platform.c (the stubs are gone, SoundMode 1, SilenceSound), rtl_sys.c (the pump)}`,
`tools/mkgame.py` (the bank, the core's call into it, the engine's `snd` object), `lua/{mailbox,watch}.lua` and the two run scripts (`MB_DAC`, `MB_WTAP`), `Makefile`, `data/state_ignore.txt`.

## 7. Playtest fixes (step 8.8b, `make play`)

Found by playing the build in a MAME window (intro, slums, the orcs at 13,1):

* **Pink and green colours.** MAME's coco3 starts with the *composite* monitor, which turns the game's RGB palette into other hues. `Field:set_value()` from Lua does nothing on the host's MAME 0.289 (the port keeps its value); assigning `user_value` does, one frame later. `lua/play.lua` and `lua/watch.lua` assign it and `scripts/play.sh` also writes `value="1"` into `build/play/cfg/coco3.cfg` before MAME starts (the setting is saved with the configuration).
* **Animations ran once.** `LoadSpriteList` (the ovl28 patch in `tools/mkgame.py`) copied each frame's delay, a longint in the DAX file's byte order, into the slot's four bytes unchanged; the animation loops read it as the CoCo's big endian longint (0x02000000 for a delay of 2) and never left the first frame. The patch now stores it big endian. The camp's fire and the encounter pictures cycle (frame changes every 20 to 25 ticks, read from the run). The translation of ovl18 (the finale) already reads the bytes as `*(s32 *)`.
* **The program ends when the party is destroyed.** The original returns to DOS (`Halt` after "Press any key to continue"); on the CoCo the engine stops with `MB_STATUS` set. `lua/play.lua` sees a status that stays non-zero for two seconds, clears BASIC's warm start flag (`$0071`; a warm start keeps Disk BASIC's variables, which the game's use of low RAM has overwritten, and `LOADM` then hangs) and resets the machine. MAME starts the script again with the machine, which boots the game; the saved games are kept (they live in `build/play/saves.ovl`).
* **Only some sounds were heard** (the death and hit sounds, not the steps or the "no action" and miss sounds). The long effects run with the driver on (`SetSoundDriverIdle(0)`); the short ones go through `PlaySound` with the driver idle (the game's default, 100): it starts the timer, loads the tune and waits `BriefSoundTime` (10 hundredths) in `WaitHundredths`, which reads the time of day, about 30 ms of 32 bit divisions on the 6809 per pass. The pump runs once a pass, so the step's tune (7 ticks, 30 ms, tune 9) was played and finished between two passes and only its end (silence) was applied. `WaitHundredths` is now `rtl_Delay(Hundredths * 10)` (the ovl patch list in `tools/mkgame.py`, res03), which counts the clock's frames and pumps at every look: a step makes 6 DAC toggles (3 periods of the thud) in the walk session, as the model has them. Sounds that play only while the game polls the clock remain as steady as 4. says.

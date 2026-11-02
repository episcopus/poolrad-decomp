# c/: the C translation of Pool of Radiance (Phase 7)

The matched Turbo Pascal in `src/` translated into portable C11 by `tools/c/pas2c.py`, with a small runtime that
gives it the 16-bit PC it expects. It builds and runs on macOS, Linux and Windows, and is proven against the
original by replaying recorded sessions.

## Play it

You need the game's files (`GAME.OVR`, the `*.DAX` files, `ITEMS` ...): your own copy of the original game folder.

```sh
make host                                   # cmake -S . -B build/cmake && cmake --build build/cmake
build/cmake/poolrad --data /path/to/game    # the game; --data may be omitted if the folder is the working directory
```

SDL3 is required for `poolrad` (macOS: `brew install sdl3`; Linux: your package manager or build it; Windows:
vcpkg `sdl3`, or configure with `-DPOOLRAD_FETCH_SDL3=ON`, which downloads and builds it).

| Option | Meaning |
|---|---|
| `--data DIR` | the original game's folder (also `$POOLRAD_DATA`, the working directory, the program's folder) |
| `--save DIR` | where saved characters and games go (default: a per-user folder); the data folder is never changed |
| `--scale N`, `--fullscreen`, `--windowed` | window size (1 to 8 times the 320x200 picture) and full screen |
| `--aspect 4:3\|square` | stretch the picture to 4:3 as a PC monitor showed it, or keep square pixels |
| `--filter nearest\|linear` | sharp or smooth scaling |
| `--sound speaker\|tandy\|off`, `--volume 0-100`, `--mute` | PC speaker or Tandy 3-voice sound |
| `--skip-intro` | start at the main menu: no title screens, music or code wheel question (the original's own `STING` switch, which also arms its developers' keys: Ctrl-D, Ctrl-C and the J cheat) |

While playing: **F11** or **Alt+Enter** full screen; **Alt+1 .. Alt+6** window size; **Alt+A** aspect; **Alt+F** filter;
**Alt+M** mute; **Alt+Minus / Alt+Plus** volume (Cmd instead of Alt on macOS). The choices are kept in
`poolrad.ini` in the save folder; an option given on the command line wins over the remembered choice and replaces it. The game's own keys are the PC's: arrows (or the numeric keypad), Home and End,
Enter, Esc, letters.

## How it works

| Directory | Contents |
|---|---|
| `game/` | **generated** by `make c-translate` from `src/` with the fixes of the original's bugs applied (`fixes/README.md`; `pas2c.py --faithful` leaves them out): one `.c` per Pascal unit, `game.h` (types, constants, DGROUP globals as macros, prototypes), `image.c` (the typed constants' bytes), `proc_table.c` (procedure pointers) |
| `driver/` | `res03_driver.c`: the sound driver, ported by hand from `src/RES03.ASM` |
| `rtl/` | Turbo Pascal's runtime: strings, sets, files over DOS names, the heap, the EGA model (`ega.c`), Crt/Dos/Overlay |
| `platform/` | `sdl_host.c` (the game you play), `psg.c` (the speaker and Tandy synthesiser), `replay.c` (headless, for tests), `null.c` (sound tests) |
| `include/` | `pool.h` (the memory model and the runtime's interface), `platform.h` (the only boundary with the machine), `ega.h`, `sha256.h` |
| `tests/` | `sound_probe.c`, `tune_wav.c` |

**Memory model.** One flat 1 MB arena addressed by segment:offset (`farptr`), DGROUP at its original paragraph,
the Turbo Pascal heap above it, the EGA window at `A000:0000`. A global is a macro into DGROUP at the offset the
original used (`re/dseg.toml`), so the data segment can be compared byte for byte. Pascal pointers are `farptr`
(4 bytes, as in the original). Video memory is reached through the EGA model (write modes 0 to 3, latches, the
sequencer and graphics controller registers), the same one `tools/oracle/ega.py` implements.

**Translator.** `tools/c/pas2c.py` (parser `pasparse.py`, types `ptypes.py`, the rest `p2c_*.py`) keeps names, comments
and control flow. It models Turbo Pascal's integer arithmetic exactly (a Word product wraps at 16 bits, a Word plus an
Integer is a Longint: probed with `make tpc`), strings as length-prefixed byte arrays, sets, `with`, nested routines
(static links through frame structs), `absolute` variables, procedure pointers (ids into `proc_table.c`) and the
built-ins. Regenerating is deterministic; the generated files are committed so the C can be read and, from now on,
edited by hand.

**Platform.** `platform.h` lists every read of the outside world (keyboard, clock, PIT, retrace) and write
(timer interrupt, speaker, Tandy chip). The SDL host answers them with the real machine; the replay driver answers
them with what the original read at the same point of a recorded run.

**Sound.** The driver changes the speaker and the Tandy chip on every tick of its 236.7 Hz timer, so a sound is a
run of writes a few milliseconds apart. The SDL host stamps each write with its tick's time and the audio thread
replays them at that time, 40 ms behind the game, so no tick is lost. `--wav FILE` also writes the sound to a file
(for tests).
`build/cmake/tune_wav DIR` plays every tune of the driver on both devices through the same synthesiser
(`platform/psg.c`) and writes `DIR/tandy-NN.wav` and `DIR/speaker-NN.wav`. The game has no music: it plays tunes 1
to 11, all sound effects (spell, hit, affect, death, attack leaves, no action, lightning bolt, miss, step, fireball,
attack arrives); tunes 12 to 20 are in the driver but nothing plays them. A sound played while the driver is idle
(the miss, the step) is cut after 0.1 s by the game's own `PlaySound`, and the arrival of an attack after one tick by
`ShowAttackAnimation`; the Tandy versions are longer than the speaker's, so the cut is easier to hear.

**Profiles (CoCo port, Phase 8).** `pas2c.py --profile coco --out DIR` writes C that CMOC 0.1.100 compiles (width casts for
byte arithmetic, named unions, no compound literals, wrapper structs for pointers to arrays); `--placement FILE` adds the
mapped / banked / engine classes of `ports/coco3/placement.toml`. The default profile writes `c/game`. Build the other
output on the host with `cmake -DPOOLRAD_GAME_DIR=DIR`; `ports/coco3` (`make coco-host`, `make place-host`) does it and
replays the sessions. `poolrad_replay --screens4 FILE` records the screen as the CoCo 3 shows it (4 bits a pixel).

## Proof

`make c-golden` plays every session of `tests/sessions/*.keys` on the C translation. For each, the oracle runs the
original (`tools/c/export_replay.py`), recording each read of the outside world and the screen at every
checkpoint; `build/cmake/poolrad_replay` then runs the C game, feeding it those reads. It must ask for the same kinds
of reads in the same order, show the same screen (a SHA-256 of the four EGA planes) at every checkpoint, write the
same files and call `Random` as often. `make c-sound` compares the sound driver's hardware writes for all 20 tunes
with the oracle's trace.

The sessions (`tests/sessions/*.keys`, goldens in `tests/sessions/golden/`): `boot-title`, `create-character`, `create-elf-mage`
(a second creation, then Add character to party), `walk-explore` (load the shipped saved game, walk, area map, view, search),
`camp-save` (the save writes SAVGAMB.DAT and the character files), `camp-rest-combat` (a rest finds kobolds; fight; treasure),
`parley-combat` (parley fails; twelve rounds of the tactical combat). `sound-driver` is `make c-sound`.

Debugging a difference: `tools/c/bisect_state.py SESSION` finds the first read after which the C state (DGROUP, heap,
video) differs from the original's, `tools/c/snap_oracle.py --diff` names the globals that differ,
`tools/c/who_writes.py` names the original's routine that writes an address, and `tools/c/call_trace.py SESSION LO HI --states`
compares the state on entry to every routine between two reads (build `-DPOOLRAD_TRACE=ON` in `build/cmake-trace` first).

The game's state (DGROUP without the runtime's own bookkeeping, the heap, the video planes: `tools/c/export_replay.py`
`STATIC_MASKS`) is compared at every checkpoint and fails a session; the heap manager and the procedure pointers are the
original's, byte for byte, so even the pointers in saved files match. Differences that are not behaviour are listed in
`tools/c/known_differences.toml`. What Turbo Pascal does that C does not: whitepaper appendix D.

## Portability rules

Portable C11 only: fixed-width types from `pool.h`, no GCC extensions, no floating point except the two routines that
use Pascal's `Real`, files only through `rtl/file.c`. Not targeted yet: the CoCo 3 (CMOC, Phase 8): the memory model
needs a 20-bit address space.

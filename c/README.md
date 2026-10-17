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

While playing: **F11** or **Alt+Enter** full screen; **Alt+1 .. Alt+6** window size; **Alt+A** aspect; **Alt+F** filter;
**Alt+M** mute; **Alt+Minus / Alt+Plus** volume (Cmd instead of Alt on macOS). The choices are kept in
`poolrad.ini` in the save folder. The game's own keys are the PC's: arrows (or the numeric keypad), Home and End,
Enter, Esc, letters.

## How it works

| Directory | Contents |
|---|---|
| `game/` | **generated** by `make c-translate`: one `.c` per Pascal unit, `game.h` (types, constants, DGROUP globals as macros, prototypes), `image.c` (the typed constants' bytes), `proc_table.c` (procedure pointers) |
| `driver/` | `res03_driver.c`: the sound driver, ported by hand from `src/RES03.ASM` |
| `rtl/` | Turbo Pascal's runtime: strings, sets, files over DOS names, the heap, the EGA model (`ega.c`), Crt/Dos/Overlay |
| `platform/` | `sdl_host.c` (the game you play), `replay.c` (headless, for tests), `null.c` (sound tests) |
| `include/` | `pool.h` (the memory model and the runtime's interface), `platform.h` (the only boundary with the machine), `ega.h`, `sha256.h` |
| `tests/` | `sound_probe.c` |

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

## Proof

`make c-golden` plays every session of `tests/sessions/*.keys` on the C translation. For each, the oracle runs the
original (`tools/c/export_replay.py`), recording each read of the outside world and the screen at every
checkpoint; `build/cmake/poolrad_replay` then runs the C game, feeding it those reads. It must ask for the same kinds
of reads in the same order, show the same screen (a SHA-256 of the four EGA planes) at every checkpoint, write the
same files and call `Random` as often. `make c-sound` compares the sound driver's hardware writes for all 20 tunes
with the oracle's trace.

Debugging a difference: `tools/c/bisect_state.py SESSION` finds the first read after which the C state (DGROUP, heap,
video) differs from the original's, `tools/c/snap_oracle.py --diff` names the globals that differ,
`tools/c/who_writes.py` names the original's routine that writes an address.

The data segment's digest is reported but does not fail a session yet: pointers into the heap and procedure ids differ
(the C heap manager is not Turbo Pascal's byte for byte, and a procedure pointer is an index).

## Portability rules

Portable C11 only: fixed-width types from `pool.h`, no GCC extensions, no floating point except the two routines that
use Pascal's `Real`, files only through `rtl/file.c`. Not targeted yet: the CoCo 3 (CMOC, Phase 8): the memory model
needs a 20-bit address space.

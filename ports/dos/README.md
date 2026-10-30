# ports/dos: the PC game, rebuilt from the decompiled Pascal

The original DOS game, linked by the pinned Turbo Pascal 6.0 from `src/` plus this port's patches, for the
machines the original ran on (8088 and up; EGA, CGA or Tandy video; PC speaker or Tandy sound). The first
patch removes the code wheel question. Later patches will make the game faster on a Tandy 1000 EX (below).

## Why the Pascal tree and not the C translation

- `make rebuild` already turns `src/` into the original program, byte for byte, so a patch to `src/` gives
  a real DOS program with the original's memory map, overlay manager, video and sound drivers. Nothing new
  has to run on the old machine.
- The C translation (`c/`, Phase 7) targets SDL hosts and the CoCo 3. A DOS build from it would need a 16-bit
  DOS C compiler, new video, sound, keyboard and overlay layers, and would not fit the EX's memory as easily
  as the original's overlay scheme does.
- For speed work on an 8088, the Pascal tree is the right base too: a slow routine can be rewritten in
  Pascal or replaced by an assembly routine linked with `{$L}` (the way res03's sound driver is already
  built, `tools/re/asm86.py`), one routine at a time, with the rest of the game unchanged and proven so.

## How it is built

`src/` is never edited. `tools/build.py` copies `src/*.PAS` and `*.ASM` to `build/stage`, applies the patches
of `patches/series` in order (`patch --fuzz=0`: when `src/` changes under a patch, the build fails and says
which patch to refresh), and links the stage with `tools/match/rebuild.py`'s recipe.

| Path | What |
|---|---|
| `patches/series` | the patches, in order, with a comment each |
| `patches/*.patch` | unified diffs against `src/` (paths `a/<FILE>`, `b/<FILE>`) |
| `build/link/` | `POOL.EXE`, `POOL.OVR`, `POOL.MAP`: what the oracle runs |
| `build/game/` | `START.EXE`, `GAME.OVR`: the files for the machine |
| `build/game.json` | patches applied, sizes, hashes, units whose code differs from the original |
| `build/dist/` | `make dist`: the two files, `INSTALL.TXT`, `SHA256.TXT` (DOS line endings) |

To write a patch: copy the file from `src/`, edit the copy, `diff -u --label a/X.PAS --label b/X.PAS
src/X.PAS copy > patches/name.patch`, add the name to `patches/series`.

## Patches

| Patch | Change | Code that differs |
|---|---|---|
| `no-code-wheel.patch` | `CheckCodeWheel` (ovl02) asks nothing: the title screens go straight to the character menu. It still draws the one `Random(13)` the original's first question draws, so the random stream after it is the original's (and a session recorded on the original replays on the port). | ovl02 only |

The original has its own way past the wheel, `START STING`, but it also skips the title screens and arms
developer keys (Ctrl-D debug mode, Ctrl-C quits: whitepaper, `ReadGameKey`). The patch changes only the wheel.

## Tests

`make test` runs `faithful`, `game` and `tandy` (about 90 s). For a patch like the wheel's that is the proof:
the pipeline adds nothing (`faithful`), the patched units are the only code that differs from the original
(`game`), and the game behaves as intended on the Tandy machine (`tandy`). `make sessions` is the gate for
patches whose code cannot be compared byte for byte any more (the speed work): run it before such a patch lands.

| Target | Proves | Time |
|---|---|---|
| `make faithful` | with no patch, the pipeline links the original program (load image, relocations, overlay file) | 2 s |
| `make game` | the patched build; prints which units' code differs from the original (expected: the patched ones) | 2 s |
| `make sessions` | every session of `tests/sessions`, Tandy sound selected, by the replay method of `tools/oracle/replay.py`: the original plays the key script and every read of the outside world is recorded; the wheel's reads are cut out; the port replays the rest and must ask for the same reads in the same order and match the original's game state, screen and random count at every key read, every shot and every 20,000 reads; then the same random draws, the same files written (saved games, stale stack bytes masked as `tools/c/known_differences.toml` says), the same sound requests (`PlaySound`, `SetSoundDriverIdle` and their arguments, in order; the driver's own code is checked by `make game`) | about 15 min (`SESSION=name` for one) |
| `make tandy` | DOSBox-X `machine=tandy`, headless, POOL.CFG `T`/`T`: the port shows every title screen of the original pixel for pixel, then the original's character menu (the original's `STING` run), and never the wheel question (the original's last screen) | 80 s |

`make play` opens a DOSBox-X window with the same Tandy machine at about the EX's speed, for trying the game by
hand. It is the only target that opens a window.

What the emulators do not cover: the oracle emulates an EGA PC (no Tandy video), and DOSBox-X does not time an
8088. The real machine stays the final check: copy `build/dist` to it (`INSTALL.TXT`).

## Plan for the speed work (Tandy 1000 EX)

The EX: 8088 at 7.16 MHz, Tandy video in system RAM (CPU and video share the bus), Tandy sound, 256 to 640 KB,
floppies. Each optimization is one patch in the series, so it can be switched off (`ONLY=`) and measured alone.

1. **Measure before changing.** Add an 8088 cycle model to a profile run of the oracle: the oracle already knows
   every executed instruction and its routine (`trace.locate`); an 8088 timing table (with the 4-cycle bus per
   byte that dominates on an 8088) and a cost for Tandy video memory accesses give an estimated time per routine
   per session. Rank routines by that, the way the CoCo port chose its hot routines (`ports/coco3/docs/PHASE-8.11.md`).
2. **Rewrite the hot routines.** Pascal first where the compiler can do better with a different form; else an
   assembly routine in a `.ASM` of the port (assembled by `tools/re/asm86.py`, linked with `{$L}`), with the
   Pascal version kept in the patch as its specification. Likely candidates from the whitepaper: the picture
   blitters and the changed-region flush of res07 (`DrawPictureItem`, `FlushPictureChanges`, adapter 2 is
   Tandy), the text drawing of res06, the 3D view drawing.
3. **Keep the game the same.** Every patch keeps `make sessions` and `make tandy` green: same decisions, same
   screens, same saved games. The sessions check is a replay, so it does not care how fast the port is: a
   first version that compared two scripted runs failed on timed keys (`press` on the animated camp screen)
   and on tune lengths as soon as the port ran a few hundred thousand instructions fewer, which any speed
   patch will do. For the same reason sound is compared as the game's requests to the driver, not as chip
   writes (in a replay, how many driver steps fit in a 0.1 s wait depends on instruction counts). A patch that must change behaviour says so in `patches/series` and teaches `sessions.py`
   the difference, as the wheel patch does (the reads it no longer makes are cut from the recording).
4. **Check on the machine.** Emulators give the ranking, the EX gives the verdict. If a closer emulator is
   wanted: MAME has no 1000 EX driver, but its `t1000hx` (same CPU, clock and video) is close; it needs a ROM
   dump of the HX and a DOS boot disk, and would be driven headless through Lua like the CoCo port's tests.
5. **Disk and memory.** The rebuilt `START.EXE` is not EXEPACK packed (5.5 KB larger on disk). A packer
   (the inverse of `tools/re/unexepack.py`) is a small task if disk space on the EX's floppies matters.

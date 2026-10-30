# ports/dos: the PC game, rebuilt from the decompiled Pascal

The original DOS game, linked by the pinned Turbo Pascal 6.0 from `src/` plus this port's patches, for the
machines the original ran on (8088 and up; EGA, CGA or Tandy video; PC speaker or Tandy sound). The first
patch removes the code wheel question; the speed patches (`patches/speed/`) make the game faster on a Tandy 1000 EX
without changing what it does (below).

## Why the Pascal tree and not the C translation

- `make rebuild` already turns `src/` into the original program, byte for byte, so a patch to `src/` gives
  a real DOS program with the original's memory map, overlay manager, video and sound drivers. Nothing new
  has to run on the old machine.
- The C translation (`c/`, Phase 7) targets SDL hosts and the CoCo 3. A DOS build from it would need a 16-bit
  DOS C compiler, new video, sound, keyboard and overlay layers, and would not fit the EX's memory as easily
  as the original's overlay scheme does.
- For speed work on an 8088, the Pascal tree is the right base too: a slow routine is rewritten with Turbo
  Pascal 6.0's built-in assembler (`procedure X(...); assembler; asm ... end;`, compiled by the same pinned
  compiler, with the unit's globals by name), one routine at a time, with the rest of the game unchanged and
  proven so.

## How it is built

`src/` is never edited. `tools/build.py` copies `src/*.PAS` and `*.ASM` to `build/stage`, applies the patches
of `patches/series` in order (`patch --fuzz=0`: when `src/` changes under a patch, the build fails and says
which patch to refresh), and links the stage with `tools/match/rebuild.py`'s recipe.

| Path | What |
|---|---|
| `patches/series` | the patches, in order, with a comment each |
| `patches/*.patch` | unified diffs against `src/` (paths `a/<FILE>`, `b/<FILE>`) |
| `build/link/` | `POOL.EXE`, `POOL.OVR`, `POOL.MAP`: what the oracle runs |
| `build/ref/` | `make ref`: the same without the speed patches, the reference their behaviour is compared with |
| `build/game/` | `START.EXE`, `GAME.OVR`: the files for the machine |
| `build/game.json` | patches applied, sizes, hashes, units whose code differs from the original |
| `build/dist/` | `make dist`: the two files, `INSTALL.TXT`, `SHA256.TXT` (DOS line endings) |

To write a patch: copy the file from `src/` (or from `build/stage` when an earlier patch already changes it), edit the
copy, `diff -u --label a/X.PAS --label b/X.PAS before copy > patches/name.patch` (one patch may hold several files),
add the name to `patches/series`. A speed patch lives in `patches/speed/` and must not change behaviour (`make func`).

## Patches

| Patch | Change | Code that differs |
|---|---|---|
| `no-code-wheel.patch` | `CheckCodeWheel` (ovl02) asks nothing: the title screens go straight to the character menu. It still draws the one `Random(13)` the original's first question draws, so the random stream after it is the original's (and a session recorded on the original replays on the port). | ovl02 only |
| `speed/unpack-rle.patch` | `UnpackRle` (res05), through which every DAX block passes, in assembler: a literal run is one `REP MOVSW`, a repeat run one `REP STOSB` | res05 |
| `speed/tandy-glyph.patch` | `DrawGlyph`'s Tandy branch (res06), all text: a new `DrawTandyGlyph` shifts each font row out two bits at a time into the four banks, where the Pascal tested every bit with the font pointer reloaded | res06 |
| `speed/tandy-blit.patch` | the Tandy row loop of `DrawPictureItem` and `DrawPictureItemClipped` (res07): the 3D view's tiles, sprites, icons. `TandyRows` does the trackers, the save-under and the copy (the masked one in an AND pass and an OR pass) each over all rows, with the original's quirks (the masked loop's `ShortInt` count, `SharedLoopIndex`), and falls back to the exact row-by-row order when rows could overlap | res07 |
| `speed/tandy-pictures.patch` | the Tandy branches of `MirrorPicture` (sprites facing left: `TandyMirrorRows`) and of `UnpackPicturePixels` (the transparent colour's mask of every picture loaded: `TandyColorMask`) | res07 |
| `speed/tandy-fill.patch` | window clears (`ClearRect`, res06; `ClearWindow`, res09), the screen flush (`FlushPictureChanges`' Tandy branch and its tracker resets) and new pictures (`AllocatePicture`) by words: TP 6's `FillChar` and `Move` go a byte at a time (`0AF8:16B7`, `0AF8:16A1`) | res06, res07, res09 |
| `speed/tandy-show.patch` | `ShowPicture`'s Tandy branch (res07), pictures straight to the screen: `TandyShowRows` copies the rows by words | res07 |
| `speed/walk-line.patch` | `WalkLine` (ovl30), the line-of-sight walk of combat targeting and the AI, in assembler: the `Bound` line it stepped beside the real one never moves in Y (its D1 starts at -N and D3 is 0), so its height is the start tile's for the whole walk; the walked line is `SetupLine`'s and `StepLine`'s arithmetic inline | ovl30 |
| `speed/sort-table.patch` | `SortTable` (ovl30), the exchange sort of every target scan, in assembler, same order and same test | ovl30 |

The speed patches change resident code, so every segment after res05 moves (the build lists every unit as different:
their far calls point elsewhere). DGROUP's layout does not change: no patch adds a global or a typed constant.

The original has its own way past the wheel, `START STING`, but it also skips the title screens and arms
developer keys (Ctrl-D debug mode, Ctrl-C quits: whitepaper, `ReadGameKey`). The patch changes only the wheel.

## Tests

Two questions, two methods. Is the reference (the behaviour patches: the wheel) the original game, apart from what
they change on purpose? `make sessions`, a replay of recordings of the original. Do the speed patches keep the
reference's behaviour exactly? `make func`, which does not care how fast either build runs.

| Target | Proves | Time |
|---|---|---|
| `make faithful` | with no patch, the pipeline links the original program (load image, relocations, overlay file) | 2 s |
| `make game`, `make ref` | the game, and the reference without speed patches; `game` lists the units whose code differs from the original | 2 s |
| `make func` | the speed patches change nothing the game does: the suite on both builds, compared (below) | about 2 min |
| `make tandy` | DOSBox-X `machine=tandy`, headless, POOL.CFG `T`/`T`: the game shows every title screen of the original pixel for pixel, then the original's character menu (the original's `STING` run), and never the wheel question | 80 s |
| `make tandy-deep` | DOSBox-X `machine=tandy` again, the reference and the game typing the same keys (`AUTOTYPE`): saved game A, the 3D view turning, a character sheet, the area map. No dice are drawn, so every screen the reference holds for 2 s must appear in the game's video pixel for pixel (12 screens): the speed patches on a real Tandy BIOS, DOS and video emulation | 2.5 min |
| `make sessions` | every session of `tests/sessions`, by the replay method of `tools/oracle/replay.py`: the original plays the key script and every read of the outside world is recorded; the wheel's reads are cut out; the reference replays the rest and must ask for the same reads in the same order and match the original's game state, screen and random count at every key read, every shot and every 20,000 reads; then the same random draws, the same files written, the same sound requests | about 15 min |
| `make prof` | not a test: the 8088 profile of both builds and the gain, per session (below) | about 5 min |

`make test` runs faithful, game, ref, func and tandy.

### `make func`: behaviour without timing (`tools/func.py`)

A replay of a recording made on the slow game cannot drive the fast one: the fast game asks for the time and polls
the keyboard a different number of times while it draws, and an emulator's timer interrupts land wherever an
instruction count says. `func.py` gives the emulated machine (the oracle, `tools/oracle`, in Tandy video and sound)
a clock that belongs to the program instead:

- **Virtual time moves only when the game waits**: a keyboard poll is 2 ms, a time-of-day read 10 ms (the hundredth
  the game reads), a read of the BIOS tick count 50 us, a blocked keyboard read runs to the next timer interrupt.
  Drawing, unpacking and game logic take no time at all, so a game that draws faster sees exactly the same times.
- **Timer interrupts arrive at the same instruction in every build**: right after the call that made virtual time
  pass the period (the service's IRET is done by the harness and IRQ 0 taken at the instruction it returns to; a
  further owed period is taken at the first instruction boundary that allows it, stepping one instruction at a time).
- **Keys are released at polls only**, by the script's rules (`tools/oracle/keys.py`: `key` when the game is idle,
  `press` at the next poll, `wait` in virtual time; a `key` waiting 10 s of virtual time on a screen that never goes
  idle goes in anyway); shots and `quit` happen at a poll too.

The suite (`sessions/suite.txt`) is played on both builds and compared, reference against game:

- at every key the game reads and every `shot`: DGROUP's data (the overlay manager's own variables masked), the heap,
  the Tandy screen (B800h, 32 KB) and the video mode, and the virtual time. Words that differ by exactly the distance a
  segment moved (a patch that changes a resident unit's size moves DGROUP, the heap and the code after it) count as
  the same pointer;
- every `Random` call (kind, range, result, the routine that asked), the files opened, the files written (saved
  games; the stale stack bytes of `tools/c/known_differences.toml` masked);
- every byte written to the Tandy sound chip, with its virtual time, and every call of `PlaySound` and
  `SetSoundDriverIdle`;
- how the run ended.

A difference prints the first checkpoint where the builds part and what differs there (`DGROUP 70C7: 04 / 00`). Two
checks that the method sees what it should: two identical builds agree everywhere (the clock is deterministic), and
planted bugs are found at once: a wrong pixel mask in the glyph routine at the first key, one byte of DGROUP not
written (`SharedLoopIndex`) at the first masked blit. It also caught a real one: a helper that did not clear the
direction flag wrote a sprite's rows backwards over its header (TP 6's `Move` leaves the flag set after a backward
copy), which hung `council-guards`.

The suite is the scripts of `tests/sessions` that still reach what they were written for in Tandy video (their dice
differ: the EGA title screen draws about 33,000 random numbers for its palette flicker, Tandy's draws one), plus
`sessions/maze-battle.keys`, written for the port: the 3D view walking the city, an ambush, a battle won with quick
combat, the treasure, a character sheet, a flight. `tools/sheet.py build/func/ref/<session>` lays the shots of a
`func.py --shots` run side by side, to see what a script does.

`make play` opens a DOSBox-X window with the same Tandy machine at about the EX's speed, for trying the game by
hand. It is the only target that opens a window.

What the emulators do not cover: the oracle's Tandy video is the B800h memory only (no CRTC, no palette registers),
and neither emulator times an 8088. The real machine stays the final check: copy `build/dist` to it (`INSTALL.TXT`).

## The speed work (Tandy 1000 EX)

The EX: 8088 at 7.16 MHz, Tandy video in system RAM (CPU and video share the bus), Tandy sound. Each optimization
is one patch of `patches/speed/`, so it can be left out (`ONLY=`) and measured alone.

**Measuring.** `tools/prof.py` plays the suite like `func.py` and charges every executed basic block an estimated
8088 cost: the larger of the 8086 execution time (plus 4 clocks per word moved over the 8-bit bus) and 4 clocks per
byte of instruction and data, `REP` string instructions per repetition. It is a model (no wait states, no prefetch
queue state, branches half taken): it ranks routines and shows what a change saves; the machine gives the verdict.
Waiting is kept apart from work (a stretch between two polls or clock reads that is short and draws nothing, and
Crt's `Delay`), and the work is cut per key: what each key press costs until the game reads the next key. Routines
are named from the build's link map (helpers of the patches are in the units' interfaces so they get their own row).

**Where the time went** (the reference over the suite): `System.Move` 25 % (TP 6 copies a byte at a time),
`DrawPictureItemClipped` 20 % (a masked byte took two far-pointer loads), `DrawGlyph` 14 %, Crt's `Delay` 10 %
(waiting), `FlushPictureChanges` 9 %, `FillChar` 3 %, `DrawPictureItem` 3 %, then unpacking (`UnpackRle`,
`UnpackPicturePixels`) and the mirrors. A step in the 3D view was mostly the tile blits (8 rows of 4 bytes per 8x8
tile, about 250 tiles a step) and the status text; a combat turn the text panels, sprite mirroring and window clears.

**What it gives** (model, 8088 at 7.16 MHz, work per key of `maze-battle`, reference -> game):

| Action | Reference | Game | |
|---|---|---|---|
| start-up to the menu | 10.0 s | 3.6 s | 2.8x |
| load a saved game | 8.2 s | 4.2 s | 1.9x |
| step forward in the 3D view | 1.2 s | 0.55 s | 2.2x |
| turn | 0.7 to 1.0 s | 0.27 to 0.39 s | 2.6x |
| the first round of a battle (`maze-battle`, goblins) | 21.2 s | 8.6 s | 2.5x |
| combat, a quick turn (with the monsters' moves) | 2.5 to 10.3 s | 0.8 to 3.7 s | 2.8 to 3.2x |
| the City Hall guards' battle (`council-guards`: the key that starts it, all their turns) | 95.9 s | 34.5 s | 2.8x |
| character sheet | 1.6 s | 0.4 s | 3.9x |
| a menu key (median: `character-menu`, `create-character`) | 0.5 s | 0.11 s | 5x |
| a key in the shop, the temple (median) | 0.9 to 1.0 s | 0.4 s | 2.4x |

Over whole sessions the work falls by 52 to 70 % (`make prof`). The rest of a screen that animates while it waits
(the camp fire, a portrait, the treasure) is redrawn on every pass of its wait loop; that is faster too, which makes
the animation smoother and the key reach the game sooner, but it is not time the player waits for.

**Next candidates** (from the current profile): in combat, `ScanTargets` and `InDirArc` (ovl30) and `FootprintCell`
(ovl31), the window clears and text panels (already at bus speed: fewer of them would mean changing what is drawn
in between, which the game shows); in the 3D view, the per-call overhead of the tile path (`DrawCellPicture` and
`DrawPictureItem`'s Pascal set-up, about 250 calls a step) and the string copies of the status text; loading. MAME's `t1000hx` (same CPU, clock and video as the EX;
needs a ROM dump of the HX) would give real timings headless, the way the CoCo port's tests drive MAME.

**Disk and memory.** The rebuilt `START.EXE` is not EXEPACK packed (about 5.5 KB larger on disk). A packer (the
inverse of `tools/re/unexepack.py`) is a small task if disk space on the EX's floppies matters.

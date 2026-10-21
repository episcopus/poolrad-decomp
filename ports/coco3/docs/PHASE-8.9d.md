# Step 8.9d: walking in the 3D view (profile, three fixes, ways forward)

Date: 2026-10-21. Follows `docs/PHASE-8.9b.md` (section 4b). Tags: **[V]** measured by running it, **[E]** estimate. Everything here was built and measured in a separate git worktree on the branch `perf/walk-3d`, so that the rebuilds of the parallel
investigation of the visual corruption in the main checkout were not disturbed; **it is not merged**. The branch touches `src/engine/gfx.c` and `src/engine/kernels.asm`, which that investigation also edits: merge by hand.

## 1. Result

One step forward in the Phlan streets: **2.34 s to 1.27 s (-46 %)**; a turn left **1.17 to 0.71 s**, a turn right **1.43 to 0.82 s** [V] (emulated 1.79 MHz machine, the game working on the key, loading excluded; 16 forward steps, 6 and 2 turns). 16 of 16 sessions pass
(`make step-check`: every labelled screen, 0 DGROUP places open, party records, save area), the engine tests pass. Busy time over all 16 sessions 2,446 to 2,387 s (-2.4 %): walking is a small part of them.

## 2. Where a step went [V]

`tools/walkstat.py` (the time of each key press up to the next, by unit and routine, from the program counter sampled every frame) and `tools/itrprof.py` (one step traced instruction by instruction with MAME's debugger, cycles from the 6809's table, call
stacks; `lua/watch.lua` takes `MB_ITRACE_ACT` for the trace's extra columns). The two agree (2.32 s traced, 2.34 s sampled). The step before the fixes, 2.34 s:

| Part | s | % | What |
|---|---:|---:|---|
| Drawing the walls (`DrawWallView`) | 1.12 | 48 | 13 `DrawWallPiece`, 198 8x8 tiles through `Put8x8Symbol` and the engine's `DrawPictureItem`: 7,600 cycles a tile, of which the blit was 2,600 |
| The area script that runs at every step (`RunScriptFrom`) | 0.72 | 31 | `DecodeString` alone 0.51 s: `s := s + Chr(c)` copied the 256 byte string twice for each character (two temporaries, `memcpy`, `memmove`) |
| The footstep sound | 0.22 | 9 | `PlaySound` runs the timer driver for `BriefSoundTime` = 10 hundredths around each sound and waits; two sounds a step. The original does the same |
| The rest | 0.28 | 12 | `MoveParty`, the location line, number to text, the clock |

## 3. What was done [V], in order, on the forward step

| Change | Step | Gain |
|---|---:|---|
| `rtl_str_push`: the idiom `s := s + Chr(c)` (4 places: `DecodeString` twice, a number entry, a text line) is rewritten in place by `tools/mkgame.py str_push` | 2.34 to 1.81 s | -0.53 s |
| `k_tile8` (kernels.asm) and `db_tile8` (gfx.c): an 8x8 item is blitted straight from the picture's block in window 1 into DrawBuf in window 0, no staging copies, no clipping, one kernel call with the row trackers; the general path remains for items across a block border, DrawBuf's split row or a mask in another block | 1.81 to 1.33 s | -0.48 s |
| `k_tile8` computes the row address itself (no `MUL16`, no `db_ptr`), bounds shortcuts for the tile case, and `DrawWallPiece` (patched in `mkgame.py`) reads its piece's tile numbers out of the banked heap once instead of twice a tile | 1.33 to 1.27 s | -0.06 s |

Cost: the engine grows 536 bytes (ends at $7A9C), the core 40 bytes ($4B85). Also fixed on the way: `tools/lwasm_peep.sh` made no `build/run` directory, so a clean checkout silently skipped the peephole pass (banks 11 KB bigger); a clean checkout also needs `build/prof`
(`tools/mkplan.py` reads the access profiles from it) and the ROMs.

## 4. What is left in a step (1.27 s) and ways forward [E unless said]

| Idea | Now | Gain | Effort | Note |
|---|---:|---:|---|---|
| Footstep sound: shorten `BriefSoundTime` (the `enum`, 10 to 4), or make the sound not block (the driver is pumped by the game's own wait loop, so that needs the pump in the frame interrupt) | 0.20 s (16 %) | -0.12 s, or -0.20 s | hours / days | A decision about the feel; the sound is cosmetic and the state is the same |
| Fold `Put8x8Symbol` (bank choice, engine call with six arguments), `api_DrawPictureItem`, `pic_of` and `db_item` into one engine routine; the trackers of `k_tile8` (0.35 of its 1,000 cycles) by rectangle | 0.30 s (24 %) | -0.10 to -0.15 s | a day | the tile path is still 2,200 cycles of C round the 1,000 of the kernel |
| The view's clear and the location line (`k_fill`, `k_glyph8`, `gfx_glyph`, flush) | 0.17 s (13 %) | -0.05 s | hours | skip the text when it did not change |
| 32 bit arithmetic of the translation (`(s32)Len > 0` on a byte: `cmpDWord*`, `sub32Stack`, `copyWordToDWord`, `isDWordZero`: 2,700 calls, 9,000 bytes in the banks) | 0.1 s in a step, 8 % of the walk profile | -0.05 s here, 3 to 5 % of every session [E] | days, in the translator, every session proves it | the `ReadPromptChoice` poll and the delay loop of the sound driver use it too |
| The script's string decode every step (cache what it decoded for an unchanged `EclPC`) | 0.10 s | -0.08 s | days, risk in the script machine | |

The floor with the first two lines done is about 0.8 s a step. A different class of fix would draw less: the view is redrawn tile by tile from scratch at every step; caching a composed piece per (wall, distance) would remove most of the 198 calls but changes what is stored.

## 5. Tools

| What | How |
|---|---|
| time of each key press by unit and routine | `python3 tools/walkstat.py build/run/prof-X.out --from T [--key CODE] [--api] [--caller]` after a run with `MB_PCLOG=0-1500`; `tests/profile/walk-profile.keys` is the walking session (12 moves twice) |
| exact profile with call stacks of one step | `MB_DEBUGGER=1 MB_ITRACE=T MB_ITRACE_ACT='tracelog "%02X %02X %02X %04X\|",b@909,b@80,b@<eng_idx>,w@90A' scripts/game_run.sh ...` (the limit in whole seconds), then `python3 tools/itrprof.py --busy [--tree ROUTINE]` |

## 6. Round 2: ways forward 1 to 4, built and measured [V]

Branch `perf/walk-3d-2` on top of the merged round 1 (193f29b0). The forward step in the Phlan streets, same session and method as section 1 (16 steps, 6 left turns, 2 right turns):

| Step | Forward | Left | Right | Engine ends |
|---|---:|---:|---:|---|
| start of round 2 | 1.27 s | 0.71 | 0.82 | $7B8C |
| 1 a brief sound waits as long as it sounds | 1.19 | 0.66 | 0.77 | $7B8C |
| 2 `DrawWallTiles`, one engine call a piece | 1.13 | 0.61 | 0.68 | $7C61 |
| 2b the bank's picture looked up once a call | 1.07 | 0.56 | 0.63 | $7C73 |
| 3 window registers written directly in the tile path | 1.06 | 0.55 | 0.62 | $7C4F |
| 4 `(s32)x OP constant` made a 16 bit compare (97 sites) | **1.04** | **0.54** | **0.62** | $7C4F |

Over the whole work on walking: a step 2.34 to 1.04 s (-56 %), a left turn 1.17 to 0.54 s, a right turn 1.43 to 0.62 s. 16 of 16 sessions pass (`make step-check`: screens, 15 sessions with 0 DGROUP places open, the council fight has no state comparison, party records, save area), the engine tests pass.
Busy time over all sessions 2,403 to 2,374 s; banks 314,322 to 313,496 bytes.

**1. The sound wait.** The upper bound (no wait at all) is -0.16 s a step, so this was never going to be large. The asynchronous version (the stop of a sound done by the pump while the game draws) was built and dropped: the pump runs only where the game polls, a late pump
catches up all its ticks at once, and the tone was silenced before it had been applied (the 25 ms footstep vanished: measured on the DAC). What stayed: a brief sound waits for the length of its tune, not for 100 ms. Four of the twenty tunes are short (38, 42 and 72 ms; tune 21 makes no
sound), measured on the host model of the driver; the footstep tone is the same 36 bursts of 24 to 25 ms before and after (`build/run/dacburst.py` over `MB_DAC=1`). The Tandy device makes no sound on the CoCo, so its wait is 0. The sounds of the fights are longer than the wait and unchanged.

**2. The tile call.** `api_DrawWallTiles` (engine) draws a piece's w x h tiles from the symbols the game keeps on its stack, with the bank lookup of `Put8x8Symbol` and `DrawPictureItem` done inside; `DrawWallPiece` makes one call when `DrawDirect` is set (the 3D view) and keeps the old loop otherwise.
The engine had 116 bytes left, so the image of the shared data (346 bytes, $0700..$08FF, copied by the boot) moved from $7C00 to $7C90 (`SHARED_IMG` in `mailbox.inc`; it must end before $7E00, where BASIC's stack is while LOADM runs). **The engine has 65 bytes of room now.**

**3. The view's clear and text.** Measured upper bound: with every `DrawGlyph` and `FillPlaneRect` removed a step is 0.97 s instead of 1.07, so the whole of the text and the cell fills is 0.10 s (9 %). Skipping the text that did not change needs a shadow of the screen's 40 x 25 cells that the engine
has no room for; the prompt line is drawn one glyph at a time (46 calls a step, 1.3 ms each). A version of `db_flush` that maps its windows only when the block changes saves about 0.007 s and costs 68 bytes of engine: not built. What was done: the tile path writes the window registers ($FFAC, $FFAD) itself, 36 bytes smaller and 0.01 s faster.

**4. 32 bit arithmetic.** In a traced step 12,600 of 13,000 calls of `cmpDWordSignedInt`, `isDWordZero` and `initDWordFromUnsignedWord` come from `ReadPromptChoice` polling the clock while it waits for a key, and the sound's wait loop uses them too: time that is spent waiting. What the work of a step spends in the helpers is 0.15 s,
of which 0.05 s is the sound wait, 0.03 s the prompt and 0.04 s the script machine. The translation widens a Word compared with a constant to `(s32)`; `tools/narrow.py cmp16` makes it a 16 bit compare when the operand is a byte or word (a local, a parameter, an element of a u8/u16 array) and the constant fits: 97 sites,
-826 bytes of banks, -0.02 s a step. CMOC 0.1.100 crashes (segmentation fault) on `x == 0xFFu` against a word read through `FPBL`: the `u` suffix is written only for constants above 32767. The other 280 `(s32)` of the game are 32 bit values (money, experience) or expressions.

**What is left in a step (1.04 s), by the sampled profile:** the wall tiles 0.23 s (the kernel 0.12, C round it 0.10), the flush to the screen 0.06, glyphs 0.06, cell fills 0.05, the script machine 0.15, the sound wait 0.07, the rest 0.3. Ideas not built: the tile loop in assembly (about -0.07 s, needs the room), a mask kept in the same block as the pixels so that it needs no copy (0.03 s),
exact trackers by tile row (0.02 s), and skipping the intermediate redraws when keys are queued (large when a key is held, changes what the screen shows between steps).

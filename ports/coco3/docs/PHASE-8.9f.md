# Step 8.9f: menus and UI navigation (camp, loot, shops, temple, character screens)

Date: 2026-10-22. Follows `docs/PHASE-8.9e.md`. Tags: **[V]** measured by running it, **[E]** estimate. Built and measured in a separate git worktree on the branch `perf/menus` (the main checkout was free for other work); merge by hand if main moved.

## 1. Result

Busy seconds a key press (the game working, not waiting for a key; `tools/walkstat.py`, the sessions are deterministic), 1.79 MHz machine [V]. The part of each session measured is the menu part (from the second given to `walkstat.py --from`; `build/run/mb.sh` plays all eight and prints it):

| Session (menu part) | start | 1 `k_put` | 2 `k_text` | 3 `PutTileRun` | 4 `DrawTextRun` | 5 `k_text` cached | 6 `k_rows` | change |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| shop-buy (buying, 22 keys) | 1.26 | 1.05 | 0.90 | 0.77 | 0.75 | 0.63 | 0.66 | **-48 %** |
| battle-aftermath (the loot screen) | 2.04 | 1.48 | 1.40 | 1.30 | 1.27 | 1.23 | 1.06 | **-48 %** |
| character-view | 1.76 | 0.98 | 0.95 | 0.89 | 0.88 | 0.86 | 0.75 | **-57 %** |
| character-menu | 0.85 | 0.60 | 0.57 | 0.57 | 0.57 | 0.55 | 0.56 | -34 % |
| temple-cast | 1.83 | 1.09 | 1.04 | 0.98 | 0.97 | 0.94 | 0.93 | -49 % |
| temple-heal | 2.81 | 2.49 | 2.45 | 2.40 | 2.39 | 2.35 | 2.32 | -17 % |
| camp-cast | 2.71 | 2.31 | 2.22 | 2.07 | 2.06 | 2.03 | 1.89 | -30 % |
| camp-save (file output) | 7.23 | 4.91 | 4.90 | 4.86 | 4.86 | 4.81 | 4.72 | -35 % |

Walking in the 3D view is unchanged by the work (a forward step 1.05 s, was 1.04 s at the end of 8.9d [V]): the 3D view's tile is `k_rows` now and the text it draws is faster, which cancel.

(The step 5 and 6 columns are measured on slightly different press counts, the run being faster: the shop's 0.63 and 0.66 are within the noise of where the first press falls.)

After every step the labelled screens of the eight menu sessions were compared with the originals'. After step 6 the whole `make step-check` ran: 16 of 16 sessions, 0 DGROUP places open, party records and the save area equal. The engine tests (`make eng-tests`) pass up to `t_task`; `t_vol2` fails in this worktree because its test disk is full (environment, as on the main checkout before the work, not this change).

## 2. Where the time went [V]

A menu key is a redraw of a window: no 3D, no combat, so the cost is the number of small engine calls and what each one costs.

* **Frames and text.** A window frame was about 100 `Put8x8Symbol` calls, a line of text one `DrawGlyph` call a character; a screen made 3,000 tiles and 8,000 glyphs. Each call is a far call into the engine (bank switch, mailbox) and C: 1 to 4 ms for 8 rows of 4 bytes.
* **Items to the screen.** `gfx_item` staged a picture item through a 256 byte buffer and called `k_copy` a row.
* **Big pictures** (the camp and loot portraits, 44 bytes by 88 rows): `DrawPictureItemClipped` read five rows at a time into two staging buffers and called `k_blit` for them: 65 ms for a draw, 6 draws a key on the loot screen.
* **What is not work:** the game's own waits (`DelayByGameSpeed`, GameSpeed * 225 ms, the setting 0 to 9 in the game; the 32 bit compares and `frames32` of the temple and camp sessions are that loop). Left unchanged. `camp-save` is file output (the emulated disk), not drawing.

## 3. What was done

1. **`k_put`** (`kernels.asm`): `gfx_item` maps the picture's block in window 1 and the screen's in window 0 and copies an item's rows straight across (an 8x8 tile is an unrolled four byte row). The picture table is 96 slots (the extent table holds 64 pictures, so more could never be used). -11 to -44 %.
2. **`k_text`**: a text glyph in assembly. Windows 0 and 1 show the screen block of the cell and the next, so a glyph whose rows cross a block border needs no slow path; the C slow path is gone (the engine is 480 bytes smaller).
3. **`PutTileRun`** (new engine call, `patches/res09_windowframe.c`): `DrawWindowFrame` makes 8 calls (4 corners, top and bottom, left and right runs) instead of about 100.
4. **`DrawTextRun`** (`patches/res06_drawtextat.c`): `DrawTextAt` draws its string in one call.
5. **`k_text` with a cached nibble table** for the last colour (16 entries, made again when the colour changes) and a fast path for blank glyphs: 2 to 5 times faster than the four entry table.
6. **`k_tilerun` and `k_rows`.** `k_tilerun` draws a run of 8x8 tiles of the frame with the source mapped once (a tile it cannot place goes back to `gfx_item`). `k_rows` draws rows of any width of a picture into DrawBuf, with masks and the trackers, as far as the picture's block and DrawBuf's block go (`db_chunk` in `gfx.c` calls it, clipped or mirrored items and the save picture of flag bit 2 stay on the old path); it replaces `k_tile8` (the 3D view's tile is `k_rows` with 4 by 8). `DrawPictureItemClipped` went from 0.38 to 0.12 s a key on the loot screen. The picture table is 64 slots now (an extent per picture, so 64 live pictures at most).

**Engine room.** The engine ends at `$7C78` of `$7C90`: 24 bytes left. (The image of the shared data starts at `$7C90`; `hibss` and `dskbss` are the sections moved out in step 8.9e.) Nothing big fits any more without removing something.

## 4. What is left [E]

* `FlushPictureChanges` is the largest part of the loot screen now (0.3 s a key, 6 flushes a key, each 3,872 bytes): the copy loop is a word a pass (12 cycles a byte). Unrolling it by eight words is about 30 % of that, and a row compare in `k_rows` (not marking a row dirty when the new bytes equal the old) would save more of it, at about 150 bytes of engine the engine does not have.
* `DrawTextRun` (0.11 s a key): a kernel that draws a string (not a run of one glyph) saves the setup each glyph repeats, perhaps 30 %.
* The waits are the game's pacing; GameSpeed 0 removes them.

## 5. Tools

| What | How |
|---|---|
| the menu benchmark | `build/run/mb.sh` in the worktree (builds, makes the disk and image, plays eight sessions with `MB_PCLOG`, prints the busy seconds a press of their menu part) |
| a key by key table | `python3 tools/walkstat.py build/run/prof-X.out --from T [--api] [--caller]` |
| busy time in windows | `python3 tools/timeline.py build/run/prof-X.out --win 15 --from T` |
| an instruction trace with call stacks | `tools/itrprof.py` (see 8.9d) |

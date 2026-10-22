# Step 8.9g: scrolling the combat map

Date: 2026-10-22. Follows `docs/PHASE-8.9f.md`. Tags: **[V]** measured by running it, **[E]** estimate. Built and measured in the profiling worktree on the branch `perf/scroll`.

## 1. Result

The aim cursor of the first Sleep spell of `combat-spells`, walked over the map (`tests/profile/scroll-profile.keys`: 14 moves right, 14 left, 10 down, 10 up, 8 left, 8 right; `build/run/sb.sh`), busy seconds a key press, 1.79 MHz [V]:

| Step | a scroll (13 of 64 keys) | a plain cursor move |
|---|---:|---:|
| start (main at 8325f2cc) | 0.53 | 0.094 |
| 1 DrawBuf's split row 97 -> 96 | 0.51 | 0.095 |
| 2 `DrawCellGrid`: the 49 cells in one engine call | 0.49 | 0.096 |
| 3 `k_flush`: groups of four words unrolled | 0.47 | 0.094 |
| 4 a row across a block border is staged alone | **0.44 (-17 %)** | 0.097 |

A scroll is the key that moves the cursor far enough from the centre of the 7 by 7 view: the view is centred on the cursor again (3 or 4 cells at once), so every fourth key or so redraws. The other effects of step 3 (the flush is every screen's last step): the loot screen 1.06 -> 0.96 s a key, the three fights 97.3/133.4/351.9 -> 95.5/131.1/344.8 busy seconds (-2 %).

`make step-check` (16 of 16 sessions, 0 DGROUP places open, party records, save area) passes. DrawBuf after the whole scroll script and after twelve scrolls is, row by row, the old build's (the split row moved, so the two 8 KB blocks differ; compared as 168 rows). The engine tests pass up to `t_task`; `t_vol2` fails on its full test disk (this worktree, as before).

## 2. Where a scroll goes [V]

An instruction trace with call stacks of one scroll key (`tools/itrprof.py`; 0.48 s before, 0.41 s after the steps): `ScrollViewTo` draws the 49 ground pictures (3 by 24 cells, 288 bytes) into DrawBuf, `MoveCombatCursor` redraws the combatants in view, the old cell and the cursor, and `FlushPictureChanges` copies the 168 rows of 84 bytes to the screen.

| | before | after |
|---|---:|---:|
| the 49 ground cells (`DrawCellPicture` x 49 / `DrawCellGrid`) | 0.26 | 0.19 |
| of it `k_icon` (the copy itself, 42 calls, the combatants' icons among them) | 0.08 | 0.08 |
| the flush (14 KB to the screen) | 0.11 | 0.087 |
| the prompt line and its window cleared (every key, scroll or not) | 0.09 | 0.09 |
| the combatants in view redrawn | 0.04 | 0.04 |

* The copying itself is the floor of this design: 14 KB into DrawBuf (8 cycles a byte) and the same to the screen (9 a byte now) are 0.13 s of the 0.41; the prompt line is another 0.09 and is the same on a plain move.
* What the steps removed was overhead: 17 of the 49 cells lay across DrawBuf's split row (97, the most a block holds; 96 is four cells of the map), 10 across a border of the picture's 8 KB block (the slow path staged up to 21 rows through the 256 byte buffer, now one row), 49 far calls to `DrawCellPicture` in another bank (one engine call now), and the flush's loop took 12.5 cycles a byte.

## 3. What was done

1. **`DB_SPLIT` 96** (`gfx.c`, `kernels.asm`'s `k_flush`): rows 0..95 in block 4, 96..167 in block 5. DrawBuf's contents are the same; only where the 8 KB blocks are cut.
2. **`DrawCellGrid`** (new engine call; `patches/ovl31_scrollviewto.c` replaces `ScrollViewTo`, which gathers the 49 picture codes and makes the one call): the cell at (i, j) is drawn at column 3i, row 3j with flags 0, as `DrawCellPicture` did (code above 127: item code - 128 of `SqrPaciBank2`, else item code of `SqrPaciBank1`).
3. **`k_flush`**: the span of a row is copied as the words left over after groups of four first, then groups of four words unrolled: 9 cycles a byte (12.5).
4. **`db_chunk`/`db_item_clip`**: a row that lies across a border of the picture's block is staged alone (`take = 1`), the rows after it go through `k_rows` again; a mask in another block still takes the whole staging path.
5. Engine room: `gfx_text`, `gfx_show_title`, `gfx_font_load` and `pic_load` are only called by the engine tests and are inside `#ifdef ENG_TEST` now. **The engine ends at `$7C6B` of `$7C90`: 37 bytes left.**

## 4. What is left [E]

* The copies at 6 cycles a byte instead of 8 to 9 (source read downwards with `LDD ,--U` and written with `PSHS D,X,Y` through the stack pointer, with interrupts masked for the row): about -0.04 s a scroll, -0.03 on a loot screen; the sound's FIRQ would be late by up to 0.3 ms a row.
* Moving the 42 kept cells of a one cell scroll instead of drawing them: about -0.05 s, and only for a one cell scroll (this game's scrolls are 3 or 4 cells); not built.
* The prompt line is redrawn every key (0.09 s): a string kernel for `DrawTextRun` is about -0.01 s.

## 5. Tools

| What | How |
|---|---|
| the scroll benchmark | `build/run/sb.sh` in the worktree (builds, plays `tests/profile/scroll-profile.keys`, prints the scrolls and the plain moves) |
| the busy stretches that contain a game routine | `python3 tools/scrollstat.py build/run/prof-X.out --name ScrollViewTo` |
| only the long keys among many | `python3 tools/walkstat.py RUN --min-busy 0.3` |

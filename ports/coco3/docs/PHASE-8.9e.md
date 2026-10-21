# Step 8.9e: combat (profile, six changes, what is left)

Date: 2026-10-22. Follows `docs/PHASE-8.9d.md`. Tags: **[V]** measured by running it, **[E]** estimate. Built and measured in a separate git worktree on the branch `perf/combat` (the main checkout was free for other work); merge by hand if main moved.

## 1. Result

Busy seconds of the fight part of three recorded sessions (the game working, not waiting for a key; `tools/prof_pc.py --from`, the sessions are deterministic), 1.79 MHz machine [V]:

| Step | parley-combat (6 monsters, from 225 s) | combat-spells (from 240 s) | council-guards (30 members, from 270 s) |
|---|---:|---:|---:|
| main (8051da41) | 134.8 | 184.9 | 579.5 |
| 1 the AI's target scan | 125.0 | 170.6 | 454.7 |
| 2 `SortTable` | 124.0 | 169.6 | 430.1 |
| 3 `k_icon`: the 3 by 24 cell items | 115.9 | 157.8 | 390.8 |
| 4 `k_fillrect`, the disk buffer moved | 111.7 | 151.7 | 381.5 |
| 5 the fill as an unrolled run | 107.7 | 145.9 | 372.7 |
| 6 `k_flush` | **106.1 (-21 %)** | **143.6 (-22 %)** | **368.1 (-36 %)** |

After every step the screens (labelled), the end state (0 DGROUP places open) and the party records of the three fights were compared with the originals'; after step 5 the whole `make step-check` (16 of 16, 15 states with 0 open) and the engine tests passed, and the same again after step 6 (section 6).
Busy time over all 16 sessions went from 2,374 to 2,042 s (-14 %) by step 5.

## 2. Where combat time went [V]

`tools/timeline.py` (busy time in windows, with the routines that took it), `MB_ENGCOUNT` (engine calls and their cost) and a temporary `DBG2` log in the engine (sizes of fills, icons, flushes; the pairs go to `$0A00/$0A02`, which `MB_RLOG=1` logs).

* **The typical fight (6 monsters):** about 28 % is `DelayByGameSpeed` (GameSpeed * 225 ms, the player's own setting 0 to 9 in the game; at 0 the waits are gone) and the sound's waits; 36 % was the engine drawing the combat map; the AI's scan was 5 %.
* **A big fight (30 members):** the AI was 40 %: `ScanTargets` is called once for every decision (560 calls, 330 with `MaxSteps` 1 and 202 with 255), each looks at every combatant, 16 pairs of cells a combatant, and walks a line for every pair that is in the arc.
* **Drawing, per call before the changes (the big fight):** a 3 by 24 cell opaque item (`DrawPictureItem`, 1,891 calls in the 500 s of the fight) 10.4 ms; an icon (`DrawIconPic`, 825 calls, 565 of them mirrored) 25 ms; the clear of the map (`FillPlaneRect`, 64 bytes by 168 rows) 18.5 ms; the flush to the screen (`FlushPictureChanges`, 49 rows of 42 bytes) 35 ms.
  They went through the clipped path: two staging copies out of the picture's block, `k_blit` a row at a time, and for a mirror a `MUL` a byte.

## 3. What was done

1. **`ScanTargets` and the line walk** (`patches/ovl30_*.c`, replaced as whole routines by `mkgame.py`). A pair of cells that `WalkLine` cannot reach is not walked: a line of N steps (N the larger of the two distances) ends with `First` of 2N or more, and the walk fails when `First` is above 2 * MaxSteps + 1,
   so N > MaxSteps cannot succeed; once a pair has been found a pair with 2N >= Best cannot be better. `InDirArc` (no effects) is asked last. The footprints are copied once instead of 8 far calls (`FootprintCell`) for every combatant. `WalkLine`, `StepLine` and `SetupLine` work on a pointer to
   their record on the C stack (the translation emulated a stack in the heap and made 32 bit far pointers for every call) in 16 bit. `CombatantIndex` takes its table's window once. -10 to -125 s.
2. **`SortTable`** on pointers with the keys of the record in locals; the exchanges are the original's. -1 to -25 s.
3. **`k_icon`** (engine): a 3 by 24 cell item wholly inside DrawBuf, straight from the picture's block in window 1 into DrawBuf in window 0, opaque, masked or mirrored, with the trackers; the tile path's `db_tile8` and this one are one routine, `db_blk`. The general path stays for items that are clipped, cross a block border or DrawBuf's
   split row, or whose mask is in another block. `DrawPictureItem` fell to 45 % of its time, `DrawIconPic` to 64 % (a mirrored byte still costs 89 cycles: a table of nibble swaps would take 256 bytes). -8 to -39 s.
4. **`k_fillrect`**: the rows of a `FillPlaneRect` that lie in one screen block are one call (it was one call a row). -4 to -9 s. Written first with `LEAU B,U`, whose accumulator offset is **signed**: rows of 160 bytes wrapped and the credits screen of `boot-title` showed it; `ABX` adds B as it is.
5. **The fill as an unrolled run** of 26 `PSHU D,X,Y` entered at the point that leaves the row's number of groups (the pattern stays in D, X and Y for all rows): a row is 170 cycles, was 360. -4 to -9 s.
6. **`k_flush`**: the row loop of `db_flush` in assembly, each window mapped only when it changes, a span across a screen block border copied in two parts. The trackers (`db_dirty`, `db_lo`, `db_hi`) belong to `kernels.asm`, in one block, and `rowa` is read from there. -1.6 to -4.6 s.

**Engine room.** The engine's address space ended at `$7C4F` of `$7C90` (the image of the shared data). Two buffers are out of it now: the picture staging buffers `gbuf` and `mbuf` (512 bytes) are at `$7E00` and `$7F00` (nothing is there after the boot; the loader's stack is while LOADM runs), and the disk sector buffer
and the driver's variables (289 bytes) at `$7C90`, where the image is until the boot has copied it (everything in them is set before it is read). Section names `hibss` and `dskbss` in `core.link`; `mkgame.py` leaves them out of the engine's end. **The engine ends at `$7BF6`: 154 bytes of room.**

## 4. What is left [E]

* The waits are the game's pacing: GameSpeed 0 removes them. Nothing was changed.
* The pixel kernels are what is left of drawing (`k_blit` 5 %, `k_flush` 4.7 %, `k_icon` 4.3 %, `k_fillrect` 4 % of a typical fight): memory work, about 8 cycles a byte. A mirrored icon could be 40 % faster with a nibble-swap table (256 bytes of room).
* `DrawGlyph`: 3,772 calls in two minutes of the parley fight, 1.4 ms each, the engine's C round the 1,300 cycle kernel: about 1 s a fight.
* The 32 bit helpers (`cmpDWord*`, `sub32Stack`, `copyWordToDWord`) are mostly the delay loops and the key polls: time spent waiting.

## 5. Tools

| What | How |
|---|---|
| busy time of a run by window, with the routines | `python3 tools/timeline.py build/run/prof-X.out --win 15 --from T` |
| the three fights | `build/run/cb.sh` in the worktree (builds, plays parley-combat, combat-spells and council-guards with `MB_PCLOG`, prints the busy seconds of their fight part); `python3 tools/gamecheck.py S build/run/prof-S` and `statecheck.py` then say whether the screens and the state are the original's |
| engine call counts | `MB_ENGCOUNT=t0-t1` and the sampled seconds by call (`prof_pc.py --api`) |

## 6. Verification of the whole

`make step-check` over the final code (steps 1 to 6): 16 of 16 sessions, every labelled screen equal, 15 sessions with 0 DGROUP places open (the council fight has no state comparison), party records and save area equal; busy time over all 16 sessions 2,374 s (main) to 2,028 s (-14.6 %). The engine tests pass.

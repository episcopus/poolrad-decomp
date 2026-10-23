# Step 8.9j: TFM, the 6309's block move, in the copy kernels

Date: 2026-10-23. Follows `docs/PHASE-8.9i.md` and the research in `docs/RESEARCH-6309.md`. Built on the branch `perf/tfm`. Tags: **[V]** measured in MAME (`coco3` 6809 and `coco3h` HD6309 machines), **[E]** estimate.

## 1. What it does

`TFM Y+,X+` with the count in W moves a block at 3 cycles a byte (6 + 3n); the unrolled `LDD ,Y++ / STD ,X++` of our kernels is 8 to 9. Three kernels have a 6309 path now, chosen **once per call** by `_cpu6309` (set by `boot.asm` when it put a 6309 in native mode, step 8.9h; in native mode an interrupt pushes W, which TFM uses):

* **`k_flush`'s span copy** (`@cpy`: the dirty rows of DrawBuf to the screen; the test is per row, 8 cycles on a copy of 250);
* **`k_rows`**'s opaque rows (the pictures drawn into DrawBuf: the portraits of the camp and loot screens, the 3D view's tiles);
* **`k_icon`**'s opaque rows (the combat map's ground and icons).

The 6809 paths are untouched: the same image runs on both CPUs, the engine tests and `make step-check` pass on both machines. The code is built from bytes where the assembler is `--6809` (`LDW`, `TFM`: `fcb $10,$A6,$E8,16`, `fcb $11,$38,$21`).

Not done: `k_copy` (a TFM version would cost 15 bytes of the 7 the engine has left), the masked blits (no gain: AND/OR per byte), the fills (`PSHU` is already 1.8 cycles a byte, faster than TFM's 3).

## 2. Measured [V]

Busy seconds of the whole session on the 6309 machine, native mode (step 8.9h) against native mode plus TFM, the same disk:

| Session | native | + TFM |
|---|---:|---:|
| parley-combat | 154.9 | 152.9 (-1.3 %) |
| combat-spells | 195.8 | 192.7 (-1.6 %) |
| council-guards (30 members) | 414.7 | 407.8 (-1.7 %) |
| shop-buy | 86.0 | 85.7 (-0.3 %) |
| camp-cast | 77.9 | 73.5 (-5.6 %) |
| battle-aftermath (loot) | 167.9 | 164.6 (-2.0 %) |
| character-menu | 72.4 | 72.3 (-0.1 %) |
| temple-heal | 180.4 | 178.2 (-1.2 %) |
| character-view | 58.2 | 56.7 (-2.6 %) |
| camp-save | 59.3 | 58.7 (-1.0 %) |
| temple-cast | 62.9 | 62.8 (-0.2 %) |
| **scroll script (65 keys)** | 9.8 | **8.6 (-12 %)** |
| a walking step (s) | 0.92 | 0.91 (-1 %) |

The whole sessions carry the game's timed delays and the logic, so the copy kernels are a small share; where the screen is redrawn in big pieces (the scroll, the camp's portrait) the gain is the 5 to 12 %. That is less than the 2 to 4 % over every session that the research suggested: its variant also had `k_copy`, and its baseline was the older build.

## 3. Verified [V]

| | 6809 machine (`coco3`) | 6309 machine (`coco3h`) |
|---|---|---|
| `make step-check` (16 sessions, 15 states with 0 DGROUP places open, party records, save area) | pass, busy 1,861 s (1,860 s before) | pass, busy **1,679 s** (1,704 s before: -1.5 %) |
| engine tests `t_disk` to `t_task` in MAME and XRoar | pass (22 of 22) | pass (22 of 22) |

(`t_vol2` stops while building its disk in this worktree: the disk is full, as before.) The 6809 column is the check that the test of `_cpu6309` costs nothing a 6809 can see.

## 4. Room

The engine ends at `$7C89` of `$7C90` (7 bytes left; 71 before). The picture slots cannot be given up for room: the highest slot used in the 17 sessions is 60 of 64 (the 30 member fight), and the full game has to run bigger fights.

## 5. What is left on the 6309 [E]

Hardware `MULD`/`DIVD` for the engine's `MUL16` and `DIV8` (under 1 %), `LDQ/STQ` for the 32 bit copies of the translated code (0.5 to 1 %), `CLRD` and the like by a peephole pass over the generated code (the tools exist: `tools/peep.py`); together 2 to 4 % at the price of a build step. The engine has no room left for more kernels without moving something out of it.

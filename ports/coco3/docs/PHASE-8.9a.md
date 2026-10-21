# Step 8.9a: performance, first slice (report)

Date: 2026-10-20. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.9: profile and hand-optimise hot routines; then decide the distribution (D9) and write
the real storage backends (D13). This is the first part, the profile and what it paid for at once. The distribution and the backends are not started: they
need decisions that section 6 puts to the human, with numbers. Tags: **[V]** verified by running something, **[E]** estimate, **[?]** open.

## 0. Result

* **Code bank traffic fell by 65 %** [V]: 20,123 bank loads in 15 sessions before, 6,972 after (146 MB of banks read from the medium before, 65 MB after: -55 %, the banks are bigger now). Two changes:
  banks that are used together share one 16 KB bank (`data/bank_groups.json`, made by `tools/bankgroup.py` from far call logs of the sessions), and the pool replaces
  the bank used longest ago instead of taking the banks in turn (the far call trampoline stamps every bank it enters).
* **The processor's busy time fell by 23 %** [V]: 3,289 s before, 2,545 s after, over 15 sessions on the emulated 1.79 MHz machine (combat sessions 23 to 26 %,
  exploration and menus 14 to 22 %). Busy time is the time the game is not waiting for a key: it still includes the game's own `Delay` loops (about a quarter of a fight).
  Drawing in assembly (`k_blit`, `k_mirror`, `k_mask`), a PSHU fill that writes 24 bytes in 52 cycles, `memset` by the same fill, the screen flush through the second
  window, and 16 bit arithmetic in the picture store did it.
* **16 of 16 sessions still match** [V] (`make baseline`, `tools/baseline_table.py`: screens, DGROUP places and party records, 0 open), the stress build (63 members)
  passes, and the eleven engine tests pass (`make eng-tests`; `t_vol2` had not fitted its floppy since 8.8 and is trimmed again, section 6).
* **What stays**: on a slow medium the bank loads still dominate everything. `parley-combat` is 221 s of processor and still 7 MB of banks: 560 s at the 12.6 KB/s
  of the floppy driver. Two more pool slots (32 KB) would cut that traffic by another 60 %, four by 90 % [E, from the logs]: this is the decision of section 6.

## 1. How it was measured

All of it runs in the headless MAME of the other steps, on the recorded sessions, nothing on the game side is instrumented: the Lua harness (`lua/watch.lua`) reads
RAM. A run costs 30 to 60 s of wall clock.

| Tool | What it gives |
|---|---|
| `MB_PCLOG=t0-t1` + `tools/prof_pc.py` | the program counter, the MMU task, the code bank and the engine call in progress at every video frame (60 Hz: a sample is 16.7 ms of emulated time); the report names routines from the link maps. A frame in which the game polled the keyboard is waiting, not working, and is left out (`--all` keeps it). `--unit` by unit, `--api` the engine's time by the call the game made |
| `MB_BANKLOG=t0-t1` + `tools/bankpool_sim.py` | every write of `FC_CURBANK` and `FC_X` by the far call trampoline: the sequence of banks the code ran in and the entry of each call. The simulator replays it for other pool sizes and policies (`fifo`, `lru`, Belady's `opt`); `fifo 6` gives the load count the run reported, exactly, for all 17 sessions |
| `MB_ENGCOUNT=t0-t1` | how many times each engine routine was called |
| `MB_SECLOG=1` + `tools/seclog.py` | every storage request, by kind (code banks, DAX data, the image's index, saves) and the seconds a medium of a given speed would need |
| `tools/bankgroup.py` | merges banks greedily, always the pair that saves most bytes loaded over all the logs, while they fit 16 KB; policy and pool size are parameters |
| `make perf-run S=<session>`, `make perf-all`, `make bank-groups [WRITE=1]` | the above, in one command each |

Sampling is statistical: a routine under 50 samples is noise, and the first 150 s of a session are start-up. The tools' findings were checked against the run's own
counters (`r9` = bank loads) before they were used.

## 2. Where the time went

**Combat** (`parley-combat`, the twelve rounds of Quick, 300 to 460 s of the run, before any change): the engine's drawing 55 % (`DrawIconPic` 13 %, `FillPlaneRect` 10 %,
`DrawPictureItem` 9 %, `FlushPictureChanges` 7 %, the bank loader 14 % of the time on a backend that costs no emulated time), the game's `Delay` loops about 25 %
(`frames32`, `rtl_Delay` and the 32 bit compares of the clock: pacing, not work), `memset` 3 to 4 %, the AI (`ScanTargets`, `WalkLine`, `StepLine`) 3 to 5 %. The 8.7 report
had put the AI's `ScanTargets` first; the profile puts the drawing first (the AI is 11 % of the 30 member fight of `council-guards`, where it is a lot of work). A `DrawIconPic` cost 57 ms (a 24x24 icon, mirrored): C code per row, a window switch, the shifts of `mirror_row`.

**Banks**: 23,741 far calls in a 520 s fight session, 188 distinct routines, and 3 of them make 52 % of the calls (`FootprintCell`, `HasAffect`, `snd_run`), 14 make 80 %. The pool
held six banks and took them in turn: 2,335 loads of a 10 KB bank. A fight's working set is about fifteen banks. Misses came from everywhere (`rtl_str_int` 99, `DrawCellPicture` 78,
the returns into `ovl09` and `ovl13_1` 262, ...): no single routine to move.

**Walking and shopping** are picture loads: `k_rle`, `pic_place` and `pic_load_e` with the 32 bit helpers of the compiler (`pic_place` found a free extent with 32 bit compares),
the colour key to mask loop of masked pictures (about 250 cycles a byte).

## 3. What changed

1. **Bank groups** (`tools/mkgame.py` reads `data/bank_groups.json`: lists of bank names that share one bank; the merged bank keeps the objects, loses the stubs between its
   members). Chosen for the LRU policy by `tools/bankgroup.py` on the logs of the 16 sessions: `ovl14 ovl29 ovl26`, `ovl24 ovl31`, `ovl30 res09 res12_2`, `res03 snd`, `res06 res12_1`.
   43 banks instead of 50, and the core is 140 bytes smaller (fewer far stubs). Regenerate with `make perf-all`, `make bank-groups WRITE=1`.
2. **Least recently used replacement** (`farcall.asm`, `api.c`): the trampoline writes a tick into the 12 byte stamp table at `$91` (DP) for the pool block of every bank it enters or
   returns to (9 bytes of code in two places, 18 bytes of core); the loader takes a free entry or the largest `tick - stamp` (8 bit, wraps; the simulator says it
   loses 0.1 % against true LRU). `parley-combat`: 2,335 loads with the turn-taking pool, 1,873 with LRU alone (the simulator said 1,873), 756 with the groups.
3. **Drawing** (`kernels.asm`, `gfx.c`): `k_blit` draws up to a chunk of rows of an item into DrawBuf (mask or not, mirrored or not, clipped on the left and right, trackers
   updated) from parameters in `bp`; `db_item` is the clipped blit with no clipping; `k_mirror` for `CopyPictureItem`; `k_mask` for the colour key; `k_fill` writes 24 bytes by
   four `PSHU D,X,Y` (2.2 cycles a byte, was 4.25), `db_clear_trackers` is three fills, `db_flush` copies from DrawBuf (window 0) to the screen (window 1) in one pass,
   `gfx_fill_cells` maps a screen block only when it changes. Result: `DrawIconPic` 2.8 times, `DrawPictureItem` 1.3 times faster; the engine got 650 bytes smaller (it ends at
   `$7969`, limit `$7C00`) because the 32 bit helpers went.
4. **`memset`** (`src/game/fillmem.asm`): the CMOC library's byte loop took 3 to 4 % of a fight (the game clears its 256 byte strings with it); `FillChar`, the pseudo stack and,
   by a text substitution in `mkgame.py` `patch_unit`, the translated game's own `memset` calls use the PSHU fill. (The library member that defines `memset` is linked anyway: CMOC needs it.)
5. **Picture store in 16 byte units** (`gfx.c`): `pic_place` and `pic_free` with 16 bit arithmetic; a picture starts on a 16 byte boundary. The store's high water is unchanged at 9,168
   of 9,728 units in every session.

## 4. Numbers

Per session, the same recording before (the turn-taking pool, the original banks, C drawing) and after (all of section 3): bank loads, busy seconds of emulated time, and the
whole traffic with the loads, in KB, from the image (`seclog`):

| Session | loads before | after | busy before | after | change | read after (KB) | of it banks |
|---|---:|---:|---:|---:|---:|---:|---:|
| `battle-aftermath` | 2,394 | 783 | 327 s | 243 s | -26 % | 8,143 | 7,312 |
| `boot-title` | 19 | 17 | 34 s | 29 s | -14 % | 294 | 112 |
| `camp-cast` | 244 | 128 | 130 s | 110 s | -15 % | 1,590 | 1,209 |
| `camp-rest-combat` | 158 | 96 | 97 s | 76 s | -22 % | 1,218 | 851 |
| `camp-save` | 83 | 57 | 86 s | 70 s | -18 % | 898 | 451 |
| `character-menu` | 576 | 157 | 119 s | 94 s | -21 % | 1,896 | 1,484 |
| `character-view` | 159 | 64 | 100 s | 80 s | -20 % | 868 | 533 |
| `combat-spells` | 3,311 | 1,063 | 386 s | 286 s | -26 % | 10,974 | 9,960 |
| `council-guards` | 6,682 | 2,222 | 941 s | 727 s | -23 % | 24,003 | 22,169 |
| `create-character` | 99 | 57 | 49 s | 40 s | -17 % | 733 | 496 |
| `parley-combat` | 2,335 | 756 | 298 s | 221 s | -26 % | 7,866 | 7,058 |
| `shop-buy` | 818 | 390 | 162 s | 134 s | -17 % | 4,335 | 3,758 |
| `temple-cast` | 272 | 134 | 107 s | 86 s | -19 % | 1,658 | 1,258 |
| `temple-heal` | 2,564 | 857 | 356 s | 269 s | -24 % | 8,948 | 8,042 |
| `walk-explore` | 409 | 191 | 99 s | 79 s | -20 % | 2,224 | 1,810 |
| **total** | **20,123** | **6,972** | **3,289 s** | **2,545 s** | **-23 %** | | |

(`camp-magic` is left out: its camp screen animates for the whole 2,500 s limit, so its time says nothing. `boot-title` includes the 30 s of loading the game.)

At the 12.6 KB/s the floppy driver reached in the emulator, `parley-combat` would spend 560 s of its 780 s on banks and 43 s on the image's index; `council-guards` (a 30 member
fight) 1,760 s on banks. The processor is no longer the problem of a fight; the medium is.

## 5. Why not stop at six slots: the simulator on the logs of the original layout

Groups chosen for each pool size (LRU, 17 logs; the same logs the groups are chosen from, so a little optimistic):

| Slots in the pool (16 KB each) | loads | MB loaded |
|---:|---:|---:|
| 6 (today, no groups, no LRU: the original) | 17,381 FIFO | 117 |
| 6 | 7,132 | 69 |
| 8 | 2,527 | 27 |
| 10 | 636 | 6.8 |
| 12 | 513 | 5.3 |

Pool slots are the lever: **8 slots instead of 6 cut the traffic by 60 %, 10 slots by 90 %**. A slot is two blocks; where could they come from (section 6)?

## 6. Open, and what the human has to decide

1. **Memory for the pool (D9/D12).** Today the blocks are: screen 4, DrawBuf 2, image index 2, pictures 19, stage 2, paged DGROUP 4, banked heap 8, **bank pool 12**, core 3, slot 0 and engine 4,
   **`$3C..$3F` 4 (Disk BASIC's ROM images for `DSKCON`)**. If the final medium is not a floppy read through `DSKCON` (SDC command mode, DriveWire), `$3C..$3F` become two more
   slots: 8 slots, -60 % of the traffic, no other change (a block table instead of `BANK_POOL_FIRST + 2 * k` in `api.c`, the stamp table to 40 bytes). If the floppy stays, only the
   Disk ROM's own block (`$3E`) may be needed, and one slot can still be had. Nothing was changed: it depends on the choice of media.
2. **Routine level banks.** Banks are whole units; 14 routines make 80 % of the far calls. Putting the hot, small routines of several units into one hot bank needs
   `split_unit` to cut by routine lists and a call trace that includes the calls inside a unit (the far call log does not see them). It is the other large lever, and the larger job.
3. **The image's index** costs a request or two per load: 2,172 index requests against 1,287 for the banks themselves in `parley-combat` (`img_find` scans the entries of a file from
   the image). A real backend should keep the entry table in RAM (12 KB for 1,246 entries, in the free part of the two index blocks). It is the first thing to do in the backend work.
4. **Compressed banks** (ZX0 or the like, about 40 % less to read) pay on the floppy and cost a decompressor in the engine; not done.
5. **`t_vol2`** (the test of two volumes) had not fitted its floppy since 8.8 (11,722 bytes of program against 11,520 free); the engine tests now leave out what only the game uses (`pic_remap`, `k_mirror`, the clipped blit), 11,452 bytes.
6. Left alone on purpose: the game's `Delay` loops (pacing, a quarter of a fight), the AI (`ScanTargets` 3 to 5 %: an assembly version would take a day for 3 %), `pic_place`'s search of the extents (3.6 %
   of a walk), the picture decoder `k_rle`.
7. **Still to do in 8.9**: the distribution (D9) and the real backends (D13: floppy volumes with swap prompts, SDC, DriveWire), the hardware test; real-hardware checks listed since 8.5 (vector fetch, disk speed, timer
   rate, sound through a speaker) remain open.

## 7. Reproduce

```
make game                              # the bank groups are read from data/bank_groups.json
make perf-run S=parley-combat LIMIT=520    # profile of one session: units, engine calls, pool simulation, storage traffic
make perf-all                          # every session, logs in build/run/prof-*.out and .banklog
make bank-groups                       # which banks to merge, from those logs (WRITE=1 writes data/bank_groups.json)
make baseline && python3 tools/baseline_table.py   # 16 of 16
```

## 8. Found by playing: the saved games of `make play` did not survive a rebuild (fixed)

A playtest showed a corrupted "add a character" list (the name `FOO` as `CFOO`) and then a lock up. **Cause: not the game, not the optimisation itself**, but the overlay file of saved games
(`build/play/saves.ovl`), which kept **absolute** sector numbers while the image is laid out again at every build: the 8.9a bank groups made the image two sectors shorter (6,983 to 6,981), the
save area moved from sector 6471 to 6469, and every old record landed two sectors late (the directory's header sector on top of its second and third sector: a directory with copies of itself, a
character list that read the start of `FOO.CHA`). The same thing had happened, a sector at a time, at every rebuild of the day (the overlay held copies of the header sector written at five different places).
Shown by replaying the player's keys headless on the player's saves: the pre-8.9 build (whose layout the saves had been written for) shows `FOO`, the 8.9a build `CFOO`; the 8.9a build is right on a fresh
image, on the same saves moved to their sector (the earlier ones; they were already mixed), and on all 17 sessions.

Fixed in `lua/play.lua`: the overlay is the magic `POVL`, a version, and records of a **save-area relative** sector number; only writes inside the save area are kept; an overlay in the old format is put
aside (`saves.ovl.old-format`) and a new one started, with a message. `tools/savecheck.py` (names printable and not repeated, rooms inside the area and not overlapping, the first free unit past every room)
runs from `make play` (a warning) and from `make baseline` on the saved games of every session (all 16 pass). `lua/watch.lua` reads an overlay too (`MB_OVL=`), which is how the report above was reproduced.
The old saved games of the player cannot be recovered reliably (they were already mixed from several layouts); `make play FRESH=1` or the automatic set-aside gives clean ones.

Not understood and not chased: after the corrupted list a selection locks the game up; it reads garbage as a character file. A save area that is consistent never does it.

## 9. Found by playing: paying off goblins stopped the game (money scaling had no Real arithmetic)

A playtest: the slums by Phlan, goblins, Parley, 100 gp paid, they left, then "the game ended (status 2)" and the harness started the game again (the screen full of coloured characters is the machine
restarting over RAM that was not cleared). **Most likely cause [E, not reproduced]**: the script command that takes money. ECL command 40 (`LoseMoneyAndItemsCommand`, `ovl03:1DB1`) scales the money of the selected
character or of the whole party by `(100 - Percent) / 100` through `ScaleMoney` (`ovl07:1CC3`), a Pascal `Real`; the CoCo build had no floating point and linked five stubs for it (`_rtl_trunc`, `divSingleSingle`, `initSingleFrom*`,
`mulSingleSingle`; every `make game` printed them as "missing", 8.6 listed them as open). A stub stops the program with status 2: exactly what the player saw, right after a payment. Nothing else in the game uses a Real,
none of the 17 sessions runs the command (`coverage.json` lists both routines as never run), and the encounter is random and unrecorded, so the exact script path was not replayed.

Fixed in `tools/mkgame.py` (PATCHES, ovl03 and ovl07, and the declaration in the copy of `game.h`): the factor is the percentage kept (an `s16`) and each of the seven amounts becomes `Money * Keep / 100` with a 32 bit product. The
build links with **0 symbols missing** for the first time. Checked: `probes/money.c` (15 amounts and percentages, from 0 to 65,535 and 0 to 100, against the exact integer scaling; CMOC and MAME), and a probe build that called `ScaleMoney(50, ...)`
in a running session (`camp-rest-combat`): the party record's money changed, no stop; then the 17 sessions again (16 of 16, 0 open) without the probe.

**Not exact [?]**: the original's `Real` has a 40 bit significand, so `trunc(Money * Real(100 - Percent) / 100)` can be one coin less than the integer result when the product is a whole number (a model of the format, rounding to
nearest: 1,708 of the 6.6 million combinations, 0.03 %, e.g. 1,900 gold at 53 % kept: 1,006, not 1,007; the host's `double` of Phase 7 differs from the integer in 462 other cases). Which one the original gives needs the original's
Real routines run on these values (the oracle); until then the integer result is the documented choice.

`lua/play.lua` now says why a game ended: the Halt code, a fatal's code and information, the name of the missing symbol (from `build/game/missing.txt`) and the mailbox words, so the next stop identifies itself.


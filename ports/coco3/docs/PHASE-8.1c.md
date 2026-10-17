# Step 8.1c: data model study (report)

Date: 2026-10-17. Question from step 8.1 (`PHASE-8.1.md` section 6.4 and 7): the data the C code dereferences
(45 to 58 KB) does not fit in the 64 KB map beside the code. Which data does the game logic really touch, how often,
and which of the four ways out (decision D12) does that favour? Tags: **[V]** measured by running the game,
**[E]** estimate. Reproduce with `make prof` (host side, needs `make c-golden` once in the repository root).

## Answer

**D12 recommendation: a hybrid of options A and B.** The measurement is clearer than expected:

1. **99% of all data references belong to the engine's work, not to the game's logic.** Outside the idle wait loops, the
   seven recorded sessions make 23.1 million references to DGROUP or through far pointers; **22.9 million (98.9%) are made by
   the picture, blit and text units** (`res05`, `res06`, `res07`, `res09`, `ovl28`, `ovl32`, `ovl34`), which the port
   replaces with assembly, and **0.26 million (1.1%) by the game logic**. The game logic makes a median of **135** references
   per key, 90% of keys under **3,936**, the worst key **22,392**.
2. Everything the engine touches (pictures, the two staging screens, the EGA model's tables, the DAX loader's buffers) never
   needs a C pointer: it stays behind handles the engine understands. That is option A, and it removes about 75 to 100 KB of the
   heap and 2.2 KB of DGROUP from the C code's view.
3. What is left for C is **58.6 KB of writable data** (15.9 KB of DGROUP variables, 42.6 KB of heap at its largest) and
   **10.6 KB of constants**, but the references are very uneven. Keeping the most referenced 22 KB of it mapped (the map of section 5) leaves a
   median of 0 references per key to banked data, 90% of keys under 720 and the worst key 3,323 (about 166,000 cycles at an assumed
   50 cycles an access [E]); even 8 KB mapped gives a worst key of 4,124: option B, far data accessors for the cold part, is cheap in time.
4. Far calls are cheap too: with every overlay a bank, the game logic makes **87 far calls per key at the median, 800 at the
   90th percentile, 2,465 at the worst** (176 cycles each [V], 8.0).
5. So the plan survives with the memory model changed from "native pointers everywhere" to a **placement table**: the
   translator is told for every global and every heap block class whether it is mapped (native pointer), banked (accessor) or
   engine-owned (handle). The proposal is in section 5.

## 1. Method [V]

`make prof` builds a profiling copy of the Phase 7 C game (`tools/mkprof.py`, `prof/prof_rt.c`, `scripts/prof_run.sh`; the game's
units are copied unchanged) and replays the seven recorded sessions on it:

- every routine is compiled with `-finstrument-functions`; a shadow stack gives the caller of every call (edges);
- game.h reaches DGROUP through `pool_prof_g(offset)`: a reference is counted per (routine, offset);
- every `FPD` (a far pointer made into a host pointer) is counted per (routine, heap block class); a class is a
  (size, allocating routine) pair, tracked from `rtl_getmem` and `rtl_freemem` (opt-in hooks in `c/rtl/heap.c`, `crt.c`);
- an interval ends when the game reads a key (`rtl_ReadKey`): the figures per key are per interval. The sessions give
  **151 intervals** (a session is 14 to 28 keys).

`tools/prof_report.py` joins the counts with the unit of each routine, the names of the globals (`c/game/globals.txt`) and the
heap classes. A "reference" is one evaluation of a macro naming a global or an `FPD`; a block copied with `rtl_Move` counts once.

**Idle polling is left out.** The game waits for a key or a time by polling the clock in a loop (`WaitKeyOrTimeout` inside
`ReadPromptChoice`, the title screen loop, `WaitHundredths`). 23.3 million DGROUP references and 10.8 million dereferences (of
41.5 and 15.8 million) are that spinning; how often it spins depends on the machine's speed, not on the game.

**What this does not show:** the sessions are short (create a character, walk, camp, save, two combats). Scripts (ECL) in towns,
shops, spells and the late game are not exercised; `GameVars` and the ECL buffer (ovl07) will be busier there. The instrumented
`parley-combat` session diverges from the recording after 4.89 of 7.39 million reads (the normal build, and the profile build
without `-finstrument-functions`, pass it): the instrumentation changes stack layout, so the C translation reads some
uninitialised stack memory somewhere. Harmless for these counts, a defect to find in the host build of step 8.2.

## 2. Who does the referencing [V]

Outside the idle loops (`make prof`, the report's first two tables):

| Referencing unit | References | Share |
|---|---:|---:|
| engine units: `res05` (DAX loader), `res06`, `res07`, `res09` (blits, text), `ovl28`, `ovl32`, `ovl34` (pictures, 8x8 symbols) | 22,871,934 | 98.9% |
| everything else (game logic, 28 units) | 261,363 | 1.1% |

The most referenced globals are all the EGA model: `EgaPlaneBitMasks` (10.8 M), `EgaPlaneMasks`, `EgaScanlineOffsets`,
`RowLastChangedOfs`, `DrawBuf`, `FillPageSegment`, `ActivePageSegment`, `GameFont`, `Raw70C7`, the dirty-row tables: 100% from
the blit units. The most dereferenced heap classes are the picture records (14,136, 3,896, 32,024, 1,464 bytes ... allocated by
`AllocatePicture`) and the DAX buffers (`AllocHeapBlock`, `LoadDaxBlock`): 100% from `res07` and `res05`.

## 3. What the game logic sees [V]

### 3.1 DGROUP

| | Entries | Bytes | Note |
|---|---:|---:|---|
| constants referenced by game logic | 63 | 10,586 | 8,643 by one unit only, 1,943 by several |
| variables referenced by game logic | 202 | 15,932 | 5,709 by one unit only, 10,223 by several |
| variables referenced only by the engine (EGA tables, dirty rows, font pointer ...) | | about 1.4 KB | go with the blitters |

The constants image (17,370 bytes, read-only in practice, step 8.1): **static** use by name in the generated C, entries counted
once: 3,635 bytes named by one unit, 6,042 by several units, 7,693 not named by any unit (reached through offsets or only by
the engine). Adding the constants a unit alone names to its code and constants, **every unit still fits a 16 KB window except
`ovl16`** (23,976 bytes with 1,268 of its own constants; it splits). `ovl13` (15,960), `ovl12` (15,783), `ovl03` (15,768) and
`ovl22` (15,080) stay under 16,384 by 0.4 to 1.3 KB: the margin is thin, so `-fomit-frame-pointer` (2.5%, 8.1) matters.
The 6 KB shared by several units is pinned (or copied into each bank that names it: spare physical RAM allows it).

### 3.2 Heap blocks the game logic dereferences (largest live bytes in any session)

| Block class (size, allocated by) | Live max | Derefs per key | Main units |
|---|---:|---:|---|
| 312 bytes, `AllocatePicture` (42 blocks: small picture records) | 13,104 | 105 | ovl17, res12, ovl16, ovl09, ovl13 |
| 7,680, `StartGame` (the ECL buffer) | 7,680 | 32 | ovl07, ovl03, ovl11, ovl17 |
| 2,048, `StartGame` (two game-variable blocks) | 4,096 | 14 | ovl20, ovl07, res12, ovl03 |
| 72 bytes, `AllocatePicture` | 2,952 | 20 | ovl17, ovl16 |
| 2,344, `StartGame` (wall tiles) | 2,344 | 221 | ovl29 |
| 1,024, `StartGame` (GEO block, `TBlock400`) | 2,048 | 32 | ovl29, ovl07, ovl11, ovl17 |
| 288 bytes, `LoadGame` (character records) | 1,728 | 71 | res12, ovl23, ovl15, ovl17, ovl20 |
| 288 bytes, `AddEncounterGroupCommand` (monster records) | 1,440 | 20 | res12, ovl13, ovl10, ovl03, ovl08 |
| 1,264, `CreateCombatMap` | 1,264 | 47 | ovl10, ovl31, ovl30, res12, ovl13 |
| the rest (items, affects, 64-byte blocks, DAX leftovers) | about 6 KB | | |
| **Total** | **42,624** | | |

The 42 blocks of 312 bytes are picture records of small icons that game logic looks at (a header field) but never
draws from: an engine call such as `PictureWidth(handle)` would take them out of C's view (about 13 KB), so 42.6 KB is an
upper bound.

### 3.3 How far calls and data references fall per key [V]

| Per key | Median | 90th percentile | Worst |
|---|---:|---:|---:|
| references to data by game logic | 135 | 3,936 | 22,392 |
| far calls, every overlay a bank, resident units pinned | 87 | 800 | 2,465 |
| far calls, every unit its own bank | 87 | 877 | 2,495 |
| far calls, overlays banked and the blit and text units pinned, other resident units banked | 40 | 295 | 2,046 |

At 176 cycles a far call [V] the worst key costs 433,840 cycles (0.24 s at 1.79 MHz), the 90th percentile 140,800 (0.08 s).
The hot paths are the same as the static count of 8.1: `ovl03` to `ovl07`, `ovl12` to `ovl24`, `ovl13` to `ovl31`.

## 4. The four options against the numbers

| Option | What the measurements say |
|---|---|
| **A. Two-level data (engine-owned data behind handles)** | Right for 99% of the references and for 75 to 100 KB of heap. Cost: the engine API has to cover every access the picture units make (they are already one layer: `DrawPictureItem`, `ShowPicture`, `LoadPicture` ...), plus a few header accessors for the small picture records. **Take it.** |
| **B. Far data accessors for the cold part** | The game logic's own data is 58.6 KB but its references are skewed: with 22 KB kept mapped, banked references per key are 0 (median), 720 (p90), 3,323 (worst); with 8 KB, 57, 1,196, 4,124; with 32 KB, 0, 720, 1,067 (the greedy choice is not monotonic). At 50 cycles an access the worst key is 53,000 to 206,000 cycles. **Take it for the part that does not fit.** The code growth of the accessors is not measured yet |
| **C. Two address spaces (task 0 / task 1)** | Not needed: the references are so few that copying arguments would cost more than banked access. Dropped |
| **D. Shrink the data** | Worth doing as part of A: the EGA tables, a smaller stack (the original's 16 KB is not needed with CMOC frames), the unused 20% of DGROUP variables (80 of 286 never referenced). Not enough alone (saves about 5 KB of 58) |

## 5. Proposed memory map under the hybrid

Logical map, task 0. 63.75 KB are usable (the top 256 bytes are I/O, the `$FE00` page holds vectors). Sizes in KB:

| Slots | Content | KB |
|---|---|---:|
| 0 to 3 and the part of 7 below `$FE00` (39.5 KB) | direct page, engine variables, mailbox | 0.5 |
| | stack | 3 [E] |
| | engine and runtime library | 8 [E] |
| | constants named by several units | 6 (3.1) |
| | **hot data**: writable variables and heap blocks the game logic references most | **22** (the rest of the 39.5) |
| 4 and 5 (`$8000` to `$BFFF`) | **code window**: one overlay, or a resident game unit (`res12`, `res04`, `res08`) treated as one more bank | 16 |
| 6 (`$C000` to `$DFFF`) | **data window**: one 8 KB page of the banked cold data (the engine uses the same slot as its picture aperture) | 8 |

Resident game units in the window means more far calls, already counted: the "every unit its own bank" row of 3.3 (87 per
key at the median, 877 at the 90th percentile, 2,495 at the worst). The alternative, `res12` and its two small neighbours
pinned (15.3 KB), leaves only 7 KB of hot data; the table of section 5.1 shows the cold-data traffic stays acceptable
even then (below).

### 5.1 Banked references per key against the size of the hot set [V]

Items ranked by references per byte; the best that fit the budget stay mapped, the rest are banked. The entries overlap
slightly, so the budgets are approximate.

| Hot data kept mapped | Banked references per key: median | 90th percentile | worst | worst key at 50 cycles each [E] |
|---:|---:|---:|---:|---:|
| 8 KB | 57 | 1,196 | 4,124 | 206,000 |
| 16 KB | 5 | 722 | 3,987 | 199,000 |
| **22 KB (the map above)** | 0 | 720 | 3,323 | 166,000 |
| 24 KB | 0 | 440 | 3,324 | 166,000 |
| 32 KB | 0 | 720 | 1,067 | 53,000 |
| 40 KB | 0 | 372 | 838 | 42,000 |

What stays mapped at 24 KB, by references: `WallSets` and its 2,344-byte block (221 per key), the character records
(`LoadGame` 288-byte blocks), the combat map (1,264) and its pointer, `EclCode`, `CombatantTable`, `GeoBlock`, `SortEntries`,
`EclStrings`. What is banked (40.7 KB): the 312-byte picture records (13.1 KB, 105 references per key: first candidates for
engine header accessors), the 7,680-byte ECL buffer (32 per key), the 2,048-byte game-variable blocks (14), `ItemTable`
(4), `PictureSlots` (2), `CellOccupant` (2).

Combined worst case at the 22 KB setting: 166,000 cycles of banked data access plus 439,000 of far calls on the worst key
(0.34 s at 1.79 MHz) if both peaks fall on the same key; the median key costs 15,000 cycles of far calls.

What is mapped, banked and engine-owned (the placement table the translator reads; numbers from section 3):

| Class | Where | Bytes |
|---|---|---:|
| Pictures, staging screens, DAX buffers, EGA tables | engine-owned, handles | 75 to 100 KB heap, about 1.4 KB DGROUP |
| Hot variables and heap blocks | mapped, native pointers | about 22 KB |
| Cold blocks (the ECL buffer, the game-variable blocks, `ItemTable`, `PictureSlots`, `CellOccupant`, the small picture records until the engine takes them) | banked, accessors | about 40 KB |
| Constants named by one unit | that unit's bank | 3.6 KB |
| Constants named by several units | pinned (or copied per bank) | 6.0 KB |
| Constants nobody names (engine tables, text) | engine bank or a read-only data bank | 7.7 KB |

## 6. What this asks of step 8.2 (the translator profile)

1. **A placement table**, a TOML file in `ports/coco3/` (global or block class, mapped/banked/engine, bank): the translator
   emits a native pointer, an accessor call (`bd_read16(class, offset)`) or an engine handle accordingly. The classes are the
   (size, allocating routine) pairs of this report, so the table can start from `build/prof/*.prof`.
2. **Two heaps**: the mapped heap keeps the Turbo Pascal allocator's behaviour; banked blocks come from a block allocator in
   physical memory. `New`, `GetMem` and `Dispose` sites choose by class (the allocating routine is known statically).
3. **Engine API for the picture units** (list from section 2) and the small-picture header accessors.
4. The construct list of 8.1 (`PHASE-8.1.md` section 2.1) and the two CMOC bugs.
5. **The host build first** (guide section 8): run the placement on the host with the accessors as ordinary functions over a
   64 KB window model, replay the sessions, and count the banked references there; this also finds the uninitialised read of
   section 1.

## 7. Risks and what is not settled

- **Coverage.** Seven short sessions: the 135 / 3,936 / 22,392 figures are for what they cover. Scripts, shops and the late
  game are not in them. Re-run `make prof` when more sessions exist (`tests/sessions`; playbook 40).
- **Accessor cost** (50 cycles) and **code growth** from accessors are estimates; the 8.3 engine test can measure the first,
  the 8.2 host build the second.
- **Pointers stored in banked data** (a block that holds a pointer to a mapped block, or the reverse) need a rule: pointers
  in banked blocks are 3-byte far values, in mapped blocks 2-byte. The saved files contain heap pointers (whitepaper appendix D);
  D7 already routes them through byte-order helpers.
- **Heap fragmentation** is not modelled: classes were counted at their largest live size, not with allocator overhead.
- The hot area (22 KB) rests on the engine and runtime size (8 KB) and the stack (3 KB), both still estimates; 8.3 measures the engine.

## 8. Reproduce

```sh
cd ports/coco3
make prof          # builds build/prof (repository root), replays the sessions, prints the report
python3 tools/constplace.py ../.. build/m/sizes-base.tsv    # constants placement (after make sizes)
```

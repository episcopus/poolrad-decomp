# Step 8.1: measure (report)

Date: 2026-10-17. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.1. Tags as in the guide: **[V]** verified here
by running a tool, **[E]** estimate, **[?]** open. Reproduce with `make sizes` (the 6809 sizes, in the container) and
`make heap-stats` (the host side: heap and DGROUP over the recorded sessions); `make test` still passes.

## Summary

> **Superseded in part by 8.2** (`PHASE-8.2.md`): the sizes below were measured on text-patched C in which byte arithmetic with constants was silently computed in 8 bits. With the translator's width casts (`pas2c --profile coco`) the 35 overlays are 219,273 bytes of code (1.11 times the x86), and three units (`ovl03`, `ovl13`, `ovl16`) need splitting for a 16 KB window. The findings about D4, the data model and the CMOC bugs stand.

1. **Code size is not the problem.** All 46 generated units of Phase 7 (35 overlays and 11 resident game units) compile
   with CMOC 0.1.100 once a handful of mechanical fixes are made (section 2). The 35 overlays come to **209,542 bytes of
   code plus 10,832 of constants, against 197,641 bytes of x86 (1.06 times)**, below the guide's 180 to 300 KB estimate.
   With `-fomit-frame-pointer` the whole game is 2.5% smaller (section 3).
2. **A 16 KB code window is enough.** Only `ovl16` (22.7 KB) is larger, and it splits at routine boundaries into 14.5 KB and
   7.5 KB. The largest single routine is `CreateCharacter` at 9,172 bytes, so an 8 KB window cannot work without refactoring
   that routine. 35 overlays pack into 14 banks of 16 KB (section 4). **D4: 16 KB window, confirmed from numbers.**
3. **The addressing model is the real problem, and it is bigger than the guide assumed.** The generated C reaches the
   game's data through far pointers into 640 KB; the CoCo's CPU sees 64 KB at a time. What the C code touches at once is
   about 15 KB of writable globals plus 29 to 41 KB of heap plus a 16 KB code window plus the resident code: more than
   the 64 KB logical space by 10 to 55 KB (section 6). The plan's step 8.2 ("native globals and native pointers") cannot be
   carried out as written. I propose a data-model study as step 8.1c before 8.2 and a new decision D12 for you (section 7).
4. **Physical RAM is enough.** The measured totals fit in 512 KB with about 35 to 55 KB to spare (section 6.3).
5. Two **CMOC 0.1.100 code generation bugs** were found and reproduced in minimal probes (section 2.2).

Exit criterion ("size table per unit; window size and data-bank decisions (D4) made from numbers"): the size table is
section 3, the window size is decided (section 4), the data-bank decision is turned into a numbered problem with options
(sections 6 and 7); it needs your call.

## 1. Method, and what the numbers do and do not mean

`../../c/game/*.c` (the Phase 7 translation of the matched Pascal) is compiled unit by unit with the port's CMOC flags
(`--void-target --no-relocate -O2`). It cannot be compiled as it is: it models a 1 MB arena, 32-bit far pointers and EGA
planes. The steps, all mechanical and listed in section 2:

- `tools/mkshim.py` writes a CMOC version of `c/include/pool.h`: `farptr` is a native 16-bit pointer, DGROUP is address 0
  (`pool_ds`), `FPD(T, p)` is a plain cast. **This is the best case for code size**: 16-bit pointers instead of 32-bit.
- `tools/cmocify.py` rewrites the constructs CMOC cannot parse.
- `tools/unitsizes.py` compiles each unit and reads the section sizes from `lwobjdump`; the x86 size is `code_bytes` of
  `re/units.toml`.

What is **not** in the numbers: the runtime library the units call (`rtl_*`: strings, sets, files, heap), the sound driver
(`res03` is `RES03.ASM`, 6,192 bytes of x86, shown here as the 559-byte C part only), and anything the port will replace
(the EGA model of `res06`, `res07` and `res09` is about 18.6 KB of CMOC code that becomes an assembly engine). The units were
**compiled, not run**: the shim changes the program's memory behaviour, so correctness is for 8.2's host build to prove.

## 2. What CMOC could not read, and the fixes

### 2.1 Mechanical transforms (`tools/cmocify.py`)

Counts are occurrences over all units. Every one is a requirement for the CoCo profile of the translator (step 8.2).

| Construct in the generated C | Count | CMOC 0.1.100 | Fix applied here |
|---|---:|---|---|
| parenthesised declarator `T (*Name)`, cast `T (*)` | 3,288 | syntax error | `T *Name`, `T *` |
| pointer to array `T (*)[N]` (casts, parameters, global array macros) | 658 | **syntax error; `(*p)[i]` on a pointer to an array typedef is "array reference on non array"** | a wrapper struct `struct PA_T_N { T a[N]; }` and `p->a[i]` (165 wrappers) |
| `&Array` passed as a pointer to the array | 100 | "unsupported indirection" or a type mismatch | the wrapper pointer, or a cast |
| pointer to an array typedef (`TPictureShown *Shown`) | 371 | same | rewritten to the explicit form first |
| compound literal `(const u8 *const[]){a, b}` for string concatenation | 233 | not supported | variadic `rtl_str_cat(dst, n, a, b)` |
| `= {0}` initialisers | 188 | invalid for arrays of structs and structs with arrays | dropped (Pascal did not initialise locals) |
| enumerators of 32 bits (`PROC_x = 0x1041016AU`) | 174 | enum values are 16-bit | numbered 1.. (only distinctness matters) |
| 32-bit and negative enumerators (`HundredthsPerHour = 360000`, `MissRoll = (-1)`) | 14 | "must be constant" / see 2.2 | `#define` with `L`, or an unsigned byte constant |
| video plane addresses `pool_arena + 0xB8000` | 14 | beyond 16 bits | a 16-bit address (the EGA model goes away) |
| void operand in a comma expression (`rtl_write_str(...), rtl_write_ln(...)`) | 20 | error | split into two statements |
| `x -= y;` | 44 | **bug, section 2.2** | `x = x - y;` |
| anonymous unions in records (variant records) | 2 | not supported | members side by side (layout differs, code does not) |
| `typedef u8 T[65520]` | 1 | arrays stop at 32,767 | capped |
| `(s32)record.Data` (array to long cast) | 1 | "casting from array to long is not supported" | `*(s32 *)&...` |
| `#pragma pack` | 2 | unknown | dropped (CMOC does not pad) |

The same list in one sentence: CMOC cannot do pointers to arrays, parenthesised declarators, compound literals, 32-bit
enumerators and anonymous unions, all of which Turbo Pascal's var parameters, array typedefs, `Concat` and variant
records produce. The translator will emit CMOC's subset directly rather than patch text afterwards.

### 2.2 Two bugs in CMOC 0.1.100 [V]

Both found in `ovl12`, both reproduced in minimal probes (`make asm-probe P=...`):

1. `probes/asm/cmoc-bug-decb.c`: `Morale -= Step;` for a byte at a fixed address, with a constant right-hand side, compiles
   to `DECB #$05`, which is not an instruction (at `-O1` and `-O2`; the optimizer then stops with "failed to determine
   registers affected by opcode"). Workaround: `Morale = Morale - Step;`.
2. `probes/asm/cmoc-bug-negbyte.c`: `*(signed char *)0x6822 = -1;` emits `LDB #$FFFF`, which lwasm rejects ("Byte overflow").
   The same store through a pointer variable is correct (`LDB #$FF`). Workaround: store the unsigned byte constant.

Both only occur when the object is a literal address, which is exactly how the DGROUP globals of the generated C are
written; a build whose globals are real C variables would avoid them, but the translator must not emit these two shapes.

## 3. The size table [V] (`make sizes`)

CMOC `-O2 --no-relocate`, sizes in bytes; "ratio" is CMOC code over x86 code (not shown for units under 100 bytes); `res03`
is the assembly sound driver (only its C wrapper is compiled), `res02`, `res10` and `res11` are empty initialisation parts.

| Unit | x86 code | CMOC code | ratio | rodata | code + rodata | with `-fomit-frame-pointer` |
|---|---:|---:|---:|---:|---:|---:|
| ovl00 | 190 | 87 | 0.46 | 100 | 187 | 82 |
| ovl01 | 2062 | 1458 | 0.71 | 513 | 1971 | 1436 |
| ovl02 | 862 | 624 | 0.72 | 295 | 919 | 603 |
| ovl03 | 13581 | 15374 | 1.13 | 394 | 15768 | 14906 |
| ovl04 | 3895 | 3338 | 0.86 | 623 | 3961 | 3371 |
| ovl05 | 5750 | 5377 | 0.94 | 595 | 5972 | 5259 |
| ovl06 | 1949 | 1579 | 0.81 | 324 | 1903 | 1605 |
| ovl07 | 8730 | 10240 | 1.17 | 175 | 10415 | 10104 |
| ovl08 | 4735 | 4490 | 0.95 | 332 | 4822 | 4407 |
| ovl09 | 6439 | 6358 | 0.99 | 130 | 6488 | 6421 |
| ovl10 | 8082 | 9021 | 1.12 | 79 | 9100 | 8930 |
| ovl11 | 1562 | 1647 | 1.05 | 84 | 1731 | 1642 |
| ovl12 | 14510 | 14842 | 1.02 | 605 | 15447 | 13999 |
| ovl13 | 15474 | 15452 | 1.00 | 504 | 15956 | 15488 |
| ovl14 | 4268 | 5808 | 1.36 | 125 | 5933 | 5654 |
| ovl15 | 8158 | 7324 | 0.90 | 1095 | 8419 | 6955 |
| ovl16 | 17497 | 22019 | 1.26 | 689 | 22708 | 20507 |
| ovl17 | 9189 | 9297 | 1.01 | 330 | 9627 | 8933 |
| ovl18 | 2299 | 2139 | 0.93 | 446 | 2585 | 2145 |
| ovl19 | 11026 | 11332 | 1.03 | 1016 | 12348 | 10467 |
| ovl20 | 3685 | 3679 | 1.00 | 197 | 3876 | 3581 |
| ovl21 | 8795 | 9921 | 1.13 | 429 | 10350 | 9583 |
| ovl22 | 14261 | 14312 | 1.00 | 764 | 15076 | 14131 |
| ovl23 | 1123 | 1544 | 1.37 | 32 | 1576 | 1555 |
| ovl24 | 6455 | 5746 | 0.89 | 309 | 6055 | 5721 |
| ovl25 | 4682 | 5078 | 1.08 | 63 | 5141 | 4941 |
| ovl26 | 677 | 892 | 1.32 | 32 | 924 | 867 |
| ovl27 | 648 | 665 | 1.03 | 34 | 699 | 660 |
| ovl28 | 1989 | 2369 | 1.19 | 96 | 2465 | 2183 |
| ovl29 | 4619 | 5866 | 1.27 | 126 | 5992 | 5661 |
| ovl30 | 3038 | 3374 | 1.11 | 32 | 3406 | 3264 |
| ovl31 | 4864 | 5551 | 1.14 | 32 | 5583 | 5468 |
| ovl32 | 1605 | 1761 | 1.10 | 97 | 1858 | 1745 |
| ovl33 | 252 | 218 | 0.87 | 37 | 255 | 215 |
| ovl34 | 690 | 760 | 1.10 | 98 | 858 | 751 |
| res02 | 16 | 1 | n/a | 32 | 33 | 1 |
| res03 | 6192 | 559 | 0.09 | 36 | 595 | 534 |
| res04 | 336 | 332 | 0.99 | 39 | 371 | 299 |
| res05 | 2416 | 2501 | 1.04 | 85 | 2586 | 2347 |
| res06 | 3984 | 4618 | 1.16 | 82 | 4700 | 4472 |
| res07 | 10832 | 13068 | 1.21 | 38 | 13106 | 13484 |
| res08 | 912 | 893 | 0.98 | 208 | 1101 | 890 |
| res09 | 880 | 936 | 1.06 | 32 | 968 | 960 |
| res10 | 16 | 1 | n/a | 32 | 33 | 1 |
| res11 | 16 | 1 | n/a | 32 | 33 | 1 |
| res12 | 12464 | 13534 | 1.09 | 264 | 13798 | 13532 |
| **total** | **235705** | **245986** | **1.04** | **11712** | **257698** | **239761** |

Totals by kind [V]: **overlays 197,641 bytes of x86, 209,542 of CMOC code (1.06) plus 10,832 of constants**; resident game
units 31,872 of x86 (without `res03`), 35,885 of CMOC code (1.13). About 1.5 KB of the constants are one 32-byte table (`StatusKilled`, `static const` in
`game.h`) that every unit carries.

- **Spread:** 16 of the 42 units that can be compared (not `res03` and the three empty ones) come out the same size or smaller than the x86; the worst are `ovl14` (1.36), `ovl23` (1.37), `ovl26`
  (1.32), `ovl29` (1.27) and `ovl16` (1.26), all drawing or character-editing code with many byte-record fields. The big units
  that decide the bank layout: `ovl13` 1.00, `ovl22` 1.00, `ovl12` 1.02, `ovl03` 1.13, `ovl16` 1.26.
- **Optimization level:** `-O1` costs 14.7% (270,950 bytes in total) and `-fomit-frame-pointer` saves 2.5% (239,761), most on
  `ovl16` (22,019 to 20,507) and `ovl12` (14,842 to 13,999), while `res07` grows (13,068 to 13,484). The flag is documented as
  experimental; it needs the test suite before use, and it does not change any window decision.
- **Routines:** 804 routines; 38 are over 1 KB, 10 over 2 KB, one over 4 KB and none over 10 KB. The largest are
  `CreateCharacter` 9,172 (ovl16), `ModifyCharacter` 3,280 (ovl16), `AppraiseGems` 3,014 (ovl21), `DrawWallView` 2,524 (ovl29),
  `BuildTreasureItem` 2,425 (ovl21). Frames over 127 bytes (16-bit offsets) were not counted.

## 4. Window size (decision D4) [V]

| Window | Result |
|---|---|
| 8 KB (one slot) | **Impossible without refactoring**: `CreateCharacter` alone is 9,172 bytes; 11 overlay units are over 8 KB |
| 16 KB (two slots) | Every unit fits except `ovl16` (22,708 with constants), which splits at routine boundaries into 14,478 and 7,541 bytes (12 and 7 routines). `ovl13` (15,956), `ovl03` (15,768), `ovl12` (15,447) and `ovl22` (15,076) fit with under 1.3 KB to spare, before the bank's entry table |
| 24 KB (three slots) | Not needed; it would take a third of the logical space (section 6) |

**Pack count:** the 35 overlay units with `ovl16` split, first-fit decreasing into 16 KB banks (affinity between units
ignored): **14 banks at 96% fill**; adding the resident game units: 16 banks. In 24 KB banks: 10.

**Recommendation for D4: a 16 KB code window (slots 4 and 5)**. What would change it is section 6.

## 5. Calls between units [V] (`tools/unitgraph.py`, static references in the generated C)

- 2,348 references from one unit to a routine of another unit: **1,138 go to resident units**, 1,162 are overlay to overlay.
- **194 routines of overlay units are named from other units**: that is the number of far-call stubs if every overlay is a bank.
- The hot overlay pairs (static count): `ovl03` to `ovl07` 205, `ovl12` to `ovl24` 89, `ovl13` to `ovl31` 72, `ovl22` to `ovl24` 69,
  `ovl16` to `ovl25` 33. `ovl24` (311 references from other overlays), `ovl07` (the ECL interpreter, 208), `ovl31`
  (171) and `ovl25` (119) are the units most called from other overlays: they should share a bank with their callers or stay
  mapped.
- The resident units are called from everywhere (1,138 references): they cannot be behind a 176-cycle far call without a
  measurement of how often each is called; the sensible default is to keep them mapped (pinned) or call them directly from
  every bank.

## 6. Memory: what the sessions need [V] (`make heap-stats`, seven recorded sessions)

### 6.1 The heap (open question Q4)

- **Peak in use: 182,984 bytes**, in start-up and the title screen, identical in all seven sessions (top of heap 215,264).
  It is two 36,887-byte pictures (`AllocatePicture` in `StartGame`), the 36,881 and 35,760 and 34,016 byte blocks `LoadPicture`
  unpacks from, two 32,023-byte title pictures with their 32,017 and 24,624 byte sources. All of it is transient except the
  two staging pictures.
- **In the game (live at the end of a session): 118,936 to 142,560 bytes.** Of that, **2 x 36,888 are the two staging
  buffers** (`DrawBuf`, the off-screen copies of the picture; on the CoCo these are the two screens), **14,136 is one picture**
  (allocated in `StartGame`), and what is left is **45 to 69 KB**:
  the loader's blocks (2 x 2,048, 1,024, 7,680 ECL buffer, 1,416, 2,344, 1,024: 17.6 KB), a few picture banks (1,016, 1,464,
  three of 2,264 when an area is loaded) and **small blocks (characters, items, affects, combat records): 11 KB at the
  main menu, 20 KB walking, 23 KB in combat** (139 blocks).
- Allocation pattern: 1,213 allocations and 1,057 frees in the combat session; every free matched a live block.

### 6.2 DGROUP (open question Q4) [V], a floor on what is written

DGROUP is 34,656 bytes: 2 for Turbo Pascal, **17,370 of typed constants (initialised data)**, 17,284 of zeroed variables.

- **No byte of the 17,370-byte constants image changed in any of the seven sessions.** It is read-only in practice (spell
  and class names, the item table, the area map template, menu texts, `Raw10A7`, ...). It can live in a banked read-only data
  bank, not in the 64 KB the code sees. (A lower bound on "written": a byte written and restored is not seen; the sessions
  cover creation, camp, save, a walk and two combats, not every screen.)
- Of the 17,284 variable bytes, **4,099 are nonzero at the end of at least one session** (23%).
- The Borland runtime owns only **708 bytes**: System, Overlay and heap variables 84, Crt variables 24, `Input` and `Output` 512, the saved
  interrupt vectors 88. Dropping it saves almost nothing; the EGA model's tables (scanline segments, dirty-row trackers) are
  about 2.2 KB more that go with the blitters.

### 6.3 Physical RAM (512 KB = 64 blocks of 8 KB): it fits

| Item | KB | Basis |
|---|---:|---|
| BASIC low RAM and ROM images (blocks `$38`, `$3C` to `$3F`) | 40 | guide 3.3; 0 if the port stops using DSKCON |
| Two screens | 64 | 2 x 32,000 bytes, replacing the two 36,888-byte staging buffers |
| Writable DGROUP | 17.3 | 17,284 + 2 |
| Constants image (banked, read-only) | 17.4 | 17,370 |
| Heap without the staging buffers | 45 to 69 | 6.1 (the pictures here are the biggest part) |
| Game code and constants | 256 | 209.5 + 35.9 code + 10.8 constants, section 3 |
| Engine, runtime library, sound | 15 | [E] |
| **Total** | **455 to 478** | of 512: about 35 to 55 KB spare |

The title-screen transient (a further 64 KB on the PC) is avoided by decoding pictures straight into screen memory.

### 6.4 The logical address space (what the CPU sees at once): it does not fit

The generated code follows pointers from anywhere to anywhere. For the C code to run unchanged on native pointers, what it
touches in one piece of work has to be in the 64 KB map together (minus 256 bytes of I/O and the `$FE00` vector page):

| Item | KB | Basis |
|---|---:|---|
| Direct page and engine variables | 0.5 | |
| Writable DGROUP | 15 to 17 | 6.2 (the EGA tables, 2.2 KB, go) |
| Heap that the C code dereferences | 29 to 41 | loader blocks 17.6 + small blocks 11 to 23 (6.1); the pictures are only handed to the blitters |
| Stack | 2 to 4 | [E] (the original's was 16 KB; CMOC frames are small) |
| Code window | 16 | section 4 |
| Pinned code: engine, runtime, resident game units | 8 to 45 | engine and runtime about 8 [E]; the resident game units are 35.9 KB of CMOC code, of which the blitter units (`res06`, `res07`, `res09`, 18.6 KB) are replaced by assembly of unknown size |
| **Total** | **71 to 124** | against about 63.5 available |

Every column of this table is measured except the stack and the engine, and the conclusion does not depend on them: **the
set of data the C code needs at once (45 to 58 KB) leaves no room for the code**, never mind a 16 KB window. The guide's
section 3.4 saw this ("globals that do not fit go into a data bank reached through accessors; measuring this is task 8.1");
the measurement says it is not a few cold tables but most of the data.

## 7. What this changes in the plan (needs your decision)

The memory model of Phase 7 is the PC's: any code can reach any heap block through a 32-bit pointer. The 6809 reaches 64 KB.
Four ways out, none free; the cost column is my estimate, not a measurement:

| Option | What it is | Cost |
|---|---|---|
| **A. Two-level data** | Hot C data (about 33 KB: writable DGROUP, the loader's blocks, the small blocks) stays in the 64 KB map as native pointers. Pictures and everything only the blitters read stay behind engine handles (a picture is a bank and an offset the asm reads physically). The code window shrinks to 8 KB or the resident game units move into banks too | The 8 KB window needs `CreateCharacter` (9.2 KB) refactored; many more far calls (the resident units: 1,138 static references); still tight |
| **B. Far data accessors** | Pointers into big blocks (the ECL buffer 7.7 KB, the two 2 KB game-variable blocks, `ItemTable` 2 KB, `PictureSlots` 2 KB, `EclStrings` 3.8 KB, about 20 KB) become 3-byte (bank, offset) values read through a data window and accessor calls | Code growth in the units that touch them (ovl07 reads game variables constantly); slower script interpreter |
| **C. Two address spaces** | Run the game logic in MMU task 0 and the engine in task 1 with a copy-in/copy-out protocol for each call | Every engine call (blit, text, DAX load) copies its arguments; the pictures stay in task 1. Heavy |
| **D. Shrink the data** | Remove what the port does not need: the EGA tables (2.2 KB), the 16 KB stack to 4 KB, load a script's strings on demand, free the loader's second 2 KB game-variable block | Saves 10 to 15 KB of 55; useful with A or B, not enough alone |

My recommendation: **an extra step 8.1c, "data model study", before the translator work (8.2)**: for each heap block class
and the 40 largest globals, find which units dereference them, how often per keypress, and whether the engine could take
the access (the blitters already do for pictures); then pick A, B or a mix from numbers, as D4 was picked here. It costs a
day, not a month, and 8.2's CoCo profile of `pas2c` depends on the answer (native pointers or accessors).

New decision **D12: data addressing model** (A, B, C, D or a mix): recommendation above, to be settled after 8.1c.

## 8. Changes to the guide

`PORTING-GUIDE.md` is updated with: the size table summary, D4 confirmed (16 KB window; `ovl16` split in two), D12 and
step 8.1c, the measured heap and DGROUP figures (sections 2.2 and 3.3), the answers to Q3 and Q4, and the note that step 8.2's
"native globals and native pointers" is conditional on D12.

## 9. Left for later

- The instrumented `c/rtl/heap.c` (opt-in, `POOL_HEAP_STATS`) is the only change outside `ports/coco3`; the default build and
  `make c-golden` are unchanged (checked on `walk-explore`).
- Nothing here ran on 6809: `-O2` code size is exact, speed is unmeasured (profiling is 8.9).
- The transform list (section 2.1) is the specification of the translator's CoCo profile; 8.2 should start from it.

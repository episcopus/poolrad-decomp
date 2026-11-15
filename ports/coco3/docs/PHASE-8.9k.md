# Step 8.9k: the big battle (the DOS port's targeting work, carried over)

Date: 2026-11-14. Follows `docs/PHASE-8.9e.md` (combat) and the DOS port's big-battle round (`ports/dos/README.md`, "The big battle"). Tags: **[V]** measured in MAME (`coco3`, 6809), **[E]** estimate.

## 1. The fight and the result

A player's saved game (slot F, which `mkimage.py` puts in the image's save area with the rest of the shipped `SAVE` folder) stands in the Temple of Bane's nave. One step east the party finds the third trapdoor; opening it and taking its loot brings High Priest Mace and 55 orcs. `tests/profile/bane-profile.keys` plays it with a run of `Q` keys until the party falls and the game ends (like `council-guards`; a profile session, not a golden: the save is not one of the pinned inputs). Run it with `QOL=0` (the session types the wheel's answer):

    make QOL=0 game
    MB_RLOG=1 MB_PCLOG=0-9000 MB_SESSION=/repo/tests/profile/bane-profile.keys MB_LIMIT=9000 scripts/game_run.sh build/run/prof-bane
    python3 tools/prof_pc.py build/run/prof-bane.out --from 200

Busy time of the fight (from 200 s, the battle's start, to the game's end), 1.79 MHz [V]:

| Step | Busy | |
|---|---:|---:|
| main (before this step) | 1,281 s | |
| `ScanTargets` and `WalkLine` | 1,115 s | -13 % |
| `CombatantIndex` by words, `ScanTargets` maps the table once | 945 s | -26 % |
| `ScanTargets` on the cells that exist | 911 s | -29 % |
| `SortTable` by pointers, `FootprintCell` | **881 s** | **-31 %** |

After every step the run drew the same 24,505 random numbers in the same order as main's (`MB_RLOG`, compared byte for byte) and ended the same way (the party's defeat, the game's exit). The screens the runs keep are not comparable one for one: a screen is kept when it has been still for 2 s, so a faster build keeps other in-between frames of the same moves (1,496 and 1,455 kept). Over the 16 sessions `make step-check` passes (section 4).

## 2. What carried over from the DOS port, and what did not

The DOS port's round (`ports/dos/patches/speed/`) had two halves. The targeting half is arithmetic that holds for any build and was proven there against the Pascal (exhaustively where it is a formula); here it is C in `patches/`:

| DOS patch | Here | |
|---|---|---|
| `scan-targets`: no walk past the step limit, sharper bound | `ovl30_scantargets.c` | 8.9e skipped a pair when max(\|DX\|, \|DY\|) > MaxSteps; now when 2 max + min > 2 MaxSteps + 1 (the walk's step count ends at exactly 2 max + min and never decreases) and, once a pair is found, when 2 max + min >= Best |
| `scan-targets`: Dir $FF needs no `InDirArc` | `ovl30_scantargets.c` | with Dir 8 or $FF (every caller) the arc test is "both cells on the map", tested once per cell; `InDirArc` is called only for another Dir |
| `scan-targets`: the hit's direction in closed form | `ovl30_scantargets.c` | was up to nine `InDirArc` calls a hit; the formula was checked against `InDirArc` for all 1,562,500 pairs of map cells |
| `walk-line-regs`: no multiply a step | `ovl30_walkline.c` | the cell is a pointer moved by 1 or 50; the `Bound` line is not stepped (its Y step is 0); one loop per major axis; `SetupLineP` and `StepLineP` are no longer called by it (they stay for the other callers) |
| `combatant-index` | `ovl31_combatantindex.c` | the record compared as two 16 bit words, low word first, instead of through the library's 32 bit compare (`cmpDWordDWord`, `cmpDWordUnsignedInt`, `sub32Stack` left the profile) |
| `sort-table-regs` | `ovl30_sorttable.c` | 8.9e already kept record I's key and value in locals; now I and J are pointers (no index times 3 a comparison) |
| `in-dir-arc` | not needed | after the above, `InDirArc` is called only by `BearingTo` and the spell aim (no longer in the profile) |

New for the CoCo: `ScanTargets` takes `CombatantTable`'s data window once (each `CombatantTable[I]` was a `vm_ptr` call, three a combatant) and again only after a call that may map another page; it lists the cells that exist once (the base's and each footprint kind's, in the original's order), so a one-cell combatant is one pair instead of sixteen tests; `FootprintCell` (`ovl31_footprintcell.c`) maps its record once instead of twice.

The drawing half does not carry over: the CoCo has its own kernels (`k_icon`, `k_flush`, `k_fillrect`: 8.9e, 8.9g, 8.9j), already in assembly with unrolled 24-row icons and trackers. The one DOS idea left is the mirror through a 256-byte table of nibble swaps (DOS `mirror-xlat`): `k_icon`'s mirrored row swaps each byte with `MUL` (89 cycles a byte for colour and mask). It needs about 500 bytes of the engine (the table and an unrolled row) and the engine has 37 (it ends at `$7C6B` of `$7C90`): see section 5.

## 3. How each change was checked

* **On the host first** (`build/hosttest/`, clang): the new `WalkLine` and `ScanTargets` against 8.9e's (which `step-check` had proven against the original) on random maps, tile tables, gates, limits and combatant tables: 200,000 walks (48,066 arriving; off-map and long lines included) and 10,000 scans (1,663 with hits, 14,216 hits), every result and the whole sort table equal. `CombatantIndex`: 200,000 searches with duplicate records and every count, the count-0 quirk included (after entry 255 the original looks at entry 0, just below the table). `SortTable`: 20,000 sorts with many ties. (8.9e's `SortTable` never ends for a count of 255, its byte counter wraps; the table holds at most 72, and the new one ends.)
* **On the CoCo**: the bane run's dice log after every step (section 1), then `make step-check`.

## 4. Verification of the whole

`make step-check QOL=0` over the final code: 16 of 16 sessions, every labelled screen equal, `create-character` 384 equal, 54 explained, 0 open, the save areas equal. `step-check` is now in the Makefile's `QOL_OFF_GOALS` (it played the default game, which has no wheel question, and every session stalled at it).

Busy seconds of each session (`tools/prof_pc.py` over the step-check logs; main against this step) [V]. The sessions without combat do not change (`camp-magic`'s figure counts its animated camp screen):

| Session | main | 8.9k | |
|---|---:|---:|---:|
| `council-guards` (30 members) | 457.3 s | 392.1 s | -14.3 % |
| `combat-spells` | 212.8 s | 204.2 s | -4.0 % |
| `parley-combat` | 168.8 s | 162.8 s | -3.6 % |
| `battle-aftermath` | 181.8 s | 175.7 s | -3.4 % |
| `temple-heal` | 197.0 s | 190.9 s | -3.1 % |
| `camp-rest-combat` | 64.5 s | 64.4 s | -0.2 % |
| the other ten | 2,411.4 s | 2,411.4 s | 0 |
| all 16 (`stepmetrics.py`, its own window) | 1,855 s | 1,763 s | -5.0 % |

The more combatants, the more it gives: the AI's scans grow with the square of the fight's size.

## 5. What is left [E]

From the profile of the bane fight after this step (881 s): `k_icon` 15.6 %, `ScanTargets` 8.6 %, `SortTable` 6.2 %, `k_flush` 5.4 %, `CombatantIndex` 4.7 % (its callers search the whole table), `WalkLine` 2.9 %, the data window calls (`vmmap`, `vm_ptr`) 5.2 %.

* **The mirror table.** A mirrored row through a table: the colour bytes swapped into a direct-page buffer by `LDB ,-Y / LDA B,X` (X at the table's middle: the offset of `B,X` is signed), the mask bytes likewise, then the masked store with direct-page operands; about 600 cycles a row instead of 1,070, `k_icon` perhaps -30 % in this fight. It needs about 500 bytes of always-mapped memory for the code and the table, which means moving something out of the engine first.
* `SortTable` and the per-combatant loop of `ScanTargets` in assembly: the C of CMOC is three to four times the instructions a hand-written loop needs.

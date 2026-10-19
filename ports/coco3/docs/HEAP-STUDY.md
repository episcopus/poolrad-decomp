# Heap study: how to give the CoCo game enough mapped heap (report for D12, step 8.9)

Date: 2026-10-19. Question from step 8.7b: three sessions (`shop-buy`, `combat-spells`, `council-guards`) stop with fatal 0x22 because the mapped heap
(8,552 bytes, `$5E98..$7FFF`) has no free block. Find and measure ways to give it more, without breaking the sessions that pass. This report does not decide D12:
it gives numbers and a recommendation. Tags: **[V]** verified by running something, **[E]** estimate, **[?]** open.

## 0. Result

* **Demand [V]**: the mapped heap needs 8,624 bytes for `shop-buy` and 8,656 for `combat-spells` (the heap had 8,552: short by 72 and 104 bytes), 16,392 for `council-guards`
  (short by 7.8 KB), and at most 8,464 for every other session (section 1).
* **Option 3, shrinking the native area, is done and committed [V]**: the heap is now **9,744 bytes** (+1,192) and costs about 9 extra accessor calls per key. With it
  **15 of the 16 sessions play to the end and match the goldens on the CoCo** (screens and state, party records included); `shop-buy` and `combat-spells` were the two that stopped
  for 72 and 104 bytes. Only `council-guards` still stops (it needs 16.4 KB).
* **Nothing but a banked character record scales [E]**: the City Hall fight holds 30 characters of 288 bytes (8.6 KB) and a script may add up to 63 members
  (`MaxEncounterMembers`). Option 2 (the second code slot as heap) buys 8 KB at the price of an 8 KB code window that `CreateCharacter` does not fit, and still leaves room for
  about 33 combatants. Option 1 (character, combatant and affect records in the banked heap) is the only one that does not hit a ceiling, and needs a fast accessor first.
* **Two findings that matter for any option (section 6)**: the bank pool (8 banks) is exhausted by a chain of 9 distinct banks that two unrelated builds hit in the first long fight
  (it passes today, probably because of where `ovl03` splits); and one 21 byte global moved to the paged area breaks every long fight for a reason not yet found.

## 1. What the sessions need [V]

The host model of the CoCo placement (`scripts/place_host.sh`: the same `placement.toml`, the mapped heap in the DGROUP segment, 30 KB so nothing fails) replays all 17 sessions
(`build/c/replay-place` now holds the 17 recordings; the ten new ones were exported with `tools/c/export_replay.py --pointer-masks`). The peak of live bytes of the mapped class
(`POOL_PLACEMENT_STATS=1`; blocks are 8 byte units, first fit as on the CoCo, so the peak is also the heap's high water) and the blocks alive at the peak:

| Session | Peak (bytes) | Blocks at the peak (count x size) |
|---|---:|---|
| `boot-title` | 2,048 | 2x1024 |
| `create-character`, `create-elf-mage` | 2,816, 2,832 | |
| `camp-save`, `walk-explore` | 4,800 | 2x1024, 6x288, 14x64, 8x16 |
| `character-menu`, `character-view`, `camp-cast`, `temple-cast`, `camp-magic` | 4,808 to 5,712 | |
| `camp-rest-combat`, `parley-combat`, `battle-aftermath`, `temple-heal` | 8,464 | 2x1024, 12x288, 20x64, 8x16, 1x1264, 12x24 |
| **`shop-buy`** | **8,624** | 2x1024, 6x288, 73x64, 8x16, 1x48 |
| **`combat-spells`** | **8,656** | 2x1024, 12x288, 20x64, 8x16, 1x1264, 12x24, 4x48 |
| **`council-guards`** | **16,392** | 2x1024, 30x288, 56x64, 8x16, 1x8, 1x1264, 30x24 |

The blocks: 1024 = `GameVars3` and the GEO block, 288 = `TCharacter` (party and monsters), 64 = `TMenuLine` (items of the characters, the shop's stock), 24 = `TCombatant`,
16 = `TAffect`, 1264 = `TCombatMap`. The CoCo agrees with the model: the table of the run's end (`tools/heaptab.py build/run/game-shop-buy.core`) shows 8,624 bytes in use, and at the
old failure the heap was 8,512 of 8,552 bytes full (`council-guards`: 14 characters loaded of the fight's 30).

A fight costs about **440 bytes per extra combatant** [E] (288 record, 24 combatant, about 1.8 items of 64): 8,552 bytes held a fight of 12 characters (6 party members and 6 monsters), 9,744
hold about 15, 17.9 KB (Option 2 with the diet) about 33. The script's limit is 63 members.

Profile of the code that would touch these records (`build/prof`, 151 keys of 7 sessions): dereferences of 288 byte blocks per key: median 0, 90th percentile 937, worst 2,581 (`parley-combat`);
of 64 byte blocks 170 and 461; of 24 byte blocks 132 and 1,160.

## 2. The room, as it is now

| Where | Bytes | Note |
|---|---:|---|
| core `$2000..$4C38` | 11,320 | `farstubs` 2,076 (already 2 to 4 bytes a stub: `bsr` chains), `proc_table` 1,046, `rtl_str` 1,402, `rtl_sys` 1,363, `engapi` 900, `rtl_vm` 666 |
| gap and `HEAPDATA` (`$4C38..$4ED0`) | 664 | the table: 579 bytes (128 + 16 entries of 4); 74 + 14 bytes unused around it |
| native globals `$4ED0..` | 2,842 (was 4,040) | section 3 |
| **mapped heap `..$7FFF`** | **9,744** (was 8,552) | |
| paged DGROUP: four pages of 7,680 usable bytes | 29,247 of 30,720 | 1,473 free (page 3) |
| stack `$0A00..$1F7F` | 5,504 | the harness paints it: **4,215 bytes used** in every session that loads a game, 3,452 in `create-character` |

The paged area cannot take more: 30,449 of 30,720 bytes were used before this study (the earlier attempt to lower the native budget failed on exactly that), which is why the diet starts by
removing dead data (about 1.6 KB of paged tables the CoCo never reads).

## 3. Option 3, shrinking the native area (done) [V]

What was in the 4,040 native bytes: 2,500 chosen by `mkplan.py` from the profiles (references per byte), 1,540 forced (promoted because they are passed by reference to game routines: `SpellPickerPointer`
565, the menu texts, `LoaderFile` 128; the System unit's `CheckBreak..Output` 536; `HeapOrg` 48). What was wrong with the 2,500:

1. **800 bytes were the EGA and Tandy scanline tables**, which `StartGame` (ovl11) fills in a loop and nothing reads on the CoCo (the engine owns the screen). They had a high reference count
   (2 x 1,400 stores), so the plan put them in native memory. The loop also fills the CGA table (paged, 400 bytes) and four dirty-row tables of the EGA planes (1,176 paged bytes) that only the
   replaced unit `res07` names. All of it is dead: **2,376 bytes of DGROUP** (800 native, 1,576 paged) go away with `tools/prepatch.py` (an exact-match patch of the translated `ovl11.c`, an error
   if the translation ever changes).
2. **`res07` is replaced by the engine** (`mkgame.py ENGINE_UNITS`): `mkvm.py` and `mkplan.py` now ignore its text, so globals only it names are not placed.
3. **`Input` (256 bytes) of the System unit** is not named by any unit or runtime routine of the CoCo: dropped from the always-native list (`Output` stays: the game's error messages use it).
4. **The budget** goes from 2,500 to 1,300 bytes: the 1,200 bytes that left were the tables above and cold globals (`ClassThac0Table`, `ds3CF4`, `ds471A`, `FacingNames`, ...), 1,357 references
   in the 151 recorded keys, **9 accessor calls per key** on average (about 1,000 cycles a key [E]).

Measured: heap 8,552 -> **9,744 bytes**; `shop-buy` ends with `final` equal, 47 of 54 unlabelled screens, 378 DGROUP places equal and 0 open, 6 party records and 0 differ; the table at its end shows
8,624 of 9,744 bytes in use. `make baseline` (4 minutes here, not 40): 15 of 16 sessions match, as in this table of the change's baseline:

| | before (8.7b) | after |
|---|---|---|
| `battle-aftermath`, `camp-*`, `character-*`, `create-character`, `parley-combat`, `temple-*`, `walk-explore`, `boot-title` | match | match |
| `shop-buy` | stops (fatal 0x22) after 32 of 54 screens | **matches** (47 of 54, state 0 open) |
| `combat-spells` | stops at the first spell, 31 DGROUP places open | **matches** (5 of 5 labelled, state 0 open, 12 party records 0 differ) |
| `council-guards` | stops (fatal 0x22, 14 of 30 characters loaded) | stops (fatal 0x22 for 285 bytes, 16 characters loaded) |

**How far the native area can go down** [V by `mkplan` and `mkvm`, not run]: heap by native budget (the paged area still fits: 1.5 KB free): 1,700 bytes: 9,352; **1,300: 9,744 (chosen)**; 0: 10,200 (the
promoted and System clusters, 2,392 bytes, cannot move). At budget 0 every one of the 100,980 planned references (669 a key, about 67,000 cycles a key [E]) goes through `vm_ptr`: not worth 456 bytes.
Beyond that, only small things are left: the 88 unused bytes around `HEAPDATA` (set `HEAPDATA` and `COCO_NAT_BASE` lower together, 88 bytes), `proc_table` (1,046 bytes of procedure ids, read only by
`rtl_proc`, which handler calls are not hot: it could go to the runtime bank, about 1 KB, a day), the stack (1,289 bytes are never touched in the sessions, but the static bound of the save chain is 3,739 bytes
plus interrupts and the sessions use 4,215: no more than about 0.8 KB without a margin, not recommended). Everything together stays below 11.7 KB: **no way to reach 16.4 KB by shrinking.**

## 4. Option 1, records in the banked heap [E, one probe]

What moves: `TCharacter` (1,512 `FPM` sites in 23 units), `TCombatant` (227), `TAffect` (120), and for the shop `TMenuLine` (516). Mapped need then: `council-guards` 6.9 KB, `combat-spells` 4.8 KB,
`shop-buy` 6.8 KB (with only the character class banked); with `TMenuLine` banked as well `council-guards` 3.3 KB and `shop-buy` 2.1 KB. The banked heap needs room for 312 bytes a combatant
(63 members: 19.7 KB, the heap has 30 KB with 15.5 KB in use: more pages are a layout change, physical memory is there).

* **Speed**: `FPB` is `vm_far(farptr)`, a C routine that does 32 bit arithmetic through about a dozen library helpers on the banked path: roughly 1,000 to 1,500 cycles a call [E, counted from the
  disassembly, not timed]. At the worst key (4,200 derefs of the three classes) that is about 5M cycles (2.5 s); at the 90th percentile 1,240 derefs (0.7 s). It needs an assembly accessor that takes a
  page-and-offset pointer and maps like `vm_ptr` (about 100 cycles): worst key 0.4M cycles (0.23 s), 90th percentile 70 ms [E]. Doing that changes the representation of banked pointers
  (a segment value that carries the page), which the saved characters do not mind (the pointer fields are masked in the goldens) but the translator's `rtl_far`, `rtl_freemem` and `vm_far` must follow.
* **What breaks**: a pointer that is good "until the next call" (two windows, least recently used out). Statements with three distinct pages in one expression, or a window pointer kept across a call, fail without
  any message. Lines with 3 or more windowed accesses (paged global, `FPB`, `FPD` or, then, the moved classes): 70 today, 187 after (an upper bound: repeated derefs of one pointer count again); each is read once.
  The typical ones copy between two lists (`ovl03.c:314` and `328`: `Last.Items = Items`, a character page and an item page in one statement).
* **Probe (not a prototype of the option) [V]**: `placement.toml` with `TCharacter`, `TCombatant` and `TAffect` banked, the banked table raised from 16 to 48 blocks (it stops at once with fatal 0x20 otherwise):
  `parley-combat` shows 3 of 5 labelled screens and the fight itself on screen, then stops with the signature of section 6 (bank pool exhausted). Not debugged. (The step's earlier attempt with `TMenuLine` banked
  stopped after 19 screens; not repeated.) Reverted: the probe is not in the commit.
* **Work**: the placement change is one line of `placement.toml`; the accessor, the pointer representation, the translator's evaluation order (`tmp = rvalue; *FPB(lvalue) = tmp`, to make a compound assignment safe
  with one live pointer less) and the review of the 187 lines are the work: about a week [E]. **It is the only option without a ceiling.**

## 5. Option 2, more map for the heap [V for the numbers of the code, E for the rest]

**Taking the second data window (slot 7, 7,680 bytes)** gives 7,680 bytes and leaves one window for paged globals and the banked heap. Today 409 source lines have two or more windowed accesses and 81 have
three or more; with one window each of the 409 that touches two different pages (a global assignment between two pages, a call with two window pointers) is wrong. Not recommended.

**Halving the code window (slot 4 as heap, `$8000..$9FFF`)** gives 8,192 bytes (17,936 with the diet, enough for `council-guards` with 1.5 KB to spare, about 4 more combatants).
Measured with `BANK_BYTES=0x2000 mkgame.py` (compile and split only, in `build/h2`, then removed):

| | 16 KB window (now) | 8 KB window |
|---|---:|---:|
| banks | 48 | 74 (+26; `ovl03` alone becomes 6, `ovl16` 6) |
| far entries (stubs) | 512 | 550 |
| far calls over the 151 recorded keys | 11,267 | 13,629 (+21%) |
| far calls per key: median / p90 / worst | 9 / 188 / 2,005 | 9 / 315 / 2,124 |
| the largest bank | 14,232 (`ovl07`) | **10,928 (`ovl16_2`: `CreateCharacter` is 9,172 bytes in one routine)**, `ovl03_6` 8,231 |

* **Speed of calls**: 2,362 more far calls over 151 keys is 16 a key (about 2,800 cycles), worst key +21,000 cycles: nothing. The unmeasured cost is **bank loads**: more banks, a pool that holds the same 128 KB.
* **What breaks**: `CreateCharacter` does not fit an 8 KB window (the routine has to be split by hand: a patch of the translation, or a stronger splitter); `ovl03_6` is also over; the engine (`banks.inc`,
  `bank.link`, `farcall.asm`, the bank loader) knows two slots; **a heap block at `$8000..$9FFF` has the same 16 bit offset as a paged global** (`vm_far`, `rtl_far`, `rtl_freemem` and `mkvm` take every offset
  `>= $8000` for a page), so the paged pointers need another encoding (the segment); the bank stack gets deeper (section 6).
* **Work**: about two weeks [E] across engine, `mkgame`, `mkvm`, the translator's patches, the state check, and a re-run of everything. A one-time gain of 8 KB, which buys fights of about 33
  combatants, not more.

## 6. Found on the way

1. **The bank pool is one chain short [V].** While bisecting item 2 below, two builds that differ in nothing but a few bytes of code stopped `parley-combat` in the same place with
   `fatal 0x00`, result words 29 = 2 and 31 = 39: `api_bankload` found all 8 banks of the pool on the bank stack and was asked for a ninth (`ovl32`). The bank stack of both runs, read from the dump,
   is the same chain: `ovl03_2, ovl03_1, ovl08, ovl09, ovl13_1, ovl13_2, res12_2, ovl31` and then `ovl32`: **9 distinct banks nested** in the first long fight. The sessions that passed run the same code, and
   `ovl03` split at different routines in the passing build (parts of 10,176 and 11,105 bytes, in the failing ones 10,840 and 10,569), so one of the calls of that chain was inside a bank there. The game works while the split
   puts a call inside one bank and stops when it does not [?: the chain of the passing build was not dumped]: any change of code size (every option here, option 2 most of all) can flip it. **A pool of 12 banks
   (24 blocks) or a depth check in `mkgame` should come first.** The stop is `api.c:48` (`MB_RESULT(29) = 2`, `MB_RESULT(31) = bank`).
2. **`GlyphRow` (21 bytes, the text cursor row) paged breaks every long fight [V].** `battle-aftermath`, `combat-spells`, `parley-combat`, `temple-heal` ended with the stop of item 1 when the cluster was in the
   paged area, and pass with it native; bisected by building the failing plan with each group of the cold globals put back (`NATIVE_BUDGET=1300`: group of tables, then 4, then 1 cluster). The cause is not
   found; item 1 may explain it [?] (the layout of the paged area shifted by 21 bytes and the code size by a few bytes changed the `ovl03` split), which makes it a symptom, not a defect of the variable.
   `mkplan.py` keeps it native (`KEEP`).
3. `make heap-stats` measures the PC heap (183 KB peak): it says nothing about the mapped class; the numbers of section 1 come from the placement model, which `tools/heaptab.py` confirms on the CoCo.

## 7. Recommendation (for the human; D12 stays open)

1. **Keep the diet (committed).** It costs nothing in speed, removes 2.4 KB of dead data, fixes `shop-buy` and `combat-spells`, and leaves fights up to about 15 combatants (the 12 of the recorded
   fights plus margin) working.
2. **Before any other change, make the bank pool safe** (section 6, item 1: more banks in the pool, or `mkgame` computing the deepest chain of distinct banks and refusing a split that exceeds the pool).
   Every later experiment otherwise risks being blamed on the heap.
3. **For the big fights choose Option 1 over Option 2** if the target is "the game as played": Option 2 costs about twice the work, hits a ceiling at about 33 combatants, and needs `CreateCharacter` rewritten.
   Option 1 needs the fast accessor first (week 1), then the placement change with the 187 lines reviewed (week 2); `council-guards` and `shop-buy` are the proofs, `combat-spells` already passes.
4. Not worth doing: lowering the native budget below 1,300 (456 bytes for 67,000 cycles a key), the stack, one data window.
5. If `council-guards` and the like are out of scope for the CoCo release (a fight of more than 15 combatants), the diet and item 2 are enough for D12; the sessions that need more are then
   documented limits, not defects.

## 8. Reproduce

```
make -C ports/coco3 game                      # the diet build (NATIVE_BUDGET=1300 by default; mkplan KEEP, prepatch.py)
make -C ports/coco3 baseline                  # 16 sessions, 4 minutes; python3 tools/baseline_table.py for the table
python3 ports/coco3/tools/heaptab.py ports/coco3/build/run/game-shop-buy.core   # the mapped heap of a run
BANK_BYTES=0x2000 scripts/tc.sh python3 tools/mkgame.py build/gen/vm build/h2    # section 5: the banks of an 8 KB window (delete build/h2 after)
```

The demand of section 1 needs the placement model built with `-DPOOL_PLACEMENT` over `placement.toml` (`scripts/place_host.sh` does it; run with `POOL_PLACEMENT_STATS=1`); the histogram
of the blocks at the peak is a local patch of `c/rtl/heap.c` (`m_hist`), not committed.

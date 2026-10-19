# Step 8.7b: coverage of the sessions, new sessions for every area, and the CoCo build against them (report)

Date: 2026-10-19. Not a row of the plan: the answer to the review of the porting approach after 8.7. The question was whether goldens recorded by playing through
the game leave whole areas of it unproven. They did: 39.5 % of the lines of the translated game ran in a session, and the rest (the wilderness code, most spells,
the shops, the temple, the party menus) was proven by nobody. This step adds a measure, a search for the missing sessions, a static check for the defect
classes already met, new sessions recorded on the original for the areas the measure showed, and a baseline of the CoCo build against all of them.
Tags: **[V]** verified by running something, **[E]** estimate, **[?]** open.

## 0. Result

**Coverage [V]** (`make coverage`, clang source coverage of the 17 sessions replayed on the C translation, `tests/sessions/COVERAGE.md`):

| | before | after |
|---|---|---|
| sessions | 7 | 17 |
| routines run | 336 of 728 | 524 of 806 |
| lines run | 39.5 % | 52.7 % (15,894 of 30,143) |
| branches | 28.8 % | 39.2 % |

(The routine count changed with the way routines are counted: nested routines and the generated stubs were not counted in the first measure.)

**Three defects of the translation found by the new sessions [V]**, each one in code no earlier session ran, each one now fixed and held by a test (`tests/unit/test_c_translation.py`):

1. **A procedure variable named as a statement was not called.** `SpellHandlers[CastingSpell];` (ovl22) was translated to an expression with no effect: no spell ever did
   anything on the translation, on the host and on the CoCo alike. Found when `combat-spells` diverged from the original at the first Sleep. One site in the whole game.
2. **`Integer(WordVar) < 0` was written `WordVar < 0`**, always false on an unsigned: the Spells window of the character sheet never opened (`battle-aftermath`).
   The translator now writes a cast of a variable to a different type of the same size as a view of the variable (`(*(s16 *)&Var)`).
3. **A record copied out of a DAX block's bytes was not turned round on the CoCo**: `AddLootCommand`'s `Move(Block^[Offset], Item, SizeOf(Item))` left the price of every shop
   item in the PC's byte order (a hand axe cost 256 instead of 1). The translator turns the words of a record round after a `Move` from a byte buffer of the record's size now.

And one defect of the original that a translation has to copy: **`TradeMoney` reads `Finished` before it writes it** (QUIRK ovl19:2468): the byte the frame held before the call
decides whether the Trade menu is left after a cancelled coin list. The original leaves it (in the camp's View); the translation's locals start at zero and stayed. `STALE_LOCALS`
in `tools/c/pas2c.py` gives such a local the value the original had (found by `character-menu`; four more sites of the same kind are in `docs/RISKS.md`).

**CoCo [V]**: thirteen of the sixteen sessions that run on the CoCo play to the end and match the goldens on screen and in the state (section 3): the labelled screens in order, the
files, the globals of DGROUP and, new in this step, the records of the party list (`statecheck.py` compares the characters' and monsters' records, which the heap holds and DGROUP
does not show). Three do not complete: the shop, the spell-casting fight and the City Hall fight stop with fatal 0x22, the mapped heap has no block left (section 4).
A regression of this step's own was found and fixed by the new party check (section 2, item 5): for an hour the CoCo played every fight with the monsters' items unswapped.

## 1. What was built

### 1.1 The measure and the search (`tools/c/`, `c/platform/explore.c`)

* `make coverage [WRITE=1]` (`tools/c/coverage.py`): builds the translation with clang's source coverage (Debug build; Release crashes on macOS), replays every recording, merges
  the profiles and reports per unit routines, lines and branches, the routines nobody runs (`--uncovered`) and the lines only one session reaches. `WRITE=1` writes
  `tests/sessions/COVERAGE.md` and `coverage.json`, the baseline a new session is measured against.
* `poolrad_explore` (`c/platform/explore.c`): the translation with a host that plays a key script instead of a recording (`key`, `press`, `wait`, `shot`, `state`, `quit`): about a
  second a script instead of a minute on the oracle. Not the oracle: its dice and timing differ on a long script, so what it finds is a lead, recorded on the original afterwards.
* `explore_fuzz.py` (random walks, says where a routine was first reached), `explore_climb.py` (coverage-guided hill climbing: appends keys and keeps what reaches new lines),
  `explore_prune.py` (drops the keys that do not matter), `explore_cov.py` (what a script adds), `explore_crawl.py` (the map exits), `explore_shrink.py` (ddmin of a script that reaches a routine), `explore_path.py` (a key path through one map), `explore_run.sh` (a script with its screens as PNGs).
* `make risk-scan`: clang's tautological comparisons on `c/game` (`tools/c/risk_clang.sh`), then the CoCo build's scan (`ports/coco3/tools/riskscan.py`, `scripts/risk_cmoc.sh`).
  `docs/RISKS.md` lists the classes, the check for each and what was read.

### 1.2 Sessions (`tests/sessions/README.md` says how they are written)

| Session | Area | New lines |
|---|---|---|
| `shop-buy` | the shop: buy, pages, view, pool, share, appraise | ovl06, ovl21, ovl19 |
| `temple-cast` | the temple menu, camp magic | ovl04, ovl15, ovl22 |
| `temple-heal` | the wounded party at the temple: cure wounds, disease, poison, raise dead, curse, stone | ovl04, ovl21, ovl24 |
| `battle-aftermath` | the fight to its end, experience, treasure, the sheet's menus | ovl05, ovl19, ovl21 |
| `combat-spells` | the same fight with Bless and Sleep cast | ovl22, ovl12, the aim prompt |
| `camp-magic` | camp menus: memorise, party order | ovl15, ovl20 |
| `camp-cast` | casting in camp: Cure Light Wounds, Detect Magic | ovl22, ovl24 |
| `character-view` | the character sheet: items, money, trade, drop | ovl19, ovl21 |
| `character-menu` | the character menu: train, modify, drop | ovl16, ovl19 |
| `council-guards` | the City Hall's guards: an ECL fight the party loses, the end of the game | ovl03, ovl07, ovl09, ovl13, ovl17 |

### 1.3 CoCo changes this step

* **The mapped heap's table**: 128 entries of 4 bytes (it was 64 of 5; the shop uses 89), `HEAPDATA` is 579 bytes, the native data starts at `$4ED0` (`rtl_heap.c`, `coco_map.h`, `mkvm.py`).
* **Cross-bank literals handed on**: a routine that passes its string parameter to another bank (`AskCastAnyway` to `ShowCharacterMessage`) is now called with a copy of a literal even from its own unit
  (`string_forwarders` in `mkgame.py`); the temple's "is not blind." was junk.
* **Harness**: `MB_NOBUILD=1` lets runs in parallel share one disk image; `lua/watch.lua` dumps the banked heap (`.bheap`); `tools/statecheck.py` has the new sessions and the stale
  spell menu pointer in `data/state_ignore.txt`; `probes/sorttable.c` and `probes/sidecmp.c` (negative results: CMOC does these two things right).
* **Oracle and replay tools**: `# max-insns: N` and `# stop: exit` in a session script (`golden.py`, `export_replay.py`), `POOL_READLOG`, `POOL_SCREENLOG`, `POOL_DUMPALL`, `POOL_PARTYLOG`,
  `POOL_MAPHEX` in `poolrad_replay` (what a divergence looks like, read by read).

## 2. Findings that changed how sessions are written

1. **A key that arrives while the game is busy is dropped** by the keyboard flush before most prompts. Which keys are dropped depends on the speed of the machine, so a session written with
   `press` and a short `wait` played one way in the oracle and another on the CoCo (the first versions of `character-menu`, `character-view`, `shop-buy` and `temple-cast` did).
   Sessions use `key` (it waits for the game to be idle) wherever the screen is still, and `press` with a long wait only on animated screens (`tests/sessions/README.md`).
2. A `wait` longer than about two seconds while the game blocks in a read stalls the oracle (`a read that can never be answered`): 30 ticks at most at prompts.
3. A `shot` after a `wait` falls between polls, in the middle of a redraw; the host can replay it, another machine cannot.
4. The CoCo harness cannot compare a camp screen bit for bit: its portrait animates with the clock (676 pixels of the picture window differ between two runs).
5. **A regression of this step's own, found by the party check.** The first baseline showed `parley-combat` going wrong (4 of 5 screens, Bakshi at 1 hit point where the original has him dying at 0), which the 8.7 run did not.
   Bisected by rebuilding the CoCo with the 8.7 translator and then with each change of this step in turn (each run ends the script at the end of the fight and reads the party's records out of the dump):
   `p2c_expr.move_swaps` now turns a record round after a `Move` out of a DAX block, and `mkgame.py`'s `PATCHES["ovl17"]` did the same by hand for the monster's affects and items: swapped twice, which
   is not swapped, and the kobolds carried 11,776 coins again (finding 6 of 8.7). The two hand patches are gone. `statecheck.py` compares the party list since (DGROUP does not show the heap): it
   would have caught this in minutes, and 8.7's state check, which only compared DGROUP, passed on a combat whose records were wrong in a way the screens did not show.

## 3. Baseline of the CoCo build against the goldens

All sessions of `tests/sessions` except `create-elf-mage` (not run on the CoCo, as before), played in headless MAME five at a time (`make baseline`), the goldens being the
original's, the state the host's at the same read (`statecheck.py`). "Labelled" are the screens the script names (`shot`), in order; "unlabelled" the screens after every key (not
decisive: a screen mid-redraw or an animated portrait is never among the CoCo's kept screens). "Party records" are the characters' and monsters' records of the party list, byte by byte
and word by word, CoCo against host.

| session | labelled screens | unlabelled | state (DGROUP places) | party records | the run ended |
|---|---|---|---|---|---|
| `battle-aftermath` | 5 of 5 | 14 of 36 | 376 equal, 73 explained, 0 open | 6, 0 differ |  |
| `boot-title` | 3 of 3 | 0 of 0 | no state check |  |  |
| `camp-cast` | 2 of 2 | 14 of 28 | 387 equal, 62 explained, 0 open | 6, 0 differ |  |
| `camp-magic` | 1 of 1 | 10 of 21 | 390 equal, 59 explained, 0 open | 6, 0 differ |  |
| `camp-rest-combat` | 2 of 2 | 3 of 21 | 386 equal, 63 explained, 0 open | 12, 0 differ |  |
| `camp-save` | 1 of 1 | 4 of 12 | 390 equal, 59 explained, 0 open | 6, 0 differ |  |
| `character-menu` | 1 of 1 | 15 of 22 | 393 equal, 56 explained, 0 open | 6, 0 differ |  |
| `character-view` | 1 of 1 | 18 of 27 | 385 equal, 64 explained, 0 open | 6, 0 differ |  |
| `combat-spells` | 4 of 5 | 5 of 32 | 348 equal, 70 explained, 31 open | 12, 10 differ | fatal 0x22 (46) |
| `council-guards` | 0 of 1 | 15 of 27 | 330 equal, 70 explained, 49 open |  | fatal 0x22 (63) |
| `create-character` | 4 of 4 | 16 of 23 | 391 equal, 58 explained, 0 open |  |  |
| `parley-combat` | 5 of 5 | 8 of 26 | 382 equal, 67 explained, 0 open | 12, 0 differ |  |
| `shop-buy` | 0 of 1 | 32 of 54 | 384 equal, 61 explained, 4 open | 6, 6 differ | fatal 0x22 (46) |
| `temple-cast` | 1 of 1 | 20 of 27 | 389 equal, 60 explained, 0 open | 6, 0 differ |  |
| `temple-heal` | 5 of 5 | 43 of 63 | 385 equal, 64 explained, 0 open | 6, 0 differ |  |
| `walk-explore` | 8 of 8 | 12 of 19 | 387 equal, 62 explained, 0 open | 6, 0 differ |  |

* `camp-save` and the camp sessions: the camp's portrait animates with the clock, so a labelled camp screen is compared bit for bit only when the animation frame happens to be the same; it was in
  this run (`camp-save` 1 of 1 was 0 of 1 in another run with the same build). The state decides for them.
* The three that stop: `shop-buy` (first Buy), `combat-spells` (the first spell cast in the fight) and `council-guards` (the City Hall fight, 14 combatants) call for a block of the mapped heap and find none
  (fatal 0x22, the request in brackets is its size). Their state columns are the state at the crash, which says nothing.


## 4. Open

1. **The mapped heap is too small** (fatal 0x22 in three sessions). The heap at the failure of the shop: 8,512 of 8,552 bytes, 72 blocks of 64 bytes (`TMenuLine`: the party's items and the
   shop's stock: 4,608 bytes), two of 1,024 (`GameVars3` and the GEO block), six characters of 288. The fights hold 12 to 14 records of 288 bytes. `docs/RISKS.md` lists the ways out; none
   is a patch: the item lists and the monsters' records need to move to the banked heap with an accessor that survives two live pointers, or the map has to give the heap another 8 KB
   (one data window less, or the code window at 8 KB). A decision for D12, step 8.9; the sessions are ready to measure it.
2. **Areas still without a session**, and why (`make coverage --uncovered` has the routines): the wilderness (`DrawAreaView`, `HandleWildernessKeys`' map pages, ovl26/ovl27: entered by an ECL command no map reachable
   from saved game A runs; the crawler found two maps and the City Hall), the ending (`ShowEndingNarrative`, ovl18: the end of the game), the locked doors (`DoBash`, `DoPick`, `DoKnock`), 110 of the 127
   affect handlers of ovl12 and 57 of the 74 spell routines of ovl22 (the party carries Bless, Cure Light Wounds, Detect Magic and Sleep; the rest are monsters' abilities and spells of other classes,
   which need other fights and other characters), 18 of the 56 ECL commands of ovl03, training (`TrainCharacter` needs experience the party does not have), `ModifyCharacter` and `PayGold`. Extending the
   search needs a stronger party and further maps: the oracle can play any script, the explorer only finds the way.
3. **Words left in the PC's byte order** (RISKS class 7): `RaceAbilityLimits`, `DoorViewRows`, `RestTime` and `SpellHandlers` are read by code no session runs on the CoCo yet; `SpellHandlers` is run by `combat-spells`,
   which stops on the heap before the first cast completes.
4. **Real arithmetic** (`ScaleMoney`, `LoseMoneyAndItemsCommand`): five Single routines are missing at link time; no session reaches them.
5. **Four more reads of a stale local** (RISKS class 11) that a session will one day hit; each is a divergence of the host replay, found at once.
6. `make baseline` takes about 40 minutes (five MAME runs at a time); the long fights dominate.


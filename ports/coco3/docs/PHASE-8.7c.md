# Step 8.7c: the mapped heap no longer limits an encounter (report)

Date: 2026-10-19. The human's requirement of the day: the CoCo port runs the whole game, the largest encounters included (a script may add up to 63 members,
`MaxEncounterMembers`), with no ceiling a bigger encounter can hit. `docs/HEAP-STUDY.md` measured the options; this step builds option 1 (what scales with the size
of an encounter goes to the banked heap behind a fast accessor) and settles the two findings of that study. Tags: **[V]** verified by running something,
**[E]** estimate, **[?]** open.

## 0. Result

* **16 of 16 sessions match on the CoCo** [V] (`make baseline`, 4 minutes): screens, DGROUP, the party records of the characters and monsters, the files. `shop-buy`,
  `combat-spells` and `council-guards` (the three that stopped with fatal 0x22 at 8.7b) play to the end; `council-guards` ends the game with Halt as the original does
  (the original's last screen is DOS text mode: `gamecheck.py` no longer counts it as a screen to match, `baseline_table.py` reads the run's mailbox).
* **The mapped heap peaks at 3.3 KB** [V] in every session (it was 8.5 KB and full): `TCharacter`, `TCombatant`, `TAffect` and `TMenuLine` and the typed views of a
  character (`TScoredCharacter`, `TSheetFields`, `TAbilityBlock`, `TDamageDice`, `TResistView`) live in the banked heap, which is eight pages of 7,680 bytes (61 KB).
* **No ceiling at 63 members** [V] (`make stress N=3 S=council-guards`: every group an ECL script adds is three times as large, up to 63 members; also `N=11` on the kobold fights):
  the banked heap peaks at 46,152 bytes of 61,440 and 314 of 640 table entries, the mapped heap at 3,320 bytes, no fatal, the session ends as normal.
* **Both findings of the study are settled** [V]: a bank on the bank stack that was taken for another is loaded again when the call returns (`farcall.asm @reload`), so the
  pool no longer limits the depth of a call chain (the four long sessions pass with a pool of **two** banks; the pool is six now); and the 21 byte global needs no
  exception: with it paged all the long fights pass (`KEEP` is gone from `mkplan.py`).

## 1. What was built

| Piece | Where | What it does |
|---|---|---|
| banked pointer | `coco_map.h`, `rtl_heap.c`, `rtl_vm.c` | `BSEG ($2000) + page` in the high word, the offset in the page in the low word (it was a PC style segment:offset that `vm_far` took apart with 32 bit arithmetic: 1,000+ cycles) |
| `vm_bp` | `vm.asm` | `FPB`: the page of a banked pointer into a data window, 65 cycles in the asm (about 95 with the caller's push [E, counted, not timed]); any other far pointer goes to `vm_far` |
| `vm_pkp` / `PEEKP` | `vm.asm`, `pool.h`, `p2c_expr.py` | a pointer that is a field of a banked block, read for another deref (`(*FPB(T, PEEKP(U, p, .Items)))`), without taking a window: the read maps the page into the window that would be the next victim for the length of the read and puts the old block back. A struct copy or a call with two addresses then needs two windows, not three |
| `with` | `p2c_stmt.py` | over a banked block the translator keeps the far pointer (`farptr w1p`) and maps again at every field; it kept a window address before |
| copies of strings | `p2c_expr.py _arg_pass` | a string field of a banked block handed to a routine of the game is copied into a temporary first (18 sites) |
| allocator | `rtl_heap.c` | banked table of 640 entries sorted by offset, next fit from a rover, a free is a binary search, adjacent free entries merge when the table needs room; the mapped table is 64 entries; high water goes to result words 22 to 24 of the mailbox |
| bank pool | `farcall.asm`, `api.c`, `gamemap.h` | any bank can be evicted; the return path loads the caller's bank again (the loader's kernels use `FC_D` as scratch: the result is saved around the call); six banks in the pool, the last four blocks of the old pool are banked heap pages |
| paged scalars | `mkvm.py` | a scalar whose address is passed to a routine of the game (`&BattleExperience`) is native like the aggregates are: the callee's accesses take the window away (battle-aftermath: the experience was written into another page) |
| `mkgame.py` | patch | the hand patch of `LoadMonster` (ovl17) said `FPM(TCharacter ...)`: with the class banked it swapped a wild address (the CPU ran off into BASIC's ROM) |
| scan | `winscan.py`, `make risk-scan` | the shapes that are unsafe with two windows (section 3) |
| stress | `mkgame.py POOL_STRESS`, `make stress` | a test build with larger encounters |
| tools | `heaptab.py`, `statecheck.py`, `lua/watch.lua` | the two heaps of a run, the party through the banked pages, the dump of eight pages, `MB_WATCH_IGNORE` and the stack at a watched write |

Memory: `HEAPDATA` is 2,826 bytes (`$4C80..$578A`), the native globals start at `$5790` (2,851 bytes), the mapped heap is `$62B8..$7FFF` (5,448 bytes, peak 3.3 KB).
Physical blocks: the banked heap is `$14..$17` and `$24..$27`, the bank pool `$18..$23`.

## 2. Proofs

**Sessions** (`make baseline` on the final build, `tools/baseline_table.py`): 16 of 16, 0 DGROUP places open, 0 party records different in every session that has a party
check; the host placement model (`make place-host`) replays all 17 recordings with the same classes.

**Stress** (`make stress`): a group of N times the size, capped at 63 members by the script's own counter.

| Run | Banked heap peak | Table entries peak | Mapped peak | Ended |
|---|---:|---:|---:|---|
| `council-guards`, N = 1 | 28,608 | 152 | 3,320 | Halt (as the original) |
| `council-guards`, N = 3 | 46,152 | 314 | 3,320 | Halt |
| `camp-rest-combat`, `parley-combat`, `combat-spells`, N = 11 | 42,120 | 241 | 3,312 | no fatal, the fight runs on (the scripts' keys no longer fit the longer fight) |
| `combat-spells`, `parley-combat`, `battle-aftermath`, `temple-heal`, N = 3 | 25,200 to 25,640 | 107 to 121 | 3,312 | no fatal |

Not proved by this: that the larger fights *play like the original's* (there is no recording of one; the oracle can record a script, the stress build cannot be played on it).
What is proved is that no allocation, no table and no pointer fails at 63 members and that the state of the fights that were recorded is exactly the original's.

**Bank pool** (`BANK_POOL_END = $1C`, two banks): `parley-combat`, `battle-aftermath` and `shop-buy` match, `council-guards` ends with Halt, at 6,528 to 23,956 bank loads.

## 3. What a window pointer can still do wrong (`docs/RISKS.md` class 13)

With two data windows a pointer into a window is good until the next access to another page. CMOC 0.1.100 works a statement out right to left, evaluates the arguments of a call
right to left and takes the address of the left side of an assignment last (`probes/asm/win-order.c`: assignment, compound assignment, index, struct copy, call, `&&`, `++`),
so a scalar read is a value before the next window call and a store happens at once. Three shapes stay, and `winscan.py` looks for each in the translation:

1. a window address handed to a routine of the game: 0 left (92 sites are runtime moves, copies in temporaries or values);
2. a call with three window addresses: 0 left (the picture copies of ovl16 and ovl32 are replaced by engine calls in `mkgame.py`);
3. a `with` over a pointer into a window: 1 (`StartingAgeTable[..]` of ovl16, a paged table whose fields are read before the dice are rolled).

The checks read text: they do not know a type. What they cannot see is a window pointer that a routine of the game receives from a paged global's address (`mkvm.py` makes aggregates and
scalars native when their address is passed on, which closes it for the globals) and an access pattern CMOC writes differently in a different version: `win-order.c` is the test to run first on a new CMOC.

## 4. Costs [V unless marked]

| | Before (the diet, 8.7c part 1) | Now |
|---|---|---|
| a banked record access | n/a (mapped: free) | about 95 cycles hit, about 135 miss [E]; a nested pointer field 130 [E] |
| the long monster turn of `parley-combat` (12 combatants), emulated seconds | 119.2 | 122.9 (+3.1 %) |
| the whole session of `parley-combat`, first to last key | 325.5 s | 322.7 s (the waits of the script dominate); `shop-buy` ends at 408.3 s, it ended at 433.6 s |
| bank loads (`r9`) | `parley-combat` 1,937, `shop-buy` 599 | 2,227 (+15 %), 778 (+30 %): the pool is six banks instead of eight |
| native memory for the heap tables | 579 bytes | 2,826 bytes (2.2 KB less mapped heap, which is 3.3 KB of 5.4 KB used) |

The bank loads are the real cost for a floppy backend (each one reads 8 to 16 KB); the pool of six is the price of four heap pages, and a pool of eight needs four blocks from the picture store
(live 118 KB of 152, high water 147 KB at the title screen: no room) or from Disk BASIC's ROM images (`$3C..$3E`, free only while nothing calls DSKCON). A decision for D13.

## 5. What is left [?]

* An encounter of 63 members was never played against the original: the stress build proves the heap and the pointers, not the AI's decisions at that size (the 72 combatants of the original's tables are the next limit
  of the game itself, not of the port).
* The paged globals keep the old hazard (a window pointer into a paged table kept across calls: `with` over `StartingAgeTable`); `winscan.py` lists it, the sessions run it.
* Code that no session runs is covered by the scan and by the host placement model, not by the CoCo (coverage 52.7 %: `make coverage`).
* 8.8 (sound) and the speed of the AI (5 to 8 s a party member's turn, 120 s for twelve monsters) are untouched.

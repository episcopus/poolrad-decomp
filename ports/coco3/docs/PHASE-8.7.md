# Step 8.7: combat (report)

Date: 2026-10-18. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.7: combat map, AI, animations; exit: the `camp-rest-combat` and
`parley-combat` sessions match on screen (and state, as in 8.5 and 8.6), turn times measured. Tags: **[V]** verified by running something,
**[E]** estimate, **[?]** open.

## 0. Result

**Both combat sessions play on the emulated CoCo 3 and match the original's goldens [V]** (`make combat`; `make first-light` and
`make exploration` still pass for the four sessions of 8.5 and 8.6):

```
camp-rest-combat: 2 of 2 labelled golden screens shown in order           encounter, combat-over (the first player's turn of the fight): equal
                  10 of 21 unlabelled ones; dgroup: 386 places equal, 63 explained, 0 open
parley-combat:    5 of 5 labelled golden screens shown in order           encounter, attitudes, parley, fight-start, and the last screen (the party's
                  15 of 26 unlabelled ones                                 twelve rounds of Quick later: "Continue Battle: Yes No"): equal
                  dgroup: 382 places equal, 67 explained, 0 open
```

The fight is played with the original's dice: the dice the two programs throw in the same order are the same (checked with the dice logs,
section 4), so the monsters' AI, the movement, the attack and damage rules, the morale and the animations all give the original's results.
All seven sessions still play on the host (`c_golden.py`), the 4bpp goldens are equal on the PC and coco host builds (`make golden4`), the port's
tests (40 engine and tool checks) and the repository's fast tests (385) pass.

**Turn times [V]** (emulated, 1.79 MHz): a party member's quick turn takes 5 to 8 s from the Q to the next menu, a monster's turn 4 to 6 s, a
whole round with six party members and the kobolds about 60 s, `parley-combat` (twelve Q) about 5 minutes of the machine. Most of it is the
AI's `ScanTargets` (a `WalkLine` for every pair of footprint cells, 20 to 30 walks a scan, several scans a turn), not the drawing; the
original did this in a few hundredths of a second on a PC. This is the first candidate of step 8.9 (the scan and the line walk in assembly,
or in the engine, would take most of it).

## 1. What changed

1. **Pictures** (the PC's picture records were the last thing in the way): `Load24x24Set` (ovl32: the tile sets of the combat map) is game code now and
   appends the loaded set to the tile bank through a new engine call, `PictureAppend`; `DrawCellPicture` is the original's routine over `DrawPictureItem`;
   `CopyPictureItem` (res12: the combat icons into the animation picture, mirrored or not) is one engine call, `PictureItemCopy` (`pic_item_copy`: colours and
   mask row by row, `mirror_row` for the left-facing copies); `ShowAttackAnimation` (ovl13) computes a byte size it never reads and no longer touches the record.
   `DrawCellPicture` and `Load24x24Set` were on the engine's list of unwritten routines (they stopped the program with 0xFA, code 26): that list is two shorter.
2. **Monster records**: `LoadMonster` (ovl17) copies a character, an affect and an item record out of a DAX block as bytes (its arguments are untyped
   pointers, so the translation could not know to turn the words round): `rtl_swapdesc` after each copy, the tables that `BlockRead` already uses. Before this a
   kobold's carried weight was 11,776 instead of 46, so it counted as overloaded, moved 3 half squares instead of 6, and the fight went another way
   (finding 6).
3. **Translator** (`tools/c`): the bounds of a `for` loop that are constants are compared at translation time (finding 1); an untyped `var` argument that is a
   small local gets three bytes of padding after it (finding 4).
4. **Heap tables**: 64 blocks for the mapped heap and 16 for the banked heap (they were 32 and 32; the mapped table filled with a fight's records, 288 +
   64 + 16 + ... each, fatal 0x20); `HEAPDATA` is 403 bytes now and the native data starts at `$4E20`.
5. **Placement** (`placement.toml`): `TWallTiles` and `TWallSets` (one 2,340 byte block with two typed views, `WallSets` is `absolute WallTiles`) are banked instead of mapped:
   2.3 KB more for the combatants. The 3D view reads them through the data window.
6. **Cross-bank literals**: a routine that is in one part of a split unit and calls one in another part (res12, ovl03, ...) hands string literals to a bank that does not
   see its rodata, so literals are copied into the caller's frame also between the parts of a split unit; so are Pascal string constants that are `#define`d in `game.h`
   (`AttitudeMenu` printed junk).
7. **Harness**: see section 4.

## 2. Numbers

| | |
|---|---|
| Engine (task 1) | 23,210 bytes from `$2000` (ends `$7AAA`, limit `$7C00`: 342 bytes left); 33 of 40 game routines written |
| Core (task 0) | 11,318 bytes, ends `$4C36` (the heap tables are at `$4C80`: 74 bytes left); `ScaleMoney`'s five Real routines still missing |
| Code banks | 48, 336,761 bytes |
| Image | 6,988 sectors |
| Stack | lowest address touched `$0F09` in `parley-combat` (the limit is `$0A00`: 1.2 KB left, 4.2 KB used) |
| Mapped heap | 8,400 of 8,728 bytes in use at the end of the fight in `parley-combat`, 56 of 64 blocks: **tight** (a larger encounter needs more; see section 5) |
| Banked heap | 15,536 of 30,720 bytes |
| Run | `camp-rest-combat` about 4 minutes, `parley-combat` about 6 minutes of the host (headless MAME) |

## 3. Findings and defects (each one is in the build now)

1. **CMOC 0.1.100 folds a comparison of two constants as unsigned**: `if ((-2) <= 2)` was false and the compiler dropped the loop, so `BuildDungeonMap` (ovl10) compiled to a
   `memset` and the call of `ScatterRareTiles`: the combat map was empty (every cell tile 0). The translator now decides a `for` loop whose bounds are both constants
   itself (no `if`), for the PC translation too (`c/game` regenerated, all seven sessions equal).
2. **The screens the harness keeps were compared in the wrong order from the 100th on**: `tools/gamecheck.py` and `tools/scr4gif.py` sorted `s100` before `s32`, so
   a session with more than 99 kept screens could only match up to there. It made `parley-combat` look as if the combat diverged after the second Q for most of this step.
   Both sort numerically now; the screen the run ends with is kept too (`lua/watch.lua`).
3. **Pictures that were not engine pictures**: the tile set loader, the icon copier and the animation size read the PC's record (finding in 8.5, now closed for all of res12, ovl13 and ovl32).
4. **An untyped `var` parameter that takes a wider value than the local that was passed** (`SelectTurnUndeadTarget(Who, Done)`, Done a byte, the callee stores a pointer
   through it): the Pascal frame has room above the byte, CMOC puts the next local or the return address there, and `TryTurnUndead` returned to address 0.
5. **Cross-bank literals again** (section 1.6): a prompt line of the combat menu showed bytes of a record.
6. **Byte order of the records inside DAX blocks** (section 1.2). Found by comparing the dice (`MB_RLOG`) of the CoCo and the host after the same key: the first die with a different range
   was `Random(100)` instead of `Random(1)`, which led to the target choice, the movement of the monster, and its carried weight.
7. **The mapped heap**: see section 5.

## 4. Tools added (debugging aids, all off unless asked)

`lua/watch.lua`: `MB_RLOG=1` logs every `Random(range) -> result` (the game keeps the two stores to `$0A00` and `$0A02` behind a flag at `$090E` that the harness sets), `MB_ITRACE=t` with
`MB_DEBUGGER=1` writes every instruction from second `t` (MAME's debugger, `build/run/itrace.txt`), `MB_DUMPRAM=1` all 512 KB, `MB_PCLOG` the program counter per frame (8.5);
`make game-run KEYS=<file>` plays another script than the session's (a shortened one). `build/run/debug_patch.json` (`{unit: [[old, new], ...]}`): `tools/mkgame.py` applies it to
the generated C of those units (probes with `DBG2(a, b)`, which logs a pair of numbers like a die; on the host `c/include/pool.h` has the same macro and `POOL_RLOG=1` prints it). `poolrad_replay`
prints the dice and, with a build made with `-DPOOLRAD_TRACE=ON`, the routines entered (`POOL_RLOG=1`), and the read index of every checkpoint (`POOL_CPLOG=1`, for `--snap`).
`tools/gread.py PREFIX NAME` reads a DGROUP global out of a run's dump. `make combat` is the exit check; `tools/statecheck.py` shows the bytes of a place that differs with `STATE_SHOW=1`
and takes the read to compare at from `STATE_SNAP=`.

## 5. Decisions and open questions

None for the human. Open for the following steps:

1. **The mapped heap is nearly full at the end of a fight** (328 bytes free, 56 of 64 table entries): a bigger encounter (the 12 monsters of a dungeon room) or an earlier moment of the same
   fight needs more. Candidates (8.9): the item and affect lists and the menu lines of the combatants to the banked heap through a window, the game variables 4 KB blocks that are still mapped
   (`TBlock400`, `TGeoCellBlock`), or a smaller `CharacterSize` record (288 bytes each for 12 to 18 characters). Not decided: a full combat was not run beyond the two sessions.
2. **Speed**: section 0.
3. **The Real arithmetic** (`ScaleMoney`: five Single routines missing at link time), sound (8.8), the real keyboard (D8), a window to play in (needs the real storage backends, 8.9).
4. **The harness times keys by the screen being still**: a prompt that never keeps the screen still for 2 s (a blinking cursor) would wait; none did in the seven sessions.
5. **Both state checks are against the host after the same read**: both explain 63 and 67 places (pointers of two heaps, picture handles, the PC's System variables); none is open.

## 6. What 8.8 starts with

Sound (plan row 8.8: the FIRQ tick, the speaker backend, the GMC backend; exit: the equivalent of `make c-sound` on the CoCo backends). `res03`'s driver is external code in the
original (`RES03.ASM`), `make sound-golden` records the tunes' hardware trace on the PC side; the CoCo side has the 6-bit DAC and the cassette bit, and the
Game Master Cartridge's PSG as the second backend. Not started.

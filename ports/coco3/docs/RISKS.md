# Classes of defect the port has met, and how each is looked for (written at step 8.7b)

Every bug of steps 8.5 to 8.7 was found by running a recorded session over the code that holds it. A session proves only the code it runs:
`tests/sessions/COVERAGE.md` says how much of the translated game that is (clang source coverage of the replays on the C translation), and a
class of defect is worth a static check as soon as one instance has been found, because the same mistake sits in code no session reaches. This
file lists the classes, the check that looks for each across the whole game, and what was read. `make risk-scan` (repository root) runs the
checks; none of them decides by itself, a section that lists sites is a list to read.

| # | Class | First found | Static check | State |
|---|---|---|---|---|
| 1 | A record copied out of a byte buffer (a DAX block) without turning its words round | 8.7 (`LoadMonster`), 8.7b (`AddLootCommand`: the shop's prices read 256 times too much) | the translator: `Move` of a byte source into a record or array of the same size is followed by `rtl_swapdesc` on the coco profile (`tools/c/p2c_expr.py move_swaps`); `riskscan.py` section 2 lists any that is not | closed: the only unswapped site was ovl03:1259 |
| 2 | A comparison of two constants with a negative one (CMOC 0.1.100 folds it as unsigned) | 8.7 | the translator decides constant `for` bounds itself; `riskscan.py` section 4 | closed |
| 3 | An untyped `var` parameter written wider than the caller's variable | 8.7 | pad locals in the translator; `riskscan.py` section 3 for globals | closed |
| 4 | A string literal handed to another bank | 8.5, 8.7 | `copy_cross_literals` in `tools/mkgame.py` | closed |
| 5 | **A typecast that loses its signedness**: `Integer(WordVar) < 0` was written `WordVar < 0` (always false on an unsigned) | 8.7b (battle-aftermath: the Spells window of the character sheet never opened on the translation, host and CoCo alike) | `make risk-scan` first part: clang's `-Wtautological-unsigned-zero-compare` over `c/game`; the translator now writes `(*(s16 *)&WordVar)` for a cast of a variable to another type of the same size | closed; the 2 remaining always-false sites are the documented quirks (`ClearTextCells` Byte < 0, `RollAttackDamage` Byte < 0) |
| 6 | **A procedure variable named as a statement is a call** (`SpellHandlers[CastingSpell];`) and the translator evaluated it and called nothing | 8.7b (combat-spells: no spell ever had an effect on the translation) | `tests/unit/test_c_translation.py` (no expression statement without effect anywhere in `c/game`) | closed; one site in the whole game (ovl22:626) |
| 7 | Words left in the PC's byte order in DGROUP | 8.5 | `riskscan.py` section 6 | read in part: the entries are overhang of a word table past its storage (`TreasureItemRows` is 0x99 words over 265 bytes of storage) or the `NOSWAP` tables; `RaceAbilityLimits` (ovl16), `DoorViewRows` (ovl18), `RestTime` and `SpellHandlers` are not run by a session yet |
| 8 | **The mapped heap is too small** | 8.6, 8.7, 8.7b | `make heap-stats` (the sessions' high water); the shop session ends with fatal 0x22 | **open** (below) |
| 9 | The stack | 8.5 | `riskscan.py` section 7 (a static bound per call chain) | no chain reaches the limit that a session runs; the static bound is above the limit for the save chain, which no session overflows |
| 10 | Real arithmetic (`ScaleMoney`, `LoseMoneyAndItemsCommand`) | 8.6 | link-time missing symbols (`riskscan.py` section 5) | **open**: five Single routines are missing; the two routines that use them are not reached by a session |
| 11 | **A local the original reads before it writes** (the byte its frame held decides) | 8.7b (character-menu: `TradeMoney`'s `Finished`, ovl19:2468) | the QUIRK notes of the Pascal (`grep -n "frame held\|stale\|never set" src/*.PAS`) | `STALE_LOCALS` in `tools/c/pas2c.py` gives `TradeMoney.Finished` the original's value; four more sites are noted and not run by a session yet: ovl03:1888 (a frame byte on entry), ovl16:1392 (`Count` never set on the first pass), ovl22:1785 (a stale local names the class), res12:839 (a function that returns what the frame held) |

## The mapped heap (class 8)

The shop (`shop-buy`, ovl06) stops on the CoCo with fatal 0x22 (no block of the mapped heap fits the request) at its first Buy. The table of the heap at the
failure (the harness' `.core` dump, `HEAPDATA`): 89 entries, 8,512 of the 8,552 bytes in use: 72 blocks of 64 bytes (`TMenuLine`: the party's items and
the shop's stock: 4,608 bytes), two blocks of 1,024 bytes (`GameVars3` and the GEO block, both `TBlock400`), six characters of 288 bytes and eight of 16 bytes
(affects). The table itself was raised from 64 to 128 entries of 4 bytes in this step (a first run failed on the table, fatal 0x20, with 56 of 64 entries used at the
end of the fight of 8.7); the heap is out of bytes, not out of entries.

What was tried: `TMenuLine` in the banked class (`placement.toml`): the game stops after 19 screens, so the item lists need more than a placement change (they are
walked by pointer chains across blocks and passed to routines that hold two of them at once; the two data windows cannot show a third).

Candidates for step 8.9, in order of what they buy: (1) item records packed to what they hold (63 of 64 bytes are used, so nothing); (2) the stock of a shop and the
loot list built straight into a banked array that `ChooseShopItem` and `FormatItemLine` reach through one window (about 4.5 KB); (3) `GameVars3` and the GEO block
to the banked heap together with their views `TBlock400` and `TGeoCellBlock` (2 KB); (4) the native globals (4,040 bytes at `$4ED0`) that no hot loop touches, moved to the paged area.
Tried and dropped: `GameVars3` (1 KB, allocated by ovl11 and cleared, never read) in the banked heap: the game hangs after loading a saved game, and the shop, `combat-spells` and
`council-guards` ran out of the freed kilobyte anyway. Not decided here: it is a design decision of D12.

## What `make risk-scan` prints

1. clang's tautological comparisons on `c/game` (`tools/c/risk_clang.sh`): the always-false ones are listed, the always-true ones (a Byte compared with `0 <=`) only counted.
2. The CoCo build's scan (`ports/coco3/tools/riskscan.py`, `build/risk/report.md`): sections 1 to 8 above. Section 8 compiles every unit with CMOC's warnings on
   (`scripts/risk_cmoc.sh`, needs the toolchain container).

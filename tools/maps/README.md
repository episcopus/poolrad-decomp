# tools/maps: one-page area maps for players

`make maps` writes one-page, US Letter landscape PDFs to `docs/maps/`: the area's 16x16 plan (walls, doors,
locked doors, event cells) with numbered markers and notes on its encounters, hints, events and secrets.
They are player aids made from the original game files, not part of the decompilation proof.

Coordinates are the game's own: a cell is written `(column,row)`, both counted 0 to 15 from the top left, the same
values the scripts keep in `[C04B]` (column) and `[C04C]` (row). The axes of every plan carry those numbers.

One spec per area in `tools/maps/areas/`, 29 in all: every GEO block of the game. Titles come from the script's own text or
from the City Hall clerk's text where it names the place; the others are descriptive and marked as inferred on the page.

| Map | Title | Source map | Spec |
|---|---|---|---|
| `docs/maps/podal-plaza.pdf` | PODAL PLAZA | `GEO1` block 18 | `areas/podal_plaza.py` |
| `docs/maps/temple-of-bane.pdf` | TEMPLE OF BANE | `GEO1` block 24 | `areas/temple_of_bane.py` |
| `docs/maps/orc-mansion.pdf` | ORC MANSION | `GEO1` block 31 | `areas/orc_mansion.py` |
| `docs/maps/stojanow-gate.pdf` | STOJANOW GATE | `GEO2` block 9 | `areas/stojanow_gate.py` |
| `docs/maps/library.pdf` | LIBRARY | `GEO2` block 15 | `areas/library.py` |
| `docs/maps/slums.pdf` | THE SLUMS | `GEO2` block 20 | `areas/slums.py` |
| `docs/maps/phlan.pdf` | NEW PHLAN | `GEO3` block 0 | `areas/phlan.py` |
| `docs/maps/kovel-mansion.pdf` | KOVEL MANSION | `GEO3` block 14 | `areas/kovel_mansion.py` |
| `docs/maps/cadorna-textile-house.pdf` | CADORNA TEXTILE HOUSE | `GEO4` block 2 | `areas/textile_house.py` |
| `docs/maps/valhingen-graveyard.pdf` | VALHINGEN GRAVEYARD | `GEO4` block 10 | `areas/valhingen_graveyard.py` |
| `docs/maps/sokal-keep.pdf` | SOKAL KEEP | `GEO4` block 21 | `areas/sokal_keep.py` |
| `docs/maps/castle-nw.pdf` | CASTLE NW | `GEO5` block 3 | `areas/castle_nw.py` |
| `docs/maps/castle-ne.pdf` | CASTLE NE | `GEO5` block 4 | `areas/castle_ne.py` |
| `docs/maps/castle-se.pdf` | CASTLE SE | `GEO5` block 5 | `areas/castle_se.py` |
| `docs/maps/valjevo-castle-yard.pdf` | VALJEVO CASTLE | `GEO5` block 6 | `areas/valjevo_castle_yard.py` |
| `docs/maps/tyranthraxus-tower.pdf` | TYRANTHRAXUS' TOWER | `GEO5` block 7 | `areas/tyranthraxus_tower.py` |
| `docs/maps/buccaneer-base.pdf` | BUCCANEER BASE | `GEO6` block 1 | `areas/buccaneer_base.py` |
| `docs/maps/wilderness-cave.pdf` | SMALL DARK CAVE | `GEO6` block 25 | `areas/wilderness_cave.py` |
| `docs/maps/zhentil-outpost.pdf` | ZHENTIL OUTPOST | `GEO6` block 28 | `areas/zhentil_outpost.py` |
| `docs/maps/nomad-camp.pdf` | NOMAD CAMP | `GEO7` block 17 | `areas/nomad_camp.py` |
| `docs/maps/pyramid-1.pdf` | PYRAMID: MAZE LEVEL | `GEO7` block 22 | `areas/pyramid_1.py` |
| `docs/maps/pyramid-2.pdf` | YARASH'S LAB | `GEO7` block 23 | `areas/pyramid_2.py` |
| `docs/maps/north-shore.pdf` | NORTH SHORE | `GEO7` block 26 | `areas/north_shore.py` |
| `docs/maps/kobold-caves.pdf` | KOBOLD CAVES | `GEO8` block 13 | `areas/kobold_caves.py` |
| `docs/maps/ruined-castle.pdf` | RUINED CASTLE | `GEO8` block 16 | `areas/ruined_castle.py` |
| `docs/maps/east-wilderness.pdf` | EAST WILDERNESS | `GEO8` block 27 | `areas/east_wilderness.py` |
| `docs/maps/kutos-well.pdf` | KUTO'S WELL | `GEO8` block 29 | `areas/kutos_well.py` |
| `docs/maps/lizardman-tunnels.pdf` | LIZARD MAN TUNNELS | `GEO8` block 30 | `areas/lizardman_tunnels.py` |
| `docs/maps/hidden-catacombs.pdf` | HIDDEN CATACOMBS | `GEO8` block 32 | `areas/hidden_catacombs.py` |

Three script blocks have no map data and so no page: the City Hall interior (`ECL3` block 8), the Training Hall
interior (`ECL3` block 11) and Diogenes' cave (`ECL6` block 19) run as menu scenes. Some GEO blocks are not the area
their name suggests (for example `GEO6` block 25 and `GEO8` block 27 are the small random caves, and the world maps of
the wilderness areas are not 16x16 plans); each page says what its plan is.

```
uv run --with reportlab python tools/maps/build.py            # all (make maps does this)
uv run --with reportlab python tools/maps/build.py slums      # one
python3 tools/maps/ecldis.py ECL4 21                          # the area script as text
```

`reportlab` is not a project dependency; `uv run --with` supplies it. The fonts are Arial from macOS
(`/System/Library/Fonts/Supplemental`); elsewhere the built-in Helvetica is used.

## Files

- `geoq.py`: reads a `GEO#.DAX` block into cells (four wall ids, four door kinds, event id, interior flag).
- `ecldis.py`: an ECL disassembler. Operand counts and types follow `src/OVL03.PAS` (`DispatchCommand` and each
  `*Command`) and `src/OVL07.PAS` (`DecodeOperands`, `DecodeString`: strings are 6-bit packed). Code base is `$9900`
  and the block body after the leading `5000` word maps to `$9900 + offset`.
- `mapkit.py`: draws a page from a spec (see its docstring for the keys). Text is fitted by shrinking the body font.
- `areas/*.py`: the content of each page (one `SPEC` per file; `build.py` discovers them). The spec keys, including
  the later additions (`arrivals`, `wrap`, `extra_starts`, `hedge_ids`, `illusion_edges`, `grey_rects`), are in `mapkit.py`.

## How the content was read (so it can be re-checked)

- The cell's event id is the index into the script's `ONGOTO` table (the `search` entry), for example
  `ECL4` block 21 entry `99C9`. Handler addresses come from that table; `ecldis.py` prints each one.
- `ADDMON kind, count, picture` adds `count` copies of monster `kind` from `MON<tileset>CHA.DAX`
  (`AddEncounterGroupCommand`). Level, AC and HP are the stored record fields (`TCharacter`: AC = 60 minus
  the byte at +$A9, HP at +$32, level at +$73).
- `LOOT` operands 1..7 are copper, silver, electrum, gold, platinum, gems, jewelry; the eighth is an
  `ITEM<tileset>.DAX` block (below $80) or a treasure table of (value minus $80) rolls.
- Door kinds: 0 blocked, 1 open, 2 locked (Bash, Pick or Knock), 3 a harder lock (`OVL14`). The reachability
  shading is a breadth first search from the arrival cell using those kinds.
- Script flags `[4A00]..[4A1F]` are cleared whenever the area script is (re)loaded (`InitScript`), so
  they last one visit; higher flags persist. The pages say "resets when you re-land" accordingly.
- Phlan "locked after dark": the step entry locks a door when the party stands on a cell with event E facing a
  wall id W for the pairs `(0, 9)`, `(4, 7)`, `(26, 11)` while the sky variable is the dark value. That the
  variable means night is an inference from the 8 or 11 palette choice, not proven.

## Reading an ECL script (cheat sheet)

- Entry points (five GOTOs at the top, `ecldis.py` prints them): step, search, pre-camp, camp-interrupted, initial.
  On arrival the initial entry runs; after every step the step entry then the search entry run. The search entry
  usually reads the event byte of the party's cell (`AND 127,[C04F],[6E82]`) and dispatches with `ONGOTO`: the
  cell's event id is the index into that table (id 0 is the first address). Cells with an id beyond the table do nothing.
- Special script addresses: `[C04B]` party column, `[C04C]` row, `[C04D]` facing (0 north, 1 east, 2 south, 3 west),
  `[C04E]` wall id ahead, `[C04F]` event byte (bit 7 is the interior flag); `[6DD5]` is set when the party walks off a
  map edge; `[6DCA]` bit 0 is search mode (the S key); `[6E12]` is the tile set the next `NEWECL` loads from
  (`ECL<n>.DAX`, `GEO<n>.DAX`, `MON<n>CHA.DAX`, `ITEM<n>.DAX`).
- `[4A00]..[4A1F]` reset on every (re)load of the area script, so they mean "this visit"; `[4A20]` and up persist.
- `ENCACTION` is the encounter menu (combat, wait, flee, advance or parlay: parlay is offered only when the distance
  is 0); `ATTITUDE` then `INSTR n` asks for a typed word of at most n letters (passwords are `CMP`ed with a literal);
  `ADDMON kind, count, picture` adds monsters; `COMBAT` fights them; `LOOT` pays out; `GETTABLE table, index, dest`
  reads one byte; `IF=`, `IF<` and so on guard only the next command; `GOSUB`/`RETURN` and `ONGOSUB` call routines.
- A `CMP2 a, b, c, d` is true when both pairs are equal (used for "event E facing wall W" door locks).

## Known gaps

- The elf's runic scroll (Sokal Keep) is shown as glyph tiles; its two passwords are inferred from the letter
  pattern of the tile pairs, not rendered.
- Treasure-table rolls (for example the slums' grain tossers) are not expanded.
- Where the "LUX" word of Sokal Keep is learned outside the area is not traced.
- Statistics are the monster record values; the engine may adjust them in combat.

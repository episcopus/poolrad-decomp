# tools/maps: one-page area maps for players

`make maps` writes one-page, US Letter landscape PDFs to `docs/maps/`: the area's 16x16 plan (walls, doors,
locked doors, event cells) with numbered markers and notes on its encounters, hints, events and secrets.
They are player aids made from the original game files, not part of the decompilation proof.

| Map | Source blocks | Spec |
|---|---|---|
One spec per area in `tools/maps/areas/`; the table of every area and its source blocks is the `SOURCE` line printed on each page.

| Map | Source blocks | Spec |
|---|---|---|
| `docs/maps/sokal-keep.pdf` | `GEO4` block 21, `ECL4` block 21 | `areas/sokal_keep.py` |
| `docs/maps/phlan.pdf` (New Phlan, the starting town) | `GEO3` block 0, `ECL3` block 0 | `areas/phlan.py` |
| `docs/maps/slums.pdf` | `GEO2` block 20, `ECL2` block 20 | `areas/slums.py` |

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
- `areas/*.py`: the content of each page (one `SPEC` per file; `build.py` discovers them).

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

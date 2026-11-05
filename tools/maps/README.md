# tools/maps: one-page area maps for players

`make maps` writes one-page, US Letter landscape PDFs to `docs/maps/`: the area's 16x16 plan (walls, doors,
locked doors, event cells) with numbered markers and notes on its encounters, hints, events and secrets.
They are player aids made from the original game files, not part of the decompilation proof.

| Map | Source blocks | Spec |
|---|---|---|
| `docs/maps/sokal-keep.pdf` | `GEO4` block 21, `ECL4` block 21 | `sokal_keep.py` |
| `docs/maps/phlan.pdf` (New Phlan, the starting town) | `GEO3` block 0, `ECL3` block 0 | `phlan.py` |
| `docs/maps/slums.pdf` | `GEO2` block 20, `ECL2` block 20 | `slums.py` |

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
- `sokal_keep.py`, `phlan.py`, `slums.py`: the content of each page.

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

## Known gaps

- The elf's runic scroll (Sokal Keep) is shown as glyph tiles; its two passwords are inferred from the letter
  pattern of the tile pairs, not rendered.
- Treasure-table rolls (for example the slums' grain tossers) are not expanded.
- Where the "LUX" word of Sokal Keep is learned outside the area is not traced.
- Statistics are the monster record values; the engine may adjust them in combat.

# Review: ovl11

decompiler: dec-4 (Agent trailer of a864d03; the unit was merged in d6165f3)
reviewer: rev-4
date: 2026-10-12
commit: dfe4726 (re-review on current main; the first review was of d6165f3, blocked by the runtime map)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl11` (rerun, on current main): `StartGame` 1512 bytes plus 45 pool,
`ovl11_init` 5; `unit: complete, 1562 bytes of code plus 0 of paragraph padding cover the original
segment`, 2 matched, 0 differ, 0 stubs. `make readability UNIT=ovl11` is clean. Packet:
`build/packets/ovl11.md`.

The blocker from the first review is gone: the `Randomize` call at ovl11:0602 (`lcall 0AF8:1247`)
now resolves, so the unit matches on main and can be reviewed.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix OVL11 unit comment: it still cites "(whitepaper 5.2.1, 5.12)". The loader's own whitepaper entry is 3.2.2 (the heading "The start-up loader StartGame"); 5.2.1 is only where the special view codes it sets are described and 5.12 is the copy protection that follows. Cite 3.2.2. (carried from the first review, still open)
- [ ] should-fix POOLVARS.PAS `ds6F68`/`ds6F69` and whitepaper 5.2.1: both name `ovl11_fn_0435` as the writer, but ovl11:0435 is not a routine: it lies inside `StartGame` (the phantom the unit's commit corrected). Replace it with `StartGame` (the acting-operator note of 2026-10-12, `escalate-general-20261012060445`, carries the same task for the next documentarian or ovl11 decompiler). (carried from the first review, still open)
- [ ] should-fix `TPresenceSlot` in POOLVARS.PAS: the fields of the 4-byte element at DS:6AAE are still named `A` and `B`, placeholders for a meaning this unit does not show. The record comment says only what the loader does with elements 2 and 3; add `Purpose unknown:` and do not read as names (for example `UnknownA`/`UnknownB`). (carried from the first review, still open)
- [ ] note StartGame: the loop counter is the global `ds465C` (DS:465C), reused by all five loops (ovl11:0130, 02CA, 035E, 0502 and the 0353 fills). The routine comment says so; a `QUIRK` mark is not needed (the original does it).
- [ ] note `ovl11_init` (ovl11:0615) is commented (empty `55 89 E5 5D CB` plus 4 bytes of padding).

## What was verified

1. `make match UNIT=ovl11` rerun on current main: complete, both routines L2. `make readability UNIT=ovl11` is clean.
2. Names true and specific: `StartGame` is the start-up loader `src/POOL.PAS` runs first; the three cell tables `ds4EC0`/`ds5050`/`ds51E0`; the heap blocks `TBlock400`/`TBlock588`/`TBlock924`/`TBlock1E00`; the file layer now uses the renamed `OpenGameFile` (was `res05_fn_025D`). Every `dsXXXX` global the routine uses has a `POOLVARS.PAS` comment with the write address.
3. The heap: seven `New` of $800, $800, $400, $1E00, $588, $924 and $400 bytes at ovl11:0034..00A0, matching the routine comment and the `TBlock...` types.
4. The tables: the loop runs `ds465C := 0..$C7` (ovl11:0245); even cells take `$B800 + (i div 2)*5`, odd `$BA00 + (i div 2)*5` (ovl11:013B..0182); `ds5050[i] := i*40` (ovl11:018B..019B); `ds51E0[i] := (i div 4)*$A + $B800/$BA00/$BC00/$BE00` by `i mod 4` (ovl11:019F..0241). `LastCell`, `CellsPerRow`, `TextSegOdd/Even` and `Plane1..4` name the constants.
5. The `FillChar` clears and the global initialisations (ovl11:024F..0456) match the source line by line; the loop counter is the documented global `ds465C`.
6. The save-load half matches: the path save `ds4661 := ds547C`, `ds547C := ''` and `ovl25_e3`; `res06_fn_0626(0,$18,$A,'Loading...Please Wait')`; the 12 `COMSPR` sprites plus (`$19,$19`); the `'ITEMS'` file path `ds2614[TileSet] + Chr(ds547D) + ':'`; `OpenGameFile`, `Reset`, `Seek(2)`, `BlockRead` of `LoadBlockSize = $810`, `Close`; the path restore; `Randomize` (ovl11:0602, `0AF8:1247`); `ovl22_e10`; `ovl12_e1`.
7. Types fit: `ds465C`, `ds4660`, `ds547D` `Byte`; `ds4661` `string[40]`; `ds468C` `file`; the tables `array[0..$C7] of Word`; `ds6AAEWords` `array[0..3] of TPresenceSlot`; `ds6AFB` `array[0..2] of TLoadSlot`.
8. Quirks: none beyond the global loop counter, which is documented. No raw machine code or assembler routine.
9. Whitepaper 3.2.2 and 5.12 record the loader (start-up, the heap blocks, the cell tables, the save-load), tagged [V].

## Verdict

Passed. The code matches on current main and every name, type and comment that the unit owns is true to the bytes; the three open items are should-fixes (they do not block), and the blocker from the first review is resolved.

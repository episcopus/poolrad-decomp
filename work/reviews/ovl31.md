# Review: ovl31

decompiler: dec-8 (Agent trailer of 92143f1, the 23 routines); dec-11 reconciled the shared types in 7a3ff90
reviewer: rev-4
date: 2026-10-12
commit: 7eb2494

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl31` (rerun): 23 routines matched, `unit: complete, 4864 bytes of code plus 0 of
paragraph padding`. `make readability UNIT=ovl31` is clean. Packet: `build/packets/ovl31.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix OVL31 unit comment: "Everything that changes the map runs only in view mode 5 (ds49F3)" is broader than the code. Only `RemoveCombatant` and `PlaceCombatant` test `ds49F3 = 5` (ovl31:0E11, ovl31:10A7); `RebuildOccupancy` (ovl31:03A0) writes `CellOccupant` and `CombatantViewCol/Row` with no gate and is called by ovl10, ovl13 and ovl24. Whitepaper 5.5.1 scopes the same claim to "Death and bodies". Scope the sentence to the two routines (or say the map-data changes happen through them).
- [ ] note ovl31_e2/ovl31_e3: both are honest `Purpose unknown:` stubs with their calls (`res07_fn_2A0D(0, 8)`/`(8, 0)` and `(0, 0)`/`(8, 8)` under `VideoAdapter = 1`), named by their re/symbols.toml placeholders. Fine.
- [ ] note RemoveCombatant: the two big QUIRKs are marked (`ovl31:0E41` reads `BodyTable[ds70C7]`, the FreeSpriteList loop counter, on every pass instead of `BodyTable[I]`; `ovl31:0E69` the early exit skips `res03_fn_01A5(10)`), and so is the `Spare` frame (`ovl31:0E14`).
- [ ] note MoveCombatCursor/SetCombatantIcon: their caller lists cross-check against the packet; `SetCombatantIcon`'s ovl08 caller is real (ovl08.bin calls the stub 03E0:0057 at ovl08:0BC3), so the packet's short list is not the whole truth there. No change.

## What was verified

1. `make match UNIT=ovl31` rerun: complete, all 23 routines L2 (`FootprintCell` 104 bytes, `UpdateViewPositions` 123, `ovl31_e2` 34, `ovl31_e3` 34, `DrawCursorAt` 430, `RedrawMapCell` 203, `RebuildOccupancy` 286, `GetMapCell` 109, `RedrawGround` 446, `IsInView` 49, `IsCombatantInView` 186, `ScrollViewTo` 450, `MoveCombatCursor` 354, `SetCombatantIcon` 239, `CombatantX/Y/Kind` 40 each, `CombatantIndex` 90, `ProbeStep` 344, `RemoveCombatant` 662, `PlaceCombatant` 497, `ShowCursorOn` 99, `ovl31_init` 5). `make readability UNIT=ovl31` is clean.
2. Names true and specific: the view (`CombatMap^.ViewX/ViewY`, `CombatMap^.Cells`, `CombatMap^.ShowCursor`, `CursorKind`), the combatants (`CombatantTable`, `CombatantRecord`, `CombatantViewCol/Row`, `CellOccupant`, `BodyTable`/`BodyCount`), the tile table `CombatTiles` (`.Picture`, `.Cost`), `Footprints`, `DyingPicture`, `ds70C7`; all carry `POOLVARS.PAS` comments with `re/dseg.toml` evidence.
3. Types fit: map/view cells `ShortInt`, columns/rows `Byte` in `CombatantTable`, `CombatantViewCol/Row` `ShortInt`, `FootprintCell`'s `DX`/`DY` `ShortInt`, `CombatantX/Y` `ShortInt`, `IsInView`/`IsCombatantInView` `Boolean`, `ProbeStep`'s `Occupant`/`Tile` `Byte`, `BodyTable` `TBody` records.
4. Comments give addresses and meaning; the ones checked hold against the packet: the footprint kinds 1..4 and the `DX >= 0` existence test (ovl31:0000); the view-position recompute (ovl31:0068); the cursor redraw with the ground picture plus `CursorIcon = $19` (`ovl31:0236`); `RebuildOccupancy`'s clear and per-footprint index write (ovl31:03A0); `GetMapCell`'s 50x25 bounds (`MapLastCol = $31`, `MapLastRow = $18`, ovl31:04C7/04D3); `ScrollViewTo`'s margin, the centre bounds 3..46/3..21 (`MaxCentreCol = $2E` at ovl31:08A2, `MaxCentreRow = $15` at ovl31:08DA), the 49-cell redraw and `NoReach`; `MoveCombatCursor`'s scroll/redraw/clamp order; `SetCombatantIcon`'s `IconSet div 4` erase test and `MoveCombatCursor(..., DirNone)` bring-into-view; `ProbeStep`'s cost rule with `TileKept`/`FirstProbeTile`; `RemoveCombatant`'s body record, `TileBody`, four cleared combat fields and the `res03_fn_01A5` bracket; `PlaceCombatant`'s `CombatSize and KindMask` and Restore path; `ShowCursorOn`'s kind 1 reset.
5. Quirks kept and marked: `ovl31:071D`, `ovl31:0C71` (`CombatantIndex` with a count of 0), `ovl31:0E14`, `ovl31:0E41`, `ovl31:0E69`. No raw machine code or assembler routine.
6. Caller lists cross-check: `FootprintCell`, `UpdateViewPositions`, `ovl31_e2`/`e3`, `DrawCursorAt`, `RedrawMapCell`, `RebuildOccupancy`, `GetMapCell`, `RedrawGround`, `IsInView`, `ScrollViewTo`, `CombatantX/Y/Kind/Index`, `ProbeStep`, `RemoveCombatant`, `PlaceCombatant`, `ShowCursorOn` all match the packet; the `MoveCombatCursor` list is packet-capped at 12.
7. Signatures this unit set (`Footprints`, `TCombatMap`, `TBody`, `CombatTiles`, `DrawCellPicture`, `DrawIcon`, `res07_fn_0D71`/`1B52`/`2A0D`, `res03_fn_01A5`/`00DC`, `DelayCounted`, `ds2736`/`ds273F`) are recorded and match the pushes.
8. Whitepaper 5.5.1 records what the unit taught (the map layout, the combatants, the footprint kinds, the view and cursor, the death and bodies, the QUIRK).

## Verdict

Passed. Every name, type and comment is true to the bytes; the unit comment's `ds49F3` sentence is a should-fix scope issue and the notes are informational.

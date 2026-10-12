# Review: ovl29

decompiler: dec-5, dec-9 (Agent trailers of 4ac9311, 90cebbd, 9a39e79), dec-8 (b573e38); the review fixes are 590bf3a (dec-11) and dafc8cf (dec-13)
reviewer: rev-4
date: 2026-10-12
commit: e2a89f4 (re-review after 590bf3a and dafc8cf; the first review was of 11ef975)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl29` (rerun): `unit: complete`, 13 routines, 4619 bytes (`DrawWallMap` 341,
`SetWallDescriptors` 31, `DrawWallDescriptors` 157, `DrawWallPiece` 270, `CellInRange` 49,
`DoorKindAt` 299, `WallIdAt` 255, `EventByteAt` 121, `StepDisplay` 10, `DrawWallView` 1975,
`LoadWallSet` 661 plus 84 pool, `Load3DMap` 319 plus 42, `ovl29_init` 5), 0 differ, 0 stubs.
`make readability UNIT=ovl29` is clean. Packet: `build/packets/ovl29.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-4, commit 11ef975)

- [x] must-fix DrawWallMap/DrawWallPiece/DrawWallView: the piece-index constants were reused for the side bits, the per-cell tile steps and the `Put8x8Symbol` Attr/Direct. 590bf3a adds `WallBitNorth/East/South/West` (1/2/4/8), `FarCellStep`/`MidCellStep`/`NearCellStep` (2/3/7) and `DrawDirect`/`MapSymbolAttr`/`WallTileAttr` (1/0/1) and uses them: `Inc(Symbol, WallBitEast)` etc. (ovl29:0000), `Dec(Shift, FarCellStep)` / `Inc(Shift, MidCellStep)` / `Inc(Shift, NearCellStep)` and `Put8x8Symbol(..., DrawDirect, MapSymbolAttr/WallTileAttr)`. The piece constants now index `WallPieceCol/Row/FirstTile/Width/Height` and pass the `Piece` argument, where they are right.
- [x] note SetWallDescriptors: dafc8cf names the parameters `Wall1..Wall4` in the comment (was "A..D") and drops the leftover frame line, and records `res07_fn_2632(A, B, C, D: Word; E: Byte; F, G: Pointer)` in `RES07.PAS` and `re/symbols.toml`.
- [x] note CellInRange/ovl29_init: dafc8cf gives `CellInRange` a parameter-level comment (the four compare order) and an address comment for the empty initialisation at ovl29:1206.

### This cycle (rev-4)

- [ ] note DrawWallView: the two `Unused1`/`Unused2` locals (`QUIRK ovl29:05FD`) and `DrawWallMap`'s 256-byte `Unused: string` (`QUIRK ovl29:0003`) are frame fillers, honestly marked.
- [ ] note LoadWallSet: the comment and whitepaper 4.2.4 agree that the size check does not ask for a multiple of `$30C` and a partial last wallset is copied whole; `QUIRK ovl29:101A` (BlockId 0 -> 10 -> 0) is marked.

## What was verified

1. `make match UNIT=ovl29` rerun: complete, all 13 routines L2. `make readability UNIT=ovl29` is clean.
2. The 590bf3a fix is complete and correct: no piece constant is used as a side bit, a cell step or a Direct/Attr any more (`grep` over the whole file), and `DrawWallMap`'s `Inc(Symbol, WallBitNorth/East/South/West)` and `DrawWallView`'s `FarCellStep`/`MidCellStep`/`NearCellStep` match the packet's push values (1/2/4/8 and 2/3/7).
3. Names, types and the rest of the comments are unchanged from the first review and were verified there: the four direction constants, the view constants, `WallTiles^[Wall, Tile]`, the GEO planes, the off-map wrap, the two `case` selectors, `CellInRange`, `DrawWallPiece`'s `WallPieceFirstTile/Width/Height` rectangle, `DrawWallView`'s far/middle/near rows down to `Depth = $FF`, `LoadWallSet`'s `WALLDEF<TileSet>.DAX` and `$30C` wallsets, and `Load3DMap`'s four planes.
4. Quirks kept and marked: `ovl29:0003`, `ovl29:047B` (WallIdAt's unassigned result for a Dir outside 0/2/4/6), `ovl29:05FD`, `ovl29:101A`. No raw machine code or assembler routine.
5. Whitepaper 4.2.1, 4.2.4 and 5.2.2 record what the unit taught and were updated with the same corrections.

## Verdict

Passed. The must-fix (the reused piece constants) is fixed in 590bf3a, the three notes are fixed in dafc8cf, and the remaining two notes are informational.

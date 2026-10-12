# Review: ovl29

decompiler: dec-5, dec-9 (Agent trailers of 4ac9311, 90cebbd, 9a39e79) and dec-8 (b573e38)
reviewer: rev-4
date: 2026-10-12
commit: 11ef975

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl29` (rerun): 13 routines matched (`DrawWallMap` 341 bytes, `SetWallDescriptors`
31, `DrawWallDescriptors` 157, `DrawWallPiece` 270, `CellInRange` 49, `DoorKindAt` 299, `WallIdAt`
255, `EventByteAt` 121, `StepDisplay` 10, `DrawWallView` 1975, `LoadWallSet` 661 plus 84 pool,
`Load3DMap` 319 plus 42, `ovl29_init` 5); `unit: complete, 4619 bytes of code plus 0 of paragraph
padding cover the original segment`. `make readability UNIT=ovl29` is clean. Packet:
`build/packets/ovl29.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix DrawWallMap/DrawWallPiece/DrawWallView: the ten piece-index constants (`PieceFarFront`..`PieceFarEdge`) are reused for unrelated values, so the names are false where they are used. In `DrawWallMap` (ovl29:0000) the north/east/south/west wall bits are added as `Inc(Symbol)`, `Inc(Symbol, PieceFarRight)`, `Inc(Symbol, PieceMidLeft)`, `Inc(Symbol, PieceNearRight)`, i.e. 1/2/4/8, and the `Put8x8Symbol` Attr is `PieceFarFront` (0); `DrawWallPiece` passes `PieceFarLeft` (1) and, in the far row, the literal `2` as its `Piece` argument. In `DrawWallView` the per-cell tile steps are `Dec(Shift, PieceFarRight)`/`Inc(Shift, PieceFarRight)` (2), `Inc(Shift, PieceMidFront)`/`Dec(Shift, PieceMidFront)` (3) and `Inc(Shift, PieceNearLeft)`/`Dec(Shift, PieceNearLeft)` (7). A reader reads `Inc(Shift, PieceMidFront)` as "move by the middle-front piece", and the north bit as "the far-front piece". Use plain named constants for the roles (a side-bit set and the per-cell steps), or the numbers with the comment, and keep the piece constants for `WallPieceCol/Row/Width/...` indices and the `Piece` argument, where they are right. (fixed in 590bf3a)
- [ ] note DrawWallView: the side-bit/step values coincide with the piece indices (2/3/4/7/8), which is why the reuse compiles; the comment "front walls (piece 0, 2 tiles per cell)" states the real meaning, so the bytes are not in doubt.
- [ ] note DrawWallView: two `Unused1`/`Unused2` locals are marked `QUIRK ovl29:05FD`; `DrawWallMap`'s 256-byte `Unused: string` is `QUIRK ovl29:0003`. Both are frame fillers, honestly marked.
- [ ] note LoadWallSet: whitepaper 4.2.4 and the comment both say the size check does not ask for a multiple of `$30C` and a partial last wallset is copied whole; the QUIRK `ovl29:101A` (BlockId 0 becomes 10 and back) is marked.

## What was verified

1. `make match UNIT=ovl29` rerun: complete, all 13 routines L2. `make readability UNIT=ovl29` is clean.
2. Names true and specific (apart from the reused piece constants above): `DrawWallMap`, `SetWallDescriptors`, `DrawWallDescriptors`, `DrawWallPiece`, `CellInRange`, `DoorKindAt`, `WallIdAt`, `EventByteAt`, `StepDisplay`, `DrawWallView`, `LoadWallSet`, `Load3DMap`; the direction constants `DirNorth/East/South/West` (0/2/4/6) and the view constants `MapLast`/`ViewLast`/`ViewLeft`/`ViewDepth`/`GeoBlockSize`/`GeoPlaneSize`/`WallSetSize`/`LastWallSlot`/`WallsPerSet`/`LastWallTile`.
3. Types fit: coordinates `ShortInt`, map/grid positions `Integer`, dirs/pieces/tile numbers `Byte`, `WallTiles^[Wall, Tile]` and `GeoCells^.WallsNE/WallsSW/Events[Row, Col]` as declared, `WallPieceCol/Row` `Integer`; `DoorKindAt`/`WallIdAt`/`EventByteAt` return `Byte`, `CellInRange` a `Boolean`, `DoKnock`'s counterpart `DoBash`/`DoPick` untouched.
4. Comments give addresses and meaning; the ones checked hold: `DrawWallMap`'s 11x11 window, the party-cell clamp to 0..5, the four side bits and the arrow `PartyArrow + Dir div 2` (`Dir shr 1 + PartyArrow`), `Put8x8Symbol(..., 1, ...)`; `DrawWallDescriptors`'s four `res07_fn_2632` calls; `DrawWallPiece`'s `WallPieceFirstTile/Width/Height` rectangle and the 0..ViewLast skip; `CellInRange`'s four compares; `DoorKindAt`/`WallIdAt`/`EventByteAt`'s off-map rule (`ds84DC = 0 or $A` answers 0, else wrap) and the nibble/bit-pair extraction (`WallsNE` high = north, low = east; `WallsSW` high = south, low = west; door bits 0-1/2-3/4-5/6-7); `DrawWallView`'s `WallMapMode` branch, the `Dir + 6`/`+ 4`/`+ 2` left/back/right dirs, the far/middle/near rows and `Depth` down to `$FF`; `LoadWallSet`'s `WALLDEF<TileSet>.DAX`, the `$30C` wallsets, the `ds6AAEWords` pairs, `Delta` (`SymbolBase`), `Load8x8Bank` block numbering (`BlockId * 10 + n`) and the `ds272C` bump; `Load3DMap`'s GEO block into the four planes.
5. Callers match the packet: `DrawWallMap`/`DrawWallView` from ShowAreaView and the movement loop, `SetWallDescriptors` from ovl26's `ShowAreaView`, `DrawWallDescriptors`/`DrawWallPiece`/`StepDisplay` from within the unit, `WallIdAt` from ShowAreaView and `DoorKindAt`, `CellInRange` from the three readers, and `LoadWallSet`/`Load3DMap` from ovl29's callers.
6. Quirks kept and marked: `ovl29:0003` (DrawWallMap's unused 256 bytes), `ovl29:047B` (WallIdAt's unassigned result for a Dir outside 0/2/4/6), `ovl29:05FD` (the two unused DrawWallView locals), `ovl29:101A` (LoadWallSet's BlockId 0 -> 10 -> 0). No `inline`/`db`/`assembler`.
7. The map's phantom `ovl29:0143` was removed (b573e38); the routine is `DrawWallMap`'s tail. The `SetWallDescriptors` signature (`retf 8`) and the other frame lines are recorded.
8. Whitepaper 4.2.1, 4.2.4 and 5.2.2 record what the unit taught (the GEO planes, the wall ids and doors, the wallset layout, the view pieces and the walk).

## Verdict

Not passed. One must-fix: the piece-index constants are reused for the side bits, the per-cell tile steps and the `Put8x8Symbol` Attr, where their names do not describe those values.

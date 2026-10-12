# Review: ovl29

decompiler: dec-5, dec-9, dec-11, dec-8 (Agent trailers of b3cf424, 4ac9311, 90cebbd, 9a39e79, 590bf3a, b573e38)
reviewer: rev-5
date: 2026-10-12
commit: 381991a

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Round 2. Round 1 (rev-4, commit 11ef975) failed on the reused piece-index constants,
fixed in 590bf3a (ticked in 6c48e4e); dec-8 also removed the phantom ovl29:0143 entry
(b573e38). This round re-runs the checklist on the fixed source.

`make match UNIT=ovl29` (rerun): 13 routines matched (`DrawWallMap` 341,
`SetWallDescriptors` 31, `DrawWallDescriptors` 157, `DrawWallPiece` 270,
`CellInRange` 49, `DoorKindAt` 299, `WallIdAt` 255, `EventByteAt` 121,
`StepDisplay` 10, `DrawWallView` 1975, `LoadWallSet` 661 plus 84 pool,
`Load3DMap` 319 plus 42, `ovl29_init` 5); `unit: complete, 4619 bytes of code plus
0 of paragraph padding cover the original segment`. `make readability UNIT=ovl29` is
clean. Packet: `build/packets/ovl29.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in round 1 (rev-4, fixed in 590bf3a unless noted)

- [x] must-fix DrawWallMap/DrawWallPiece/DrawWallView: the ten piece-index constants were reused for side bits, per-cell steps and the Put8x8Symbol Attr. (fixed in 590bf3a: WallBitNorth/East/South/West, FarCellStep/MidCellStep/NearCellStep, DrawDirect/MapSymbolAttr/WallTileAttr, used consistently)
- [ ] note DrawWallView: the side-bit/step values coincide with the piece indices, which is why the reuse compiles. (carried; still true)
- [ ] note DrawWallMap/Unused and DrawWallView/Unused1/Unused2 frame fillers, honestly marked QUIRKs. (carried; still true)
- [ ] note LoadWallSet: the non-multiple-of-$30C size check and QUIRK ovl29:101A. (carried; still true)

### This cycle (rev-5)

- [ ] must-fix DrawWallDescriptors: the stub this unit set in RES07.PAS (`procedure res07_fn_2632(A, B, C, D: Word; E: Byte; F, G: Pointer)`, added by dec-5 in b3cf424) has no `signature` in re/symbols.toml (checklist item 9). The recorded signature must be exactly that string: the four calls push A=2, B, C=$B, D as words, E the descriptor byte, F=@ds260A and G=DrawBuf as far pointers (ovl29:0177..020A).
- [ ] should-fix ovl29_init: the empty initialisation at ovl29:1206 (`55 89 E5 5D CB`) has no comment and no address. Every reviewed unit carries an init comment with the address.
- [ ] should-fix OVL29 unit comment: cites "(whitepaper 4.2.1, 4.2.4, 5.2)". The 3D-view half of the unit is section 5.2.2; cite it (prior reviews required the exact section).
- [ ] should-fix SetWallDescriptors/CellInRange: the skeleton frame comments ("retf 8: 8 bytes of parameters; 0 bytes of locals", "retf 4: ...; 2 bytes of locals") were left above the real comments. Remove them, as the ovl28 round 1 fix did for FreeSpriteList.
- [ ] should-fix SetWallDescriptors: "Stores the four wall view descriptors: A..D into ds6A60..ds6A63". The parameters are Wall1..Wall4; "A..D" names nothing. Say Wall1..Wall4.

Round 2 verification (all checked against the bytes): the WallBit/FarCellStep/MidCellStep/NearCellStep/Direct/Attr constants are used only in their roles (DrawWallMap 109..116, DrawWallPiece 161, DrawWallView 326..468); DrawWallMap's clamp, $104 base, side bits, arrow and Direct-1/Attr-0 calls match; SetWallDescriptors stores Wall1..Wall4 into ds6A60..ds6A63 in push order; DrawWallDescriptors' four calls match the comment letter for letter; DrawWallPiece's rectangle, clip, tile test and Direct-1/Attr-1 call match; CellInRange's compare order matches its comment; DoorKindAt/WallIdAt/EventByteAt match (nibbles, bit pairs, +$200 event plane, the ds84DC 0/$A rule, the wrap, QUIRK ovl29:047B's unassigned Dir); the ovl14 movement reading of DoorKindAt (0 solid, 1 open, 2/3 locked) is backed by DoWildernessMenu's matched arms; DrawWallView's WallMapMode branch, DirLeft/Back/Right mods, far/middle/near loops, edge logic, piece calls and Depth-$FF exit match; LoadWallSet's fatal condition, Delta, repeat-Move, SetIn [1..3] slot test, $FFFF marks, ds272C-gated Delta add, BlockId*10+WallSet numbering, QUIRK ovl29:101A and the (BlockId, First) record match; Load3DMap's $402 check, four plane Moves, FreeMem and VarGeoBlock match; TGeoCellBlock/TWallTiles/TWallSets/WallPiece tables/ds260A/VarGeoBlock/ds84DC/WallMapMode declarations match every use; interface order is address order; no inline, db or assembler; whitepaper 4.2.1, 4.2.4 and 5.2.2 cover the unit and agree with the source.

## Verdict

Not passed. One must-fix: the res07_fn_2632 stub signature this unit set is missing from re/symbols.toml.

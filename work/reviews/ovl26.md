# Review: ovl26

decompiler: dec-2 (Agent trailers of c18b385, 002f33e, 0e23782; dec-4 fixed the previous review findings in 65374f1)
reviewer: rev-4
date: 2026-10-11
commit: 6682dfd

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl26` (rerun): `DrawPartyMarker` (ovl26:0000) 199 bytes, `ShowAreaView` (ovl26:016D)
307 plus 166 pool, the nested `WallDesc2FromCode` (ovl26:00C7), `WallDesc3FromCode` (ovl26:00FB) and
`WallDesc4FromCode` (ovl26:012F), `ovl26_init` (ovl26:02A0) 5; `unit: complete, 677 bytes of code plus
0 of paragraph padding cover the original segment`. `make readability UNIT=ovl26` is clean. Packet:
`build/packets/ovl26.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-1, commit 0321003, fixed in 65374f1)

- [x] must-fix DrawPartyMarker: the constant comment credited DrawAreaView with the window clamp (ovl26:001F). DrawAreaView does not clamp; ShowAreaView does. (fixed in 65374f1)
- [x] must-fix whitepaper 5.2.1: "everything up to column 42 / row 34 becomes the centre cell 2" counted 42 and 34 as cell 2; the compares make them cell 3. (fixed in 65374f1)
- [x] should-fix OVL26: the unit comment cited whitepaper 5.x; the section is 5.2.1. (fixed in 65374f1)
- [x] should-fix WallDesc2FromCode/WallDesc4FromCode: the comments named a script command as the writer of ds6F69/ds6F68; this unit only reads them. (fixed in 65374f1)
- [x] should-fix ovl26_init: the empty initialisation at ovl26:02A0 had no comment and no address. (fixed in 65374f1)

### This cycle (rev-4)

- [ ] must-fix const comment and DrawPartyMarker: both cite `ovl26:0137` for the window clamp ("(ovl26:0137)" in the constant comment and in the routine comment). `ovl26:0137` is inside `WallDesc4FromCode` (`8A 46 08 3C 0B` at ovl26:0135), so a reader following the pointer lands in the wrong routine. The clamp is in `ShowAreaView` at ovl26:0253..0285: `cmp byte [bp-1],0` at ovl26:0253, `cmp byte [bp-1],$27` at ovl26:025D, `cmp byte [bp-2],0` at ovl26:0275, `cmp byte [bp-2],$1F` at ovl26:027F. Whitepaper 5.2 already cites ovl26:0289 for the same clamp, so the source's 0137 is also inconsistent with it.
- [ ] should-fix OVL26 unit comment: "The callers are the view dispatcher of the resident unit ... and the wilderness map screen ..." names two, but the packet lists eight callers of `ShowAreaView`: ovl03:08E5, ovl03:2AA2, ovl03:2DD3, ovl03:31B4, ovl03:3379 (ovl03, Encounter), ovl07:054E (`ovl07_e8`, Loader), res12:27D9 and res12:2B5E. Say "the main callers" or list them.
- [ ] should-fix const comment: "a party column of 42 (a party row of 34) puts the marker at cell 3" (ovl26:001F) is exact only for AreaViewKind 2, whose MapBaseX is 0. The compare is on the marker column `MapBaseX[AreaViewKind] + GameVars^[VarMapX]` (ovl26:000D..001C), so for kinds 3 and 4 (bases 13 and 26) the 42 threshold is on the marker column, not on the party column. Only the row threshold 34 is the party row. The routine comment already states this correctly.
- [ ] should-fix DrawPartyMarker/ShowAreaView: the meaningful limits are left bare where the comments explain them: the centre cell 2 (ovl26:001F, ovl26:0043), the frame count 6 (ovl26:00B5), the first marker picture 9 (ovl26:00A5), the interior bit limit `$7F` (ovl26:01A3), and the clamp limits `$27` and `$1F` (ovl26:025D, ovl26:027F). Named constants would match the convention already used for `Cell3Column`..`Cell4Row`. Not blocking; the comments carry the meaning.
- [ ] note DrawPartyMarker: the comment says the marker goes "onto the 5x5 map window that ShowAreaView just drew", but the packet also lists res12_fn_2B5E (00BA:2B5E) as a direct caller, which reaches DrawPartyMarker without going through ShowAreaView.
- [ ] note DrawPartyMarker: "the display step res07_fn_1B52 that drawing units call" (ovl26:00BE) fits the callee's bytes (it drives the EGA sequencer at ports 3C4h/3C5h and copies rows into segment A200h) and its many drawing callers (ovl16, ovl18, ovl24, ovl28, ovl29, ovl31, res12); the routine is not decompiled yet, so the description is an inference from its bytes.

## What was verified

1. `make match UNIT=ovl26` rerun: complete, three routines matched and three nested helpers proven in the parent. `make readability UNIT=ovl26` clean.
2. Names true and specific: `DrawPartyMarker` folds the party position into a 0..4 window cell and draws it, stepping the six-frame `MarkerFrame`; `ShowAreaView` dispatches on the view kind; `WallDesc2FromCode`..`WallDesc4FromCode` are named for the descriptor each produces (ds6A61, ds6A62, ds6A63). `MapBaseX`, `AreaViewKind`, `GameVars`, `MarkerFrame` are named in `re/dseg.toml`; `ds0C26`, `ds6A60..ds6A63`, `ds6AB1`, `ds6AAC`..`ds6AAF`, `ds6F68`, `ds6F69`, `ds84E5`, `ds2612` carry `POOLVARS.PAS` comments. The `Var...` constants map to the read offsets (word 195 = +$186, 196 = +$188, 230 = +$1CC, 251 = +$1F6, 253 = +$1FA, 254 = +$1FC; `TGameVars` is an array of Word, so word n is 2n).
3. Types fit: `MarkerCol`, `MarkerRow`, `WindowLeft`, `WindowTop` are `ShortInt` (signed `jge`/`jle` compares, `cbw` before the `Integer` parameters of `DrawAreaView`); `ViewKind`, `SpecialCode`, the descriptors and the icon set are `Byte`; `case SpecialCode` uses equality, so Byte is exact; `GameVars^[...]` is Word (`cmp word`, unsigned `jae`/`jbe`). `ovl32_e5(A, B: ShortInt; C, D, E: Byte)`, `ovl29_e4(X, Y: ShortInt): Byte`, `ovl29_e1(A, B, C, D: Byte)`, `ovl29_e5(A, B, C: Byte)` and `DrawAreaView(LeftCol, TopRow: Integer)` in the other units' stubs match the pushes.
4. Comments give addresses and game meaning; the kind-1 path (GeoLoad event byte, the interior test `> $7F`, ds0C26 by `VarWallIndexInside`/`VarWallIndexOutside`, the ds84E5 refresh, `ovl29_e1`, the ds6AAC clear, `ovl29_e5`) and the kind 2..4 path (window minus 2, clamps, `DrawAreaView`, `DrawPartyMarker`) match the bytes at ovl26:0193..0299. The nested-function QUIRK (static link pushed at ovl26:01D7, 01E3, 01EF) and the empty-branch QUIRK (ovl26:001F) are marked.
5. No record type is declared here; `GameVars: ^TGameVars` comes from `POOLVARS.PAS`.
6. Quirks kept and marked: `QUIRK ovl26:001F` (the empty `then` branch) and `QUIRK ovl26:018C` (the nested functions and their static link).
7. No `inline`, no `db`, no `assembler`.
8. Behaviour claims match whitepaper 5.2.1 and are tagged [V] (with [?] where the descriptors or the icon sets are not yet known).
9. Stub signatures this unit set are recorded in `re/symbols.toml` and the other units' files: `ovl29_e4(X, Y: ShortInt): Byte`, `ovl29_e1(A, B, C, D: Byte)`, `ovl29_e5(A, B, C: Byte)`, `ovl32_e5(A, B: ShortInt; C, D, E: Byte)`.
10. Whitepaper 5.2.1 records what the unit taught: the two view kinds, the marker fold, the special view codes and the TP 6.0 idioms proven here.

## Verdict

Not passed. One must-fix: both comments that cite the window clamp point at `ovl26:0137`, which is inside `WallDesc4FromCode`; the clamp is at `ovl26:0253..0285`.

# Review: ovl30

decompiler: dec-5 (Agent trailers of 56307ea, 08daafe, 3edb435) and dec-1 (49b45fe, 8c599b0, 500ae8d)
reviewer: rev-4
date: 2026-10-12
commit: 8333bc2

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl30` (rerun): `SignOf` 46 bytes, `SortTable` 370, `SetupLine` 300, `StepLine` 342,
`WalkLine` 345, `InDirArc` 910, `ScanTargets` 720, `ovl30_init` 5; `unit: complete, 3038 bytes of code
plus 0 of paragraph padding cover the original segment`. `make readability UNIT=ovl30` is clean.
Packet: `build/packets/ovl30.md`.

Routines: `SignOf` (ovl30:0000), `SortTable` (ovl30:002E), `SetupLine` (ovl30:01A0), `StepLine`
(ovl30:02CC), `WalkLine` (ovl30:0422), `InDirArc` (ovl30:057B), `ScanTargets` (ovl30:0909), the empty
`ovl30_init` (ovl30:0BD9).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix WalkLine: the source still carries the stale `BLOCKED (dec-5, 2026-10-12)` comment above the routine (src/OVL30.PAS lines 148..154), which says "the ds2745 index codegen does not reproduce" and points at `re/symbols.toml`. That is no longer true: dec-1 decompiled the routine (500ae8d, `[L2]`), `make match` proves it (345 bytes, matched), the `re/symbols.toml` note now says "UNBLOCKED (dec-1, 2026-10-12): matched at L2", and whitepaper 5.18 says the same. A reader is told the routine cannot be reproduced. Remove the blocked note. (fixed in 9809acf)
- [x] should-fix ScanTargets: the comment says "Called from combat and item aiming (ovl22_e5) and from ovl09, ovl13, ovl24 and res12" (ovl30:0909). The packet's caller scan finds ovl22:266B (`ovl22_e48`), not `ovl22_e5`; `ovl22_e5` (ovl22:0C20) is the aiming loop that calls `InDirArc`, as its own comment says. Whitepaper 5.18 repeats "(ovl22_e5, which loops Dir to aim)". Name `ovl22_e48` (or say the ovl22 aiming/combat code and keep `ovl22_e5` only for `InDirArc`). (fixed in dc2f4e3)
- [x] note POOLVARS.PAS: the `TLineState` comment says "(whitepaper 5.x)"; the unit's section is 5.18. Same for the `TMapRow` and `TTileEntry` comments in that block. (fixed in dc2f4e3)
- [x] note StepLine: the ellipsis/`Pattern` write happens on every call, even when the routine returns False (`Pattern := ds25C0[StepY + 1, StepX + 1]` with StepX/StepY both 0 gives `ds25C0[1,1]`); the comment does not say the Pattern is written on the no-step path. Faithful to the bytes; worth knowing. (fixed in dc2f4e3)

## What was verified

1. `make match UNIT=ovl30` rerun: complete, all eight routines L2. `make readability UNIT=ovl30` is clean.
2. Names true and specific: `SignOf`, `SortTable`, `SetupLine`, `StepLine`, `WalkLine`, `InDirArc`, `ScanTargets`; the types `TLineState`/`PLineState`, `TSortRec` (Head/Key/Val), `TMapRow`/`TMapRows`/`PMapRows`, `TTileEntry` (BoundY/BlockY), `TMapEntry`; the globals `ds25C0`, `ds2736`, `ds273F`, `ds2745`, `ds5F27`, `ds6718` all carry `POOLVARS.PAS` comments and `re/dseg.toml` evidence.
3. Types fit: `SignOf(N: Integer): Integer`; the line state coordinates are `Integer` (word compares) and `SX`/`SY` `ShortInt`; `InDirArc`'s coordinates are `ShortInt` and `Dir` a `Byte` (the `case` selector zero-extends); `SortTable`'s indexes and `Val`/`Key` are `Byte`; `StepCount`/`Limit`/`Best` are `Word`.
4. Comments give addresses and meaning; the ones I checked hold: `SignOf`'s three results and callers; `SortTable`'s count-in-element-0 and the Key/Val with the mod-2 tie-break (ovl30:002E); `SetupLine`'s DX/DY, the `SignOf` directions and the three Bresenham steps (ovl30:01A0); `StepLine`'s `DX > DY` split, the `First` 2/3 and `ds25C0[StepY+1, StepX+1]`; `InDirArc`'s 0..49 / 0..24 bounds, the `$FF`/8 omni, the `ds2736`/`ds273F` step, and the eight half-plane `case` bodies (ovl30:057B); `ScanTargets`' `ds5F27` walk, the `ovl31_e1` neighbours with -1 for invalid, the `InDirArc`/`WalkLine` pair search, the `ds6718` append and `SortTable`.
5. The caller lists match the packet except the `ovl22_e5` clause above: `SignOf` from ovl22_e63/SetupLine/res12_fn_1CE0, `SetupLine`/`StepLine` from ovl22_fn_295B/WalkLine/res12_fn_1A29, `WalkLine` from ovl09_fn_0B96/ovl12_e70/ovl13_fn_2DFA/ScanTargets, `InDirArc` from ovl13_e18/ovl22_e5/ScanTargets.
6. Quirk kept and marked: `WalkLine`'s dead `StepDone` (`QUIRK ovl30:0544`); `TMapRow`'s out-of-range `Cells` read is documented.
7. No `inline`, no `db`, no `assembler`.
8. Side effects and the `var` outputs (`Ex`/`Ey`/`StepCount`, `SignOf`'s result) are stated; the line walk's `False` exits set `Ex`/`Ey`/`StepCount` before returning.
9. Signatures this unit set are recorded (`PLineState`, `PMapRows`, `ovl31_e1`, `res12_fn_1CE0`/`1A29`, `ovl22_e63`, `ovl22_fn_295B`, `ovl22_e5`, `ovl22_e48`, `ovl09_fn_0B96`, `ovl12_e70`, `ovl13_fn_2DFA`/`e18`) and match the pushes.
10. Whitepaper 5.18 records what the unit taught (the line stepper, the arc test, the walk and the scan), including the compiler notes (the far 2D subscript, the `Exit` epilogue, the frame pad) and the tile table.

## Verdict

Not passed. One must-fix: the `WalkLine` source still carries dec-5's `BLOCKED` note although the routine is decompiled and matches at L2; the `ScanTargets` caller clause is a should-fix.

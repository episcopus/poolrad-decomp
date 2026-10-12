# Review: ovl30

decompiler: dec-5 (Agent trailers of 56307ea, 08daafe, 3edb435) and dec-1 (49b45fe, 8c599b0, 500ae8d); the review fixes are 9809acf and dc2f4e3
reviewer: rev-4
date: 2026-10-12
commit: 48666ec (re-review after 9809acf and dc2f4e3; the first review was of 8333bc2)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl30` (rerun): `unit: complete`, 8 routines, 3038 bytes (`SignOf` 46, `SortTable`
370, `SetupLine` 300, `StepLine` 342, `WalkLine` 345, `InDirArc` 910, `ScanTargets` 720,
`ovl30_init` 5), 0 differ, 0 stubs. `make readability UNIT=ovl30` is clean. Packet:
`build/packets/ovl30.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-4, commit 8333bc2)

- [x] must-fix WalkLine: the stale `BLOCKED (dec-5, 2026-10-12)` comment above the routine claimed "the ds2745 index codegen does not reproduce". Removed in 9809acf; the routine is L2 and matches (`make match`: 345 bytes), and the `re/symbols.toml` note says UNBLOCKED. The source now carries only the real routine comment with the address ovl30:0422, the Bound line, the stop conditions and the callers.
- [x] should-fix ScanTargets: the comment said "Called from combat and item aiming (ovl22_e5)". Fixed in dc2f4e3 to "(ovl22_e48)", matching the packet's caller (ovl22:266B); ovl22_e5 (ovl22:0C20) is the aiming loop that calls InDirArc, as its own comment says.
- [x] note StepLine: the note that `Pattern` is written on every call (even on the no-step path, `ds25C0[1,1]`) is now in the comment (dc2f4e3).

### This cycle (rev-4)

- [ ] note POOLVARS.PAS: the `TLineState` comment still says "(whitepaper 5.x)"; the unit's section is 5.18 (same for the `TMapRow` and `TTileEntry` comments in that block). Cosmetic.

## What was verified

1. `make match UNIT=ovl30` rerun: complete, all eight routines L2. `make readability UNIT=ovl30` is clean.
2. The three fixes hold: no `BLOCKED` text remains in src/OVL30.PAS; the WalkLine comment (ovl30:0422) describes the Bound line, the tile gate, the Limit cutoff and the callers; the ScanTargets comment names ovl22_e48; the StepLine comment (ovl30:02CC) explains the unconditional `Pattern` write.
3. Names, types and the rest of the comments are unchanged from the first review and were verified there: `SignOf`'s three results, `SortTable`'s Key/Val with the mod-2 tie-break, `SetupLine`'s Bresenham state, `StepLine`'s `DX > DY` split and `ds25C0`, `InDirArc`'s bounds and eight half-plane bodies, `ScanTargets`' `ds5F27` walk with `ovl31_e1` neighbours and the `ds6718` append; and the types `TLineState`, `TSortRec`, `TMapRow`, `TTileEntry`, `TMapEntry` with the globals `ds25C0`, `ds2736`, `ds273F`, `ds2745`, `ds5F27`, `ds6718`.
4. Quirks kept and marked (`StepDone`, QUIRK ovl30:0544; the out-of-range `Cells` read). No `inline`/`db`/`assembler`. Whitepaper 5.18 has the same corrections.

## Verdict

Passed. The must-fix (the stale BLOCKED comment) and the ScanTargets caller should-fix are fixed in 9809acf and dc2f4e3; the one remaining note is cosmetic.

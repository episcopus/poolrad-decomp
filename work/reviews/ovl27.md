# Review: ovl27

decompiler: dec-1, dec-2
reviewer: rev-1
date: 2026-10-11
commit: 0f26ba1

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl27` reports `unit: complete` (DrawAreaView 518 bytes, DrawAdventureScreen 124, ovl27_init 5). `make readability UNIT=ovl27` is clean. The packet is `build/packets/ovl27.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix DrawAreaView: the comment says every SpecialBlocks entry has its own condition (ovl27:0000). Entries 1 and 2 are tested for position (ovl27:006A, index times 6 from DS:0C30) and then the case has no arm, so a match leaves Count unchanged. Only entries 3 to 9 can replace the block, and the conditions in the source match the compares (word 396 at +$318, 466 at +$3A4, 380 bit 3 at +$2F8, 415 at +$33E, 416 bits at +$340, 435 at +$366). (fixed in 98ab0d8)
- [x] must-fix DrawAreaView: the comment says ovl18_e2 passes (17, 15). That is only the first call, and only when ovl18_e2's byte parameter is nonzero (ovl18:06C2 pushes 0011h then 000Fh). The same routine also calls DrawAreaView with words from DS:094D and DS:095F (ovl18:07C8) and with (23, 25) (ovl18:08D4, pushes 0017h then 0019h). (fixed in 98ab0d8)
- [x] should-fix DrawAreaView: ShowAreaView does pass party column and row minus 2, clamped to 0..39 and 0..31 (ovl26:0137, compares with $27 and $1F). The column is MapBaseX[ViewKind] plus the party column, not the party column alone. (fixed in 98ab0d8)
- [x] should-fix OVL27: the unit comment cites whitepaper 5.8. This unit is section 5.2. 5.8 is the keyboard chapter. (fixed in 98ab0d8)
- [x] should-fix whitepaper 5.2: the condition list for entries 3 to 9 matches the bytes, and it does not say that entries 1 and 2 never override. Section 5.2.1's "3 pixels per cell" is the same step of 3 that the source calls 3x3 view cells. (fixed in 98ab0d8)
- [x] should-fix ovl27_init: the empty initialisation at ovl27:0283 (`55 89 E5 5D CB`) has no comment and no address. (fixed in 98ab0d8)
- [ ] note DrawAdventureScreen: the three calls match the named rectangles (ovl27:020D pushes 1,1,15,15; ovl27:0233 pushes 17,1,38,15; ovl27:0259 pushes 1,17,38,22), then frame 0, colour 0, and an empty string (the 00 byte at ovl27:0206). The res09_fn_02E8 and ovl32_e2 signatures this unit recorded agree with the pushes. QUIRK ovl27:01CC is the inc/dec pair on both coordinates. TSpecialBlock field order Col, Row, Pic matches the three words at +0, +2, +4.

## Verdict

Not passed. DrawAreaView's comment gives entries 1 and 2 a condition they do not have, and it understates what ovl18_e2 passes.

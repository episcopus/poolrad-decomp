# Review: ovl26

decompiler: dec-2 (Agent trailers of c18b385, 002f33e, 0e23782; dec-4 fixed the review findings in 65374f1 and 0dd8a38)
reviewer: rev-5
date: 2026-10-11
commit: 925b2a5

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Round 3. Round 1 (rev-1, commit 0321003) failed on the window clamp and whitepaper
5.2.1 cell counts, fixed in 65374f1. Round 2 (rev-4, commit 6682dfd) failed on the
ovl26:0137 clamp citation, fixed in 0dd8a38 together with its should-fix items. This
round re-runs the checklist on the fixed source.

`make match UNIT=ovl26` (rerun): `DrawPartyMarker` (ovl26:0000) 199 bytes, `ShowAreaView` (ovl26:016D)
307 plus 166 pool, the nested `WallDesc2FromCode` (ovl26:00C7), `WallDesc3FromCode` (ovl26:00FB) and
`WallDesc4FromCode` (ovl26:012F), `ovl26_init` (ovl26:02A0) 5; `unit: complete, 677 bytes of code plus
0 of paragraph padding cover the original segment`. `make readability UNIT=ovl26` is clean. Packet:
`build/packets/ovl26.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycles (rev-1 round 1, fixed in 65374f1; rev-4 round 2, fixed in 0dd8a38)

- [x] must-fix DrawPartyMarker: the constant comment credited DrawAreaView with the window clamp (ovl26:001F). DrawAreaView does not clamp; ShowAreaView does. (fixed in 65374f1)
- [x] must-fix whitepaper 5.2.1: "everything up to column 42 / row 34 becomes the centre cell 2" counted 42 and 34 as cell 2; the compares make them cell 3. (fixed in 65374f1)
- [x] should-fix OVL26: the unit comment cited whitepaper 5.x; the section is 5.2.1. (fixed in 65374f1)
- [x] should-fix WallDesc2FromCode/WallDesc4FromCode: the comments named a script command as the writer of ds6F69/ds6F68; this unit only reads them. (fixed in 65374f1)
- [x] should-fix ovl26_init: the empty initialisation at ovl26:02A0 had no comment and no address. (fixed in 65374f1)
- [x] must-fix const comment and DrawPartyMarker: both cited ovl26:0137 for the window clamp, which is inside WallDesc4FromCode. The clamp is at ovl26:0253..0285. (fixed in 0dd8a38)
- [x] should-fix OVL26 unit comment: named only two callers while the packet lists eight. (fixed in 0dd8a38: main callers plus ovl03 five sites plus ovl07_e8)
- [x] should-fix const comment: the 42 threshold is on the marker column for kinds 3 and 4, not the party column. (fixed in 0dd8a38)
- [x] should-fix DrawPartyMarker/ShowAreaView: bare limits 2, 6, 9, $7F, $27, $1F. (fixed in 0dd8a38: CentreCell, MarkerFrames, FirstMarkerPicture, InteriorBit, MaxWindowLeft, MaxWindowTop)
- [x] note DrawPartyMarker: res12_fn_2B5E calls it directly, not only through ShowAreaView. (fixed in 0dd8a38)
- [ ] note DrawPartyMarker: "the display step res07_fn_1B52 that drawing units call" (ovl26:00BE) fits the callee's bytes (it drives the EGA sequencer at ports 3C4h/3C5h and copies rows into segment A200h) and its many drawing callers (ovl16, ovl18, ovl24, ovl28, ovl29, ovl31, res12); the routine is not decompiled yet, so the description is an inference from its bytes. (carried from round 2; confirmed in round 3: res07_fn_1B52 has twelve callers across the drawing units)

### This cycle (rev-5)

No new findings. Round 3 verification (all checked against the bytes): the clamp
citations are exact (cmp 0 at ovl26:0253, cmp $27 at ovl26:025D, cmp 0 at ovl26:0275,
cmp $1F at ovl26:027F); the marker fold matches the compares (column 2/$2A/$2B at
ovl26:001F, row 2/$22/$23 at ovl26:0043, row reads at +$188 without a page base);
res12_fn_27D9 calls ShowAreaView for view types 4 and 3 (cmp al,4 at 00BA:2874, cmp
al,3 at 00BA:2896); res12_fn_2B5E calls DrawAdventureScreen, ShowAreaView then
DrawPartyMarker (00BA:2B66, 2B6B, 2B70); the named constants match their compares
(CentreCell 2, Cell3Column $2A, Cell4Column $2B, Cell3Row $22, Cell4Row $23,
MarkerFrames 6 at ovl26:00B5, FirstMarkerPicture 9 at ovl26:00A5, InteriorBit $7F at
ovl26:01A3, MaxWindowLeft $27, MaxWindowTop $1F); the nested-function QUIRK cites the
static-link pushes (ovl26:01D7, 01E3, 01EF); all four stub signatures this unit set
(ovl29_e4, ovl29_e1, ovl29_e5, ovl32_e5) are recorded in re/symbols.toml and agree
with the OVL29/OVL32 stubs; "GeoLoad"/"PicLoad" and the mirrored-half frame follow
whitepaper 5.2.1 and the dseg.toml MarkerFrame evidence; whitepaper 5.2.1's "pure
setter" for ovl29_e1 matches its bytes (four stores to ds6A60..6A63, ovl29:0155).

## Verdict

Passed. No open must-fix findings; the unit is complete, readable and true to the bytes.

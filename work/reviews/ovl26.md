# Review: ovl26

decompiler: dec-2
reviewer: rev-1
date: 2026-10-11
commit: 0321003

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl26` reports `unit: complete` (DrawPartyMarker, ShowAreaView, ovl26_init, and three nested helpers proven inside ShowAreaView). `make readability UNIT=ovl26` is clean. The packet is `build/packets/ovl26.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix DrawPartyMarker: the constant comment says DrawAreaView clamps the window to columns 0..39 and rows 0..31 (ovl26:001F). DrawAreaView does not clamp; ShowAreaView does, at ovl26:0137 (`WindowLeft > $27`, `WindowTop > $1F`). The fold numbers themselves match: column byte compared with 2, $2A and $2B (ovl26:001F), so 42 is cell 3 and 43 or more is cell 4; the row word at GameVars offset $188 is compared with 2, $22 and $23 (ovl26:0043). MapBaseX is added only to the column.
- [ ] must-fix whitepaper 5.2.1: "everything up to column 42 / row 34 becomes the centre cell 2" includes 42 and 34, which the compares treat as cell 3 (`jge` / `jae` at ovl26:0027 and ovl26:0061). Below those values is cell 2.
- [ ] should-fix OVL26: the unit comment cites whitepaper 5.x. The section is 5.2.1.
- [ ] should-fix WallDesc2FromCode: the comment says script command $F7 sets ds6F69, and WallDesc4FromCode says $F1 sets ds6F68. This unit only reads those bytes. POOLVARS names the writers as ovl07_e3 and ovl11_fn_0435, and 5.2.1 does not pair $F1 with ds6F68 or $F7 with ds6F69.
- [ ] should-fix ovl26_init: the empty initialisation at ovl26:02A0 has no comment and no address.
- [ ] note ShowAreaView: kind 1 versus kinds 2..4, the interior test `ds6AB1 > $7F`, the ds0C26 index, the ds84E5 refresh, and the window `MapBaseX[ViewKind] + VarMapX - 2` match the comment. The nested-helper QUIRK (push bp at ovl26:01D7, 01E3, 01EF) matches the matcher. MarkerFrame mod 2 is the signed `idiv` remainder and div 2 is `shr` (ovl26:0096, ovl26:00A3); `(MarkerFrame + 1) mod 6` is the inc then `idiv` 6 at ovl26:00AE. The three case mappings match their comments, including the arms that only repeat the else value.

## Verdict

Not passed. The marker comment names DrawAreaView as the routine that clamps the window, and whitepaper 5.2.1 counts column 42 and row 34 as the centre cell.

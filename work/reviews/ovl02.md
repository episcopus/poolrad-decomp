# Review: ovl02

decompiler: dec-1, dec-2
reviewer: rev-5
date: 2026-10-11
commit: fc43f11

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Round 2. Round 1 (rev-1, commit 0c597b3) failed on three res06 stub signatures this
unit set in RES06.PAS but left out of re/symbols.toml; the decompiler recorded all
three in e302d2f. This round re-runs the checklist on the fixed source.

`make match UNIT=ovl02` reports `unit: complete` (CheckCodeWheel 604 bytes, ovl02_init 5). `make readability UNIT=ovl02` is clean. The packet is `build/packets/ovl02.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix CheckCodeWheel: the signatures this unit wrote into RES06.PAS are not in `re/symbols.toml` `signature` (checklist item 9). `res06_fn_01DF(A, B, C, D, E, F: Byte)`, `function res06_fn_09E3(Prompt: string; A, B: Byte): string` and `procedure res06_fn_0D68(Text: string; A: Byte)` were added in commit 627b321; the three `signature` fields are still empty. `res06_fn_0626` is recorded. (fixed in e302d2f: all three recorded)
- [x] should-fix CheckCodeWheel: those new parameters are named A through F, and A, B. The fifth byte of res06_fn_01DF is the glyph (rune index + $40, ovl02:01B4) and res06_fn_0D68's second byte is the colour ($0E, ovl02:033F). The prompt's 13 and 6 (ovl02:02F7) and the rune call's bare $0C, 1 and 0 are unnamed; 6 is the length of CodeWord. (fixed in e302d2f: Glyph, Color and MaxLen named; A, B, C, D, F and the 13 left for res06's decompiler)
- [x] should-fix ovl02_init: the empty initialisation at ovl02:0359 (`55 89 E5 5D CB`) has no comment and no address. (fixed in e302d2f: comment with address added)
- [x] note CheckCodeWheel: the rest of the comment matches the bytes. Random(13) is at ovl02:010D. The record stride is $15 and the field offsets are +2, +9, +$A, +$B, +$C and +$D, which is TCodeWheelEntry. The fourth rune is skipped when the byte at +$C is $FF (ovl02:023D). The path line is five spaces concatenated with that string (ovl02:029A, System_StrConcat) in colour $0C. A match jumps to the epilogue (ovl02:032E); the third failure, Attempt = 3, calls QuitGame (ovl02:0347). Whitepaper 5.12 says the same. (confirmed in round 2)
- [ ] should-fix whitepaper 5.12: the first bullet says CheckCodeWheel "draws two rune glyphs and a path pattern". The code draws three rune glyphs always (OuterRune, InnerRune, ThirdRune at ovl02:01A2, 01C5, 020C) and a fourth when the record has one (FourthRune, ovl02:0244, skipped only on $FF at ovl02:023D). The next bullet lists all four correctly, but the summary should say up to four.

Round 2 verification (all checked against the bytes): the three recorded signatures in
re/symbols.toml agree word for word with the RES06.PAS stubs; every call in
CheckCodeWheel matches the disassembly pushes (DrawWindow 1,1,$26,$16 at ovl02:0119;
the seven res06_fn_0626 texts and colours; the four res06_fn_01DF rune calls with
offsets +9/+$A/+$B/+$C and +$40; the 13 and 6 of res06_fn_09E3 at ovl02:02F7; the $0E
of res06_fn_0D68 at ovl02:033F; the Attempt = 3 compare and QuitGame at ovl02:0347);
TCodeWheelEntry field offsets match the code (CodeWord string[6] at +2, runes at
+9..+$C, Path string[7] at +$D, stride $15); Answer is truncated to 40 by StrLCopy
with max $28. The bare 13, $0C, 1 and 0 stay with res06's stub parameters by the
round-1 agreement, recorded above. No quirks, no inline code, no new stubs beyond the
now-recorded three.

## Verdict

Passed. No open must-fix findings; one should-fix on the whitepaper summary (two rune
glyphs, should say up to four) is left for the decompiler.

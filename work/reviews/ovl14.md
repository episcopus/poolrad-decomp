# Review: ovl14

decompiler: dec-1
reviewer: rev-5
date: 2026-10-12
commit: bb81dd4

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

First review. `make match UNIT=ovl14` reports `unit: complete` (14 routines, 4268 bytes:
ClearIconBits, SetIconBits, HasRecFlag, DoBash, DoPick, FindCodeSlot, FindCodeRecord,
DoKnock, ClampPartyPosition, MoveParty, CheckMapCell, HandleWildernessKeys,
DoWildernessMenu, ovl14_init). `make readability UNIT=ovl14` is clean. The packet is
`build/packets/ovl14.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix DoWildernessMenu: the comment says the menu "prompts through ovl25_e2 (Bash/Pick/Knock dispatch to DoBash, DoPick, DoKnock)". That is true only of the ovl29_e3 = 2 arm (ovl14:0EC2: 'B' calls DoBash, 'P' calls DoPick at ovl14:0ED6, 'K' calls DoKnock). In the = 3 arm 'P' only clears the Pick flag (mov ds6DDF,0 at ovl14:1015, no DoPick call) while 'B'/'K' dispatch. The two arms also differ for Knock (= 2 tests FindCodeRecord($1F) at ovl14:0E14, = 3 tests HasRecFlag(5) at ovl14:0F53), which the comment never mentions although it is the visible difference between the arms. Correct the dispatch sentence to name both arms; whitepaper 5.3 ("dispatches to DoBash/DoPick/DoKnock") needs the same correction.
- [ ] should-fix ovl14_init: the empty initialisation at ovl14:10A7 (`55 89 E5 5D CB`) has no comment and no address. Every reviewed unit carries an init comment with the address.
- [ ] should-fix OVL14 unit comment: cites "(whitepaper 5.2)". The unit's section is 5.3 (5.2 is the area view); prior reviews required the exact section.
- [ ] should-fix HandleWildernessKeys: `'C': if PByteArray(SelectedCharacter)^[$10C] = 0 then ovl15_e2` (ovl14:0A2D). TCharacter names +$10C Status (raised by this same unit's RaiseDead/StoneToFlesh convention in ovl04, and POOLVARS documents it); use `SelectedCharacter^.Status = StatusOkay` (or at least ^.Status = 0) instead of the untyped PByteArray dereference.
- [ ] should-fix HasRecFlag: the comment says "a nonzero byte at +$96+Which", but the code counts only positive bytes (cmp byte,0 with jle at ovl14:026A; $FF counts as 0). The source says `> 0`. Say "a positive byte". Same word in the TCodeRec Flags comment ("nonzero gates a menu item").
- [ ] should-fix ClampPartyPosition: "The direction tables ds2736/ds273F are indexed by the icon set [I]." The trailing "[I]" is stray (an evidence tag needs an address or section). Drop it or cite the indexing instructions.
- [ ] should-fix MoveParty: "clears ds6DDE" for `FillChar(ds6DDE, 3, 1)` (ovl14:07A9). It sets three bytes to 1 (reenabling the Bash/Pick/Knock menu flags), not clearing. Say "resets the ds6DDE..ds6DE0 menu flags to 1".
- [ ] should-fix CheckMapCell: `GameVars^[418]` is bare (ovl14:0905, word at +$344 gating the river crossing). The ovl27 precedent names even still-unknown game words (GateVarBlock3 etc.); introduce a named constant saying what is known (river-crossing gate, meaning otherwise open) in POOLVARS or the unit, and use it in whitepaper 5.3 ("game word 418").
- [ ] should-fix TCodeRec/ds5D96: `ds5D96: LongInt` in POOLVARS, but every use in this unit treats it as the head pointer of the TCodeRec list (`Rec := Pointer(ds5D96)`, three walks). Type it as what it is (Pointer; TCodeRec lives in this unit's interface so PCodeRec cannot reach POOLVARS) and drop the conversion, or document why LongInt stays.
- [ ] should-fix ds49D6: typed `^TGameVars` (array[0..511] of Word) but this unit indexes words 713, 714 and 725 (byte +$592/+$594/+$5AA), past the type's bound; the block itself is $800 bytes (1024 words, POOLVARS line 269). Harmless under $R- and the addresses are right, but document the overrun at the declaration or introduce a wider word-array type.
- [ ] note DoWildernessMenu/DoBash: what ovl29_e3's return values (1/2/3, 3/not-3) mean in game terms belongs to ovl29 (undecompiled); the comments describe the dispatch structure faithfully. No change needed, recorded so a reader does not mistake the structure for the meaning.
- [ ] note HandleWildernessKeys: SpareBuf/SpareLong are honestly marked as never-read frame fillers. Fine as is.

What was verified (all checked against the bytes): ClearIconBits/SetIconBits masks
($3F/$CF/$F3/$FC, or $40/$10/$04/$01) and the SetIconBits 0..$F range guard; the
TCodeRec offsets used (+$10 LockType, +$16 Strength, +$17..$2B Codes, +$78
PickThreshold, +$96..$A3 Flags as bytes with signed compare, +$104 Next, +$10C
PickFlag); DoBash's two case trees arm for arm ($12/$5B..$63/$64 with the ds6DDE[0]
else, $13..$19; $03..$12 when e3 <> 3; the (ds6AAF+4) mod 8 facing cell via idiv);
DoPick's 1d100 roll against +$78 with +$10C clear and the unconditional ds6DDF := 0;
FindCodeSlot's 21 slots with $FF; DoKnock clearing slot $1F; ClampPartyPosition's four
clamps with the +$5AA edge flag (word 725 = byte $5AA); MoveParty's wrap, ds6AB0/ds6AB1
refresh, FillChar 3,1 and the [714]-bit-0 sound mode; CheckMapCell's clamps, the
$4E/impassable/river case ranges and the +$344 word; HandleWildernessKeys' A/C/V/E/S/L
and H/P/K/M arms in both views, the ICON loads, the ds49F9/ds84E4 epilogue and the
ovl03_fn_3379 caller; DoWildernessMenu's menu strings, ' Exit'-only ClearIconBits
path, MoveParty-on-Done and the sprite-bank tidy epilogue; GeoCells row*16+col at
+$300; all parameterized stub signatures used are recorded in re/symbols.toml
(parameterless ovl15_e2 and the decompiled ClearWindow/FreeSpriteList resolve through
their own units); QUIRK-free code needs none; no inline, db or assembler; whitepaper
5.3 covers the unit except the = 3 'P' correction.

## Verdict

Not passed. The DoWildernessMenu dispatch comment claims Pick always calls DoPick, but the ovl29_e3 = 3 arm clears ds6DDF instead; the Knock difference between the arms (code record vs flag 5) is undocumented.

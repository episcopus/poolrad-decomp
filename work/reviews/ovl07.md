# Review: ovl07

decompiler: dec-17
reviewer: rev-5
date: 2026-10-12
commit: 499678b

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

First review. `make match UNIT=ovl07` reports `unit: complete` (33 routines, 8730 bytes;
see the match output for the full list, ovl07:0000 through ovl07:2215 plus ovl07_init).
`make readability UNIT=ovl07` is clean. The packet is `build/packets/ovl07.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix ovl07_init: the empty initialisation at ovl07:2215 (`55 89 E5 5D CB`) has no comment and no address. Every reviewed unit carries an init comment with the address.
- [ ] should-fix DamageWithMessage: `StatusDead = 6` (`if Who^.Status = StatusDead then Exit`, ovl07:20CC) uses the name ovl04 and ovl05 use for value 1 (`StatusDead = 1`, `StatusGone = 6` in OVL04.PAS) for the same TCharacter.Status field. The whitepaper treats 6, 7, 8 as "killed" (5.20), so 6 is a dead state, but the two names for value 6 (Gone here Dead) will confuse a porter. Reconcile with ovl04 (or cross-reference both meanings) no later than phase 6; at minimum the comment should say 6 is also ovl04's StatusGone.
- [ ] should-fix AskMenu: "An extended key goes to ovl19_e10" (ovl07:1684 comment). The code tests `ExtKey <> 0`, the var flag of the undecompiled ReadPromptChoice; nothing yet says that flag means an extended key (in ovl14 the same flag selects movement keys). Say "when ExtKey is set" until ovl25 proves more.
- [ ] should-fix SixBitChar: "codes 1..$1F become $41..$5F (the letters)". $5B..$5F are `[\]^_`, not letters (whitepaper 5.1 says `A`..`_`). Say so.
- [ ] note ScaleMoney: Factor is a Real although the project notes say no floating point; `make match` proves the `Trunc(x * Factor)` code including whatever emulation the compiler emits, so the source stands as is.
- [ ] note ds5D96: kept LongInt with a documented, probed reason (POOLVARS: `:= 0` is Error 26 for a Pointer). No change; this answers the same suggestion on the ovl14/ovl05 reviews.

What was verified (checked against the bytes; `make match` proves the rest):
DecodeOperands' type/low/high layout with the $80/$81 string arms and EclPC accounting;
OperandValue's type arms with QUIRK ovl07:01AD (other types fall through unassigned);
InitScript's flag/code/PC/header/entry-address writes and the ds49F8 keep/clear arms;
LoadEcl's repeat-until-size loop and copy-past-the-word; LoadCharacter's New/fill/return;
OpenStepsAhead's VarForceWallView shortcut and wall-count loop; ShowHeadBody's banks,
ds49FD/ds49FE and ds84E1; ShowEncounterPicture's Shown[0]/Shown[1] gating, the SPRIT
load, the slot/2 choice, the ds84EA/$2E1, Distance, AreaViewKind and ShowMonsterPics
exits and the PIC-vs-HEAD/BODY close-up; MakeWord/SixBitChar/MemRegion (ranges
$4900..$4CFF, $6B00..$6EFF, $9700..$98FF, $9900..$B6FF, else Special); PartyIndexOf;
GetCharacterVar's arms including the $6C0D QUIRK (Found set, result unassigned),
the $A5..$AC index math, the $2B1/$2B4 and $2CF mappings and the $33E read of word
830; SetCharacterVar's arms including the $6B20..$6B70 QUIRK (0AA3), the $B8/$100/$10C
mappings and the $312/$322/$324/$326 loader calls; WriteVmWord's five regions with
the $49FD/$49FE side effect, the SetCharacterVar follow-up, and the special addresses
($BF68 split, the icon-mapping loop with Dec(Value, 4), the view-code sets);
ReadVmWord's mirror arms with QUIRKs 0EE7/0F45; WriteVmString/ReadVmString
(per-word/per-byte loops, the $6B00 name case, no special-address arm); DecodeString's
phase machine; ParseHotkeys with the digit QUIRK 15BF; AskMenu's repeat/prompt/ExtKey
arms with the 0-based/$FF returns (callers ovl03, VisitTemple, TreasureMenu, ShopMain
per the packet); AskListMenu dropping the key (caller ovl03:0FE2); CompareStrings/
CompareWords' six flags; ScriptGosub's stack push and jump; StepPartyForward's wrap
and ds6AB0/ds6AB1 refresh; SetupDuel's Flag10D clearing, the 'ROLF' copy ($B2, Side 1,
Quick 1, CPIC $B, no affects, item copies); LoseItems' weight-stepped chance with
RollDice and res12_fn_1509; SkipCommand's opcode table shape; MovementRange's
$27-double/$2A-halve min/max; DamageWithMessage's Status-6 exit, dies/hit texts,
paging, res12_fn_2228, ClearRect and redraw; TCharacter/TCombatant offsets used
(+$73 HighestLevel, +$2F ClassMask, +$10..$13 requisites, +$AC Experience, +$B8/+$BA
XpValue/XpPerHp, +$88 Money, +$85 HirelingShare, +$17 Spells, +$32 Plus, +$34 Readied,
+$108 Combat, +$13 NoBody); the Var* word constants against their byte offsets;
TVmWords4900/6B00/9700 absolute views; all parameterized stub signatures used are
recorded in re/symbols.toml (ovl17_e6, res12_fn_2228/1509, DrawTextAt, SelectTileSet,
RollDice among them; matched units resolve through their interfaces); interface order
is address order; no inline, db or assembler; whitepaper 5.1 covers the unit and
agrees with the source.

## Verdict

Passed. No open must-fix findings; the unit is complete, readable and true to the bytes.

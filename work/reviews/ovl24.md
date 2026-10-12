# Review: ovl24

decompiler: dec-12 (Agent trailer of 3843a62, the whole unit; merged in 034e839)
reviewer: rev-4
date: 2026-10-12
commit: 8e3e398

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl24` (rerun): 24 routines matched, `unit: complete, 6455 bytes of code plus 0 of
paragraph padding`. `make readability UNIT=ovl24` is clean. Packet: `build/packets/ovl24.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix RollDice: the comment's quirk is marked as "QUIRK: the sum is a Byte and wraps above 255" (ovl24:0DE3) with no address, where the file's other quirks carry one (`ovl24:02FD`, `ovl24:1659`). Cite the `Inc(Total, ...)` that wraps (ovl24:0E0F area) or say it is the whole routine.
- [ ] note TCharacter `Flag10D`/`Flag11B`: both are offset names, but `POOLVARS.PAS` documents them (Flag10D "meaning unknown", set by Raise Dead/Stone to Flesh and read by MoveCombatCursor; Flag11B "the current hit points [I]", capped at HpMax) and the whitepaper and other units use the same names. Phase 6 territory; the comments carry the meaning.
- [ ] note RollDice: the comment says "ovl04 rolls 1d8, 2d8 and 3d8 for the cure spells"; whitepaper 5.21 line 880 gives 1d8, 2d8+1 and 3d8+3 (the "+n" is added by the caller). Fine as an example.
- [ ] note RunAffectHooks: the 20-kind table is a large literal; `make match` proves it and the comment names the six kinds this unit uses and the three other units use (`7`, `$F`, `$13`); `QUIRK ovl24:02FD` marks the unused frame.

## What was verified

1. `make match UNIT=ovl24` rerun: complete, all 24 routines L2, `make readability UNIT=ovl24` clean.
2. Names true and specific: the affect list (`AddAffect`, `RemoveAffect`, `ApplyAffect`, `CureAffect`, `CallAffectHandler`, `AffectHandlers`, `TAffect`/`PAffect`), the hooks (`RunAffectHook`, `RunAffectHooks`), the rolls (`RollDice`, `RollDiceCounted`, `SavingThrow`, `RollToHit`, `RollBeatsResistance`), the combat effects (`DealDamage`, `DropCombatant`, `HealCharacter`, `ReviveCombatant`, `ApplyCloudTile`, `ClearAttackerAffect`, `RemoveDeathAffects`) and strength (`EncodeStrength`, `DecodeStrength`, `RaiseStrength`). The constants name the modes, statuses, sides, hook kinds, `NaturalOne`/`NaturalTwenty`/`TwentyCounts`, the side-bonus game words and the affect ids.
3. Types fit: ids/positions `Byte`, `AttackRoll`/`SaveRoll`/`DamageAmount` as the POOLVARS declarations say, `Who` a `PCharacter`, `SavingThrow(..., Kind, Bonus: ShortInt)`, `EncodeStrength(Strength, Percent: Byte): Byte`, `RollDice(Count, Sides: Byte): Byte` (the Byte sum is the quirk).
4. Comments give addresses and meaning; the ones checked hold against the packet: `CallAffectHandler`'s `AffectHandlers[Id](Who, Affect, Mode)`; `RemoveAffect`'s id/nil search, the mode 1 handler call for a flagged affect and the 9-byte free; `RunAffectHook`'s `$15`/`$2D`/`$2E`/`$31` cross-member rule with `ScanTargets` (6 for `$31`, 1 otherwise) and the ds6718 save/restore; the `RunAffectHooks` kind lists; `ApplyCloudTile`'s `ProbeStep(Who, 8, ...)`, the five affect checks and saved/failed arms; `RollBeatsResistance`/`RollToHit`/`SavingThrow`'s d20 rules, `TwentyCounts`, the side word (`VarSideBonusParty` 881, `VarSideBonusMonsters` 880) and `ClearAttackerAffect`; `DealDamage`'s save effect (0/half), the damage-kind messages, the `CanCast`/`PendingSpell` combat effect, the `Goes Down`/`Dying`/`killed` messages and the `RemoveCombatant` vs stand-up branch; `ApplyAffect`'s `HookAffectId`, the duration-replacement rule and the message; `HealCharacter`'s status filter, the `AffectHealingBlock` gate, the HpMax cap and the revival handler; `ReviveCombatant`'s `PlaceCombatant`, the two messages and `res12_fn_23DB`; `EncodeStrength`/`DecodeStrength`'s 18/percentile encoding and `RaiseStrength`'s earlier-strength affect.
5. Quirks kept and marked: `ovl24:02FD`, `ovl24:1659`; the `RollDice` Byte wrap is the should-fix.
6. Caller lists cross-check against the packet (`CallAffectHandler`, `RemoveAffect`, `RunAffectHooks`, `ApplyCloudTile`, `SavingThrow`, `RollDice`, `RollDiceCounted`, `AddAffect`, `DropCombatant`, `ClearAttackerAffect`, `RemoveDeathAffects`, `ovl24_e14`, `CureAffect`, `EncodeStrength`/`DecodeStrength`, `RaiseStrength`, `DealDamage`, `ApplyAffect`, `HealCharacter`, `ReviveCombatant`); `ovl24_e14`'s caller is `ovl09_fn_10D7` (still a stub), which is why its own comment says the callers are not decompiled yet.
7. No raw machine code or assembler routine. `ovl24_init` is the empty initialisation at ovl24:1932 with a comment.
8. Whitepaper 5.21 records what the unit taught (the affect record and list, the handler table and hook kinds, the rolls, damage and healing, the strength encoding) with the same names.

## Verdict

Passed. Every name, type and comment is true to the bytes; the one should-fix is a quirk mark without an address and the notes are informational.

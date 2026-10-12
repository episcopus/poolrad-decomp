# Review: ovl05

decompiler: dec-12
reviewer: rev-5
date: 2026-10-12
commit: ece225a

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

First review. `make match UNIT=ovl05` reports `unit: complete` (12 routines, 5750 bytes:
ComputeBattleExperience, AwardExperience, SettleBattleOutcome, ShowBattleResult,
ChooseLootItem, TakeLootItems, TakeTreasure, TreasureMenu, RemoveBattleCombatants,
TakeHirelingShares, EndBattle, ovl05_init). `make readability UNIT=ovl05` is clean.
The packet is `build/packets/ovl05.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix TakeTreasure/TreasureMenu/ShopMain: `AnswerNo = 1; { ovl07_e13 returns the 0-based word of '~Yes ~No' }`. ovl06 says "the 0-based hotkey position" for the same routine and value (whitepaper 5.4/5.20 agree); "word" says nothing. Use one wording everywhere ("0-based hotkey position").
- [ ] should-fix SettleBattleOutcome: "the walks stop at the first extra combatant (TCombatant.NoBody = 1)". The three non-duel walks do (ovl05:04EB, 054F, 0637); the two duel arms (ovl05:0776, 07DB) walk the whole list with no NoBody test. Qualify the sentence.
- [ ] should-fix ComputeBattleExperience: "Sets MonstersLooted when a monster was looted". It is set for every non-fled monster (Side 1, Status <> 3, ovl05:0088) whether or not any item is taken (VarNoItemLoot = 1 skips the items, an itemless monster still sets it). Say "when a non-fled monster is processed".
- [ ] should-fix TCodeRec/ds5D96: `ds5D96: LongInt` in POOLVARS, but every use in this unit (and ovl14) treats it as the head pointer of the character list (`Who := PCharacter(ds5D96)`, five walks). Same finding as the ovl14 review: type it as what it is (Pointer) and drop the conversions, or document why LongInt stays.
- [ ] note EndBattle/ShowBattleResult/TakeHirelingShares: the `Key` locals of the last two are stored and never read (the prompt's return, conventionally kept). No change.

What was verified (all checked against the bytes): the duel/FixedXp path (HighestLevel * 100 with the Integer-mul QUIRK ovl05:002B) and every arm of the monster walk (Side/Status gates, the 7-word money add, XpValue + XpPerHp * HpB1, the VarNoItemLoot gate, the Value/worthless-item test with 1d10, the prepend with res12_fn_0442); the money-kind values (200/20/2/1/5/250/2200) and the ds5D9A-bounded Plus walk; the VarPartySize-less-NoExperienceCount division; AwardExperience's Flag10D/Status gate, the four prime-requisite arms (+$10..$13 > 15), the 8,10..14,16-halving and 9,15-thirding, and the +$AC credit; SettleBattleOutcome's PartyFled/PartyDestroyed/BattleWon/NoExperienceCount logic, the survived/fled/destroyed/duel arms with their Status writes, the ovl16_e2 removals and the VarPartySize zeroing; ShowBattleResult's five texts, the Xp zeroing, the duelist/each lines and the prompt; ChooseLootItem's picker call (Flag/Choice/First plumbing, Item := Selected) and 0442 prep; TakeLootItems' Take/Enter loop, unlink, $3F free and 27D9 tail; TakeTreasure's money/items/both arms with the G/O keys and the e9 refresh; TreasureMenu's menu composition, the 0..20 spell scan for 5/$B, all key arms, the E-arm question with AnswerNo and the G/O arms; RemoveBattleCombatants' NoBody/Side walk, the VarRemovedCount count, the ovl16_e2 removals and the $16 combat-state frees; TakeHirelingShares' share counts, the div-Byte QUIRK ovl05:13A5, the deduction and the listing window; EndBattle's prologue, live/duel path with loot freeing, destroyed path with 'The END!', and the ds4A00/880..882/739/742 tail; TCharacter/TCombatant/TMenuLine/TPartyMoney offsets used (+$73 HighestLevel, +$2F ClassMask, +$10..$13 abilities, +$AC Experience, +$B8/+$BA XpValue/XpPerHp, +$88 Money, +$85 HirelingShare, +$17 Spells, +$32 Plus, +$34 Readied, +$108 Combat, +$13 NoBody); the Var* word constants against their byte offsets (711/$58E, 712/$590, 739/$5C6, 742/$5CC, 830/$67C, 880..882/$6E0..$6E4); all parameterized stub signatures used are recorded in re/symbols.toml (ovl16_e2's Uncounted/FreePicture among them, set by this unit's own commit); the four frame-filler QUIRKs (04CC, 0B17, 0ED0, 12EB); no inline, db or assembler; interface order is address order; whitepaper 5.20 covers the unit and agrees with the source.

## Verdict

Passed. No open must-fix findings; the unit is complete, readable and true to the bytes.

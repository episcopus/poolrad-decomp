# Review: ovl21

decompiler: dec-18 (Agent trailers throughout; merged in 4a55f50)
reviewer: rev-4
date: 2026-10-12
commit: 499678b

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl21` (rerun): 22 routines matched, `unit: complete, 8795 bytes of code plus 0 of
paragraph padding`. `make readability UNIT=ovl21` is clean. Packet: `build/packets/ovl21.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix ReadAmount/TakeMoney/ShareMoney: the frame fillers are uncommented. `ReadAmount` has `Unused: Byte` (ovl21:0294), `TakeMoney` `Unused: Word` (ovl21:0CEB) and `ShareMoney` `Unused1: Pointer` and `Unused2: Byte` (ovl21:063A, `Unused2` is set to 0 and never read). The file marks its other unused locals with a `QUIRK <address>:` comment (for example `TakeMoney`'s `Count`, QUIRK ovl21:0D5C); do the same so a reader knows they are frame filler, not missing state.
- [ ] note TransferMoney: the packet finds no caller for it (it is an overlay entry with no direct call in the decompiled units); the comment does not claim one, so this is only recorded. Its weight QUIRK `ovl21:04DB` (the weight is added back to Giver) is marked.
- [ ] note BuildTreasureItem: the per-type weights and values are bare hex data (for example `Weight := $4B`, `Value := Plus * $9C4`); naming them would add noise. The comment says what they are and the three QUIRKs (`ovl21:10D5`, `ovl21:1753`, `ovl21:17A6`) are marked.
- [ ] note ShareMoney: the comment describes the "every member below B84 $80" pass and the remainder pass, matching the two loops.

## What was verified

1. `make match UNIT=ovl21` rerun: complete, all 22 routines L2. `make readability UNIT=ovl21` is clean.
2. Names true and specific: the weight layer (`CarryLimit`, `RemoveCarriedWeight`, `AddCarriedWeight`, `WouldOverload`), the money-value and set routines (`MoneyValueInGold`, `SetCharacterGold`, `SetPooledGold`, `GivePlatinum`), the commands (`ReadAmount`, `TransferMoney`, `PoolMoney`, `CountSharers`, `ShareMoney`, `DropMoney`, `TakeFromPool`, `MoneyKindOfLine`, `TakeMoney`), the treasure (`TreasureLeft`, `RollItemBonus`, `BuildTreasureItem`, `AppraiseGems`). The constants name the seven money kinds, `BaseLoad`, `GoldPerPlatinum`, the prompt row, the view modes (`ViewShop` 1, `ViewTreasure` 6), `SharerB84`/`ComputerRunB84`, `GemItemName`/`JewelItemName`/`GemItemType`, `MaxItems`, `HalfGoldInCopper`.
3. Types fit: `Amount`/`Max`/`Room`/`Weight` `Word`, money kinds `ShortInt`, `MoneyValueInGold(...): LongInt`, `CarriedWeight` as declared, `TPartyMoney`/`TMenuLine`/`PCharacter`/`PMenuLine` the shared POOLVARS types.
4. Comments give addresses and meaning; the ones checked hold against the packet: `CarryLimit`'s `res12_fn_13AB` plus 1500; `WouldOverload`'s Room; `MoneyValueInGold`'s five-kind copper total plus half a gold, divided by the gold value (`GemsKind`/`JewelryKind` excluded); `SetCharacterGold`/`SetPooledGold`'s div/mod 5; `GivePlatinum`'s overload split into the pool; `ReadAmount`'s digit loop, `Val` and the Max clamp; `TransferMoney`'s overload test and the weight quirk; `PoolMoney`/`CountSharers`'s B84 filter and `MoneyInPool`; `ShareMoney`'s div/mod, the two passes and the remainder; `DropMoney`'s view-mode pool rule; `TakeFromPool`'s pool clamp; `MoneyKindOfLine`'s letter rules; `TakeMoney`'s list build, `ChooseFromList` and the two QUIRKs; `TreasureLeft`'s two flags; `RollItemBonus`'s d20 bands; `BuildTreasureItem`'s arms for 1..$3B/$49/$4D/$5D, $3D/$3E, the fixed rows and the `TreasureItemRows` five-byte read; `AppraiseGems`'s gem/jewel bands, the sell-versus-keep choice and the two QUIRK addresses.
5. Quirks kept and marked: `ovl21:04DB`, `ovl21:0CB1`, `ovl21:0D5C`, `ovl21:0EA3`, `ovl21:10D5`, `ovl21:1753`, `ovl21:17A6`, `ovl21:1E74`, `ovl21:21C7`; the unmarked frame fillers are the should-fix.
6. Caller lists cross-check against the packet (`CarryLimit`, `RemoveCarriedWeight`, `AddCarriedWeight`, `WouldOverload`, `MoneyValueInGold`, `SetCharacterGold`, `SetPooledGold`, `GivePlatinum`, `ReadAmount`, `PoolMoney`, `CountSharers`, `ShareMoney`, `DropMoney`, `TakeFromPool`, `MoneyKindOfLine`, `TakeMoney`, `TreasureLeft`, `RollItemBonus`, `BuildTreasureItem`, `AppraiseGems`, and `TransferMoney` has none).
7. No raw machine code or assembler routine. `ovl21_init` is the empty initialisation at ovl21:2256 with a comment.
8. Whitepaper 5.4.1 records what the unit taught (the seven money kinds, the weight and load, the Pool/Share/Take/Appraise commands, the treasure item build) with the same names.

## Verdict

Passed. Every name, type and comment is true to the bytes; the should-fix is uncommented frame fillers and the notes are informational.

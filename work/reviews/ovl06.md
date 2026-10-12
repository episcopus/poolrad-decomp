# Review: ovl06

decompiler: dec-5 (Agent trailers of 265ea8c, e1ac919, 062ef1e, 3e29f87), dec-10 (f8c6e4a), dec-13 (58c4860)
reviewer: rev-4
date: 2026-10-12
commit: 7eb2494 (re-review after f8c6e4a and 58c4860; the first review was of 1d0a180)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl06` (rerun): `unit: complete`, 5 routines, 1949 bytes (`ChooseShopItem` 510,
`AddInventoryItem` 278, `BuyItems` 275, `ShopMain` 602, `ovl06_init` 5), 0 differ, 0 stubs.
`make readability UNIT=ovl06` is clean. Packet: `build/packets/ovl06.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-4, commit 1d0a180)

- [x] must-fix ChooseShopItem/BuyItems: the number the shop shows and pays was called "Count" though it is the word at +$3A, which `POOLVARS.PAS` names `Value` (the record's `Count` is +$39). f8c6e4a calls it `Value`/`Price` (`Price := Selected^.Value`, ovl06:0361) and the comment says "its Value (the price, +$3A)" and "Price is its Value (+$3A)"; the `SelCount` local is gone.
- [x] must-fix OVL06/whitepaper 5.4: the item/menu record was called `TMenuItem`, which does not exist. f8c6e4a uses `TMenuLine` (the unit comment and `AddInventoryItem`), and the whitepaper was corrected.
- [x] should-fix whitepaper 5.4: the field names it listed (`Name`/`Enabled`/`Value37`/`Factor39`/`Count` +$3A) contradicted `POOLVARS.PAS` and whitepaper 4.2.5. Corrected with the rename pass.

### This cycle (rev-4)

- [ ] note ChooseShopItem: the "picker" is now `ChooseFromList` and the prompt `ReadPromptChoice`, the real names dec-8 gave ovl25 (their former stub names are `ovl25_e4`/`ovl25_e2`); the merge APPLY'd the renames and the call matches the 14-parameter signature.
- [ ] note BuyItems: the two money QUIRKs came from rev-6's ovl06/ovl04 finding; they are marked (`ovl06:03C7`, `ovl06:0449`) and the ovl04 fix list carries the same note. Correct as far as this unit goes.
- [ ] note ShopMain: the comment now names `MoneyPooled`, `MenuFlag`, `LeaveAnswer`, `Appraised` and `AnswerNo`; the `G`/`O` keys and the second `case` are covered.

## What was verified

1. `make match UNIT=ovl06` rerun: complete, all five routines L2. `make readability UNIT=ovl06` is clean.
2. The rename pass holds against the packet: `Entry^.Value` (+$3A, `cmp word ptr es:[di + 0x3a],0` at ovl06:0068), the price comment at ovl06:0361, `TMenuLine`, the locals `Price`/`Money`/`Pooled`/`Overloaded`/`Cancelled`/`MenuFlag`/`MoneyPooled`/`PoolSecond`/`LeaveAnswer`/`Appraised`.
3. The QUIRK addresses match: `ovl06:026D` (`Overloaded := 1`), `ovl06:0277` (0), `ovl06:03C7` (the `Word` store of `ovl19_e11`'s LongInt), `ovl06:03E7..03F3` (the deduction), `ovl06:0430..0446` (`Pooled - Price` as a LongInt) and `ovl06:0449` (the low-word push to `ovl21_e11`).
4. Comments give addresses and meaning: the stock walk and the 30-character rewrite (`Entry^.Text[0] := #30` QUIRK ovl06:012B), `DrawWindow(1,1,$26,$16,0,$0F,'Shop')`, the `ChooseFromList('Items: ','Buy',$0D,$0A,$0F,1,4,$26,$16,List,1,MenuFlag,Choice,Head)` call and the `res12_fn_0442` passes; `AddInventoryItem`'s `ovl19_e9`, `res12_fn_1693('OverLoaded')`, the `New`/record copy/append and `res12_fn_0BB8`; `BuyItems`'s money-then-pool order and the two truncation QUIRKs; `ShopMain`'s `ds49F3 := 1`, the two redraws, `FillChar(ds67F4, SizeOf(ds67F4), 0)`, the two menu texts, the full key dispatch (`B`/`V`/`T`/`P`/`S`/`A`/`E`/`G`/`O`), the Leave prompt with `AnswerNo` and the second `case`.
5. Types fit: `Action`/`Key` `Char`, the list pointers `PMenuLine`, `Choice` `Integer`, `Price`/`Money` `Word`, `Pooled` `LongInt`, the flags `Byte`, `Cancelled` `Boolean`, `Title` `string[1]`, `MenuText` `string[40]`.
6. Quirks kept and marked: ovl06:012B, ovl06:03C7, ovl06:0449. No `inline`/`db`/`assembler`.
7. Stub signatures this unit set are recorded (`res12_fn_0442`, `res12_fn_0BB8`, `ovl19_e9`, `ovl25_e4`/`e2`, `ovl21_e2`/`e3`/`e4`/`e9`/`e10`/`e11`/`e12`/`e14`, `ovl07_e13`, `res06_fn_0768`/`0DD3`); `ovl06_init` has an address comment.
8. Whitepaper 5.4 has the corrected record, field names and dispatch.

## Verdict

Passed. The two must-fixes (the +$3A field name and `TMenuItem`) and the whitepaper should-fix are fixed in f8c6e4a; the remaining notes are informational.

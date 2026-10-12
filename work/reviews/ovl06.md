# Review: ovl06

decompiler: dec-5 (Agent trailers of c3ab8af, 265ea8c, e1ac919, 062ef1e, 3e29f87)
reviewer: rev-4
date: 2026-10-11
commit: 1d0a180

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl06` (rerun): `ChooseShopItem` 510 bytes, `AddInventoryItem` 278, `BuyItems` 275,
`ShopMain` 602, `ovl06_init` 5; `unit: complete, 1949 bytes of code plus 0 of paragraph padding cover
the original segment`. `make readability UNIT=ovl06` is clean. Packet: `build/packets/ovl06.md`.

Routines: `ChooseShopItem` (ovl06:0030), `AddInventoryItem` (ovl06:0239), `BuyItems` (ovl06:0361),
`ShopMain` (ovl06:053E), the empty `ovl06_init` (ovl06:0798).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix ChooseShopItem/BuyItems: the number the shop shows and pays is `Selected^.Value`, the word at +$3A (`cmp word ptr es:[di + 0x3a],0` at ovl06:0068, and `SelCount := Selected^.Value` at ovl06:0361). `POOLVARS.PAS` names +$3A `Value` and declares a separate `Count` at +$39, and whitepaper 4.2.5 lists an item's fields as "weight, count, value". The comments call +$3A "the Count right-justified" and "the entry's Count", and the locals are `SelCount`/`Count`; whitepaper 5.4 says "the quantity `Count` at +$3A". That is a wrong field name and a wrong meaning (the amount is paid from money and pooled money). Rename to the value/price and reconcile whitepaper 5.4.
- [ ] must-fix OVL06/whitepaper 5.4: the item/menu record is called `TMenuItem` (AddInventoryItem's comment "a new TMenuItem is allocated", whitepaper 5.4 "63-byte `TMenuItem` records") but no such type exists: `src/POOLVARS.PAS` declares `TMenuLine` (with the `PItem`/`TItem` aliases). Use `TMenuLine`.
- [ ] should-fix whitepaper 5.4: the field names it lists for the record (`Name` +0, `Enabled` +$29, `Value37` +$37, `Factor39` +$39, `Count` +$3A) do not match `POOLVARS.PAS` (`Text`, `Flag29`, `Weight`, `Count`, `Value`) or whitepaper 4.2.5. One set of names must win.
- [ ] note ChooseShopItem: the comment says the field the routine rewrites is the entry's "Name"; the field is `Entry^.Text` (+0, `string[40]`). Minor, part of the same naming pass.
- [ ] note ShopMain: the comment summarises the menu and the Leave prompt but does not mention the two keys that are in neither menu text (`G` and `O`, both `ovl19_e10(Key)`, ovl06:053E) or the second `case` (B/T redraw `res12_fn_27D9`, A redraws when `Restored <> 0`). Whitepaper 5.4 has the G/O keys.
- [ ] note AddInventoryItem: "record assignment of $3F bytes" is right (`TMenuLine` is 63 bytes, Text +0 to Affects +$3E) and matches whitepaper 4.2.5's 63-byte item.

## What was verified

1. `make match UNIT=ovl06` rerun: complete, all five routines L2. `make readability UNIT=ovl06` is clean.
2. Names true and specific: the four entry points, `SelectedCharacter`, `ds6810` (the shop stock list), `ds67F4` (the money block), `ds6DC0`, `ds49F3`, `PByte`, `PMenuLine`/`TMenuLine`. The record fields the code reads (`Text` +0, `Next` +$2A, `Count` +$39, `Value` +$3A) carry `POOLVARS.PAS` offsets.
3. Types fit: `Action`/`Key` are `Char`, `Selected`/`Head`/`Entry`/`List`/`Tail`/`NewItem` are `PMenuLine`, `Count`/`SelCount`/`Avail` are `Integer`/`Word`, `Money` is `LongInt`, `OK`/`Flag2`/`Done`/`Choice`/`Restored`/`Has1`/`Has2` are `Byte`, `Flag` is `Boolean`, `Title` is `string[1]`, `MenuText` is `string[40]`, `Field` is `string[30]`.
4. Comments give addresses and meaning: the stock walk and the 30-character rewrite with the right-justified number (ovl06:0068..012B, including the `Entry^.Text[0] := #30` QUIRK at ovl06:012B); `DrawWindow(1,1,$26,$16,0,$0F,'Shop')`; the `ovl25_e4('Items: ','Buy',$0D,$0A,$0F,1,4,$26,$16,List,1,Flag,Count,Head)` call, which matches `ovl25_e4`'s 14-parameter signature; the two per-entry passes of `res12_fn_0442`; `AddInventoryItem`'s `ovl19_e9` overload test, `res12_fn_1693('OverLoaded')`, the `New`/record-copy/append and `res12_fn_0BB8`; `BuyItems`'s pool-then-money order with `ovl19_e11`/`ovl21_e10`/`ovl21_e12`/`ovl21_e11` and `'Not enough Money.'`; `ShopMain`'s `ds49F3 := 1`, `res12_fn_27D9`, `res12_fn_0767`, the `$1C`-byte money clear, the two menu texts, the key dispatch and the Leave prompt.
5. Quirk kept and marked: the double length set in `ChooseShopItem` (`QUIRK ovl06:012B`).
6. No `inline`, no `db`, no `assembler`.
7. Side effects stated: the screen, the inventory, the money, `ds49F3`.
8. Whitepaper 5.4 records what the unit taught (the shop menu, the stock list, the buy flow, the leave prompt, the `G`/`O` keys), with the item-naming clauses above.
9. Signatures this unit set (`ovl25_e4`'s 14 parameters, `ovl25_e2`, `ovl19_e9`/`e10`/`e11`/`e5`, `ovl21_e2`/`e3`/`e4`/`e9`/`e10`/`e11`/`e12`/`e14`, `ovl07_e13`, `res12_fn_0442`/`0767`/`0BB8`/`1693`/`27D9`, `res06_fn_0768`/`0DD3`) are recorded and match the pushes.
10. `ShopMain` is called from ovl03 (`ovl03:179B`), `BuyItems`/`ChooseShopItem` from within the unit, `AddInventoryItem` from ovl05 and `BuyItems` (packet callers); the merge reconciled the callee signatures with main (`3e29f87`).

## Verdict

Not passed. Two must-fix, both about the item record: the number at +$3A is the record's `Value` (not the `Count`) in the comments, the locals and whitepaper 5.4, and the record type is `TMenuLine`, not `TMenuItem`.

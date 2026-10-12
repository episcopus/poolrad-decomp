# Review: ovl06

decompiler: dec-5, dec-7 (Agent trailers of the src/OVL06.PAS commits)
reviewer: rev-6
rounds: 1 rev-4 at 1d0a180; 2 rev-6 at 58026af
date: 2026-10-12
commit: 58026af

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

- [x] must-fix ChooseShopItem/BuyItems: the number the shop shows and pays is `Selected^.Value`, the word at +$3A (`cmp word ptr es:[di + 0x3a],0` at ovl06:0068, and `SelCount := Selected^.Value` at ovl06:0361). `POOLVARS.PAS` names +$3A `Value` and declares a separate `Count` at +$39, and whitepaper 4.2.5 lists an item's fields as "weight, count, value". The comments call +$3A "the Count right-justified" and "the entry's Count", and the locals are `SelCount`/`Count`; whitepaper 5.4 says "the quantity `Count` at +$3A". That is a wrong field name and a wrong meaning (the amount is paid from money and pooled money). Rename to the value/price and reconcile whitepaper 5.4. (fixed in 65d3a4e)
- [x] must-fix OVL06/whitepaper 5.4: the item/menu record is called `TMenuItem` (AddInventoryItem's comment "a new TMenuItem is allocated", whitepaper 5.4 "63-byte `TMenuItem` records") but no such type exists: `src/POOLVARS.PAS` declares `TMenuLine` (with the `PItem`/`TItem` aliases). Use `TMenuLine`. (fixed in 65d3a4e)
- [x] should-fix whitepaper 5.4: the field names it lists for the record (`Name` +0, `Enabled` +$29, `Value37` +$37, `Factor39` +$39, `Count` +$3A) do not match `POOLVARS.PAS` (`Text`, `Flag29`, `Weight`, `Count`, `Value`) or whitepaper 4.2.5. One set of names must win. (fixed in 65d3a4e)
- [x] note ChooseShopItem: the comment says the field the routine rewrites is the entry's "Name"; the field is `Entry^.Text` (+0, `string[40]`). Minor, part of the same naming pass. (fixed in 65d3a4e)
- [x] note ShopMain: the comment summarises the menu and the Leave prompt but does not mention the two keys that are in neither menu text (`G` and `O`, both `ovl19_e10(Key)`, ovl06:053E) or the second `case` (B/T redraw `res12_fn_27D9`, A redraws when `Restored <> 0`). Whitepaper 5.4 has the G/O keys. (fixed in 65d3a4e)
- [ ] note AddInventoryItem: "record assignment of $3F bytes" is right (`TMenuLine` is 63 bytes, Text +0 to Affects +$3E) and matches whitepaper 4.2.5's 63-byte item.


Round 2 (rev-6, at 58026af): the round-1 fixes in 65d3a4e are verified (`Value` at +$3A as the price in the comments, locals and whitepaper 5.4; `TMenuLine`; the field names of 4.2.5; `Text`; ShopMain's G/O keys and second case). The money order is now right too (character's money through `ovl19_e11`, then the pool `DS:67F4`, as ovl04 and whitepaper 5.19 say; this answers escalate-ovl06-20261012053719). `make match UNIT=ovl06`: complete, 5 matched; `make readability UNIT=ovl06`: clean. New findings:

- [ ] must-fix BuyItems: two unmarked truncations a port must keep. `ovl19_e11` returns a LongInt (re/symbols.toml signature; whitepaper 5.4 "a LongInt"), but only AX is kept (`mov [bp-0xa], ax` at ovl06:03C7, `Money: Word`), so the character's money is compared and deducted modulo 65536: a character with 65536 or more can be told the price fits when its low word does, or pays from the pool when it does not, and `ovl21_e10` then stores the low word less the price (ovl06:03E7..03F3). The pool path computes `Pooled - Price` as a LongInt (ovl06:0430..0446) but `ovl21_e11(Amount: Word)` receives only the low word (`push [bp-0xe]` at ovl06:0449), so a pool above 65535 is rewritten with the truncated amount. Mark both `QUIRK ovl06:03C7` and `QUIRK ovl06:0449` with what happens, and give whitepaper 5.4 a sentence. (The same `Money: Word` truncation is in ovl04's `ChargeForCure`; reported to the orchestrator for ovl04.)
- [ ] must-fix AddInventoryItem/BuyItems: the parameter `OK` holds the opposite of its name: `OK^ := 1` when the item does not fit (ovl06:026D, after "OverLoaded") and `OK^ := 0` when it was added (ovl06:0277); BuyItems pays only `if OK = 0`. A reader takes `OK = 0` as failure. Rename it for what 1 means (for example `Overloaded`), in both routines. A `var Overloaded: Byte` (or Boolean) parameter compiles to the same address push as `PByte` with `@OK` at the callers (ovl06:03D8..03DC), if `make match` agrees; that would read better too.
- [ ] should-fix ShopMain: the locals `Has1`, `Has2`, `Flag2` and `Restored` are vague or disagree with ovl04, which names the same results `MoneyPooled`/`PoolSecond` (ovl21_e9), `MenuFlag` (ovl25_e2's var flag) and `Appraised` (ovl21_e14). READABILITY rule 7: one thing, one name. `Restored` has no evidence; `Appraised` at least follows the A key.
- [ ] should-fix ShopMain: the comment says E "leaves (asking first through ovl07_e13 when money lies in the pool)" but not on which answer. `ovl07_e13` returns the 0-based position of the pressed hotkey (`dec ax` at ovl07:1775, $FF when the key is not in the list), so `Choice = 1` is the second hotkey of '~Yes ~No': the party leaves when it answers No to "Do you want to go back and get your Money?". Say so, and name the constant.
- [ ] should-fix ChooseShopItem: the local `Flag` (set to 1 and passed as ovl25_e4's var flag) and BuyItems' `Flag` (True when the picker key is neither 'B' nor Enter: the player cancelled) are vague; for BuyItems `Cancelled` or `Leave` says what it is.
- [ ] note ShopMain: `FillChar(ds67F4, $1C, 0)`; `SizeOf(ds67F4)` (as ovl04 writes it) reads better if it compiles the same.

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

Round 2 (rev-6, at 58026af): not passed. Two must-fix: BuyItems' unmarked Word truncations of the LongInt money (ovl06:03C7, ovl06:0449), and the `OK` flag of AddInventoryItem/BuyItems, which is 1 when the item was refused.

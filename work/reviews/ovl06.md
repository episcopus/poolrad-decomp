# Review: ovl06

decompiler: dec-5, dec-7, dec-10 (Agent trailers of 062ef1e, 3e29f87, 65d3a4e, f8c6e4a)
reviewer: rev-5
rounds: 1 rev-4, 2 rev-6 at 58026af
date: 2026-10-12
commit: ea69de3

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Round 3. Round 1 failed on the +$3A Value/Count naming and TMenuItem (fixed in 65d3a4e).
Round 2 failed on the unmarked money truncations and the inverted OK flag (fixed in
f8c6e4a: QUIRKs ovl06:03C7/0449, Overloaded, MoneyPooled/PoolSecond/MenuFlag/Appraised,
AnswerNo, Cancelled, SizeOf). This round re-runs the checklist on the fixed source.

`make match UNIT=ovl06` (rerun): `ChooseShopItem` 510 bytes, `AddInventoryItem` 278,
`BuyItems` 275, `ShopMain` 602, `ovl06_init` 5; `unit: complete, 1949 bytes of code
plus 0 of paragraph padding cover the original segment`. `make readability UNIT=ovl06`
is clean. Packet: `build/packets/ovl06.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in rounds 1-2 (rev-4, rev-6; fixed in 65d3a4e, f8c6e4a)

- [x] must-fix ChooseShopItem/BuyItems: +$3A called Count, is Value. (fixed)
- [x] must-fix OVL06/whitepaper 5.4: TMenuItem, no such type. (fixed: TMenuLine)
- [x] should-fix whitepaper 5.4 field names. (fixed)
- [x] note ChooseShopItem Text field naming. (fixed)
- [x] note ShopMain G/O keys and second case. (fixed)
- [x] must-fix BuyItems: unmarked LongInt-to-Word truncations. (fixed: QUIRKs ovl06:03C7, ovl06:0449, whitepaper 5.4 sentence)
- [x] must-fix AddInventoryItem/BuyItems: OK inverted. (fixed: Overloaded)
- [x] should-fix ShopMain vague locals. (fixed: MoneyPooled/PoolSecond/MenuFlag/Appraised)
- [x] should-fix ShopMain Leave answer. (fixed: AnswerNo = 1, leaves on No)
- [x] should-fix ChooseShopItem/BuyItems vague Flags. (fixed: MenuFlag, Cancelled)
- [x] note ShopMain FillChar SizeOf. (fixed)

### This cycle (rev-5)

- [ ] must-fix stub signatures: three parameterized stubs this unit uses have full declarations in the other units' files (set for this unit's calls in 3e29f87) but empty `signature` fields in re/symbols.toml (checklist item 9; the same class that failed the ovl02 round-1 review): `res12_fn_0442(Value: LongInt; P: Pointer; A, B, C, D: Byte)` (RES12.PAS:12, called with (0, Entry, 0, 0, 0, 0) at ovl06:01FE), `res12_fn_0BB8(Who: Pointer)` (RES12.PAS:21, AddInventoryItem's tail call with SelectedCharacter), and `function ovl19_e9(Shop: Pointer; Item: Pointer): Boolean` (OVL19.PAS:52, called at ovl06:024D, result tested at ovl06:0252). Record each string. (Parameterless ovl21_e2/e3/e4 and res12_fn_27D9 correctly record none; every other parameterized callee is recorded.)
- [ ] should-fix ovl06_init: the empty initialisation at ovl06:0798 (`55 89 E5 5D CB`) has no comment and no address. Every reviewed unit carries an init comment with the address.
- [ ] note ChooseShopItem: the var-parameter plumbing (ChooseFromList receives @MenuFlag, @Choice, @Head as its Flag/Choice/First; Action takes the returned key; Selected takes Head) matches the pushes byte for byte; the comment describes it exactly.

Round 3 verification (all checked against the bytes): the QUIRK wordings match the
instructions (only AX kept at ovl06:03C7; only [bp-0xe] pushed at ovl06:0449);
Overloaded is 1-refused/0-added at ovl06:026D/0277 with BuyItems paying on 0; the
ChooseShopItem rewrite (Value 0 to 1, Str, right-justify at 30-N+I, name copy,
Text assign, QUIRK ovl06:012B length reset), the ChooseFromList arguments, the
Selected-Head copy direction and the res12_fn_0442 per-entry loop match; the $3F
New, the +$2A/+$2C nil link and the 0BB8 redraw match; the BuyItems B/Enter
($42/$0D) test, price, pool order and 'Not enough Money.' match; ShopMain's prologue,
both menu texts, all key arms, the AnswerNo leave rule, the G/O arms, the second
case and the 0767 tail match; callers agree with the packet (ShopMain from
ovl03:179B, AddInventoryItem from ovl05:0C06); whitepaper 5.4 covers the unit and
agrees with the fixed source.

## Verdict

Not passed. Three stub signatures this unit's calls rely on are missing from re/symbols.toml.

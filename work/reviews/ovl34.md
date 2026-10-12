# Review: ovl34

decompiler: dec-4 (Agent trailer of 09e1420, the reconciling commit; 380bdbb re-applied the unit)
reviewer: rev-4
date: 2026-10-11
commit: 12f1669

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl34` (rerun): `Load8x8Bank` 255 bytes, `Put8x8Symbol` 336, `ovl34_init` 5; `unit:
complete, 690 bytes of code plus 0 of paragraph padding cover the original segment`. `make
readability UNIT=ovl34` is clean. Packet: `build/packets/ovl34.md`.

Routines: `Load8x8Bank` (ovl34:003B), `Put8x8Symbol` (ovl34:015D), the empty `ovl34_init` (ovl34:02AD).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix Put8x8Symbol: the comment ends "the callers pass 0 for Direct (the window frame path)" (ovl34:015D). Only `DrawWindowFrame` passes 0. ovl29's three calls all pass 1: ovl29:010C pushes `(..., [bp-$0A], 1, 0)`, ovl29:0146 pushes `(..., [bp+6]/2+$100, 1, 0)` and ovl29:02FB pushes `(..., <symbol byte>, 1, 1)`, i.e. `(XPos, YPos, Symbol, Direct, Attr)` with `Direct = 1` and `Attr = 0/0/1` (TP pushes the parameters left to right, so the fourth push is the fourth parameter, which the callee reads at bp+8, `cmp byte [bp+8],0`). Direct = 1 is the `res07_fn_08D4` path, which matches the earlier clause in the same comment ("through res07_fn_08D4 when Direct is nonzero (the 3D view)"). The clause is also in whitepaper 4.2.3 ("the callers pass 0"). Correct it to "DrawWindowFrame passes 0; the ovl29 calls pass 1". (fixed in cb57254)
- [x] should-fix Load8x8Bank: the constants `LoadArg2 = 1` and `LoadArg3 = $D` name argument positions, not meaning ("second/third argument Load8x8Bank passes res07_fn_0111"). In the callee those are `B` and `C` of `res07_fn_0111(S: String; A, B, C: Byte; var P: PT8x8Bank)` (ovl34:00A7, 00AA), which is no better. Their meaning is not shown by this unit: name what is known or say `Purpose unknown:`. (fixed in cb57254: TileLoadB/TileLoadC with Purpose unknown and what the other loads pass; Count renamed BlockId, the DAX block id)
- [x] should-fix OVL34 unit comment: it cites "(whitepaper 4.x)", which is not a section. The 8x8 tile content is in whitepaper 4.2.3 (EGA pictures, `Load8x8Bank`/`Put8x8Symbol` at whitepaper line 403). (fixed in cb57254)
- [ ] note Load8x8Bank: the `Unused: Byte` local exists only to reach the 264-byte frame (`sub sp,0x108`, ovl34:003E). The comment says so; it is not a stray declaration.
- [ ] note Load8x8Bank: `if Bank in [FirstBank..LastBank]` is `Bank in [0..4]`; the set constant is the 32-byte pool at cs:0000 (`System_SetIn` at ovl34:004B), and the check is an unsigned `jbe` chain, so a Bank above 4 does nothing. Correct and documented.

## What was verified

1. `make match UNIT=ovl34` rerun: complete, all three routines L2. `make readability UNIT=ovl34` is clean.
2. Names true and specific: `Load8x8Bank` loads one 8x8 bank; `Put8x8Symbol` draws one symbol; `Bank`, `Symbol`, `XPos`, `YPos`, `Direct`, `Attr`, `TileSet`, `TileBanks`, `TileBuf`, `DrawBuf`, `SymbolBase`, `TBlock...` are named for what they hold. `TileSet`, `TileBanks`, `SymbolBase`, `TileBuf`, `DrawBuf` have `re/dseg.toml` evidence and `POOLVARS.PAS` comments; the unit reconciled with ovl11 (one declaration per offset).
3. Types fit: `Count`/`Bank`/`Direct`/`Attr` are `Byte` (byte compares and pushes), `XPos`/`YPos` are `ShortInt` (`cwde` before the `Integer` parameters of `res07_fn_08D4`/`res07_fn_1951`), `Symbol` is `Word` (`cmp word [bp+$0A]`, ranges up to $11E), `TileBanks` is `array[0..4] of PT8x8Bank` and `TileBuf` is `PT8x8Bank`. `Direct: Byte` with `Direct <> 0` compiles to the same `cmp byte [bp+8],0` a `Boolean` did, which the whitepaper records.
4. Comments give addresses and meaning: the bank ranges 1..$2D, $2E..$73, $74..$B9, $BA..$FF, $100..$11E (ovl34:0163..01B4), the fatal 0 and $11F..$7FFF, the `Bad symbol number` string and quit, the `Unable to load 8x8D<set>-<count>` message and quit, the `TileBanks[Bank] = nil` test, `Dec(Symbol, SymbolBase[Bank])` (ovl34:0206..0213), and the two branches (`res07_fn_08D4` versus `Move` to `TileBuf` + `res07_fn_1951`).
5. `T8x8Bank` matches the offsets the code uses: `Stride` is the word at +$11 (`es:[di+$11]`, ovl34:0287) and `Data` at +$17 (ovl34:0274, 027E); the header fields are documented as not read here.
6. Quirk kept and marked: `QUIRK ovl34:01C0`, symbols above $7FFF skip the fatal check and run on with an unset `Bank` (ovl34:01C0 `ja 0x1EE`).
7. No `inline`, no `db`, no `assembler`.
8. Behaviour claims match whitepaper 4.2.3 and are tagged [V]; the caller claim is the must-fix above.
9. `Load8x8Bank(Count, Bank: Byte)` and `Put8x8Symbol(XPos, YPos: ShortInt; Symbol: Word; Direct: Byte; Attr: Byte)` are recorded in `re/symbols.toml`; the callee stubs this unit set (`res07_fn_0111(S: String; A, B, C: Byte; var P: PT8x8Bank)`, `res07_fn_08D4(X, Y: Integer; S, A: Byte; Tile, Buf: Pointer)`, `res07_fn_1951(X, Y: Integer; Buf: Pointer)`) are recorded too, and res09's DrawWindowFrame still matches with `Direct = 0`.
10. Whitepaper 4.2.3 records what the unit taught (the banks, the message, the symbol ranges, the QUIRK, the branches, the record layout), with the caller clause to correct.

## Verdict

Not passed. One must-fix: the `Put8x8Symbol` comment (and whitepaper 4.2.3) says the callers pass 0 for `Direct`, but ovl29's three calls pass 1.

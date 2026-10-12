# Review: ovl14

decompiler: dec-1 (Agent trailers throughout; the review fix is 51cd2ec); the unit was merged in 680710e
reviewer: rev-4
date: 2026-10-12
commit: b372e5a (re-review after 51cd2ec; the first review was of bb81dd4)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl14` (rerun): `unit: complete`, 14 routines, 4268 bytes (`ClearIconBits` 265,
`SetIconBits` 301, `HasRecFlag` 94, `DoBash` 587, `DoPick` 204, `FindCodeSlot` 67, `FindCodeRecord` 90,
`DoKnock` 69, `ClampPartyPosition` 174, `MoveParty` 185, `CheckMapCell` 354, `HandleWildernessKeys`
963, `DoWildernessMenu` 826, `ovl14_init` 5), 0 differ, 0 stubs. `make readability UNIT=ovl14` is
clean. Packet: `build/packets/ovl14.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-5, commit bb81dd4, fixed in 51cd2ec)

- [x] must-fix DoWildernessMenu: the comment claimed Pick always calls DoPick; the `ovl29_e3 = 3` arm only clears `ds6DDF` (ovl14:1015). The comment now names both arms: `= 2` 'B'/'P'/'K' call DoBash/DoPick (ovl14:0ED6)/DoKnock with Knock offered by `FindCodeRecord($1F)` (ovl14:0E14), `= 3` 'B'/'K' call DoBash/DoKnock with Knock offered by `HasRecFlag(5)` (ovl14:0F53) and 'P' clears the flag. (fixed in 51cd2ec; whitepaper 5.3 has the same correction)
- [x] should-fix ovl14_init: the empty initialisation at ovl14:10A7 now carries a comment with its address. (fixed in 51cd2ec)
- [x] should-fix OVL14 unit comment: now cites whitepaper 5.3. (fixed in 51cd2ec)
- [x] should-fix HandleWildernessKeys: `SelectedCharacter^.Status = 0` replaces the untyped byte dereference (ovl14:0A2D). (fixed in 51cd2ec)
- [x] should-fix HasRecFlag: "positive byte at +$96+Which" and `> 0`, matching the signed `jle` (ovl14:026A). (fixed in 51cd2ec)
- [x] should-fix ClampPartyPosition: the stray "[I]" is gone. (fixed in 51cd2ec)
- [x] should-fix MoveParty: "resets the ds6DDE..ds6DE0 menu flags to 1" for `FillChar(ds6DDE, 3, 1)` (ovl14:07A9). (fixed in 51cd2ec)
- [x] should-fix CheckMapCell: `VarRiverGate = 418` in `POOLVARS.PAS` replaces the bare `GameVars^[418]`. (fixed in 51cd2ec)
- [x] should-fix TCodeRec/ds5D96: the `LongInt` typing is documented (the ovl11 `ds5D96 := 0` write needs it). (fixed in 51cd2ec)
- [x] should-fix ds49D6: the declaration now records that ovl14 reads words 713, 714 and 725 and that they lie inside `TGameVars`. (fixed in 51cd2ec)

### This cycle (rev-4)

- [ ] note HasRecFlag: the comment says "the Bash/Pick/Knock menu (DoWildernessMenu) offers Pick when flag 6 is found and Knock when flag 5 is found". Pick is flag 6 in both arms, but Knock is flag 5 only in the `ovl29_e3 = 3` arm; the `= 2` arm offers Knock from `FindCodeRecord($1F)` (the DoWildernessMenu comment now says so). Say "Knock in the = 3 arm" or leave the flag relation to DoWildernessMenu.
- [ ] note HandleWildernessKeys: the ICON load of pages 2..4 is guarded by `ds49F9 < 2` (ovl14:0A5B area); the comment says "it loads the ICON pictures for map pages 2..4" without the guard. Faithful and minor.
- [ ] note DoWildernessMenu/DoBash: what `ovl29_e3`'s return values (1, 2, 3) mean in game terms belongs to ovl29; the comments describe the dispatch structure, not the meaning (carried over from the first review).

## What was verified

1. `make match UNIT=ovl14` rerun: complete, all 14 routines L2. `make readability UNIT=ovl14` is clean.
2. The 51cd2ec fixes all hold against the packet: the four DoWildernessMenu addresses (`ovl14:0ED6` DoPick call, `ovl14:0E14` `FindCodeRecord($1F)`, `ovl14:0F53` `HasRecFlag(5)`, `ovl14:1015` `mov ds6DDF,0`); `SelectedCharacter^.Status = 0`; `FillChar(ds6DDE, 3, 1)`; `VarRiverGate`; the `ds49D6` and `ds5D96` `POOLVARS.PAS` comments (`ds49D6` names words 713/714/725, `ds5D96` keeps `LongInt` because ovl11 stores 0).
3. Names true and specific: the eleven routines, `TCodeRec`/`PCodeRec` (LockType +$10, Strength +$16, Codes +$17..$2B, PickThreshold +$78, Flags +$96..$A3, Next +$104, PickFlag +$10C), `GeoCells`, and the menu flags `ds6DDE`/`ds6DDF`/`ds6DE0` (with the documented overrun of `ds6DE0` into `ds6DDE[2]`).
4. Types fit: icon sets and flags are `ShortInt`/`Byte`, the coordinates `ShortInt`/`Integer`, `DoKnock` a `Boolean`, `HasRecFlag`/`DoBash`/`DoPick` `Byte`; `FindCodeSlot` returns `$FF` when absent; the `ds2736`/`ds273F` tables are indexed by the icon set.
5. Comments give addresses and meaning; the ones checked hold: `ClearIconBits`/`SetIconBits` masks ($3F/$CF/$F3/$FC or $40/$10/$04/$01) with the SetIconBits 0..$F guard; `HasRecFlag`'s positive-byte test; `DoBash`'s two `LockType` case trees arm for arm; `DoPick`'s 1d100 against +$78 with +$10C clear and the unconditional `ds6DDF := 0`; `FindCodeSlot`'s 21 slots; `DoKnock`'s `KnockCode = $1F`; `ClampPartyPosition`'s four clamps and the +$5AA edge flag; `MoveParty`'s wrap, refreshes and sound mode; `CheckMapCell`'s clamps, the pass-through set and the river gate; `HandleWildernessKeys`' A/C/V/E/S/L and H/P/K/M arms in both views; `DoWildernessMenu`'s menu strings, the `' Exit'`-only ClearIconBits path, MoveParty-on-Done and the sprite-bank tidy (`FreeSpriteList(@ds6ABE)`, `res07_fn_2595(ds6B01/ds6B06)`).
6. Quirks and honest unknowns: `SpareBuf`/`SpareLong` are marked as never-read frame fillers, `TCodeRec`'s unread ranges are marked, and the source keeps the code's odd bits without "fixing" them. No `inline`/`db`/`assembler`.
7. Stub signatures used are recorded in `re/symbols.toml`; `ovl14_init` is commented.
8. Whitepaper 5.3 has the corrected dispatch and the `VarRiverGate` name.

## Verdict

Passed. Every name, type and comment is true to the bytes; the must-fix and all should-fixes are fixed in 51cd2ec, and the three notes are informational.

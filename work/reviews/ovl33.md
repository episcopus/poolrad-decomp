# Review: ovl33

decompiler: none (src/OVL33.PAS commits 548ad72 and 551e46c have no Agent trailer)
reviewer: rev-2
date: 2026-10-11
commit: 0f26ba1

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Routines: `ShowDebugTrace` (ovl33:0004) and the empty initialisation `ovl33_init` (ovl33:00F7).

## Checked

1. `make match UNIT=ovl33` (rerun): `ShowDebugTrace` 243 bytes, 4 byte pool, 14 address fields; `ovl33_init` 5 bytes; `unit: complete, 252 bytes of code plus 0 of paragraph padding`. `make readability UNIT=ovl33` is clean.
2. `ShowDebugTrace`, `Message: String40`, `DebugMode` and `Yellow = 14` match the bytes (see below). `First`, `Second` and `Third` are only the order of the three bytes.
3. `String40` matches the `StrLCopy` limit `$28` at ovl33:0015. The three `string` locals match `Str` with limit `$FF` (256 byte slots at bp-$129, bp-$229, bp-$329). `DebugMode` is a byte compared with 0 at ovl33:001E.
4. The unit comment and the routine comment describe a debug trace gated on `DebugMode`, and that part is true. They leave the screen coordinates as bare numbers, and they do not say what the only caller passes.
5. No record type in this unit. The caller indexes a far record; that record is not declared here.
6. No quirk. The second clear is after `ShowMessageLine` returns, which is what the comment says.
7. No `inline`, `db` or `assembler`.
8. Whitepaper 5.8 describes the routine and tags it [V]. The names there are the old placeholders (should-fix).
9. `ShowDebugTrace`'s signature is recorded in `re/symbols.toml`. This unit does not add a stub signature of its own.
10. Whitepaper 5.8 has the trace, the `DS:49F7` gate, the call `res06_fn_0DD3(0, 0, 39, 0)`, colour 14, `ShowMessageLine`, and the caller `ovl12:2233`. It does not record what that caller pushes.

`ShowDebugTrace` frame is `retf 10`: `Message` at bp+$0C (copied with max 40), `First` at bp+$0A, `Second` at bp+$08, `Third` at bp+$06. The pool at ovl33:0000 is the Pascal string `' , '` (length 3). `DebugMode` is only read. `Yellow` is the byte `$0E` pushed at ovl33:0090 and ovl33:00D3.

`res06_fn_0DD3` (0709:0DD3, not decompiled) uses the four bytes as left column, top row, right column and bottom row. 0709:0E02 computes the fill count as (right - left + 1); 0709:0DE3 and 0709:0DEE run the scanlines from top*4 through bottom*4+3. With (0, 0, 39, 0) that is columns 0..39 and the four scanlines of character row 0. The arms selected by DS:4A1E fill that rectangle with 0 (`System_FillChar` to the video planes) or pass the same rectangle to `res06_fn_00B7`. So "clears the top line" is what this call does. `res06_fn_0626(0, 0, Yellow, ...)` is column 0, row 0: the callee's signature names the second byte `Row`, and `CheckCodeWheel` passes 1, 2, 5, 8 as successive rows. `ShowMessageLine` then draws on row 24 and waits (`ReadGameKey`, whitepaper 5.15).

The only caller is `ovl12:2233` (`ovl12_fn_2233`, unit name TrainRewards, evidence "[V] training reward"). It copies the literal `'max,cur,lost'` (ovl12:210B, length 12) and pushes `es:[di+$32]`, `es:[di+$11B]` and `es:[di+$75]` of the far pointer at its `[bp+8]`. `$32` is `hp_max` on the character record (whitepaper 4.2.5). `$11B` is inside the 285 byte record; `$75` is too. The trace label says those three bytes are max, current and lost, in that order.

`ovl33_init` is `55 89 E5 5D CB` and nothing else.

## Findings

- [ ] must-fix ShowDebugTrace: the screen position is left as bare numbers, at ovl33:0079 and ovl33:00E0 (`res06_fn_0DD3(0, 0, 39, 0)`) and at ovl33:008A (`res06_fn_0626(0, 0, Yellow, ...)`). 39 is the inclusive right column of the 40 column grid (whitepaper 5.2): 0709:0E02 fills (right - left + 1) columns, and 0709:0DE3 / 0709:0DEE cover character row top through bottom. The zeros are column 0 and row 0. Name them.

- [ ] should-fix ShowDebugTrace: `First`, `Second` and `Third` only number the bytes. The only caller, ovl12:2233, passes the message `'max,cur,lost'` and the bytes at +$32 (`hp_max`), +$11B and +$75. The comment's quoted "First , Second , Third" reads like the literal text; the literals are the separators `' , '` (ovl33:0000). Both the numbers and `Message` are drawn in `Yellow`, and the comment only says the numbers are.

- [ ] should-fix ShowDebugTrace: whitepaper 5.8 still writes `ShowDebugTrace(Text, A, B, C)` and colour 14, and does not record the caller's `'max,cur,lost'` arguments. `re/units.toml` still names the unit `ovl33` with empty evidence.

- [ ] note ovl33_init: empty initialisation at ovl33:00F7, five bytes, matched. The unit comment's "one routine" is the trace.

- [ ] note ShowDebugTrace: the overlay copies `Message` with `System_StrLCopy` max $28 (ovl33:0015) before the `DebugMode` test, so the copy runs even when the trace is skipped. That is the compiler's string parameter copy. `DebugMode` (DS:49F7) is only read. The stub `res06_fn_0DD3(A, B, Width, D)` names the third byte `Width`; the callee uses it as the right column (escalated separately).

## Verdict

Not passed. One must-fix: name the column and row constants in `ShowDebugTrace` (the 0s and the 39).

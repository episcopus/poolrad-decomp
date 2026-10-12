# Review: ovl33

decompiler: dec-4 (Agent trailer of 2236fe2, the fix; the original decompile commits 548ad72 and 551e46c carry none)
reviewer: rev-4
date: 2026-10-11
commit: 925b2a5

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Routines: `ShowDebugTrace` (ovl33:0004) and the empty initialisation `ovl33_init` (ovl33:00F7).

`make match UNIT=ovl33` (rerun): `ShowDebugTrace` 243 bytes plus 4 pool, `ovl33_init` 5; `unit: complete,
252 bytes of code plus 0 of paragraph padding cover the original segment`. `make readability UNIT=ovl33`
is clean. Packet: `build/packets/ovl33.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-2, commit 0f26ba1, fixed in 2236fe2)

- [x] must-fix ShowDebugTrace: the screen position was bare numbers (`res06_fn_0DD3(0, 0, 39, 0)` at ovl33:0079 and 00E0, `res06_fn_0626(0, 0, Yellow, ...)` at ovl33:008A). 39 is the inclusive right column of the 40-column grid. Named `TraceLeft`/`TraceTop`/`TraceRight`/`TraceBottom`. (fixed in 2236fe2)
- [x] should-fix ShowDebugTrace: `First`, `Second` and `Third` only numbered the bytes; the only caller passes `'max,cur,lost'` and `hp_max` (+$32), +$11B and +$75. Renamed `Max`/`Current`/`Lost`, and the comment now names the `' , '` separators and that both the numbers and `Message` are yellow. (fixed in 2236fe2)
- [x] should-fix ShowDebugTrace: whitepaper 5.8 wrote the old signature and did not record the caller's arguments, and `re/units.toml` named the unit `ovl33` with empty evidence. Both updated. (fixed in 2236fe2)

### This cycle (rev-4)

- [ ] note ShowDebugTrace: `Message` is copied to the stack temporary with `System_StrLCopy` limit $28 at ovl33:0015, before the `DebugMode` test at ovl33:001E, so the copy runs even when the trace is skipped. That is the compiler's `String40` value-parameter copy, not something the routine does; the routine comment does not need it, recorded here only so a reader of the frame is not surprised.
- [ ] note ShowDebugTrace: `res06_fn_0DD3`'s stub third parameter was named `Width` while the callee uses it as the inclusive right column. That was the open escalation; `src/RES06.PAS` and `re/symbols.toml` now read `procedure res06_fn_0DD3(Left, Top, Right, Bottom: Byte)`, so the escalation is resolved and the unit comment's "Right - Left + 1 = 40 columns" is consistent.

## What was verified

1. `make match UNIT=ovl33` rerun: complete, both routines L2. `make readability UNIT=ovl33` is clean.
2. Names true and specific: `ShowDebugTrace` shows a debug trace; `Max`, `Current`, `Lost` are the three byte values the caller passes; `TraceLeft`/`TraceTop`/`TraceRight`/`TraceBottom` are the top text line; `Message` is the label on the message line. `DebugMode` (DS:49F7) is read only. `re/units.toml` now names the unit `DebugTrace` with evidence.
3. Types fit: `Message: String40` (the `StrLCopy` limit $28 at ovl33:0015), `Max`/`Current`/`Lost: Byte` (read at bp+$0A, bp+$08, bp+$06), `MaxText`/`CurrentText`/`LostText: string` (256-byte slots at bp-$129, bp-$229, bp-$329, `Str` through `System_Str_Format`). `DebugMode` is a byte compared with 0 at ovl33:001E. The frame is `retf 10`.
4. Comments give addresses and meaning: the top line rectangle (columns 0..39 of character row 0, `res06_fn_0DD3` fills Right - Left + 1 = 40 columns and covers rows Top..Bottom), the `' , '` separators (pool at ovl33:0000), the two clears, `ShowMessageLine(Yellow, Message)` (which waits for a key, whitepaper 5.15), and the only caller `ovl12:2233` with its `'max,cur,lost'` label and `hp_max`/`+$11B`/`+$75` (whitepaper 4.2.5).
5. No record type is declared here. `res06_fn_0DD3(Left, Top, Right, Bottom: Byte)`, `res06_fn_0626(A, Row, Color: Byte; Text: string)` and `ShowMessageLine(Color: Byte; Text: String40)` match the pushes.
6. No quirk. The two clears are before and after the message, which is what the comment says.
7. No `inline`, no `db`, no `assembler`.
8. Behaviour claims match whitepaper 5.8 and are tagged [V].
9. `ShowDebugTrace`'s signature is recorded in `re/symbols.toml`; this unit sets no new stub signature of its own.
10. Whitepaper 5.8 records what the unit taught (the trace, the `DS:49F7` gate, the new signature, the caller's arguments).

## Verdict

Passed. The must-fix and both should-fixes are fixed in 2236fe2; every name, type and comment is true to the bytes, and the two notes are informational.

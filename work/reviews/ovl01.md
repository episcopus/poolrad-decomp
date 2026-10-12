# Review: ovl01

decompiler: dec-2 (Agent trailers of c2e76ca, 6ce2cc6, d8d585d)
reviewer: rev-4
date: 2026-10-11
commit: 109bf74

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl01` (rerun): `WaitKeyOrTimeout` 74 bytes, `ShowCredits` 1051 plus 444 pool,
`ShowTitleScreen` 482 plus 6 pool, `ovl01_init` 5; `unit: complete, 2062 bytes of code plus 0 of
paragraph padding cover the original segment`. `make readability UNIT=ovl01` is clean. Packet:
`build/packets/ovl01.md`.

Routines: `WaitKeyOrTimeout` (ovl01:0000), `ShowCredits` (ovl01:0206), `ShowTitleScreen` (ovl01:0627),
the empty `ovl01_init` (ovl01:0809).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix WaitKeyOrTimeout: the comment says it "then drains the keyboard buffer (FlushKeyboard) so the key does not leak into the next screen" (ovl01:003F). `FlushKeyboard` (`0899:0104`) is a no-op: its first statement is `Exit`, so the drain loop after it is dead code (QUIRK `0899:010A`, whitepaper 5.8). Nothing is drained and a pending key does reach the next screen. Say "calls FlushKeyboard, which does nothing (0899:010A)". The `re/symbols.toml` note for `WaitKeyOrTimeout` repeats "then drains keys with FlushKeyboard".
- [ ] must-fix ShowTitleScreen: the comment says "then flushes keys and shows the credits (ShowCredits)" (ovl01:07FC, `FlushKeyboard` call). Same no-op as above, so the flushes-keys half is not true. State the call and its real effect (none).
- [ ] should-fix ShowTitleScreen: whitepaper 5.8 line 557 says `WaitKeyOrTimeout` "then drains keys (`FlushKeyboard`)" and line 559 repeats the QUIRK; 5.8 line 505 already says FlushKeyboard "returns at once", so the section contradicts itself. Correct line 557's "drains keys".
- [ ] note ShowTitleScreen: `DirBackup: String40` truncates the backed-up `GameDir` to 40 characters (the backup `StrLCopy` limit is $28 at ovl01:0647, the restore `StrLCopy` limit is $FF at ovl01:06DD). Faithful to the original (a 41+ character directory would come back cut), and worth knowing; the comment says only "backs up GameDir".
- [ ] note ShowTitleScreen: the QUIRK "Total is Random(4), always below 50000" (ovl01:0729) rests on the iteration count of the 500-tick wait (`res06_fn_0C3F` + 500). The comparison is a real `Longint > 50000` (high word then `0xC350` at ovl01:0734), so the animation does run once `Total` passes 50000; the whitepaper's [V] (a trace of about 30,000 `Random(4)` calls, mean 1.5, is about 45,000) leaves only a thin margin. Not a defect, but "always" is stronger than the evidence reads.

## What was verified

1. `make match UNIT=ovl01` rerun: complete, all four routines L2. `make readability UNIT=ovl01` is clean.
2. Names true and specific: `WaitKeyOrTimeout(Pause)` waits; `ShowCredits` shows the credits; `ShowTitleScreen` runs the title sequence; `Green`/`LightCyan`/`Yellow` name the EGA colours ($0A/$0B/$0E), `Start`/`Limit`/`Deadline` the tick bounds, `DirBackup` the saved `GameDir`, `Pic` the loaded `PT8x8Bank`.
3. Types fit: `Pause` is `Word` (`mul` by $64), `Start`/`Limit`/`Total`/`Deadline` are `Longint` (32-bit compares and `adc`), `I` is `Byte`, `DirBackup` is `String40` (proven by the $28 copy limit at ovl01:0647), `Pic` is `PT8x8Bank`, `GameDir` is the shared `string`.
4. Comments give addresses and meaning: the res06_fn_0C3F tick bound (`100 * Pause + Start`, the `mul 0x64` at ovl01:0011) and the `KeyPressed` exit; the two `DrawWindow` calls (`1,1,$26,3` and `1,5,$26,$17`, both frame set 0, colour 0, empty text) and the ~33 `res06_fn_0626(Column, Row, Colour, Text)` credit lines, checked against the disasm (for example `res06_fn_0626(5,1,$0A,'scenario created by:')` at ovl01:0258, `($1A,1,$0E,'tsr, inc.')` at ovl01:0275); the `title` picture loads (`res07_fn_0111('title', 1/2, 0, 0, Pic)`), `res07_fn_1951`, `res07_fn_2595(Pic)`, the `res06_fn_0C3F + 500` deadline, the EGA gate `VideoAdapter = 1`, the palette animation through `res07_fn_2A0D` with `Delay($96/$64/$32)` (150/100/50 ms), and `ShowCredits`.
5. `WaitKeyOrTimeout` is `repeat until (res06_fn_0C3F >= Limit) or KeyPressed`, then `FlushKeyboard`; the disasm is the `jg/jl/jae` 32-bit compare at ovl01:0025..003D. `ShowTitleScreen` is `Total := 0; Pic := nil; DirBackup := GameDir; GameDir := ''; ...`, and the backup/clear/restore copies match (ovl01:063D, 0650, 0697, 06CF, 0724).
6. Quirks: `ShowTitleScreen`'s `Total`/`Random(4)` gate is marked `QUIRK ovl01:0729`; the FlushKeyboard no-op is not marked, which is the must-fix. No `inline`/`db`/`assembler`.
7. Side effects stated: screen, `GameDir`; `WaitKeyOrTimeout` and `ShowCredits` are documented as leaving the keyboard as-is (once the flush claim is fixed).
8. Callers: `ShowCredits` calls `WaitKeyOrTimeout($0A)`, `ShowTitleScreen` calls `WaitKeyOrTimeout(5)` and `ShowCredits` (packet callers), `ShowTitleScreen` is the unit entry (the main program calls it before the code wheel, whitepaper 2.2 line 223).
9. Stub signatures this unit set (`res07_fn_0111(S: String; A, B, C: Byte; var P: PT8x8Bank)`, `res07_fn_1951(X, Y: Integer; Buf: Pointer)`, `res07_fn_2595`, `res07_fn_2A0D`, `res06_fn_0C3F: Longint`) are recorded in `re/symbols.toml`.
10. Whitepaper 5.8 records what the unit taught (the title sequence, the credits, the tick wait, the QUIRK, the Boots-to-title oracle check), with the FlushKeyboard clause to correct.

## Verdict

Not passed. Two must-fix: the `WaitKeyOrTimeout` and `ShowTitleScreen` comments claim `FlushKeyboard` drains the keyboard, and it does nothing.

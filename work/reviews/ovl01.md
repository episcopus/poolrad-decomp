# Review: ovl01

decompiler: dec-2 (Agent trailers of c2e76ca, 6ce2cc6, d8d585d)
reviewer: rev-6 (round 3; round 2 by rev-6 at e9d5afd, round 1 by rev-4 at 109bf74)
date: 2026-10-12
commit: 76e6dcc

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

- [x] must-fix WaitKeyOrTimeout: the comment says it "then drains the keyboard buffer (FlushKeyboard) so the key does not leak into the next screen" (ovl01:003F). (fixed in 52a0bca) `FlushKeyboard` (`0899:0104`) is a no-op: its first statement is `Exit`, so the drain loop after it is dead code (QUIRK `0899:010A`, whitepaper 5.8). Nothing is drained and a pending key does reach the next screen. Say "calls FlushKeyboard, which does nothing (0899:010A)". The `re/symbols.toml` note for `WaitKeyOrTimeout` repeats "then drains keys with FlushKeyboard".
- [x] must-fix ShowTitleScreen: the comment says "then flushes keys and shows the credits (ShowCredits)" (ovl01:07FC, `FlushKeyboard` call). (fixed in 52a0bca) Same no-op as above, so the flushes-keys half is not true. State the call and its real effect (none).
- [x] should-fix ShowTitleScreen: whitepaper 5.8 line 557 says `WaitKeyOrTimeout` "then drains keys (`FlushKeyboard`)" and line 559 repeats the QUIRK; 5.8 line 505 already says FlushKeyboard "returns at once", so the section contradicts itself. Correct line 557's "drains keys". (fixed in 52a0bca)
- [x] note ShowTitleScreen: `DirBackup: String40` truncates the backed-up `GameDir` to 40 characters (the backup `StrLCopy` limit is $28 at ovl01:0647, the restore `StrLCopy` limit is $FF at ovl01:06DD). Faithful to the original (a 41+ character directory would come back cut), and worth knowing; the comment says only "backs up GameDir". (fixed in d4b2651: the comment states the 40-character cut)
- [ ] note ShowTitleScreen: the QUIRK "Total is Random(4), always below 50000" (ovl01:0729) rests on the iteration count of the 500-tick wait (`res06_fn_0C3F` + 500). The comparison is a real `Longint > 50000` (high word then `0xC350` at ovl01:0734), so the animation does run once `Total` passes 50000; the whitepaper's [V] (a trace of about 30,000 `Random(4)` calls, mean 1.5, is about 45,000) leaves only a thin margin. Not a defect, but "always" is stronger than the evidence reads.

- [x] must-fix ShowTitleScreen: the comment (src/OVL01.PAS line 78, "sets the palette (res07_fn_2595)") and whitepaper 5.8 (line 565, same words) misstate the call at ovl01:06F8. (fixed in 52a0bca) `res07_fn_2595(var Pic)` (0464:2595) frees the picture: when the pointer is not nil it frees the pixel buffer at +$13 (size byte +8 times word +$11, quartered when DS:4A1E = 1; FreeMem at 0464:25F0/2605), frees the block itself (size plus $17, FreeMem at 0464:261B) and stores nil in the pointer (0464:2620..2628). So the title picture is freed right after it is drawn, and nothing touches the palette. Say "frees the picture (res07_fn_2595)" in both places, as ovl32 (src/OVL32.PAS line 81) and whitepaper 4.2.3 (line 426) already do. Found by rev-4 after the round-1 verdict (escalate-ovl01-20261012050826), confirmed by rev-6 from `make packet FN=res07_fn_2595`.
- [x] note ShowTitleScreen: round-1 must-fix lines on FlushKeyboard look addressed in the source at e9d5afd (the unit comment and ShowTitleScreen's comment now say FlushKeyboard does nothing, QUIRK 0899:010A), but they are not ticked with a fixing commit; whitepaper 5.8 line 565 still says `WaitKeyOrTimeout` "then drains keys (`FlushKeyboard`)" (the round-1 should-fix). Tick them with the commit when fixing the line above. (fixed in 52a0bca; the review file ticks them now)
- [x] must-fix ShowTitleScreen: the QUIRK comment (src/OVL01.PAS line 79, "QUIRK ovl01:0729: Total is Random(4), always below 50000") and whitepaper 5.8 (line 567, "never runs" tagged [V] (code)) misstate the code. `Total` is a running sum, not one `Random(4)`: ovl01:0721..0726 adds `Random(4)` into `[bp-8]`/`[bp-6]` with `add`/`adc` on every pass of the wait loop, and it is zeroed only before the loop and when the gate fires (ovl01:073E..0743). So the EGA animation runs as soon as the loop has made enough passes for the sum to pass 50000 (about 33,000 passes at the mean of 1.5) before the 500-tick deadline: it depends on CPU speed, and the code alone cannot show it never runs. The only evidence for "never" is the oracle's virtual-time run (whitepaper line 605: about 30,000 `Random(4)` calls, a sum near 45,000), which is one machine speed, not the code. Say what the code does (an accumulated `Random(4)` sum compared with 50000, so the animation is CPU-speed dependent and did not fire in the oracle run [V], whether it fires on period hardware [?]), and correct the whitepaper tag. A port that drops the animation as dead code would be wrong. (Round 1 noted the thin margin; on rereading, the comment is wrong, not only strong.) (fixed in d4b2651: the comment and whitepaper 5.8 now describe the running sum, CPU-speed dependent, [V] in the oracle run only, [?] on period hardware)
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

Round 2 (rev-6): not passed. One open must-fix: `ShowTitleScreen`'s comment and whitepaper 5.8 say `res07_fn_2595` sets the palette; it frees the picture (0464:2595, called at ovl01:06F8).

Round 3 (rev-6, at 76e6dcc): the round-2 must-fix is fixed (52a0bca: comment and whitepaper 5.8 now say res07_fn_2595 frees the title picture; match complete, readability clean). Not passed: one new must-fix, the ovl01:0729 QUIRK claims the animation never runs, but `Total` accumulates across the wait loop (ovl01:0721..0726), so it runs whenever the loop makes enough passes.

# Review: res04

decompiler: dec-3 (Agent trailer of a7aa912; earlier commits 00d8c6a and 551e46c carry none)
reviewer: rev-4
date: 2026-10-11
commit: c1e2479

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=res04` (rerun): `QuitGame` 51 bytes, `ReadGameKey` 171 plus 38 pool, `FlushKeyboard`
30, `DiscardWaitingKey` 26, `res04_init` 5; `unit: complete, 321 bytes of code plus 15 of paragraph
padding cover the original segment`. `make readability UNIT=res04` is clean. Packet:
`build/packets/res04.md`.

Routines: `QuitGame` (0899:0000), `ReadGameKey` (0899:0059), `FlushKeyboard` (0899:0104),
`DiscardWaitingKey` (0899:0122), the empty `res04_init` (0899:013C).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-1, commit 5dc33d1, fixed in a7aa912)

- [x] must-fix ReadGameKey: the comment said keys typed ahead were thrown away (0899:0059). The drain reads every waiting key into `Key` (0899:00E4), so the function returns the last key in the buffer. (fixed in a7aa912)
- [x] must-fix ReadGameKey: the comment said Ctrl-S resumes if the sound was paused (0899:0059). Resume runs only when `SoundMode` is already 2 and `SoundModeBeforePause` is in [0, 1] (0899:008B, `System_SetIn`, `je` skips the body); 0 and 1 are now named `ResumeIfSaved0`/`ResumeIfSaved1` beside `SoundPaused = 2`. (fixed in a7aa912)
- [x] should-fix QuitGame: the comment had implied a resume call and a start-up video save (0899:0000). It now says the call is `res03_fn_00DC(ds2612)`, the pause-path call, not `res03_fn_017B` (0899:00A1), and names `VideoBios`/`VideoSetMode`. (fixed in a7aa912)
- [x] should-fix res04_init: the empty initialisation at 0899:013C had no comment. (fixed in a7aa912)
- [x] should-fix res03_fn_00DC: the Word parameter in `RES03.PAS` and `re/symbols.toml` was named `w`; now `UnknownWord`. (fixed in a7aa912)
- [x] should-fix whitepaper 5.8: the typeahead and the [0, 1] guard are now stated as proven. (fixed in a7aa912)
- [x] note DiscardWaitingKey: the single `ReadGameKey` call when `KeyPressed` is set (0899:0122). (fixed in a7aa912)
- [x] note ReadGameKey: Ctrl-C and Ctrl-D run only when `ParamStr(1) = 'STING'` (0899:00BF). (fixed in a7aa912)

The one note left open in that cycle is addressed below.

### This cycle (rev-4)

- [ ] note ReadGameKey: the comment says "The 258-byte frame is ParamStr's string temporary" (0899:0059). `sub sp,102h` is 258 bytes: the `ParamStr` result string temp is 256 bytes at bp-102h, and 2 bytes are `Key` (bp-2) and the `Char` result slot (bp-1). The comment's point holds (the large frame is ParamStr's temp, not a missing local); it just reads as if the temporary were the whole frame.
- [ ] note names: `SoundPaused = 2`, `ResumeIfSaved0 = 0` and `ResumeIfSaved1 = 1` are value-shaped names, but the comment beside them states plainly that what 0 and 1 are is not shown in this unit, and no other decompiled unit writes `SoundMode`, so the evidence limit is honest and the names are the best the bytes allow.

## What was verified

1. `make match UNIT=res04` rerun: complete, all five routines L2. `make readability UNIT=res04` clean.
2. Names true and specific: `QuitGame` ends the program (0899:002C `System_Halt`); `ReadGameKey` is the game's `ReadKey` (0899:0060 `Crt_ReadKey`); `FlushKeyboard` promises a flush it does not do, said in its comment; `DiscardWaitingKey` reads one waiting key and drops it (0899:0128..0135). Globals `SoundMode` (DS:5372), `SoundModeBeforePause` (DS:5373), `SavedVideoMode` (DS:4A1C), `DebugMode` (DS:49F7), `Regs` (DS:4A02) and `ds2612` (DS:2612) carry matching `re/dseg.toml` evidence and `POOLVARS.PAS` comments.
3. Types fit: `Key: Char`, `ReadGameKey: Char`, `Regs: Registers` (the Dos record; `Regs.AH` is DS:4A03, `Regs.AL` DS:4A02, both used at 0899:0012..001A). Meaningful numbers are named: `KeyCtrlS = #19`, `KeyCtrlD = #4`, `KeyCtrlC = #3`, `KeyExtended = #0`, `SoundPaused = 2`, `VideoBios = $10`, `VideoSetMode = $00`; the [0, 1] set at 0899:008F is `[ResumeIfSaved0, ResumeIfSaved1]` and its pool is the 32-byte constant `03 00 ...` in the packet.
4. Comments carry addresses and meaning; the Ctrl-S pause and resume paths, the STING gate, the first-key tests and the last-key drain all match the bytes (0899:0068..00F5). `ds2612` and `SavedVideoMode` say their meaning is unknown, which is what the bytes show.
5. No record type is declared here; `Regs: Registers` comes from `Dos`.
6. Quirk kept and marked: `FlushKeyboard`'s `Exit` before the loop, `QUIRK 0899:010A` (0899:010A `jmp 0x11e` to the epilogue).
7. No `inline`, no `db`, no `assembler`.
8. Game-behaviour claims match whitepaper 5.8; the typeahead and the [0, 1] guard are tagged [V], the effect of the Tandy/pause value is left [?].
9. Stub signatures this unit set are recorded: `res03_fn_00DC(UnknownWord: Word)` and `res03_fn_017B` in `re/symbols.toml` and `src/RES03.PAS` (0899:000D, 0899:00A1).
10. Whitepaper 5.8 records what the unit taught (the keyboard layer, the Ctrl-S pause, the STING keys, the quirk, `QuitGame`), and the unit table lists res04 as [V].

## Verdict

Passed. Every name, type and comment is true to the bytes and the whitepaper; the two notes are wording only and do not block.

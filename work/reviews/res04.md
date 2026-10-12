# Review: res04

decompiler: the human operator (no Agent trailer on src/RES04.PAS; commits 00d8c6a, 551e46c)
reviewer: rev-1
date: 2026-10-11
commit: 5dc33d1

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=res04` reports `unit: complete` (5 routines, 321 bytes of code, 15 of paragraph padding). `make readability UNIT=res04` is clean. The packet is `build/packets/res04.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix ReadGameKey: the comment says keys typed ahead are thrown away (0899:0059). The drain is `while KeyPressed do Key := ReadKey` (0899:00E4), so each extra key overwrites Key and the function returns the last key in the buffer, not the first with the rest discarded. A port that dropped typeahead without storing it would not match.
- [ ] must-fix ReadGameKey: the comment says Ctrl-S resumes the sound if it was paused (0899:0059). Resume runs only when SoundMode is already 2 and SoundModeBeforePause is in [0, 1] (0899:008B, `System_SetIn`, `je` skips the body). Otherwise a second Ctrl-S does nothing. 0 and 1 are bare beside the named constant SoundPaused = 2; name them for that test, without guessing speaker versus Tandy. The pause path passes ds2612 to res03_fn_00DC and the comment never says so.
- [ ] should-fix QuitGame: the comment says it puts the sound back the way it was before a Ctrl-S pause, stops the sound unit's output, and restores a video mode saved at start-up (0899:0000). The code copies SoundModeBeforePause into SoundMode and calls res03_fn_00DC(ds2612), the pause-path call, not res03_fn_017B (the resume call at 0899:00A1). Whitepaper 5.8 says "restores the setting" and marks sound on/off [I]; 5.14's proven stop is 08AE:13B1. No writer of SavedVideoMode (DS:4A1C) is shown, so "at start-up" is not backed. Intr($10) is bare; AH=0 is the named constant VideoSetMode.
- [ ] should-fix res04_init: the empty initialisation at 0899:013C (`55 89 E5 5D CB`, then 15 zero bytes of paragraph padding) has no comment and no address. `begin end.` is what the bytes are.
- [ ] should-fix res03_fn_00DC: the signature this unit recorded in RES03.PAS and re/symbols.toml names the Word parameter `w`. The width is right (`retf 2`, one word pushed at 0899:0009 and 0899:007B). The meaning of ds2612 is still unknown, so the name should say that instead of a placeholder.
- [ ] should-fix whitepaper 5.8: "keys typed ahead are lost, as for a person" reads as if the first key were kept, and "two-state setting" leaves out the [0, 1] guard at 0899:008B. The quoted `Key := ReadKey` is the part that is right. The 3.2 unit table still marks res04 [?]; section 5.8 is the real entry.
- [ ] note FlushKeyboard: the name is the flush the dead loop would have done. QUIRK 0899:010A matches the `jmp` to the epilogue (the `Exit` before `while KeyPressed do Key := ReadGameKey`). Callers include CheckCodeWheel (ovl02:00FD), as the comment says.
- [ ] note DiscardWaitingKey: one call of ReadGameKey when KeyPressed is set (0899:0122), so Ctrl-S and the STING keys do run. The typeahead drain inside ReadGameKey can still consume more than that one key; the comment points at ReadGameKey but does not say so.
- [ ] note ReadGameKey: Ctrl-C and Ctrl-D run only when ParamStr(1) = 'STING' (0899:00BF), and Ctrl-D is `DebugMode := not DebugMode` (0899:00C7). That matches the comment and whitepaper 5.8. The 258-byte frame is ParamStr's string temporary (`sub sp,102h`), not a missing local.

## Verdict

Not passed. ReadGameKey's comment misstates the keyboard drain and the Ctrl-S resume condition; those two must be fixed before review-pass.

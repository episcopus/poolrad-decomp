# Review: ovl00

decompiler: the human operator (no Agent trailer on src/OVL00.PAS; commits 00d8c6a, 551e46c)
reviewer: rev-1
date: 2026-10-11
commit: dbc6aa9

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl00` reports `unit: complete` (HeapErrorHandler 106 bytes, ovl00_init 18 bytes). `make readability UNIT=ovl00` is clean. The packet is `build/packets/ovl00.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix HeapErrorHandler: the QUIRK says the handler never returns to the heap manager because QuitGame halts (ovl00:00A3). Size = 0 takes `jbe` at ovl00:004C straight to ovl00:00A3, which loads AX from the unassigned result word at [bp-2] and `retf 2`. That path does not call QuitGame. The "never assigned" half of the quirk is true on both paths; "never returns" is true only for Size > 0.
- [ ] must-fix whitepaper 5.15: the same sentence, "the handler never returns to it", follows a paragraph that already limits the warning to a non-zero size. Size = 0 still returns. The rest of the paragraph matches the bytes (colour 14, the two strings, ds49D0, ovl17_e9, ds557D, QuitGame, HeapError := @HeapErrorHandler).
- [ ] should-fix ovl00_init: the initialisation at ovl00:00AC has no comment of its own. The unit comment is right: it stores @HeapErrorHandler as the far pointer at DS:4414 (offset 0025, stub segment 0016; whitepaper 3.6).
- [ ] should-fix ds557D: POOLVARS says ovl17_e9 sets it. This unit only reads it after the call (ovl00:0075). Who writes it is not shown until ovl17 is decompiled.
- [ ] note HeapErrorHandler: for Size > 0 the comment matches the loop. ds49D0 false shows both strings and quits; ds49D0 true calls ovl17_e9 and repeats while ds557D is false (ovl00:0069). Calling ovl17 the save and load unit follows re/units.toml (SaveLoad, [V] save disk prompt). Yellow = 14 matches `mov al,0Eh`. The ovl17_e9 signature this unit recorded is `procedure ovl17_e9` (`retf` with nothing pushed). The 40-byte frame is the $O+ copies of the two string constants (0AF8:0B0B), not missing locals.

## Verdict

Not passed. The comment and whitepaper 5.15 say the handler never returns; Size = 0 returns with an unassigned Integer result.

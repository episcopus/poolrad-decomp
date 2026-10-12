# Review: res02

decompiler: the human operator (no Agent trailer on src/RES02.PAS; commits 548ad72, 551e46c)
reviewer: rev-1
date: 2026-10-11
commit: b5a2505

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=res02` reports `unit: complete` (res02_init, 5 bytes of code, 11 of paragraph padding). `make readability UNIT=res02` is clean. The packet is `build/packets/res02.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix res02_init: the unit comment does not give the address 0A31:0000. This unit has no procedure, so that comment is the routine comment, and the checklist asks for the address there. The bytes are `55 89 E5 5D CB` (`push bp; mov bp,sp; pop bp; retf`) followed by 11 zero bytes of paragraph padding (`make match UNIT=res02`). A port can still be written from `begin end.` alone.
- [ ] note res02_init: no game name is justified. The segment holds only the empty initialisation, called from the main program because `src/POOL.PAS` lists RES02 after Crt. `re/symbols.toml` keeps the provisional name `res02_init`. Whitepaper 2.2 and 3.2 mark the same fact [V].
- [ ] note res02_init: `re/symbols.toml` size 16 counts the 11 padding bytes with the 5 bytes of code. That is the usual approximate boundary; the matcher is the authority.
- [ ] note RES02: the unit comment's second sentence ("complete, nothing else to decompile") is process status. It is true. No parameters, locals, globals, constants, records, quirks, raw machine code, or stub signatures in other units.

## Verdict

Passed. The source is an empty unit whose initialisation does nothing, which is what 0A31:0000 is, and the whitepaper (2.2, 3.2) says so with evidence.

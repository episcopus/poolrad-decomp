# Review: res11

decompiler: the human operator (no Agent trailer on src/RES11.PAS; commits 548ad72, 551e46c)
reviewer: rev-1
date: 2026-10-11
commit: b5a2505

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=res11` reports `unit: complete` (res11_init, 5 bytes of code, 11 of paragraph padding). `make readability UNIT=res11` is clean. The packet is `build/packets/res11.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] should-fix res11_init: the unit comment does not give the address 03DA:0000. This unit has no procedure, so that comment is the routine comment, and the checklist asks for the address there. The bytes are `55 89 E5 5D CB` (`push bp; mov bp,sp; pop bp; retf`) followed by 11 zero bytes of paragraph padding (`make match UNIT=res11`). A port can still be written from `begin end.` alone.
- [ ] note res11_init: no game name is justified. The segment holds only the empty initialisation. `src/POOL.PAS` lists RES11 in the uses clause, so the main program calls it at start-up. `re/symbols.toml` keeps the provisional name `res11_init` (notes `auto:init`).
- [ ] note res11_init: whitepaper 3.2's unit table still marks the role [?], while the paragraph later in 3.2 states that res11 contains nothing but this empty initialisation (`make match`, complete) [V]. `re/units.toml` evidence for res11 is empty. The source comment matches the paragraph and the bytes, not the stale table cell.
- [ ] note res11_init: `re/symbols.toml` size 16 counts the 11 padding bytes with the 5 bytes of code. That is the usual approximate boundary; the matcher is the authority.
- [ ] note RES11: the unit comment's second sentence ("complete, nothing else to decompile") is process status. It is true. No parameters, locals, globals, constants, records, quirks, raw machine code, or stub signatures in other units.

## Verdict

Passed. The source is an empty unit whose initialisation does nothing, which is what 03DA:0000 is, and the whitepaper paragraph in 3.2 says so.

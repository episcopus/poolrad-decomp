# Review: res10

decompiler: none (src/RES10.PAS commits 548ad72 and 551e46c have no Agent trailer)
reviewer: rev-2
date: 2026-10-11
commit: b5a2505

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

The only routine is the initialisation `res10_init` at 03ED:0000, written as `begin end.`

## Checked

1. `make match UNIT=res10` (rerun): `res10_init` matched, 5 bytes of code, 0 pool, 0 address fields; `unit: complete, 5 bytes of code plus 11 of paragraph padding cover the original segment`.
2. Names: the file and unit stay `RES10` (the id). There are no parameters, locals, globals or constants. `res10_init` in `re/symbols.toml` is the init entry (`notes = "auto:init"`). No game role is claimed.
3. Types: none. The init takes nothing and returns nothing (`retf` with no immediate).
4. The unit comment is true: the segment is 16 bytes and its only instructions are the empty initialisation. It does not state the address, the caller, or that nothing is read or written (should-fix below).
5. No record types.
6. No quirk. The 11 bytes after `retf` are paragraph padding (zeros), which `begin end.` already produces.
7. No `inline`, `db` or `assembler`.
8. The comment cites whitepaper 3.2. That section's paragraph states the same fact with `[V]`. The units table in that section still has `[?]` for this unit (should-fix below).
9. This unit sets no stub signature in another unit.
10. Whitepaper 3.2 (the paragraph after the main-program listing) says res10 contains nothing else: a 16-byte unit whose only code is that empty initialisation, evidenced by `make match`. The table row was not brought in line with that paragraph.

Bytes at segment 03ED: `55 89 E5 5D CB` then eleven `00` bytes (`push bp; mov bp, sp; pop bp; retf`). The only caller is the main program at 0000:0042, `9A 00 00 ED 03`, with a relocation on the segment word. That call is the res10 step of the init chain, between ovl33 (0000:003D) and ovl32 (0000:0047), which is the `RES10` place in `src/POOL.PAS`. `make readability UNIT=res10` is clean.

## Findings

- [ ] should-fix res10_init: the unit comment does not give the address 03ED:0000, the caller, or the globals and side effects. The routine is the empty initialisation (5 bytes, plus 11 bytes of paragraph padding). Its only caller is the main program at 0000:0042. It reads and writes no globals and has no side effect. The purpose is stated and true, so this does not block; the comment should still carry the address and those facts.

- [ ] should-fix res10_init: whitepaper 3.2's unit table still lists the role as `[?]` (`res10 | 03ED:0000 | [?]`). The same section already records that the unit contains nothing else. The res02 row of that table was updated; this row was not.

- [ ] note res10_init: `re/symbols.toml` size 16 is the whole paragraph. `make packet` reports no caller because it only searches inside mapped routines, and this call sits in the init chain before the main block at 0000:00F6. `re/units.toml` keeps the name `res10` with empty evidence, which matches there being no game role beyond the empty init.

## Verdict

Passed. The source is an empty initialisation, and that is what the bytes at 03ED:0000 are. No must-fix finding.

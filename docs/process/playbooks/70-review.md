# 70 Review a unit (Reviewer)

**Inputs:** a unit branch where `make match UNIT=<id>` passes; a fresh agent session that did not write the code.

L2 already proves the instructions. The review is about everything the compiler cannot check: what the names, types and comments claim.

## Checklist (per routine)

1. `make match UNIT=<id>` passes on the branch as given (rerun it; do not trust the commit message).
2. The routine's name, if not the provisional `resNN_fn_XXXX` / `ovlNN_eN`, is backed by evidence (strings, behaviour in the oracle, callers) recorded in `re/symbols.toml` notes or the whitepaper.
3. Parameter and local names and types say what the code does with them (a `Byte` used as a Boolean is a `Boolean`; a word compared unsigned is a `Word`).
4. Globals: every `re/dseg.toml` name added for this unit has evidence; `dsXXXX` placeholders are fine.
5. Record types (if any) match every field offset the code uses.
6. Quirks are kept and marked `QUIRK:` with the address; nothing was "fixed".
7. No raw machine code (`inline`, `db`) and no `assembler` routine where Pascal would match.
8. Comments are accurate; claims about game behaviour carry a whitepaper tag ([V], [I], [H]).
9. Stub signatures this unit changed in other units' files still let every matched routine match (`make check`).

## Output

Write findings into `work/reviews/<unit>.md` (routine id, finding, severity: must-fix / should-fix / note). Do not edit the code. When there are no must-fix findings, run `make review-pass UNIT=<id>` (records L1 for the routines; delivered in P4).

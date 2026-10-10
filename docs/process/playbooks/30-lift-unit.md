# 30 Lift a unit (Lifter)

**Inputs:** a unit id from `make next` or the orchestrator; the unit unlocked.

## Steps

1. `make lock UNIT=<id>`; create a worktree: `git worktree add ../poolrad-<id> -b unit/<id>`.
2. `make packet UNIT=<id>`; read it, then the whitepaper sections it lists.
3. Order the unit's routines leaves first (callees before callers).
4. For each routine:
   1. Confirm or write its signature in `re/symbols.toml` and any record types in `re/types/` (with offset asserts).
   2. Write the **faithful** C in `src/game/<unit>.c`: same control flow and evaluation order, Pascal semantics through `src/rtl` helpers, globals through `G`, heap through `FP()`. Provenance comment above the function (SPEC 7.1).
   3. `make hybrid host` must build without warnings.
   4. `make fuzz FN=<id>`. On a difference, read the first divergence report (address, expected vs actual), fix, rerun. Maximum 5 attempts, then write a `blocked` note and continue with the next routine.
   5. Commit: `<unit>: lift <name> (<id>) [L2]`.
5. When every routine is L2 (or justified), run `make sessions` with the unit in C (`HYBRID_C=<unit>`); bisect failures per playbook 40.
6. Readability pass for the unit: rename locals, introduce enums and named constants, add comments that explain intent; rerun `make fuzz UNIT=<id>` and `make sessions` after each step.
7. Request review (playbook 70) from a fresh agent session.
8. Update the design doc (playbook 60).
9. `make unlock UNIT=<id>`; hand the branch to the orchestrator for merge.

## Rules of thumb

- Ghidra's decompiler output is a hint, not the answer: it often mis-types Pascal strings, sets and nested-procedure frames.
- When a code shape is unclear (string temporaries, set operations, `with`, `case` tables, nested-procedure frames, Boolean evaluation), write the Pascal you think it was and compile it with the compiler that built the game: `make tpc SRC=<scratch dir>/GUESS.PAS DISASM=1` (TP 6.0, June 1991; output in `build/tpc/`). Use POOL's switches: `{$F+,S-,R-,G-}`, plus `{$I+}` only for res05 (whitepaper 2.2). Runtime calls in the listing are labelled with the matching POOL routine. TP 6.0 has no `const` parameters and no `$Q`. Keep scratch Pascal out of `src/`; the C is still the deliverable.
- Keep original quirks (off-by-ones, uninitialised reads); comment them as `QUIRK:` with the address.
- Never change shared headers or `platform.h` yourself; ask the orchestrator.

## Done when

All routines of the unit at L2 (or L1 plus L3 with a justification), sessions green, review passed, whitepaper updated.

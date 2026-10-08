# 70 Review a unit (Reviewer)

**Inputs:** a unit branch at L2; a fresh agent session that did not write the code.

## Checklist (per routine)

1. Same parameters, in the same order, with the same types and sizes as the disassembly shows.
2. Same calls, in the same order, with the same arguments; no call added or removed.
3. Same evaluation order where side effects or RNG calls are involved.
4. Pascal semantics respected: string lengths and truncation, set operations, signed vs unsigned comparisons, integer wraparound, Boolean as byte.
5. Every global and record field used by offset matches `re/dseg.toml` / `re/types/`.
6. Quirks kept and marked `QUIRK:`.
7. Fuzz spec covers the routine's interesting inputs (look at branches the fuzz report shows as never taken).
8. Names and comments are accurate and evidence-backed.
9. Portability rules (SPEC 7.2) followed.

## Output

Write findings into `work/reviews/<unit>.md` (routine id, finding, severity: must-fix / should-fix / note). Do not edit the code. When there are no must-fix findings, run `make review-pass UNIT=<id>` (records L1 for the routines).

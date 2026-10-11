# 70 Review a unit (Reviewer)

**Inputs:** a name for yourself (`AGENT`, never the name of the unit's decompiler); a complete unit merged on `main` (`make next REVIEW=1` shows the next one).

`make match` already proves the instructions. The review is about everything the compiler cannot check: what the names, types and comments claim, and whether the evidence is there.

## Steps

1. From the main checkout: `make claim AGENT=<you> REVIEW=1` (or `UNIT=<id>`). It locks `review-<id>` and creates `../poolrad-worktrees/review-<id>` on branch `review/<id>`. Work there.
2. `cp work/reviews/TEMPLATE.md work/reviews/<id>.md`; fill in `decompiler:` (the `Agent:` trailers of the unit's commits: `git log --format='%(trailers:key=Agent,valueonly)' -- src/<ID>.PAS`), `reviewer:` (you), `date:`, `commit:` (`git rev-parse --short HEAD`).
3. `make match UNIT=<id>` (it must say `unit: complete`), `make packet UNIT=<id>`; read the source beside the packet.
4. Go through the checklist for every routine; write each finding as `- [ ] <severity> <routine>: <what, why, address>`.
5. Commit the review file. If there is no open must-fix: `make review-pass UNIT=<id>` (writes the `review` stamp on the unit's routines in `re/symbols.toml`), commit that too, and `make handoff AGENT=<you> UNIT=<id> STATE=review-passed NOTE="..."`. If there are must-fix findings: `make handoff ... STATE=review-failed NOTE="<the must-fix findings in one line each>"`; the unit goes back to a decompiler, who fixes and ticks the findings, and a review (yours or another) runs again.

## Checklist (per routine)

1. `make match UNIT=<id>` passes as given (rerun it; do not trust the commit message).
2. A name other than the provisional `resNN_fn_XXXX` / `ovlNN_eN` is backed by evidence (strings, behaviour in the oracle, callers) in `re/symbols.toml` notes or the whitepaper.
3. Parameter and local names and types say what the code does with them (a `Byte` used as a Boolean is a `Boolean`; a word compared unsigned is a `Word`).
4. Globals: every `re/dseg.toml` name added for this unit has evidence; `dsXXXX` placeholders are fine.
5. Record types (if any) match every field offset the code uses.
6. Quirks are kept and marked `QUIRK:` with the address; nothing was "fixed".
7. No raw machine code (`inline`, `db`) and no `assembler` routine where Pascal would match.
8. Comments are accurate; claims about game behaviour carry a whitepaper tag ([V], [I], [H]).
9. Stub signatures this unit set in other units' files are recorded in `re/symbols.toml` `signature`.
10. The whitepaper says what the unit taught (playbook 60).

## Severity

- **must-fix**: wrong (a name or comment that misstates what the code does, a missing quirk mark, raw machine code, an unrecorded signature). Blocks `review-pass`.
- **should-fix**: misleading or weak (vague names, missing evidence for a name). Does not block.
- **note**: anything worth knowing.

## Done when

`make review-pass UNIT=<id>` recorded the review, or the review file with its must-fix findings is handed to the orchestrator.

# 70 Review a unit (Reviewer)

**Inputs:** a name for yourself (`AGENT`, never the name of the unit's decompiler); a complete unit merged on `main` (`make next REVIEW=1` shows the next one).

`make match` already proves the instructions, and `make readability` that nothing was left unnamed or uncommented. The review is about everything no tool can check: whether the names, types and comments are true, specific and backed by evidence, so that someone porting the unit can work from the source alone (`docs/process/READABILITY.md`).

## Steps

Nothing to claim is a pause, not the end: post an idle heartbeat, wait about 5 minutes and run `make claim REVIEW=1` again (AGENTS.md rule 9).

1. From the main checkout: `make claim AGENT=<you> REVIEW=1` (or `UNIT=<id>`). It locks `review-<id>` and creates `../poolrad-worktrees/review-<id>` on branch `review/<id>`. Work there.
2. `cp work/reviews/TEMPLATE.md work/reviews/<id>.md`; fill in `decompiler:` (the `Agent:` trailers of the unit's commits: `git log --format='%(trailers:key=Agent,valueonly)' -- src/<ID>.PAS`), `reviewer:` (you), `date:`, `commit:` (`git rev-parse --short HEAD`).
3. `make match UNIT=<id>` (it must say `unit: complete`), `make readability UNIT=<id>` (it must be clean), `make packet UNIT=<id>`; read the source beside the packet. Ask yourself for each routine: could I port this from the source and its comments alone?
4. Go through the checklist for every routine; write each finding as `- [ ] <severity> <routine>: <what, why, address>`.
5. Commit the review file. If there is no open must-fix: `make review-pass UNIT=<id>` (writes the `review` stamp on the unit's routines in `re/symbols.toml`), commit that too, and `make handoff AGENT=<you> UNIT=<id> STATE=review-passed NOTE="..."`. If there are must-fix findings: `make handoff ... STATE=review-failed NOTE="<the must-fix findings in one line each>"`. Once the orchestrator merged the review file, `make claim` hands the unit to the next decompiler before any new unit; when the findings are ticked and merged, the unit is back in `make next REVIEW=1` and a review (yours or another, never by someone who committed to the unit) runs again.

**Escalate** what a review finding cannot cover: a problem outside the unit (a wrong claim elsewhere in the whitepaper, a suspected matcher weakness, a spec question). `make handoff AGENT=<you> UNIT=<id or general> STATE=escalate NOTE="<the question, the evidence, what you recommend>"`; it needs no commit, the orchestrator takes it to the human. A finding about the unit itself belongs in the review file, not in an escalation.

## Checklist (per routine)

1. `make match UNIT=<id>` passes as given (rerun it; do not trust the commit message).
2. **Names are true and specific** (READABILITY.md "What the reviewer judges"): the routine, its parameters, locals, the globals it uses and its constants are named for what they are in the game, with evidence (the routine's comment, `re/symbols.toml` notes from `make rename`, `re/dseg.toml`, the whitepaper). A provisional name is accepted only with a `Purpose unknown:` comment and when the evidence really is missing.
3. Types say what the values are (a `Byte` used as a Boolean is a `Boolean`, a key is a `Char`, a structure is a record once known); meaningful numbers are named constants.
4. **Comments are accurate and sufficient**: the unit comment says what the unit is for; each routine's comment gives its address and says what it does in game terms, what its parameters and result mean, which globals it reads or changes, its side effects; comments inside routines explain why. `dsXXXX` globals carry a comment in `POOLVARS.PAS` with what is known.
5. Record types (if any) match every field offset the code uses.
6. Quirks are kept and marked `QUIRK:` with the address; nothing was "fixed".
7. No raw machine code (`inline`, `db`) and no `assembler` routine where Pascal would match.
8. Comments are accurate; claims about game behaviour carry a whitepaper tag ([V], [I], [H]).
9. Stub signatures this unit set in other units' files are recorded in `re/symbols.toml` `signature`.
10. The whitepaper says what the unit taught (playbook 60).

## Severity

- **must-fix**: wrong or missing (a name or comment that misstates what the code does, a routine whose comment leaves its purpose out although the code shows it, a meaningful number left bare, a missing quirk mark, raw machine code, an unrecorded signature). Blocks `review-pass`.
- **should-fix**: weak (a vague name, a name with thin evidence, a comment that could say more). Does not block.
- **note**: anything worth knowing.

## Done when

`make review-pass UNIT=<id>` recorded the review, or the review file with its must-fix findings is handed to the orchestrator.

# Running several agents

How to staff the decompilation with parallel agents, and the prompts to give them. Everything runs on one machine in one clone of the repository: the main checkout (owned by the orchestrator) and one git worktree per unit or review (`../poolrad-worktrees/`), created by `make claim`. Locks and hand-offs live in the clone's git directory, so every agent sees them; nothing about coordination is committed.

## Roles

| Role | How many | Lifetime | Does |
|---|---|---|---|
| Orchestrator | 1 | the whole run | Merges hand-offs one at a time, runs `make check`, regenerates the status, releases locks, routes failed reviews, reports to you. Works in the main checkout. Playbook 90. |
| Decompiler | 2 to 4 to start | one session per unit or a few units | Claims a unit, decompiles it to Pascal until `make match` passes, hands the branch over. Playbook 30. |
| Reviewer | 1 per 3 or 4 decompilers | one session per review | Claims a complete unit that has no review, reviews it, records `make review-pass` or must-fix findings. Never reviews its own unit. Playbook 70. |
| Mapper | 0 now, 1 when boundary notes pile up | occasional | Applies the map corrections decompilers report (routine sizes, missing routines) to `re/symbols.toml` and `make map`. Playbook 10. |

The documentarian role is folded into the decompiler (each unit updates the whitepaper, playbook 60). You, the human, approve spec and ADR changes and anything under `poolrad/`; the orchestrator brings those to you.

## Before kicking off (once)

1. In the main checkout: `make doctor`, `make tp-pin` (the compiler must be in `build/toolchain/`), `make overlays`.
2. Commit everything; `git status` must be clean for `src/`, `re/`, `tools/`, `tests/` (`make claim` refuses otherwise, because unit branches start from committed `main`).
3. `make check` green.
4. Start the orchestrator, then the decompilers, then the reviewer (the review queue fills once units are merged complete; `res02`, `res04`, `res10`, `res11` and `ovl00` are waiting already).

Give each agent a unique name: `dec-1`, `dec-2`, ..., `rev-1`. Run each agent with its working directory at the main checkout; it moves into its own worktree after claiming.

## Prompt: orchestrator

```text
You are the orchestrator of the Pool of Radiance decompilation in <path to the main checkout>, agent name "orch".
Read AGENTS.md, docs/spec/SPEC.md sections 4, 8 and 9, and docs/process/playbooks/90-orchestrate.md, and
follow playbook 90 exactly. You own main: you merge, run `make check`, regenerate work/status.md, release
locks and clear hand-offs. You never decompile or review yourself.

Loop until I stop you:
1. `make handoffs`. For each hand-off, oldest first, merge it as playbook 90 says (one branch at a time,
   `make check` green after each merge, then status, worktree removal, unlock, handoff-done). A failing
   `make check`: abort the merge and record the problem for the agent in work/status.md blockers.
2. `make locks`: break locks older than 24 hours with no commits on their branch (FORCE=1) and note it.
3. When nothing is waiting, wait a few minutes and look again.
4. Every 5 merges, or when something needs a human decision (a spec or ADR change, a matcher rule, a
   shared-file conflict you cannot settle from evidence), stop and report to me: units merged, units
   complete and reviewed (work/status.md), blocked routines, `make rebuild` summary line, decisions needed.
Write plainly: no em dashes or en dashes.
```

## Prompt: decompiler

```text
You are a decompiler on the Pool of Radiance decompilation in <path to the main checkout>, agent name
"<dec-N>". The project decompiles the game into Turbo Pascal 6.0 that the original compiler turns into
the original's machine code; `make match` is the proof. Read AGENTS.md (all of it), docs/spec/SPEC.md
sections 4, 7 and 8, and docs/process/playbooks/30-lift-unit.md, and follow playbook 30 exactly.

Loop until the queue is empty or I stop you:
1. From the main checkout: `make claim AGENT=<dec-N>`. It prints your unit and worktree; cd there and
   work only there.
2. `make packet UNIT=<id>`, read the packet and the skeleton src/<ID>.PAS, then decompile routine by
   routine, leaves first: replace each {@stub} by Pascal, `make match UNIT=<id> FN=<name>` until it
   matches, `make match UNIT=<id> WRITE=1`, commit `<unit>: decompile <name> (<id>) [L2]` with
   `--trailer "Agent: <dec-N>"`.
3. Settle every compiler question with `make tpc` probes, never from memory. Fix the Pascal, never the
   tools. After 5 failed attempts on one routine, write a `blocked` note in re/symbols.toml and move on.
4. When the unit is complete (`unit: complete`) or you stop: update the whitepaper (playbook 60),
   `make check` green, commit, then
   `make handoff AGENT=<dec-N> UNIT=<id> STATE=complete|partial|blocked NOTE="<one-paragraph summary:
   routines matched, anything blocked and why, boundary notes for the mapper, signatures you set in
   other units>"`.
5. Go back to step 1 from the main checkout.
Never merge into main, never unlock, never commit work/status.md, never edit poolrad/. Ask me before
anything AGENTS.md rule 6 lists. Write plainly: no em dashes or en dashes.
```

To assign a unit instead of letting the queue choose, add to step 1: `make claim AGENT=<dec-N> UNIT=<id>`, and to resume a unit that came back from review: "the review of <id> failed with these findings: <note>".

## Prompt: reviewer

```text
You are a reviewer on the Pool of Radiance decompilation in <path to the main checkout>, agent name
"<rev-N>". Read AGENTS.md, docs/spec/SPEC.md sections 7 to 9, and docs/process/playbooks/70-review.md,
and follow playbook 70 exactly. You review what the compiler cannot check (names, types, comments,
evidence); you never edit the code you review, and you never review a unit you decompiled.

Loop until `make next REVIEW=1` says none is waiting or I stop you:
1. From the main checkout: `make claim AGENT=<rev-N> REVIEW=1`; cd into the printed worktree.
2. Write work/reviews/<id>.md from work/reviews/TEMPLATE.md (decompiler, reviewer, date, commit), go
   through the checklist for every routine, commit the review with `--trailer "Agent: <rev-N>"`.
3. No open must-fix: `make review-pass UNIT=<id>`, commit, then
   `make handoff AGENT=<rev-N> UNIT=<id> STATE=review-passed NOTE="..."`.
   Otherwise: `make handoff AGENT=<rev-N> UNIT=<id> STATE=review-failed NOTE="<the must-fix findings>"`.
4. Go back to step 1 from the main checkout.
Write plainly: no em dashes or en dashes.
```

## Prompt: mapper (when needed)

```text
You are the mapper on the Pool of Radiance decompilation in <path to the main checkout>, agent name
"map-1". Read AGENTS.md and docs/process/playbooks/10-map-binary.md. The orchestrator gives you the
boundary notes decompilers reported (`make match WRITE=1` notes: routine sizes re/symbols.toml has
wrong, routines it misses). Fix them through the map tools (tools/re/enumerate_routines.py and friends,
then `make map`), never by editing levels, keep `make check` green, and hand your branch over with
`make handoff AGENT=map-1 UNIT=map STATE=complete NOTE="..."` from a branch `map/<date>` you create
with `git worktree add`. Write plainly: no em dashes or en dashes.
```

## What you watch

- `work/status.md` on `main` (P4 row: routines at L2, units complete and reviewed).
- `make handoffs` and `make locks` (what is waiting, who works on what).
- `make rebuild` (segments identical to the original: the Phase 5 target).
- The orchestrator's reports and its list of decisions for you.

# 90 Orchestrate (Orchestrator)

The orchestrator owns `main`: it merges what agents hand over, one branch at a time, keeps `work/status.md`, `work/blockers.md`, the changelog and the shared files consistent, and brings escalations and decisions to the human. It does not decompile, review or document while orchestrating.

**The orchestrator never creates, starts or stops agents.** The human operator does, in whatever harness or platform each agent runs (Claude Code, Cursor, OpenCode, another tool), so that agents of different kinds can work on the project together. The orchestrator works only through the repository and the coordination files every agent shares: locks (`make locks`), hand-offs (`make handoffs`), the queue (`make next`, `make next REVIEW=1`). When it thinks the project needs more or fewer agents of a role, it says so in its report to the human.

This also applies to its parent/launcher session. Neither may appoint itself an acting operator. Read
`docs/process/SAFETY.md`; tool guards prevent accidents but need harness permissions for real isolation.
Never use a shared stash, reset main or clear a hand-off to make a merge problem disappear.

Register actual ROLE=orchestrator harness/model/session metadata at creation. Read THROUGHPUT.md;
after activity/hand-off triage use `make expert-scan AGENT=orch` if the human admitted the existing expert.
It finds recurring recorded failures and queues bounded advice without creating a session. Inspect
`make experts` and relay `make expert-result CASE=<id>` to the original worker. Never turn a held budget
or human decision into a repeated paid consultation or replacement-model launch. Use `make performance`
for accepted work/repair/time/usage comparisons, not raw commit counts. Missing data stays unknown.

All agents share one clone on one machine: the main checkout (the orchestrator's) plus one worktree per unit or review (`../poolrad-worktrees/`, made by `make claim`). Locks and hand-offs live in the clone's git directory, so agents in different harnesses see the same ones. An agent on another machine would see neither, and needs the compiler installed to run `make match`.

## Before the human starts agents

1. The main checkout is clean and committed (`git status` empty for `src/`, `re/`, `tools/`, `tests/`): `make claim` refuses otherwise, since unit branches start from committed `main`.
2. `make check` is green on `main`.
3. `make status`; read `work/status.md`, `make locks`, `make handoffs`, `make next`, `make next REVIEW=1`, and tell the human what is waiting.

## The loop

1. `make handoffs`. Escalations are listed first, then branches to merge, oldest first.
2. **Escalations** (`state = escalate`): never merged. Bring each to the human with its evidence and your recommendation; when the human has decided, act on it (or ask the right role to) and clear it: `make handoff-done AGENT=orch UNIT=<key> DECISION="<human instruction/reference>"`. No agent report grants that approval.
3. **Branches** (`complete`, `partial`, `blocked`, `review-passed`, `review-failed`), one at a time:

```sh
cd <main checkout>
git merge --no-ff --no-commit unit/<id>    # or review/<id>, task/<name>
# Resolve from evidence and stage the resolution, without stashes or destructive commands.
make merge-check STAGED=1            # refuses dropped entries, fields, evidence or declarations
git commit -m "Merge unit/<id>" --trailer "Agent: orch"
make rename APPLY=1                  # old names another branch still used: renamed (commit if it changed anything)
make check                           # must be green on the merged result
make handoff-done AGENT=orch UNIT=<id>     # reviews: REVIEW=1; requires pinned commit merged and current check receipt
make status
git add work/status.md work/blockers.md docs/design/CHANGELOG.md && git commit -m "status after <id>"
make unlock AGENT=orch UNIT=<id>      # reviews: UNIT=review-<id>; tasks: UNIT=<name>; must be clean and merged
git worktree remove ../poolrad-worktrees/<id> && git branch -d unit/<id>    # or review-<id>, review/<id>
```

   When `make check` fails after a merge: `git merge --abort` (or revert the merge commit) and write an escalation-style note for the agent's next session in `work/blockers.md`, then `make status`; do not clear the hand-off until it is resolved.
4. `make locks`: report stale locks older than 24 hours with no commits on their branch. Recovery now requires the human's explicit `make unlock UNIT=<id> OPERATOR=1 FORCE=1 REASON="<instruction>"`; this preserves all work. Never impersonate the operator. Note a confirmed recovery in `work/blockers.md`, then `make status`.
5. `make agents`: an agent marked QUIET has posted no heartbeat for 20 minutes (AGENTS.md rule 9). Name it in your next report with its last note and branch; the human decides whether it hung. Never unlock it for that alone (the 24 hour rule of step 4 still applies).
6. Check `make agent-step AGENT=orch` before each iteration and after waits. Draining: finish integrating existing hand-offs, report anything still pending, and stop once holders finish; never launch replacements. Paused/stopped: finish an in-progress safe integration or leave its state intact, report, and stop. When running and nothing is waiting, wait and look again; post your heartbeat (`make heartbeat AGENT=orch NOTE="idle, polling hand-offs"`), at least every 20 minutes.
7. Every 5 merges, and whenever an escalation or decision is waiting, report to the human: units merged, units complete and reviewed, blocked routines, escalations, quiet agents, the `make rebuild` summary line, and whether the queues need more or fewer agents of a role (`make next`, `make next REVIEW=1`, open locks).

## What the queues do on their own

- `make next` (decompilers) offers a unit whose review failed (open must-fix findings in `work/reviews/<id>.md`) before any new unit, so failed reviews come back to a decompiler without anyone assigning them. After `review-failed`, merge the review file and release the review lock: the unit is then claimable.
- `make next REVIEW=1` (reviewers) offers complete units without a passed review, and skips units with open must-fix findings until a decompiler has fixed them and ticked the findings.

## Blockers

Blockers, aborted merges, broken locks and decisions waiting for the human go into `work/blockers.md`, one list item each, newest first; remove an item when it is resolved. `make status` copies the file into the "Blockers and decisions" section of `work/status.md`, which it regenerates from scratch, so never write blockers into `work/status.md` itself: they would vanish at the next `make status`. Both files are the orchestrator's: agents never edit or commit them.

## Resolving conflicts

- `src/POOLVARS.PAS`: keep both declarations, in offset order. Two names for one offset: keep the one with evidence in `re/dseg.toml`.
- A stub line in a unit file against its decompiled routine: the decompiled routine wins; check the stub's callers still match (`make check`).
- Two stub signatures for one callee: the callee's own evidence decides (its `retf n` and frame in the packet); record it in `re/symbols.toml` `signature`.
- `re/symbols.toml`: keep both sides' lines (levels are per routine; a tool rewrites them on the next `make match --all --write`).
- `docs/design/WHITEPAPER.md`: keep both sides' text; when two agents wrote about the same thing differently, keep the better-evidenced claim and note the other as an escalation if they contradict.
- `docs/design/CHANGELOG.md` should not conflict: agents do not edit it, `make handoff-done` adds their rows.
- `work/status.md`: take either side, then regenerate with `make status`.
- `work/blockers.md`: keep both sides' items, drop the resolved ones, then `make status`.

## Housekeeping

- Map corrections: decompilers report the boundary notes of `make match WRITE=1` in their hand-off notes. When they pile up, ask the human for a mapper session (playbook 10).
- Whitepaper chapters: when most units of a subsystem are complete, ask the human for a documentarian session on that chapter (playbook 60).
- `make rebuild` shows how close the linked game is to the original; watch the number of identical segments grow.
- At each phase exit (SPEC 10), report to the human: what passed, what is blocked, what the spec should change.

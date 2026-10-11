# 90 Orchestrate (Orchestrator)

The orchestrator owns `main`: it starts the other agents, merges their branches one at a time, keeps `work/status.md` and the shared files consistent, and reports to the human. It does not decompile while orchestrating. Everything runs on one machine, in one clone: the main checkout plus one worktree per unit (`../poolrad-worktrees/<id>`), coordinated by locks in the clone's git directory (`make locks`).

## Before starting agents

1. The main checkout is clean and committed (`git status` empty for `src/`, `re/`, `tools/`, `tests/`): `make claim` refuses otherwise, since unit branches start from committed `main`.
2. `make check` is green on `main`.
3. `make status`; read `work/status.md`, `make locks`, `make next`, `make next REVIEW=1`.

## Starting agents

Give each agent its prompt from `docs/process/KICKOFF.md` with a unique name (`dec-1`, `dec-2`, `rev-1`, ...). Two to four decompilers and one reviewer is a good start; add decompilers while merges stay easy. Each decompiler claims its own units (`make claim`); you may instead assign one (`UNIT=<id>` in its prompt), for example to keep a subsystem with one agent.

## Merging a hand-off (one branch at a time)

`make handoffs` lists the branches agents handed over (unit, agent, branch, commit, state, note), oldest first.

```sh
cd <main checkout>
git merge --no-ff unit/<id>          # or review/<id>
make check                           # must be green on the merged result
make status && git add work/status.md && git commit -m "status after <id>"
git worktree remove ../poolrad-worktrees/<id> && git branch -d unit/<id>    # or review-<id>, review/<id>
make unlock UNIT=<id>                # review branches: make unlock UNIT=review-<id>
make handoff-done UNIT=<id>          # review branches: make handoff-done UNIT=<id> REVIEW=1
```

State `review-failed`: merge the review file only (it is the branch's content), then the unit is free for a decompiler to take again (`make claim UNIT=<id>`); put the note in front of the next decompiler.

A partial unit (some routines L2, the rest blocked or left) merges the same way; release its lock so another agent can continue, and note the blocked routines in `work/status.md` blockers.

## Resolving conflicts

- `src/POOLVARS.PAS`: keep both declarations, in offset order. Two names for one offset: keep the one with evidence in `re/dseg.toml`.
- A stub line in a unit file against its decompiled routine: the decompiled routine wins; check the stub's callers still match (`make check`).
- Two stub signatures for one callee: the callee's own evidence decides (its `retf n` and frame in the packet); record it in `re/symbols.toml` `signature`.
- `re/symbols.toml`: keep both sides' lines (levels are per routine; a tool rewrites them on the next `make match --all --write`).
- `work/status.md`: take either side, then regenerate with `make status`.

When `make check` fails after a merge: `git merge --abort` (or revert the merge commit), hand the failure back to the agent with the tool output.

## Reviews

After merging a complete unit, it appears in `make next REVIEW=1`. A reviewer claims it (`make claim REVIEW=1`). A passed review merges like a unit branch. A review with must-fix findings: merge the review file, then a decompiler takes the unit again (`make claim UNIT=<id>`; the lock is free once you released it).

## Housekeeping

- Map corrections: decompilers report the boundary notes of `make match WRITE=1` (sizes `re/symbols.toml` has wrong, routines it misses). Batch them for a mapper session (playbook 10), then `make map` and `make check`.
- A lock older than 24 hours with no commits on its branch may be broken: `make unlock UNIT=<id> FORCE=1`; note it in `work/status.md`.
- `make rebuild` shows how close the linked game is to the original; watch the number of identical segments grow.
- At each phase exit (SPEC 10), report to the human: what passed, what is blocked, what the spec should change.

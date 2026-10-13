# 90 Integrate (the human, or a script on a timer)

Integration is mechanical: `make integrate` merges every waiting hand-off into `main`, one at a time,
oldest first, and nothing a model decides is on that path. The former orchestrator session is retired
(SYSTEM-REVIEW 6.2); what it reported is now `make inbox`. `main` is never dirty: every step runs in a
temporary worktree and `main` only ever moves by a fast-forward to a checked commit.

**The human operator still creates and stops every agent** (`make worker`, or a session by hand with the
prompts of `docs/process/KICKOFF.md`). Scripts never launch sessions.

## What `make integrate` does for one hand-off

1. A temporary worktree `build/integrate/<key>` on branch `integrate/<key>` from `main`.
2. `git merge --no-ff --no-commit <branch>`. The shared files (`re/symbols.toml`, `re/dseg.toml`,
   `re/renames.toml`, `re/learnings/*.toml`, `src/POOLVARS.PAS`) merge record by record through the driver
   installed by `make merge-driver` (`.gitattributes`), so two branches conflict only when both changed the
   same record.
3. `make rename APPLY=1` (old names another branch still used), `make stubs WRITE=1` (every `{@stub}` line
   from the registry's `signature`), `make merge-check STAGED=1` (nothing lost).
4. `make status` and the hand-off's changelog row (`CHANGELOG=`), so the merge commit carries both.
5. `make check` in the temporary worktree: fast tests, every unit's match, readability, the rebuild link,
   the goldens. The receipt is for exactly the tree that lands.
6. One merge commit (`Merge unit/<id> (<state>): <note>`, trailers `Agent: integrator` and the worker's),
   `git merge --ff-only` into `main`, the hand-off archived (`performance` attribution as before), the lock
   released, the worker's worktree removed when clean, its branch deleted.

A failing step (conflict, lost record, red check) rejects the hand-off: the record gets `integrate =
rejected` with the reason and the log (`build/integrate/<key>.log`), `main` is untouched, the temporary
worktree is removed. The worker (or whoever takes the unit next with the same agent name) re-claims the
unit (`make claim AGENT=<owner> UNIT=<id>` reuses its lock and worktree and prints the reason), fixes the
branch and hands off again; the new hand-off clears the rejection.

`make integrate DRY=1` merges and checks without touching `main`. `KEY=<key>` integrates one hand-off,
including a rejected one after a fix elsewhere (for example a matcher change that now accepts it).

## The loop

```sh
make inbox          # what waits for a human: escalations, rejections, stale locks, frontier, is main checked
make integrate      # merge everything that is waiting
make inbox
```

Run it whenever hand-offs are waiting, or on a timer (a cron entry or `make watch-agents` next to it).
Escalations are never merged: each is listed by `make inbox` with its evidence, the recommendation and
the command that records the decision (`make handoff-done AGENT=integrator UNIT=<key> DECISION="..."`).
Clearing an escalation needs a human decision; `integrator` is the registered orchestrator identity the
scripts use for bookkeeping, not an actor that approves anything.

## Resolving a conflict the driver could not

Only the same record changed on both sides reaches a human. Resolve it from evidence, on the worker's
branch (re-claim it as the owner, fix, commit, hand off again), never on `main`:

- `src/POOLVARS.PAS`: two names for one offset: keep the one with evidence in `re/dseg.toml`.
- Two stub signatures for one callee: the callee's own frame decides (`retf n`, `make packet FN=`); record
  it as `signature` in `re/symbols.toml`; `make stubs WRITE=1` rewrites every stub line from it.
- `re/symbols.toml` notes: keep both notes (the driver joins them with `; ` when it can).
- `docs/design/WHITEPAPER.md`: keep both sides' text; when two agents wrote about the same thing differently,
  keep the better-evidenced claim and escalate a contradiction.

## Locks, worktrees and stopped agents

- A lock is released by `make integrate` when its branch is merged, or by the worker's supervisor when its
  branch has no commits beyond `main` (the owner release path of `make unlock`).
- A lock whose owner stopped without a hand-off and whose branch has commits is listed by `make inbox`;
  the human releases it with `make unlock UNIT=<id> OPERATOR=1 FORCE=1 REASON="..."`, which keeps the
  branch and worktree; the next claimer of that unit continues from them.
- `make agents` and `make watch-agents` still show heartbeats; a worker run by `make worker` heartbeats
  from its supervisor, so QUIET means the supervisor itself is gone.

## Housekeeping

- Boundaries: `make match WRITE=1` writes the compiler's boundaries into the registry as part of every
  routine's match; there are no boundary notes to collect and no mapper session to ask for.
- Whitepaper chapters: when most units of a subsystem are complete, start a documentarian session on that
  chapter (playbook 60).
- `make rebuild` shows how close the linked game is to the original; it converges only in Phase 5 (the
  smart linker drops every routine nothing calls yet, SYSTEM-REVIEW 3).
- At each phase exit (SPEC 10), report to the human: what passed, what is blocked, what the spec should change.

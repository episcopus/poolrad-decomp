# Running the decompilation as the human operator

What you do once the tools are installed, what each `make inbox` line asks of you, and how to stop.
Everything a model decides happens inside a worker session; everything that lands on `main` goes
through `make integrate`; everything that needs you is printed by `make inbox` with the command to run.

## Once per machine

```sh
make doctor && make tp-pin && make overlays     # environment, compiler, overlay code
make merge-driver && make hooks                 # record-level merge of the shared files, pre-commit guard
make check                                      # a receipt for the current main
```

## The short way: one command each way

```sh
make start-run        # admits the run and opens one iTerm tab per session of work/roster.toml
make run-status       # heartbeats, processes, locks, inbox
make stop-run         # drains, lets workers hand off, integrates, releases every lock, resets, closes the tabs
```

`work/roster.toml` lists the sessions (name, role, OpenCode model id, reasoning-effort `variant`); edit it to change the roster or
the models. Decompilers and reviewers run as workers by default: their tab runs the supervisor
(`make worker`, below and docs/process/WORKER.md), which starts a fresh `opencode run` session for each
batch of routines or each review and claims again until the run is stopped. Optional per-worker fields:
`variant` (the OpenCode model variant), `batch` (routines per session) and `timeout` (minutes per
session); the supervisor's own output is also in build/run/<name>.log and each session's in
build/worker/<name>/. Every other role (orchestrator, expert) is an interactive OpenCode session started
with the prompt block of docs/process/START-AGENT.md that its `heading` names; `mode = "interactive"`
makes a decompiler or reviewer one too, but then it lasts only as long as its model keeps working in one
turn (on 2026-10-13 every such session stopped on its own within 90 minutes, work still queued). The first
entry is the orchestrator session, which runs the loop below and decides what the inbox lists (its
limits are in its KICKOFF.md prompt: the spec, ADRs, the session set and `poolrad/` stay yours). With
it running, your own involvement is reading its reports in its tab and answering what it leaves for you.
`make stop-run` waits up to `WAIT=20` minutes for the sessions to hand off, then sends SIGTERM to what
still runs (a worker answers with a hand-off of what it committed; stop-run waits for it), lands what they handed off,
releases the rest with an operator record (branches with commits are kept for the next claimer and
listed), and leaves control `stopped`, so `make start-run` can follow immediately.

### Tiers, escalation and the end of a run

Tier-1 decompilers (cheap models) take units from the queue; escalation workers (`tier = 2`, a stronger
model, `cost_cap` and `timeout` per session) take only the routines tier 1 gave up on (WORKER.md, "The
escalation tier"). What both tiers fail on appears in `make inbox` under "Escalation failed", with the
routine's notes; that, rejected integrations the loop could not resolve, and failed reviews it could not
fix are what the run leaves for you. When nothing is planned for `idle_stop` minutes (60 by default)
the integrator loop starts `make stop-run` itself (log build/run/auto-stop.log), so an overnight run
ends when its work does.

### The integrator loop

The roster entry with `role = "integrator"` (`int-loop`) is a script, not a model session
(tools/agent/integrator.py): every `interval` seconds it runs `make integrate` when hand-offs wait,
queues expert cases when you admitted an expert budget, and posts a heartbeat. A hand-off that
`make integrate` rejects for a merge conflict or a red check gets up to two tries per pinned commit in the
branch's worktree: first a plain `git merge main` with the recorded renames and `make check`, then, if
that is not clean, one fresh `opencode run` session with the entry's model that resolves the conflict
(keeping both sides, as tools/agent/resolve_prompt.md asks); its result must be a clean, committed merge
of main or it is saved as patches and reset. Anything else (lost records, attempts spent) stays in
`make inbox` for you. Logs: build/integrator/ and build/run/int-loop.log. `make integrate` holds an
exclusive lock, so running it yourself or from an orchestrator session at the same time is harmless.
On 2026-10-14 the interactive orchestrator ended its turn and hand-offs waited an hour: the loop is why
the orchestrator session is now optional.

`make run-add NAME=<name>` starts one roster entry in the running run without admitting it again: an
entry added to work/roster.toml after `make start-run` (such as the integrator), or one whose tab was
closed (a worker you stopped with Ctrl+C). It refuses a name whose process is still alive.

## Starting a run by hand

```sh
make agent-control STATE=running OPERATOR=1 REASON="human approved: 3 decompilers, 1 reviewer"
```

Then one terminal per worker, from the main checkout. The first time a name is used, give its
creation metadata; later runs of the same name need only the first two values:

```sh
make worker AGENT=dec-1 ROLE=decompiler HARNESS=opencode MODEL=<provider/model> SESSION=dec-1-run1 [SESSION_MODEL=<provider/model>]
make worker AGENT=dec-2 ROLE=decompiler HARNESS=opencode MODEL=<provider/model> SESSION=dec-2-run1
make worker AGENT=rev-1 ROLE=reviewer   HARNESS=opencode MODEL=<provider/model> SESSION=rev-1-run1
```

A worker claims the queue's next unit (or `UNIT=<id>`), runs one `opencode run` session per batch of
routines (`BATCH=6`, `TIMEOUT=90` minutes), verifies each batch with `make match`, hands the branch off
when the unit is done or exhausted, and goes to the next unit. Ctrl+C stops it cleanly: it hands off
what is committed, or gives back an untouched claim, and never leaves a lock. `docs/process/WORKER.md`
has every option; `docs/process/START-AGENT.md` is the alternative for a session you drive by hand.

## Your loop

```sh
make inbox        # what needs you
make integrate    # merge every waiting hand-off (temporary worktree, make check, fast-forward)
make inbox
```

Run it whenever you look in, or on a timer:

```sh
while sleep 600; do make integrate; make inbox; done
```

`make watch-agents` shows live progress and heartbeats; `work/status.md` on `main` has the counts
(`make integrate` regenerates it with every merge).

## What each inbox section means

- **Escalations.** A worker asked a question it may not answer itself (a spec rule, a contradiction
  between units, a matcher result it believes wrong). Read the note (the file it names has the full
  text), decide, then run the printed command with your decision in `DECISION="..."`. A matcher gap is
  not for you to approve any more: say "tooling task" in the decision and start a tooling session on
  it; the change merges when `make match-gate` passes.
- **Rejected.** `make integrate` could not merge a branch: a conflict in the same record, a lost record,
  or a red `make check`. The reason is on the line and the log holds the details. The printed command
  restarts the owner's worker on that unit; its sessions see the rejection reason and fix the branch,
  then hand off again. A whitepaper conflict (two agents wrote the same section) is the usual cause and
  is resolved by keeping both sides.
- **To merge.** Branches waiting: run `make integrate`.
- **Locks.** A lock whose holder stopped without handing off, or is older than a day with nothing on its
  branch. Look at the branch (`git log main..unit/<id>`) and the worktree; release with the printed
  `make unlock ... OPERATOR=1 FORCE=1 REASON="..."`, which keeps the branch and worktree for the next
  claimer. Untracked scratch files in a worktree block the normal release: move them out of the
  worktree first.
- **Frontier.** Routines two sessions could not match. Nothing to do until something changes (a
  matcher fix, a hint in the registry notes); then `.venv/bin/python tools/agent/worker.py --release <unit>`
  puts them back in the queue.
- **Main.** No passing check receipt for the current tree: run `make check` (needed before an
  already-merged hand-off can be cleared; `make integrate` does it itself when it has to).
- **Queues.** The next unit and the next review: start a worker if none is running.

## Stopping

```sh
make agent-control STATE=draining OPERATOR=1 REASON="finish current units and stop"   # claims stop, holders finish
make agent-control STATE=stopped OPERATOR=1 REASON="run ended"                          # after the workers exit
```

Ctrl+C in each worker terminal, then `make integrate` once more to land what they handed off, and
`make inbox` to see that nothing is left.

## Things that still need a person

- Decisions: escalations, the spec, the session set, anything under `poolrad/`.
- Reading matcher diffs after they merge (`git log -- tools/match`).
- Whitepaper chapters across units (a documentarian session, playbook 60) and the Phase 5 link order.

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

## Starting a run

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

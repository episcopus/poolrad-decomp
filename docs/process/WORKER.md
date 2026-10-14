# Workers: a supervisor owns the lock, sessions are disposable

`make worker` replaces the long-lived model session as the holder of a unit lock (SYSTEM-REVIEW
2026-10-12, sections 5.4 and 6.5). The supervisor is a plain Python script (`tools/agent/worker.py`):
it claims a unit, keeps the lock, posts the heartbeats, and starts a fresh model session for each
bounded batch of routines. A session that runs out of context or crashes costs one batch, never the
lock or a parked draft. `make inbox` shows everything that still needs a human.

## Starting a worker

From the main checkout: `make worker AGENT=dec-1 ROLE=decompiler HARNESS=opencode MODEL=<provider/model>
SESSION=<harness session id>` (the creation metadata is needed the first time a name is used, exactly as
for `make agent-register`; afterwards `make worker AGENT=dec-1 ROLE=decompiler` is enough). With `UNIT=<id>`
the worker claims that unit (or, as a reviewer, that review), works it and stops; without it, the
worker takes the queue's next unit again and again until the shared control is no longer `running`
(`make agent-control`). `ROLE=reviewer` claims reviews instead. Options: `BATCH` routines per session
(6), `TIMEOUT` minutes per session (90), `MAX_SESSIONS` for a bounded run, `MAX_ATTEMPTS` before a
routine goes to the frontier (2), `IDLE` seconds to wait when nothing is claimable (300), and
`SESSION_CMD`, the shell template that starts a session with `{worktree}`, `{prompt_file}` and
`{model_flag}` placeholders. The default is the installed opencode in a non-interactive run:
`cd {worktree} && opencode run --auto --session {session_id} --title {title}{model_flag} "$(cat {prompt_file})"`;
`SESSION_MODEL=` fills `{model_flag}` with ` --model <m>` (OpenCode takes `provider/model#variant`),
`{title}` is `<agent> <unit>-batch<N>`, so each session's cost can be found in OpenCode afterwards, and
`{session_id}` is a fresh id the supervisor chooses. The sessions run on OpenCode's background service,
which holds the provider credentials (a `--standalone` private server found no models on 2026-10-13);
a session there outlives its killed client, so on a timeout or a stop the supervisor also interrupts
it through the service API by that id.
`make start-run` starts this supervisor for every decompiler and reviewer of work/roster.toml. For the Claude CLI use
`SESSION_CMD='cd {worktree} && claude -p "$(cat {prompt_file})"'`. Stop a worker with Ctrl+C or
SIGTERM: it kills the running session, saves and discards uncommitted changes, hands off the branch (or
gives back an untouched claim) and posts a `stopped` heartbeat. It never leaves a lock behind.

## What a session gets and what happens after it

Each session receives one prompt (`tools/agent/worker_prompt.md`, filled in with the worktree, the
unit, the agent name and the batch: the next `BATCH` routines of the unit that are still `{@stub}`,
not at L2/L3, not `blocked` in `re/symbols.toml` and not in the frontier, in address order, with the
`{@stub-init}` initialisation part as the last item). The prompt asks for playbook 30 step 3 on exactly
those routines, one commit per matched routine with the `Agent:` trailer, and a committed `blocked`
note for a routine the session gives up on. When the session ends (done, timed out and killed, or
crashed) the supervisor saves any uncommitted change to a patch file and discards it, then runs
`make match UNIT=<id>`: if anything that is not a stub differs, the batch's commits are saved as
patches and the branch is reset to where the batch started; otherwise `make match WRITE=1` records L2
and the registry change is committed. A reviewer session gets `tools/agent/review_prompt.md` and runs
once per review (playbook 70); the supervisor hands off `review-passed` when the committed review has no
open must-fix and the stamp is written, else `review-failed` with the findings in the note.

## Exhaustion: hand-off or release

When nothing is left to plan for the unit (everything is matched, blocked or in the frontier), or
`MAX_SESSIONS` is reached, or the control turns to `paused`/`stopped`, the supervisor runs `make check`
in the worktree and hands the branch off from there (`STATE=complete` when every routine of the unit is
at L2/L3, else `partial`) with an automatic note: how many routines matched in this run, how many are
blocked, how many are in the frontier, whether the check was green and where its log is. A branch with
no commits beyond main has nothing to merge: the supervisor gives the claim back with
`tools/agent/unlock.py <key> --agent <name> --owner`, which removes the lock, the worktree and the branch
(allowed only for the holder, with no pending hand-off, zero commits beyond main and a clean worktree;
every other unlock rule is unchanged). If the hand-off itself is refused, the supervisor writes an
escalation so the lock still shows up in the inbox.

## The frontier

`.git/poolrad-frontier/<unit>.json` (in the clone's common git directory, shared by every worktree,
never committed) counts the attempts per routine: a routine still `{@stub}` after a batch, without a
`blocked` note, gets one more attempt; at `MAX_ATTEMPTS` (2) the planner stops offering it. The frontier
is what keeps a worker from spending every session on the same unmatched routine. Print it with
`.venv/bin/python tools/agent/worker.py --frontier [UNIT]`; after a matcher or map fix, clear it with
`.venv/bin/python tools/agent/worker.py --release <unit> [routine]` and start a worker on the unit
again. `make inbox` lists the routines at the limit.

## Reading the logs

Everything a worker produces outside git lives in `build/worker/<agent>/` of the main checkout
(ignored by git): `<unit>-batch<N>.prompt.md` is the prompt the session got, `<unit>-batch<N>.log` the
session's stdout and stderr followed by the `make match` output that verified it, `<unit>-batch<N>.patch`
the uncommitted changes the supervisor discarded after the session (the status listing, the diff and
every untracked file's content), `<unit>-batch<N>-commits/` the commits of a batch that was reset
because `make match` showed a difference, `<unit>-check.log` the `make check` before the hand-off and
`<unit>-handoff.log` the hand-off itself. A reviewer's files are `<unit>-review.*`. The heartbeat
(`make agents`) names the unit, the batch and its routines while a session runs; the frontier entry of a
routine names the batch log of its last attempt.

## Running two workers

Two workers need two agent names (`AGENT=dec-1`, `AGENT=dec-2`) and nothing else: the lock is taken
atomically, so each claims a different unit, each has its own worktree under `../poolrad-worktrees/`,
its own log directory and its own heartbeat. Start each in its own terminal (or under `nohup`), from
the main checkout. A decompiler and a reviewer can run side by side the same way (`ROLE=reviewer`).
Keep the number of workers to what the machine's compiler runs can take: every `make match` compiles
every unit, and the hand-off's `make check` takes about a minute.

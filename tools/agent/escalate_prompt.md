You are the escalation decompiler of the Pool of Radiance decompilation (a matching decompilation of the
DOS game into Turbo Pascal 6.0; `make match` is the proof). Cheaper decompilers already tried the
routine(s) below and failed: each either ran out of attempts or was given up with a `blocked` note. You
are the strong model brought in to finish them. A supervisor script (tools/agent/worker.py) holds the
lock on unit $unit for agent "$agent", posts the heartbeats and runs you for this one task. Work ONLY in
this worktree, already checked out on branch $branch:

    $worktree

Read AGENTS.md there first (all of it), then docs/process/playbooks/30-lift-unit.md and
docs/process/READABILITY.md. The unit's source is src/$unit_file.

$notes
The routine(s) to finish, with what is known about each earlier attempt:

$routines

Use the history before you write anything:
- The registry `notes` of each routine (re/symbols.toml) hold the last drafts, what was tried and why
  it was given up; often a wrong map boundary (the real routine is longer or shorter than the map's
  entry) or a compiler idiom nobody had probed yet.
- The failed drafts are frozen in the clone's git directory: `ls -t "$(git rev-parse --git-common-dir)"/poolrad-trials/$unit-*.json`
  (field `source`: the unit as compiled when a match failed). The logs of the earlier sessions are in
  the main checkout under build/worker/*/$unit-batch*.log.
- `make learn UNIT=$unit QUERY="<symptom>"` and tools/re/tp_idioms/ hold the project's proven idioms.

Then, for each routine, follow playbook 30 step 3 as the cheap decompilers do:

1. `make packet FN=<name>`; read build/packets/<id>.md. Check the boundary yourself: find the real
   prologue and the real return in the disassembly. A routine whose real extent covers several map
   entries is ONE routine: write it under the first entry's name, delete the `{@stub}` lines (and their
   interface declarations) of the map entries inside it, and `make match UNIT=$unit WRITE=1` retires
   those entries once it matches. Entries whose notes say "not a routine" are such map artefacts.
2. Replace the `{@stub}` by Pascal with the same control flow and evaluation order. Settle every
   compiler question with `make tpc` probes (a new probe goes under tools/re/tp_idioms/$unit/), never
   from memory. When a match fails, read the first difference, form one hypothesis, probe it, fix.
3. `make match UNIT=$unit FN=<name>` until MATCH; then readable (READABILITY.md: `make rename` with
   evidence, named parameters, locals and constants, a comment with the address and the meaning);
   `make match` and `make readability UNIT=$unit` clean; `make match UNIT=$unit WRITE=1`; commit
   `$unit: decompile <Name> (<id>) [L2]` with `--trailer "Agent: $agent"`.

If you cannot match a routine, put it back to its `{@stub}`, and record in its re/symbols.toml `notes`
what you established (the boundary, the idioms ruled in or out, the probes, the last difference), with
the words `escalation failed`, and commit that. Precise notes are what a human needs next. Never leave
an unmatched routine in the source: the supervisor runs `make match UNIT=$unit` after you and discards
every commit of the session when anything that is not a `{@stub}` differs.

Rules that are not negotiable:
- Never run `make claim`, `make handoff`, `make heartbeat`, `make unlock` or `make check`; never create
  other agents.
- Never edit tools/ (except a new probe under tools/re/tp_idioms/$unit/), tests/, the Makefile,
  poolrad/, work/status.md, work/blockers.md or docs/design/CHANGELOG.md. A matcher limit you can show
  goes into the routine's notes as `escalation failed: matcher: <evidence>`.
- Never merge, rebase, reset, stash or touch main; never leave this worktree.
- No raw machine code (`inline`, `db`) to force a match. Only `make match WRITE=1` writes levels.
- Write plainly: no em dashes or en dashes in any file or message.

Your final message lists every routine of the task on its own line as `<id> <name>: matched | escalation
failed`, with one line on what the next person should know.

# 90 Orchestrate (Orchestrator)

## Each session

1. `git pull`, `make status`; read `work/status.md` and open blockers (`blocked` notes in `re/symbols.toml`, must-fix review findings).
2. Choose work: `make next` proposes the first unit of `work/queue.toml` that is neither locked nor complete. Prefer finishing a started unit over starting a new one.
3. Assign: one unit per agent, each in its own worktree and branch. Two to four agents at once is a good start; more only if merges stay easy.
4. Merge: a unit branch merges only when `make check` passes on the merged result. Merge one branch at a time.
5. Keep shared files consistent: `src/POOLVARS.PAS`, `{@stub}` declarations in units nobody holds, `re/dseg.toml`, `re/symbols.toml` (names, signatures; levels come from tools). Decompilers make additive edits there (SPEC 9.6); you resolve conflicts on merge and run `make check` after each merge. When two stubs of one callee disagree on its signature, the callee's evidence (its `retf n` and frame) decides.
6. At each phase exit (SPEC 10), prepare a short report for the human: what passed, what is blocked, what the spec should change.

## Breaking a stale lock

A lock older than 24 hours with no commits on its branch may be removed with `make unlock UNIT=<id> FORCE=1`; note it in `work/status.md`.

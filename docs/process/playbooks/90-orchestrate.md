# 90 Orchestrate (Orchestrator)

## Each session

1. `git pull`, `make status`; read `work/status.md` and open blockers (`blocked` notes in `re/symbols.toml`, must-fix review findings).
2. Choose work: `make next` proposes units whose callees are already lifted. Prefer finishing a started unit over starting a new one.
3. Assign: one unit per agent, each in its own worktree and branch. Two to four agents at once is a good start; more only if merges stay easy.
4. Merge: a unit branch merges only when `make check` passes on the merged result. Merge one branch at a time.
5. Keep shared files consistent: `src/include`, `src/rtl`, `src/platform`, `re/types/`, `re/dseg.toml`. Requests from lifters for changes there come to you; batch them.
6. At each phase exit (SPEC 10), prepare a short report for the human: what passed, what is blocked, what the spec should change.

## Breaking a stale lock

A lock older than 24 hours with no commits on its branch may be removed with `make unlock UNIT=<id> FORCE=1`; note it in `work/status.md`.

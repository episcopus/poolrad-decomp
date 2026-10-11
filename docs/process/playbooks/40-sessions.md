# 40 Sessions and goldens (Verifier)

**Inputs:** the oracle (playbook 25); `re/state.toml`.

## Recording a session

1. Write the input script `tests/sessions/<name>.keys` (one step per line: keys, text, waits in virtual ticks, named screenshots, named checkpoints).
2. `make golden SESSION=<name>`: runs the original twice in the oracle; both runs must be identical; writes digests, screenshots and the recording of the run's reads of the outside world (`replay.json.gz`) to `tests/sessions/golden/<name>/`.
3. Review the screenshots by eye (they are the only proof the script did what you meant), then commit the script and its golden together.

## Verifying a build of the game

- `make golden CHECK=1` re-runs the original and compares it with every golden and recording (part of `make check`).
- The rebuild from Pascal (Phase 5, SPEC 8.4) is compared the same way: byte-identical files need nothing more; otherwise the rebuilt program plays every golden in the oracle.
- A build whose code takes a different number of instructions (the C translation, Phase 7) is replayed from the golden's recording (`tools/oracle/replay.py`): every read of the outside world is answered from the recording, and checkpoints sit on read boundaries. On a mismatch the report names the read; bisect by swapping routines back to the original (`oracle.routines.replace`).

## Rules

- Masks in `re/state.toml` need a reason and human approval (AGENTS rule 2).
- A golden changes only when the original-side tooling changes; never to make a build of ours pass.

## Done when

The session passes in the oracle twice identically and its golden is committed.

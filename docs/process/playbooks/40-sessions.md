# 40 Sessions and goldens (Verifier)

**Inputs:** the oracle (playbook 25); `re/state.toml`.

## Recording a session

1. Write the input script `tests/sessions/<name>.keys` (one step per line: keys, text, waits in virtual ticks, named screenshots, named checkpoints).
2. `make golden SESSION=<name>`: runs the original twice in the oracle; both runs must be identical; writes digests and screenshots to `tests/sessions/golden/<name>/`.
3. Review the screenshots by eye (they are the only proof the script did what you meant), then commit the script and its golden together.

## Replaying

- `make sessions` replays every golden against the C build (hybrid while lifting, native from P5).
- On a mismatch: the report names the first checkpoint that differs and the state fields that differ. Bisect: rerun with fewer units in C (`HYBRID_C=...`) until one unit, then one routine, is responsible; hand that routine back to its lifter with the evidence.

## Rules

- Masks in `re/state.toml` need a reason and human approval (AGENTS rule 2).
- A golden changes only when the original-side tooling changes; never to make the C side pass.

## Done when

The session passes in the oracle twice identically and its golden is committed.

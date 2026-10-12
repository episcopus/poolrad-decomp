# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- review/res02 merge backed out (orch, 2026-10-11): the review is fine (passed, no must-fix), but after the merge `make check` fails in tests/unit/test_agent_tools.py::test_a_failed_review_goes_back_to_a_decompiler_not_to_a_reviewer (`assert 'res10' == 'res02'`). The test copies the live re/symbols.toml and assumes res02 is the first complete unit without a review; recording res02's review moves the review queue on to res10, so every review merge will hit this. Needs a tools fix (the test should build its own symbols.toml or take its unit from the data); the review-res02 hand-off stays open until then.

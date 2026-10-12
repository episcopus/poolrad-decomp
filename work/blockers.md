# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- tools-map merge reverted (orch, 2026-10-12, revert 5043e0c of merge 61d10f0): on main, its new tests fail (tests/unit/test_enumerate_routines.py, 4 tests: `enumerate_routines.main(--merge)` returns 1). The tool reports `size ovl34:003B Load8x8Bank: 255 -> 290` and `CONFLICT proven routine ovl34:003B changed size`: ovl34 (merged after the branch was cut) recorded the compiler's size 255 (the 35 bytes after it are the next routine's 59-byte literal pool, which TP places before Put8x8Symbol), and the scan wants 290. For op-map: merge main into task/tools-map, make the map keep the compiler-proven size of an L2 routine (pool bytes go to the next routine), make the tests pass against main's live symbols.toml, `make check`, hand off. The escalation escalate-ovl11-20261012040038 stays open; do not run `make map` on main until then.

- res08 merge reverted (orch, 2026-10-12, revert 2bf7810 of merge 6c14e33): unit/res08 (7e918b5, partial) fails `make check`: `DIFF res08_init 042B:00A4 our code changes length with the layout (912 vs 5 bytes)`, the matcher bug dec-2 escalated (escalate-general-20261012041843: variant B's init_region takes the padding procedure as the init of a unit with no interface routines). The merge commit 6c14e33 already resolves the conflicts with main (dseg/renames kept both sides; DS:547C has one name, GameDir, and ovl11's three uses point at it). After the matcher fix is merged, the orchestrator brings res08 back by reverting the revert (`git revert --no-edit 2bf7810`), then merges any newer res08 commits. The res08 hand-off stays open.


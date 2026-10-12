# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- tools-map merge reverted (orch, 2026-10-12, revert 5043e0c of merge 61d10f0): on main, its new tests fail (tests/unit/test_enumerate_routines.py, 4 tests: `enumerate_routines.main(--merge)` returns 1). The tool reports `size ovl34:003B Load8x8Bank: 255 -> 290` and `CONFLICT proven routine ovl34:003B changed size`: ovl34 (merged after the branch was cut) recorded the compiler's size 255 (the 35 bytes after it are the next routine's 59-byte literal pool, which TP places before Put8x8Symbol), and the scan wants 290. For op-map: merge main into task/tools-map, make the map keep the compiler-proven size of an L2 routine (pool bytes go to the next routine), make the tests pass against main's live symbols.toml, `make check`, hand off. The escalation escalate-ovl11-20261012040038 stays open; do not run `make map` on main until then.


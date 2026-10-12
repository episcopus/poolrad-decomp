# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- ovl26 merge aborted (orch, 2026-10-11): unit/ovl26 (56439d2) conflicts with ovl27, merged first, over DS:49D2. ovl27 declares `GameVars: ^TGameVars` (array[0..511] of Word, named with evidence in `re/dseg.toml`) and ovl26 declares `ds49D2: ^TGameState` (record, MapX at +$186 = word 195). `make rename APPLY=1` would also turn ovl26's `ds49D2` into `GameVars`. Also conflicting: `re/dseg.toml`, `re/renames.toml`, `re/symbols.toml`, the whitepaper, and `src/OVL27.PAS` (ovl26 still has ovl27's stubs; the decompiled routines win). For the ovl26 decompiler: merge `main` into `unit/ovl26`, give DS:49D2 one name and one type that both units compile and match against, run `make check`, and hand off again. The hand-off stays open until then.

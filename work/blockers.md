# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- Still open after ovl33's review fixes merged without it (operator decision on escalate-res06-20261012033157, 2026-10-11): the next decompiler who touches res06 or a caller of res06_fn_0DD3 (ovl33's ShowDebugTrace) should rename res06_fn_0DD3's stub parameters to Left, Top, Right, Bottom in src/RES06.PAS and update its re/symbols.toml `signature`, citing 0709:0E02 (fills third - first + 1 columns) and 0709:0DE3/0DEE (the second and fourth parameters are the top and bottom character rows). The third parameter is the inclusive right column, not a width.
- For the decompiler who takes ovl26's review fixes (operator, 2026-10-11): also remove the stale sentence "the level stays none only because the matcher reports no per routine row ..." from the `notes` of the three nested routines (WallDesc2FromCode, WallDesc3FromCode, WallDesc4FromCode: ovl26:00C7, 00FB, 012F) in re/symbols.toml; they are L2 now (make match proves them as NESTED).

- ovl34 merge reverted (orch, 2026-10-11, revert c72239a of merge 2f1186b): unit/ovl34 (0d77369, partial) fails `make check` on main: `DIFF Put8x8Symbol ovl34:015D far call: ours goes to 0AF8:13E2, the original to 0AF8:1685`, the System.Move misattribution in escalate-ovl34-20261012033554 (tools/re/tp_toolchain.py runtime_names). Waiting for the human's decision on the tool fix. When ovl34 is merged again, the orchestrator first reverts the revert (c72239a), then merges the branch. The ovl34 hand-off stays open.

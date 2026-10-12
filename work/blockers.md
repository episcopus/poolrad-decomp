# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- Waiting for the human (acting operator held it, 2026-10-12): res08 is a resident unit but its code shows it was compiled with O+ (dec-2, res08 hand-off note), which AGENTS.md's compiler-switch facts do not allow for resident units. A spec question; nothing to do until the human decides.

- ovl23 merge reverted (orch, 2026-10-12, revert 5cc6252 of merge 56a5c3d): unit/ovl23 (524930f, partial) fails `make check` because its three drafted routines do not match yet (`DIFF RecalcCharacter ovl23:0000`, `MinimizeLeast ovl23:0255`, `ComputeClassVal ovl23:0329`; the table-index computation dec-1 noted). `make check` matches every decompiled routine, so a partial hand-off can only carry drafts that match; put the others back as `{@stub}` (keep the draft in the notes or on the branch) before handing off. Acting operator, 2026-10-12: dec-1 (or whoever continues ovl23) turns RecalcCharacter, MinimizeLeast and ComputeClassVal back into `{@stub}`, keeping the drafts, then brings ovl23 back; `make handoff` now refuses a unit hand-off while `make match` shows differences (tools-matchguard). Merge 56a5c3d already resolves the conflicts with main (POOLVARS: main's 1024-word TGameVars kept, ovl23's TCharacter, TFlagEntry and class tables added). To bring ovl23 back: `git revert --no-edit 5cc6252`, then merge the newer ovl23 commits. The ovl23 hand-off stays open.

- escalate-ovl11-20261012040806 (runtime_entries, single unit vs --all): fix ready on task/tools-rtl2 (op-rtl, 1acdcc9), held for the human: it relaxes when a byte counts as present (AGENTS.md rule 2). Do not merge it, and do not rerun `make map` for it, until the human confirms.
- ovl11 review can be redone now (orch, 2026-10-12): on current main `make match UNIT=ovl11` matches StartGame alone (2 matched, 0 differ), so rev-4 or any reviewer can redo the ovl11 review. op-rtl reports that ovl02 run alone is still affected; on main at this commit `make match UNIT=ovl02` also shows 2 matched, 0 differ.

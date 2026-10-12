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

- ovl04 (acting operator, 2026-10-12, from escalate-ovl04-20261012054432 by rev-6): for the next ovl04 decompiler: mark the two 16-bit money QUIRKs in ChargeForCure exactly as rev-6 found in ovl06 (ovl06:03C7 LongInt result stored as Word; ovl06:0449 low word only).

- ovl11 and the whitepaper (acting operator, 2026-10-12, from escalate-general-20261012060445 by rev-5): for the next documentarian or ovl11 decompiler: rewrite the three references to the phantom `ovl11_fn_0435` (whitepaper 5.2.1 line 550; the src/POOLVARS.PAS comments on ds6F68 and ds6F69) to StartGame (ovl11_e1): ovl11:0435 lies inside StartGame (whitepaper 3.2.2).

- Waiting for the human (acting operator held it, 2026-10-12): escalate-res06-20261012110841 (dec-1). ShowPagedText (res06, 0709:0768) with its nested DrawTextRun (06A7) and SkipSpaces (0714) is decompiled (draft in dec-1's res06 worktree, notes in re/symbols.toml at 0768) but cannot match: the parent's pre-entry region (the nested code) is compared byte-exact, and it holds layout-dependent fields (GlyphCol DS addresses, a near call to res06_fn_01DF, a far call to Crt Delay). Proposal: compare proven-nested ranges instruction by instruction with the same address resolution as top-level routines. Conditions proposed by orch: (1) only ranges proven nested by the existing strict rule; (2) every current --all and single-unit verdict unchanged; (3) a test where a nested routine with a wrong global or wrong callee is caught. Held because it replaces a byte-exact comparison with one that accepts named address fields (AGENTS.md rule 2).


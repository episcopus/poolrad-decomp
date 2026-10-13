# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- Hand-off unit/ovl09 (partial, dec-1) is NOT merged: its merge (c892063) broke make check and was reverted (2b9557e). Cause: ScoreTarget (ovl09_fn_128D) reads Actor^.Pad9E[$A0], but TCharacter's Pad9E is only $9E..$9F and +$A0 is ByteA0 (ShortInt). The next merge has to revert that revert first (git will not re-apply a reverted merge), use ByteA0 (Byte(Actor^.ByteA0) if the ShortInt compare changes the code), carry the ovl09 renames, and prove make match. Do not add a second name for ds6814: main already has ds6814Sides. RaceRow, ds6825 and ds6E2F from that branch are not on main yet.

- res03 from 08AE:01D7 to the end of the segment (about 5.7 KB) is a TASM-assembled sound driver linked after the empty initialisation (`{$L SOUND.OBJ}`). It is not Pascal: the prologue is `mov bp,sp` encoded 8B EC, DS is loaded with the code segment, and the tune tables are raw data. Five Pascal routines match; the unit cannot be complete until the tail is reproduced. The matching route is an assembler in the toolchain and a `{$L SOUND.OBJ}` whose bytes match. Treating the tail as unmatched data would leave the rebuild short those bytes. Not started: it is a 5.7 KB assembly port, not a matcher rule.

- ovl20 is locked by haiku-dec (branch unit/ovl20). Whoever finishes it reconciles ovl20_e2 with the frame (`retf n` and the packet) and with ovl15's calls. The nested-routine comparison is no longer a hold: DisplaySpellEffects and AddDisplayLine can be matched with the pre-entry rule now in the matcher.

- Nested pre-entry comparison is in the matcher (proven-nested ranges only; make match --all still passes, 316 matched). Still to land, from drafts, not from a new rule: ShowPagedText (res06 0709:0768, nested DrawTextRun and SkipSpaces; draft was in dec-1's res06 worktree) and ovl25 ReadPromptChoice / ChooseFromList (drafts in commit 3c8dac5). ovl25_init is still not decompiled and has no blocked note, so the queue keeps offering ovl25 until that routine is matched or the note is written.

- A registered orchestrator can clear hand-offs (the name orch, or any agent whose registration has role orchestrator). review-ovl11 is already on main (merge 6b4729a) and its hand-off record was not cleared; haiku-orch can run handoff-done for it. Do not merge task/tools-rtl2 (1acdcc9): the masked body search replaced that rule.

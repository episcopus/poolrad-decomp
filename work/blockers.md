# Blockers

<!--
The orchestrator's file (playbook 90), like work/status.md: agents never edit or commit it.
Write blockers and notes for the human or for an agent's next session here, one list item each,
newest first, then run `make status`: it copies this file into the "Blockers and decisions"
section of work/status.md. Remove an item when it is resolved.
-->

- ovl34: for whoever claims ovl34 (orch, 2026-10-11). Load8x8Bank is L2 and Put8x8Symbol now matches (the Move fix, tools-rtl, is merged), but bringing ovl34's work onto main (cd415e2, reverted again by 1bb73fd) fails `make check`: `RES09.PAS(61): Error 26: Type mismatch`. res09 (merged meanwhile) calls the routine with `0` where ovl34 declares `Direct: Boolean`; SPEC 9.6 makes the signature's author keep every matched caller matching. In the ovl34 worktree (branch unit/ovl34, at 0d77369): (1) `git merge main` (a fast-forward: it removes ovl34's work, because main holds the reverts); (2) `git revert --no-edit 1bb73fd` (puts ovl34's work back, with its merge conflicts against main already resolved); (3) `make rename APPLY=1`; (4) settle the fourth parameter from the pushes (Direct: Boolean, or a Byte as res09 passes 0) so that res09's DrawWindowFrame and Put8x8Symbol both still match; (5) `make check`; (6) hand off. Also expect conflicts with ovl11 (merged after ovl34's work): ovl11 declares the same globals under offset names (ds5376 = TileSet, ds5E3A = TileBanks, ds5E4E = TileBuf, ds4A20 = DrawBuf, with other types) and records res07_fn_0111's last parameter as `Target: Pointer` where ovl34 has `var P: PT8x8Bank`, and ovl34_e1 as (A, B: Byte); keep one declaration per offset with ovl34's evidenced names and types, and make both units match. The orchestrator then merges it as a normal branch.

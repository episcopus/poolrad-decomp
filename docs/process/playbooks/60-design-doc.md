# 60 Update the design doc (Decompiler, Documentarian)

**Who writes what:**

- **The decompiler** of a unit writes what that unit taught, before handing it over (playbook 30 step 5): facts about its routines, globals, data and quirks, in the sections they belong to. It does not edit `docs/design/CHANGELOG.md`; it gives its changelog row in the hand-off (`CHANGELOG="<section> | <change> | <evidence>"`) and the orchestrator's `make handoff-done` adds it when merging.
- **The documentarian** writes the chapters across units: when most units of a subsystem are complete, the human starts a documentarian session (prompt in `docs/process/KICKOFF.md`) that turns the facts scattered through sections 3 and 5 into a chapter a reader can follow (what the subsystem does, its data, its algorithms, its quirks), and hands its branch over like any other (`make claim AGENT=<you> TASK=doc-<chapter>`: lock `doc-<chapter>`, branch `task/doc-<chapter>`).
- **The reviewer** checks that the decompiler did its part (playbook 70, checklist item 10).
- **The orchestrator** merges and adds changelog rows; it does not write the whitepaper.

## Steps

1. Find the right section of `docs/design/WHITEPAPER.md` (add a subsection if needed; keep the numbering stable).
2. Write for a reader who knows programming but not this game: what the subsystem does, the data it uses, the algorithm, notable quirks.
3. Tag every claim: **[V]** with evidence (address `ovl12:0A3C`, `make match UNIT=<id>`, test name, tool output), **[I]** with the reasoning, **[H]** for unproven leads (cite the source), **[?]** for open questions. A matched routine is [V] evidence of what the code does.
4. Promote earlier [H]/[I] claims you have now proven to [V]; correct wrong ones and say so in the changelog row.
5. Add diagrams as Mermaid or ASCII when they help (state machines, data layouts, call flows).
6. The changelog row (`<section> | <change> | <evidence>`) goes in your hand-off, not in the file.

## Done when

The section describes what the unit (or subsystem) does in plain language, every claim is tagged, and the hand-off carries the changelog row.

# 60 Update the design doc (Documentarian)

**Inputs:** verified findings from a unit, a format or the oracle.

## Steps

1. Find the right section of `docs/design/WHITEPAPER.md` (add a subsection if needed; keep the numbering stable).
2. Write for a reader who knows programming but not this game: what the subsystem does, the data it uses, the algorithm, notable quirks.
3. Tag every claim: **[V]** with evidence (address `ovl12:0A3C`, test name, tool output), **[I]** with the reasoning, **[H]** for unproven leads (cite the source), **[?]** for open questions.
4. Promote earlier [H]/[I] claims you have now proven to [V]; correct wrong ones and say so in the changelog.
5. Add diagrams as Mermaid or ASCII when they help (state machines, data layouts, call flows).
6. Add one line to `docs/design/CHANGELOG.md`: date, section, what changed, evidence.

## Done when

The section describes what the unit does in plain language, every claim is tagged, and the changelog has the entry.

# Playbooks

Step-by-step procedures. Each one is harness neutral: run it by telling your agent "follow docs/process/playbooks/<file> for <target>", or use the `pr-*` command wrappers in `.claude/commands`, `.cursor/commands` or `.opencode/commands`.

Every playbook has the same parts: **Inputs**, **Steps**, **Done when**, **Hand-off**. If a step needs a tool that does not exist yet, the playbook for the phase that builds it is named; do not improvise a replacement silently.

| File | Role | Phase |
|---|---|---|
| 00-bootstrap.md | anyone | P0 |
| 10-map-binary.md | Mapper | P1 |
| 20-data-formats.md | Mapper / Verifier | P2 |
| 25-oracle.md | Verifier | P2 |
| 30-lift-unit.md | Decompiler | P3 to P4 |
| 40-sessions.md | Verifier | P2 to P5 |
| 60-design-doc.md | Documentarian | all |
| 70-review.md | Reviewer | P4 to P6 |
| 90-orchestrate.md | Orchestrator | all |

Several agents at once: `../KICKOFF.md` (the roles to start and a prompt for each). What "readable" means, for decompilers and reviewers: `../READABILITY.md`.

# Review: <unit id>

decompiler: <the Agent: trailers of the unit's commits: git log --format='%(trailers:key=Agent,valueonly)' -- src/<ID>.PAS>
reviewer: <your agent id; never the decompiler>
date: <YYYY-MM-DD>
commit: <short hash of the commit you reviewed>

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] note <routine>: <finding>

## Verdict

<passed / not passed, in one sentence>

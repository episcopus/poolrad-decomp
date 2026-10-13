#!/bin/sh
# Claude Code PreToolUse hook (.claude/settings.json): when the session runs as a worker
# (POOLRAD_ROLE=decompiler or reviewer, set by tools/agent/worker.py), refuse edits to the matcher,
# the tests, the pinned inputs, the spec and the orchestrator's files. Without POOLRAD_ROLE it allows
# everything. Reads the tool call as JSON on stdin; exit 2 blocks the call with the message on stderr.
case "${POOLRAD_ROLE:-}" in
  decompiler|reviewer) ;;
  *) exit 0 ;;
esac
py=.venv/bin/python
[ -x "$py" ] || py=python3
exec "$py" tools/agent/hooks/guard_edit.py "$POOLRAD_ROLE"

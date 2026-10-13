#!/usr/bin/env python3
"""guard_edit.py: the Claude Code PreToolUse check behind tools/agent/hooks/guard-edit.sh.

Reads the tool call (JSON) on stdin and the worker role as its argument. A decompiler may edit src/,
re/, docs/design, docs/process, work/reviews and new probes under tools/re/tp_idioms/; never the
matcher, the tests, the pinned inputs, the spec or the orchestrator's files. A reviewer may not edit
src/ either. Exit 2 blocks the call with the reason on stderr.
"""
import json
import re
import sys

BLOCKED = ("tools/", "tests/", "poolrad/", "docs/spec/", "re/state.toml", "work/status.md",
           "work/blockers.md", "docs/design/CHANGELOG.md", "Makefile", ".claude/", ".git/")
PROBES = "tools/re/tp_idioms/"


def decide(role: str, path: str) -> str:
    rel = re.sub(r"^.*?/(poolrad-decomp|poolrad-worktrees/[^/]+)/", "", path)
    if rel.startswith(PROBES):
        return ""
    if any(rel.startswith(b) for b in BLOCKED) or (role == "reviewer" and rel.startswith("src/")):
        return "guard-edit: a %s session may not edit %s (AGENTS.md rules 2 and 3); escalate it" % (role, rel)
    return ""


def main() -> int:
    role = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        call = json.load(sys.stdin)
    except ValueError:
        return 0
    path = str((call.get("tool_input") or {}).get("file_path") or "")
    why = decide(role, path)
    if why:
        print(why, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

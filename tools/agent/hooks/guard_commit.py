#!/usr/bin/env python3
"""guard_commit.py: the pre-commit hook's check (tools/agent/hooks/pre-commit).

Refuses a commit on a unit/ or review/ branch when tools/agent/safety.py finds a change that role may
not make. Prints the findings; exit 1 blocks the commit. `make handoff` and `make integrate` run the
same check again, so bypassing the hook (`--no-verify`) only moves the refusal to the hand-off.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import safety  # noqa: E402


def main() -> int:
    try:
        findings = safety.branch_findings()
    except (ValueError, RuntimeError) as e:
        print("pre-commit: %s" % e, file=sys.stderr)
        return 1
    if findings:
        print("pre-commit: this branch may not change:", file=sys.stderr)
        for f in findings:
            print("  " + f, file=sys.stderr)
        print("pre-commit: escalate tooling or spec changes to a tooling task (AGENTS.md rule 2)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

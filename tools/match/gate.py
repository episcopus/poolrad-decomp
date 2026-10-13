#!/usr/bin/env python3
"""gate.py: the regression gate for a matcher change (AGENTS.md rule 2, SYSTEM-REVIEW 6.4).

  make match-gate

A change to tools/match/ or tools/re/tp_toolchain.py merges when this gate passes; a human reads the
diff afterwards. The gate proves that nothing the matcher accepted or rejected before changed hands:

  1. every routine at L2 in re/symbols.toml (of a unit with source, outside external objects) is still
     matched (or proven nested) by `match --all`, verdict for verdict;
  2. the same holds when each unit is matched alone (runtime identification must not depend on
     which other units are in the build: escalate-ovl11-20261012040806);
  3. the negative fixtures still fail: a wrong constant, global, set, callee, nested address or
     cross-unit address must be caught (tests/unit/test_match*.py).

Byte equality of code and literal pools is an invariant tested here, not a rule in prose.
"""
from __future__ import annotations

import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

NEGATIVE = ("tests/unit/test_match.py", "tests/unit/test_match_nested.py", "tests/unit/test_match_address.py",
            "tests/unit/test_match_alias.py", "tests/unit/test_match_init.py", "tests/unit/test_rtl_resolve.py")


def proven(results: list[match.Result]) -> set[str]:
    return {r.id for r in results if r.status in ("matched", "nested") and r.id}


def main(argv=None) -> int:
    units = match.units_with_source()
    registry = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
    expected: dict[str, set[str]] = {}
    for r in registry:
        if r.get("level") in ("L2", "L3") and r["unit"] in units and not r.get("external"):
            expected.setdefault(r["unit"], set()).add(r["id"])
    problems = []
    try:
        together = match.match_units(units)
    except match.MatchError as e:
        print("gate: match --all failed to build: %s" % e)
        return 1
    for u in units:
        if u == "main":
            continue
        got = proven(together[u][0])
        lost = sorted(expected.get(u, set()) - got)
        if lost:
            problems.append("%s: no longer matched by --all: %s" % (u, ", ".join(lost)))
        try:
            alone = proven(match.match_unit(u)[0])
        except match.MatchError as e:
            problems.append("%s alone: build failed: %s" % (u, e))
            continue
        lost = sorted(expected.get(u, set()) - alone)
        if lost:
            problems.append("%s: no longer matched when built alone: %s" % (u, ", ".join(lost)))
        extra = sorted(got ^ alone)
        if extra:
            problems.append("%s: --all and alone disagree on: %s" % (u, ", ".join(extra)))
    n = sum(len(v) for v in expected.values())
    print("gate: %d L2 routines in %d units checked together and alone: %s" % (
        n, len(expected), "all still matched" if not problems else "%d problems" % len(problems)))
    for p in problems:
        print("gate: " + p)
    r = subprocess.run([sys.executable, "-m", "pytest", "-q", *NEGATIVE], cwd=ROOT)
    if r.returncode:
        problems.append("the negative fixtures (tests/unit/test_match*.py) do not all pass")
    print("gate: %s" % ("PASS" if not problems else "FAIL"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

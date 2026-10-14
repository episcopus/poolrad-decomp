#!/usr/bin/env python3
"""review.py: record that a decompiled unit passed its independent review (SPEC 8.1, playbook 70).

  .venv/bin/python tools/agent/review.py UNIT
  make review-pass UNIT=<id>
  make review-pass UNIT=<id> CHECK=1      only check, write nothing

The review lives in work/reviews/<unit>.md (template: work/reviews/TEMPLATE.md). The review passes when:

  1. the file names a `decompiler:` and a `reviewer:`, and they differ (the reviewer of a unit is never
     its decompiler, SPEC 9.2);
  2. no finding is open with severity must-fix (`- [ ] must-fix ...`; a resolved one is `- [x] ...`);
  3. the unit matches completely now (`make match UNIT=<id>`: every routine L2, `unit: complete`); code
     linked from an external object file (`external_from` in re/units.toml, SPEC 8.3) counts as matched,
     exactly as `make match` counts it for completeness;
  4. the unit passes the checkable readability rules (`make readability UNIT=<id>`); the reviewer has
     judged the rest (docs/process/READABILITY.md).

Then every routine of the unit gets `review = "passed <date> by <reviewer>, <commit>"` in re/symbols.toml
(only tools write it, AGENTS rule 2). A unit is done when it is complete and reviewed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

REVIEWS = ROOT / "work/reviews"
# Results a reviewed unit may consist of: Pascal proven at L2, nested routines a matched routine proves,
# and routines inside an external object file, which the matcher keeps as the original's bytes.
ACCEPTED = ("matched", "nested", "external")


def field_of(text: str, key: str) -> str:
    m = re.search(r"^%s:\s*(.+?)\s*$" % key, text, re.I | re.M)
    return m.group(1) if m else ""


def open_must_fix(text: str) -> list[str]:
    return [l.strip() for l in text.splitlines() if re.match(r"\s*-\s*\[ \]\s*must-fix\b", l, re.I)]


def unit_agents(unit: str) -> set[str]:
    """Agents named by the `Agent:` trailer of the commits that touched the unit's source."""
    r = subprocess.run(["git", "log", "--format=%(trailers:key=Agent,valueonly)", "--", "src/%s.PAS" % unit.upper()],
                       cwd=ROOT, capture_output=True, text=True)
    return {l.strip().lower() for l in r.stdout.splitlines() if l.strip()}


def head_commit() -> str:
    r = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip() or "?"


def write_review(unit: str, stamp: str) -> int:
    path = ROOT / "re/symbols.toml"
    text = path.read_text()
    blocks = re.split(r"(?=^\[\[routine\]\]\n)", text, flags=re.M)
    n = 0
    for k, b in enumerate(blocks):
        if not re.search(r'^unit = "%s"$' % re.escape(unit), b, re.M):
            continue
        if re.search(r"^review = ", b, re.M):
            b = re.sub(r'^review = ".*"$', 'review = "%s"' % stamp, b, count=1, flags=re.M)
        else:
            b = re.sub(r'^(level = ".*")$', r'\1\nreview = "%s"' % stamp, b, count=1, flags=re.M)
        blocks[k] = b
        n += 1
    path.write_text("".join(blocks))
    return n


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit")
    ap.add_argument("--check", action="store_true", help="only check; write nothing")
    a = ap.parse_args(argv)
    unit = a.unit.lower()
    path = REVIEWS / ("%s.md" % unit)
    if not path.exists():
        print("review-pass: no %s (copy work/reviews/TEMPLATE.md)" % path.relative_to(ROOT))
        return 1
    text = path.read_text()
    dec, rev = field_of(text, "decompiler"), field_of(text, "reviewer")
    problems = []
    if not dec or not rev:
        problems.append("the review must name its `decompiler:` and its `reviewer:`")
    elif dec.lower() == rev.lower() or rev.lower() in unit_agents(unit):
        problems.append("the reviewer (%s) is the decompiler (or committed to src/%s.PAS): a review needs a "
                        "fresh agent session" % (rev, unit.upper()))
    problems += ["open finding: %s" % f for f in open_must_fix(text)]
    try:
        results, whole = match.match_unit(unit)
    except match.MatchError as e:
        problems.append("make match: %s" % e)
        results, whole = [], ""
    bad = [r for r in results if r.status not in ACCEPTED]
    if bad:
        problems.append("not every routine matches: %s" % ", ".join("%s (%s)" % (r.name, r.status) for r in bad[:8]))
    if results and not whole.startswith("unit: complete"):
        problems.append("the unit is not complete: %s" % (whole or "stubs remain"))
    import readability
    problems += ["readability: %s" % f for f in readability.check(unit)]
    if problems:
        print("review-pass %s: NOT PASSED" % unit)
        for p in problems:
            print("  - " + p)
        return 1
    stamp = "passed %s by %s, %s" % (dt.date.today().isoformat(), rev, head_commit())
    if a.check:
        print("review-pass %s: would record %r" % (unit, stamp))
        return 0
    n = write_review(unit, stamp)
    print("review-pass %s: recorded for %d routines (%s)" % (unit, n, stamp))
    return 0


if __name__ == "__main__":
    sys.exit(main())

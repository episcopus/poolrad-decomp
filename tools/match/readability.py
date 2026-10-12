#!/usr/bin/env python3
"""readability.py: the checkable part of a unit's readability (docs/process/READABILITY.md).

  make readability UNIT=<id>         (UNIT=main: src/POOL.PAS; no UNIT: every unit with decompiled routines)

For every decompiled (non-stub) routine of the unit, and for the unit itself:

  R1 unit comment     the comment after `unit X;` says what the unit is (not the skeleton's text; 8 words
                      or more)
  R2 routine name     not a provisional name (`resNN_fn_XXXX`, `ovlNN_eN`), unless its comment says
                      `Purpose unknown:` and what is known
  R3 routine comment  a comment right above the routine: 8 words or more, with its address (`0899:0059`,
                      `ovl33:0004`) for provenance
  R4 names            no parameter or local named by a single letter (I, J, K, N are fine for counters) or
                      a generic placeholder (Tmp, Temp, Dummy, Value1, Param2, ...)
  R5 globals          a `dsXXXX` global the routine uses has a comment on its declaration in POOLVARS.PAS
                      saying what is known about it (3 words or more)

Whether a name or comment is *good* is the reviewer's judgement (playbook 70); this tool only makes sure
nothing was skipped. Exit 1 with the findings, 0 when the unit is clean.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

PROVISIONAL = re.compile(r"^(res|ovl)\d\d_(fn_[0-9a-f]{4}|e\d+|init)$", re.I)
ADDRESS = re.compile(r"\b([0-9A-F]{4}|ovl\d\d):[0-9A-F]{4}\b", re.I)
GENERIC = re.compile(r"^([A-HL-MO-Z]|Tmp\d*|Temp\d*|Dummy\d*|Value\d+|Param\d+|Arg\d+|Var\d+|Local\d+|X\d+)$", re.I)
COUNTERS = {"i", "j", "k", "n"}
DS = re.compile(r"\bds[0-9A-F]{4}\b", re.I)


def words(text: str) -> int:
    return len(re.findall(r"[A-Za-z]{2,}", text))


def comment_above(lines: list[str], k: int) -> str:
    """The comments directly above line k (no blank line between), `{ ... }` or `(* ... *)`, possibly
    spanning several lines and stacked; a `{@...}` marker ends the search."""
    out, i = [], k - 1
    while i >= 0 and lines[i].strip().endswith(("}", "*)")):
        j = i
        while j >= 0 and not lines[j].lstrip().startswith(("{", "(*")):
            j -= 1
        if j < 0 or lines[j].lstrip().startswith("{@"):
            break
        out[:0] = lines[j:i + 1]
        i = j - 1
    return "\n".join(out)


def body_of(lines: list[str], k: int) -> tuple[list[str], int]:
    """From a routine header at line k to its closing column-1 `end;` (convention), and that line."""
    for j in range(k + 1, len(lines)):
        if re.match(r"end;", lines[j], re.I):
            return lines[k:j + 1], j
    return lines[k:], len(lines) - 1


def names_in(header: str, body: list[str]) -> list[str]:
    names = []
    m = re.search(r"\((.*)\)", header)
    if m:
        for group in m.group(1).split(";"):
            left = group.split(":")[0]
            left = re.sub(r"^\s*(var|const)\s+", "", left, flags=re.I)
            names += [n.strip() for n in left.split(",") if n.strip()]
    in_var = False
    for line in body[1:]:
        s = line.strip()
        if re.match(r"begin\b", s, re.I) or re.match(r"(procedure|function)\b", s, re.I):
            break
        if re.match(r"var\b", s, re.I):
            in_var, s = True, s[3:].strip()
        elif re.match(r"(const|type|label)\b", s, re.I):
            in_var = False
        if in_var and ":" in s:
            names += [n.strip() for n in s.split(":")[0].split(",") if n.strip()]
    return names


def poolvars_comments() -> dict[str, str]:
    p = match.SRC / "POOLVARS.PAS"
    out = {}
    if p.exists():
        for line in p.read_text().splitlines():
            m = re.match(r"\s*(ds[0-9A-F]{4})\s*:[^;]*;\s*(\{.*\})?", line, re.I)
            if m:
                out[m.group(1).lower()] = m.group(2) or ""
    return out


def check(unit: str) -> list[str]:
    name = match.PROGRAM if unit == "main" else unit.upper()
    path = match.SRC / (name + ".PAS")
    if not path.exists():
        return ["no source %s" % path.relative_to(ROOT)]
    text = path.read_text()
    lines = text.split("\n")
    findings = []
    m = re.search(r"^(unit|program)\s+\w+;\s*\n\s*(\{[^}]*\}|\(\*.*?\*\))", text, re.I | re.S | re.M)
    if not m or "Skeleton by" in m.group(2) or words(m.group(2)) < 8:
        findings.append("R1 unit: the comment after `%s` must say what the unit is (8 words or more)" % (
            "program POOL;" if unit == "main" else "unit %s;" % name))
    if unit == "main":
        return findings
    globals_ = poolvars_comments()
    impl = next((k for k, l in enumerate(lines) if re.match(r"\s*implementation\b", l, re.I)), 0)
    for k in range(impl, len(lines)):
        h = re.match(r"(procedure|function)\s+([A-Za-z_]\w*)", lines[k], re.I)
        if not h:
            continue
        routine = h.group(2)
        body, _end = body_of(lines, k)
        comment = comment_above(lines, k)
        if PROVISIONAL.match(routine) and "purpose unknown:" not in comment.lower():
            findings.append("R2 %s: provisional name (`make rename OLD=%s NEW=<Name> WHY=...`), or say "
                            "`Purpose unknown:` and what is known in its comment" % (routine, routine))
        if words(comment) < 8 or not ADDRESS.search(comment):
            findings.append("R3 %s: needs a comment right above it, 8 words or more, with its address" % routine)
        for n in names_in(lines[k], body):
            if (len(n) == 1 and n.lower() not in COUNTERS) or (len(n) > 1 and GENERIC.match(n)):
                findings.append("R4 %s: `%s` says nothing about its role" % (routine, n))
        for ds in sorted({d.lower() for d in DS.findall("\n".join(body))}):
            if words(globals_.get(ds, "")) < 3:
                findings.append("R5 %s: global %s needs a comment in POOLVARS.PAS saying what is known, or a "
                                "name (`make rename OLD=%s NEW=<Name> WHY=...`)" % (routine, ds, ds))
    return findings


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit", nargs="?")
    a = ap.parse_args(argv)
    units = [a.unit.lower()] if a.unit else match.units_with_source()
    bad = 0
    for u in units:
        f = check(u)
        bad += bool(f)
        for x in f:
            print("%s: %s" % (u, x))
        print("readability %s: %s" % (u, "clean" if not f else "%d finding(s)" % len(f)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

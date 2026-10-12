#!/usr/bin/env python3
"""rename.py: give a routine or a global its real name, everywhere at once (docs/process/READABILITY.md).

  make rename OLD=<name> NEW=<Name> WHY="<evidence>"
  make rename APPLY=1                       re-apply every recorded rename to src/ (after a merge)

The matcher finds routines by their name in re/symbols.toml and globals by their name in re/dseg.toml (or
`dsXXXX`), so a name lives in the registry and in every source file that uses it. This tool changes both
in one step:

  routine   re/symbols.toml `name` (and `signature`), every use in src/*.PAS and the whitepaper
  global    re/dseg.toml (an entry is added for a `dsXXXX` global, with the evidence), every use in src/
            and the whitepaper

String literals are left alone; comments follow the rename. Every rename is recorded in re/renames.toml
(old, new, kind, evidence, date), so `make rename APPLY=1` can fix a branch that still used an old name
when it was merged. Parameters, locals, types and constants need no tool: they live in one unit's source.
Run `make match` (or `make check`) afterwards: a rename never changes the code, so everything that matched
still matches.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

SYMBOLS = ROOT / "re/symbols.toml"
DSEG = ROOT / "re/dseg.toml"
LOG = ROOT / "re/renames.toml"
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,62}$")
RESERVED = set("""and array asm begin case const constructor destructor div do downto else end exports file for
function goto if implementation in inherited inline interface label library mod nil not object of or packed
procedure program record repeat set shl shr string then to type unit until uses var while with xor absolute
assembler external far forward interrupt near private public virtual""".split())


# What a rename must not touch. Pascal: a 'string literal' never spans a line, and an apostrophe inside a
# { comment } or (* comment *) starts nothing (comments follow the rename, so they are matched only to be
# passed through). Markdown: a quoted 'name' is a literal only when its quotes stand apart from words, so
# the apostrophes of prose ("the player's", "games'") never pair with a quote further on.
PAS_TOKENS = re.compile(r"\{[^}]*\}|\(\*.*?\*\)|'(?:[^'\n]|'')*'", re.S)
DOC_LITERALS = re.compile(r"(?<![A-Za-z0-9_])'(?:[^'\n]|'')*'(?![A-Za-z0-9_])")


def replace_word(text: str, old: str, new: str, pascal: bool = True) -> tuple[str, int]:
    """Replace the identifier `old` (any case) by `new`, outside string literals (comments follow it)."""
    out, n, pos = [], 0, 0
    word = re.compile(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(old), re.I)
    for m in (PAS_TOKENS if pascal else DOC_LITERALS).finditer(text):
        if m.group(0)[0] != "'":                                  # a comment: renamed like code
            continue
        chunk, k = word.subn(new, text[pos:m.start()])
        out += [chunk, m.group(0)]
        n += k
        pos = m.end()
    chunk, k = word.subn(new, text[pos:])
    out.append(chunk)
    return "".join(out), n + k


def left_behind(text: str, old: str) -> list[int]:
    """Line numbers where `old` still appears after a rename (inside a literal, so on purpose or not)."""
    word = re.compile(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(old), re.I)
    return [i for i, line in enumerate(text.splitlines(), 1) if word.search(line)]


def in_sources(name: str) -> int:
    return sum(replace_word(p.read_text(), name, name)[1] for p in match.SRC.glob("*.PAS"))


DOCS = (ROOT / "docs/design/WHITEPAPER.md",)


def rename_sources(old: str, new: str) -> int:
    """src/*.PAS and the whitepaper (addresses stay; only the name changes). Warns about every use of the
    old name left inside a literal, so a half-applied rename cannot pass unnoticed."""
    total = 0
    for p in sorted(match.SRC.glob("*.PAS")) + [d for d in DOCS if d.exists()]:
        text, n = replace_word(p.read_text(), old, new, pascal=p.suffix.upper() == ".PAS")
        if n:
            p.write_text(text)
            total += n
        for line in left_behind(text, old):
            print("rename: warning: %s:%d still says %s (inside a quoted string; check it)"
                  % (p.relative_to(ROOT) if p.is_relative_to(ROOT) else p, line, old))
    return total


def toml_text(why: str) -> str:
    """Evidence as the inside of a TOML basic string: backslashes escaped, double quotes made single."""
    return " ".join(why.split()).replace("\\", "\\\\").replace('"', "'")


def log(old: str, new: str, kind: str, why: str) -> None:
    entry = '[[rename]]\nold = "%s"\nnew = "%s"\nkind = "%s"\nwhy = "%s"\ndate = "%s"\n\n' % (
        old, new, kind, toml_text(why), dt.date.today().isoformat())
    if not LOG.exists():
        LOG.write_text("# Every rename of a routine or a global (tools/match/rename.py). `make rename APPLY=1`\n"
                       "# replaces old names still used in src/ by the new ones (after a merge).\n\n")
    with LOG.open("a") as f:
        f.write(entry)


def taken(name: str) -> str | None:
    if name.lower() in RESERVED:
        return "a reserved word"
    routines = tomllib.loads(SYMBOLS.read_text())["routine"]
    if any(r["name"].lower() == name.lower() for r in routines):
        return "the name of a routine"
    if any(g["name"].lower() == name.lower() for g in tomllib.loads(DSEG.read_text()).get("global", [])):
        return "the name of a global"
    if in_sources(name):
        return "already used in src/"
    return None


def rename_routine(old: str, new: str, why: str) -> str:
    text = SYMBOLS.read_text()
    block = re.compile(r'(\[\[routine\]\]\nid = "[^"]*"\n(?:(?!\[\[routine\]\]).)*?\nname = )"%s"' % re.escape(old),
                       re.S | re.I)
    text, k = block.subn(lambda m: m.group(1) + '"%s"' % new, text, count=1)
    if not k:
        raise SystemExit("rename: no routine %s in re/symbols.toml" % old)
    text, _ = re.subn(r'(signature = "(?:procedure|function) )%s\b' % re.escape(old), r"\g<1>%s" % new, text, flags=re.I)
    text, _ = re.subn(r'(name = "%s"(?:(?!\[\[routine\]\]).)*?\nnotes = ")' % re.escape(new),
                      lambda m: m.group(1) + "renamed from %s (%s); " % (old, toml_text(why)), text,
                      count=1, flags=re.S)
    SYMBOLS.write_text(text)
    return "routine"


def rename_global(old: str, new: str, why: str) -> str:
    text = DSEG.read_text()
    m = match.DS_RE.match(old)
    named = re.search(r'^name = "%s"$' % re.escape(old), text, re.M | re.I)
    if named:
        text = text[:named.start()] + 'name = "%s"' % new + text[named.end():]
    elif m:
        text = text.rstrip("\n") + '\n\n[[global]]\noffset = 0x%s\nname = "%s"\nevidence = "%s"\n' % (
            m.group(1).upper(), new, toml_text(why))
    else:
        raise SystemExit("rename: %s is neither a routine of re/symbols.toml nor a global (re/dseg.toml or dsXXXX)" % old)
    DSEG.write_text(text)
    return "global"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("old", nargs="?")
    ap.add_argument("new", nargs="?")
    ap.add_argument("--why", default=os.environ.get("RENAME_WHY", ""),
                    help="the evidence (make passes WHY= unexpanded through RENAME_WHY)")
    ap.add_argument("--apply", action="store_true", help="re-apply every rename of re/renames.toml to src/")
    a = ap.parse_args(argv)
    if a.apply:
        n = 0
        for r in tomllib.loads(LOG.read_text()).get("rename", []) if LOG.exists() else []:
            n += rename_sources(r["old"], r["new"])
        print("rename: %d stale use(s) of old names replaced in src/" % n)
        return 0
    if not (a.old and a.new):
        ap.error("give OLD and NEW (or --apply)")
    if not IDENT.match(a.new):
        print("rename: %r is not a Turbo Pascal identifier (letters, digits, _; at most 63)" % a.new)
        return 2
    if not a.why.strip():
        print("rename: give the evidence for the new name (WHY=...)")
        return 2
    clash = taken(a.new)
    if clash and a.new.lower() != a.old.lower():
        print("rename: %s is %s" % (a.new, clash))
        return 2
    routines = tomllib.loads(SYMBOLS.read_text())["routine"]
    kind = (rename_routine if any(r["name"].lower() == a.old.lower() for r in routines) else rename_global)(
        a.old, a.new, a.why)
    n = rename_sources(a.old, a.new)
    log(a.old, a.new, kind, a.why)
    print("rename: %s %s -> %s (%d use(s) in src/); run `make match` to confirm" % (kind, a.old, a.new, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())

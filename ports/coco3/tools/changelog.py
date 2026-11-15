#!/usr/bin/env python3
"""changelog.py: the CoCo 3 port's version and changelog (docs/VERSIONING.md): ports/coco3/VERSION and ports/coco3/CHANGELOG.md.

  changelog.py check              the changelog follows docs/VERSIONING.md section 3 and VERSION is its newest release (exit 1 if not)
  changelog.py next               the version the next release would make, and why (nothing is written)
  changelog.py release [--date D] turn Unreleased into the next version: the level from its sections, VERSION written, the release dated (today
                                  by default); with nothing under Unreleased, says so (and warns when commits touched the build since) and keeps it
  changelog.py json OUT           the changelog as data for the site (build/dist/changelog.json)
  changelog.py version            the version in VERSION

make dist runs check and release before it builds (the Makefile's dist target), so a distribution always carries a dated version."""
import argparse
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

PORT = Path(__file__).resolve().parent.parent
REPO = PORT.parent.parent
CHANGELOG = PORT / "CHANGELOG.md"
VERSION = PORT / "VERSION"

# docs/VERSIONING.md section 3: the sections of a release, in the order they are written, and the level each one asks for
SECTIONS = {"Breaking": "major", "Added": "minor", "Changed": "minor", "Fixed": "patch", "Internal": "patch"}
LEVELS = ["patch", "minor", "major"]
UNRELEASED = "Unreleased"
RELEASE_RE = re.compile(r"^## (\d+)\.(\d+)\.(\d+) - (\d{4}-\d{2}-\d{2})$")
DASHES = "\u2012\u2013\u2014\u2015"     # figure, en, em and horizontal bar: the repository writes none (AGENTS.md rule 10)

# what reaches a build folder of make dist (docs/VERSIONING.md section 4 rule 1): the translated Pascal and its fixes, the translator, the port's
# sources, patches, tools, data and build files. Commits here after a release without a changelog entry are worth a warning, no more.
BUILD_PATHS = ["src", "fixes", "tools/c/pas2c.py", "ports/coco3/src", "ports/coco3/patches", "ports/coco3/tools", "ports/coco3/scripts",
               "ports/coco3/data", "ports/coco3/cfg", "ports/coco3/Makefile", "ports/coco3/placement.toml", "ports/coco3/placement-coco.toml"]


class ChangelogError(Exception):
    pass


def parse(text):
    """{"head": [lines before Unreleased], "unreleased": {section: [item]}, "releases": [{"version", "date", "note", "sections"}]}; an item is the
    text of one "- " line with its indented continuation lines joined by spaces. Raises ChangelogError on anything section 3 does not allow."""
    head, blocks, cur = [], [], None
    for n, line in enumerate(text.splitlines(), 1):
        for ch in DASHES:
            if ch in line:
                raise ChangelogError("line %d: a dash U+%04X (write a comma, colon or parentheses)" % (n, ord(ch)))
        if line.startswith("## "):
            if line == "## " + UNRELEASED:
                if blocks:
                    raise ChangelogError("line %d: Unreleased must come first, once" % n)
                cur = {"version": None, "line": n, "note": [], "sections": {}, "section": None}
            else:
                m = RELEASE_RE.match(line)
                if not m:
                    raise ChangelogError("line %d: a release heading is '## MAJOR.MINOR.PATCH - YYYY-MM-DD': %r" % (n, line))
                if not blocks:
                    raise ChangelogError("line %d: '## Unreleased' must come before the first release" % n)
                try:
                    datetime.date.fromisoformat(m.group(4))
                except ValueError:
                    raise ChangelogError("line %d: not a date: %s" % (n, m.group(4)))
                cur = {"version": tuple(int(m.group(i)) for i in (1, 2, 3)), "date": m.group(4), "line": n, "note": [], "sections": {},
                       "section": None}
            blocks.append(cur)
        elif cur is None:
            head.append(line)
        elif line.startswith("### "):
            name = line[4:].strip()
            if name not in SECTIONS:
                raise ChangelogError("line %d: unknown section %r (one of %s)" % (n, name, ", ".join(SECTIONS)))
            if name in cur["sections"]:
                raise ChangelogError("line %d: section %s twice" % (n, name))
            cur["sections"][name] = []
            cur["section"] = name
        elif line.startswith("- "):
            if cur["section"] is None:
                raise ChangelogError("line %d: an entry outside a ### section" % n)
            cur["sections"][cur["section"]].append(line[2:].strip())
        elif line.startswith("  ") and line.strip():
            if cur["section"] is None or not cur["sections"][cur["section"]]:
                raise ChangelogError("line %d: an indented line that continues no entry" % n)
            items = cur["sections"][cur["section"]]
            items[-1] += " " + line.strip()
        elif line.strip():
            if cur["section"] is not None:
                raise ChangelogError("line %d: text after a section's entries (an entry starts with '- ')" % n)
            cur["note"].append(line.strip())
    if not blocks:
        raise ChangelogError("no '## Unreleased' section")
    for b in blocks:
        for name, items in b["sections"].items():
            if not items:
                raise ChangelogError("line %d: section %s has no entries" % (b["line"], name))
    releases = blocks[1:]
    for b in releases:
        if not b["sections"]:
            raise ChangelogError("line %d: release %s has no entries" % (b["line"], vstr(b["version"])))
    for a, b in zip(releases, releases[1:]):
        if not a["version"] > b["version"]:
            raise ChangelogError("line %d: %s is not newer than %s below it" % (a["line"], vstr(a["version"]), vstr(b["version"])))
        if a["date"] < b["date"]:
            raise ChangelogError("line %d: %s is dated before %s" % (a["line"], vstr(a["version"]), vstr(b["version"])))
        if a["version"] != bump(b["version"], level_between(b["version"], a["version"])):
            raise ChangelogError("line %d: %s does not follow %s by one step" % (a["line"], vstr(a["version"]), vstr(b["version"])))
    for a, b in zip(releases, releases[1:]):
        want = level_of(a["sections"])
        got = level_between(b["version"], a["version"])
        if want != got:
            raise ChangelogError("line %d: %s is a %s release but its sections (%s) ask for %s" %
                                 (a["line"], vstr(a["version"]), got, ", ".join(a["sections"]), want))
    return {"head": head, "unreleased": blocks[0]["sections"],
            "releases": [{"version": b["version"], "date": b["date"], "note": " ".join(b["note"]),
                          "sections": b["sections"]} for b in releases]}


def vstr(v):
    return "%d.%d.%d" % v


def level_of(sections):
    """the highest level the sections ask for (section 2), None for no entries"""
    levels = [SECTIONS[s] for s, items in sections.items() if items]
    return max(levels, key=LEVELS.index) if levels else None


def level_between(old, new):
    return "major" if new[0] != old[0] else "minor" if new[1] != old[1] else "patch"


def bump(v, level):
    if level == "major":
        return (v[0] + 1, 0, 0)
    if level == "minor":
        return (v[0], v[1] + 1, 0)
    return (v[0], v[1], v[2] + 1)


def load():
    return parse(CHANGELOG.read_text())


def read_version():
    text = VERSION.read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", text):
        raise ChangelogError("VERSION is %r, not MAJOR.MINOR.PATCH" % text)
    return tuple(int(x) for x in text.split("."))


def check():
    log = load()
    if not log["releases"]:
        raise ChangelogError("no release yet")
    v = read_version()
    if v != log["releases"][0]["version"]:
        raise ChangelogError("VERSION says %s, the changelog's newest release is %s" % (vstr(v), vstr(log["releases"][0]["version"])))
    return log


def render_section(name, items):
    out = ["### " + name]
    for item in items:
        out.extend(wrap("- " + item, "  "))
    return out


def wrap(text, indent, width=150):
    """the changelog's lines are at most about 150 characters, continuation lines indented"""
    words, lines, cur = text.split(" "), [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = indent + w
        else:
            cur = cur + " " + w if cur else w
    lines.append(cur)
    return lines


def release(date):
    log = check()
    level = level_of(log["unreleased"])
    current = log["releases"][0]["version"]
    if level is None:
        print("changelog: nothing under Unreleased: the build stays %s" % vstr(current))
        warn_unrecorded(current)
        return current
    new = bump(current, level)
    if date < log["releases"][0]["date"]:
        raise ChangelogError("the date %s is before the last release's (%s)" % (date, log["releases"][0]["date"]))
    text = CHANGELOG.read_text()
    lines = text.splitlines()
    start = lines.index("## " + UNRELEASED)
    end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("## "))
    body = ["## " + UNRELEASED, "", "## %s - %s" % (vstr(new), date), ""]
    for name in SECTIONS:
        if log["unreleased"].get(name):
            body.extend(render_section(name, log["unreleased"][name]))
            body.append("")
    new_text = "\n".join(lines[:start] + body + lines[end:]) + "\n"
    parsed = parse(new_text)
    assert parsed["releases"][0]["version"] == new and not parsed["unreleased"]
    CHANGELOG.write_text(new_text)
    VERSION.write_text(vstr(new) + "\n")
    print("changelog: released %s (%s: %s), VERSION written; commit it as 'coco3: release %s'" %
          (vstr(new), level, ", ".join(s for s in SECTIONS if log["unreleased"].get(s)), vstr(new)))
    return new


def git(*args):
    r = subprocess.run(["git", "-C", str(REPO)] + list(args), capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def warn_unrecorded(current):
    """section 4 rule 2: commits that touched what reaches a build since VERSION last changed, with nothing under Unreleased"""
    if not VERSION.resolve().is_relative_to(REPO):
        return                                   # a VERSION outside the repository (the tests): no history to look at
    if git("status", "--porcelain", "--", str(VERSION.relative_to(REPO))):
        return                                   # the release itself is not committed yet: nothing can have come after it
    base = (git("log", "-1", "--format=%H", "--", str(VERSION.relative_to(REPO))) or "").strip()
    if not base:
        return
    commits = (git("log", "--format=%h %ad %s", "--date=short", base + "..HEAD", "--", *BUILD_PATHS) or "").splitlines()
    dirty = (git("status", "--porcelain", "--", *BUILD_PATHS) or "").splitlines()
    if commits or dirty:
        print("changelog: warning: %d commits and %d uncommitted files touched the build since %s was released, and Unreleased is empty. "
              "If a player would notice any of them, add the entry first (docs/VERSIONING.md):" % (len(commits), len(dirty), vstr(current)))
        for c in commits[:20]:
            print("  " + c)
        if len(commits) > 20:
            print("  ... and %d more" % (len(commits) - 20))
        for d in dirty[:10]:
            print("  (uncommitted) " + d.strip())


def as_data(log):
    return {"version": vstr(log["releases"][0]["version"]),
            "date": log["releases"][0]["date"],
            "releases": [{"version": vstr(r["version"]), "date": r["date"], "level": None, "note": r["note"],
                          "sections": [{"name": s, "items": r["sections"][s]} for s in SECTIONS if s in r["sections"]]}
                         for r in log["releases"]]}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    sub.add_parser("next")
    sub.add_parser("version")
    r = sub.add_parser("release")
    r.add_argument("--date", default=datetime.date.today().isoformat())
    j = sub.add_parser("json")
    j.add_argument("out")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "check":
            log = check()
            print("changelog: ok, version %s, %d releases, %d entries waiting under Unreleased" %
                  (vstr(log["releases"][0]["version"]), len(log["releases"]), sum(len(v) for v in log["unreleased"].values())))
        elif a.cmd == "next":
            log = check()
            current = log["releases"][0]["version"]
            level = level_of(log["unreleased"])
            if level is None:
                print("%s (nothing under Unreleased: make dist builds the same version)" % vstr(current))
                warn_unrecorded(current)
            else:
                why = ", ".join("%s %d (%s)" % (s, len(log["unreleased"][s]), SECTIONS[s]) for s in SECTIONS if log["unreleased"].get(s))
                print("%s (%s release from %s: %s)" % (vstr(bump(current, level)), level, vstr(current), why))
        elif a.cmd == "version":
            print(vstr(read_version()))
        elif a.cmd == "release":
            datetime.date.fromisoformat(a.date)
            release(a.date)
        elif a.cmd == "json":
            log = check()
            data = as_data(log)
            for prev, cur in zip(log["releases"][1:], data["releases"]):
                cur["level"] = level_between(prev["version"], tuple(int(x) for x in cur["version"].split(".")))
            data["releases"][-1]["level"] = "first"
            Path(a.out).write_text(json.dumps(data, indent=2) + "\n")
            print("changelog: %s (%s)" % (a.out, data["version"]))
    except ChangelogError as e:
        print("changelog: %s: %s" % (CHANGELOG.relative_to(REPO), e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

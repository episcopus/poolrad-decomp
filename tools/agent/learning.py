#!/usr/bin/env python3
"""Retrieve small, evidence-linked learning briefs before spending model time on probes."""
from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common


def committed(root: Path, path: str) -> str | None:
    """Read accepted main, not its possibly half-resolved working-tree files."""
    try:
        names = common.git("ls-tree", "--name-only", "main", "--", path, cwd=root)
        return common.git("show", "main:" + path, cwd=root) if names else None
    except RuntimeError:
        return None                          # standalone fixtures/docs can still use local evidence


def lessons(root: Path | None = None) -> list[dict]:
    root = root or common.ROOT
    out, ids = [], set()
    sources = []
    try:
        names = common.git("ls-tree", "-r", "--name-only", "main", "--", "re/learnings", cwd=root).splitlines()
        sources += [(name, committed(root, name), True) for name in names if name.endswith(".toml")]
    except RuntimeError:
        pass
    sources += [(str(path.relative_to(root)), path.read_text(), False) for path in sorted((root / "re/learnings").glob("*.toml"))]
    for path, content, accepted in sources:
        local_ids = set()
        for row in tomllib.loads(content or "").get("lesson", []):
            if row.get("id") in local_ids:
                raise ValueError("%s: duplicate lesson id" % path)
            local_ids.add(row.get("id"))
            if row.get("id") in ids and not accepted:
                continue                      # accepted main wins over a stale worktree's copy
            if not row.get("id") or row["id"] in ids or row.get("confidence") not in ("V", "I", "H", "?"):
                raise ValueError("%s: lesson needs a unique id and V/I/H/? confidence" % path)
            for key in ("title", "lesson", "units", "tags", "evidence"):
                if not row.get(key):
                    raise ValueError("%s: missing %s" % (row["id"], key))
            if not isinstance(row["title"], str) or len(row["title"]) > 160 or not isinstance(row["lesson"], str) or len(row["lesson"]) > 1500:
                raise ValueError("%s: keep lessons small and searchable, not full transcripts" % row["id"])
            for key in ("units", "tags", "evidence"):
                if not isinstance(row[key], list) or len(row[key]) > 50 or any(not isinstance(v, str) for v in row[key]):
                    raise ValueError("%s: %s must be a bounded string list" % (row["id"], key))
            for pointer in row["evidence"]:
                rel = pointer.split("#", 1)[0]
                p = (root / rel).resolve()
                if not p.is_relative_to(root.resolve()) or (not p.is_file() and committed(root, rel) is None):
                    raise ValueError("%s: missing or outside-repository evidence %s" % (row["id"], pointer))
                if rel.startswith("build/"):
                    raise ValueError("%s: durable lessons must not depend on ignored build logs" % row["id"])
            out.append(row)
            ids.add(row["id"])
    return out


def search(unit: str, query: str = "", root: Path | None = None, limit: int = 8) -> list[dict]:
    words = set(re.findall(r"[a-z0-9_-]+", query.lower()))
    scored = []
    for row in lessons(root):
        local = unit in row["units"]
        general = "*" in row["units"]
        text = " ".join([row["title"], row["lesson"], *row["tags"]]).lower()
        hits = sum(word in text for word in words)
        if local or (not words and general) or hits:
            scored.append((10 * local + 2 * hits + general, row["id"], row))
    return [row for _score, _id, row in sorted(scored, key=lambda r: (-r[0], r[1]))[:limit]]


def whitepaper_sections(unit: str, root: Path | None = None) -> list[dict]:
    root = root or common.ROOT
    path = root / "docs/design/WHITEPAPER.md"
    accepted = committed(root, "docs/design/WHITEPAPER.md")
    if not path.exists() and accepted is None:
        return []
    lines = (accepted if accepted is not None else path.read_text()).splitlines()
    headers = [(i, line) for i, line in enumerate(lines) if re.match(r"^#{2,6} ", line)]
    sections = []
    for k, (start, title) in enumerate(headers):
        end = headers[k + 1][0] if k + 1 < len(headers) else len(lines)
        text = "\n".join(lines[start:end])
        count = len(re.findall(r"\b%s\b" % re.escape(unit), text, re.I))
        if re.match(r"^#{2,6} 3\.6\b", title) or (count and re.match(r"^#{2,6} (4|5)\.", title)):
            sections.append(dict(title=title.lstrip("# "), line=start + 1, end=end,
                                 excerpt=text[:2200], score=count + (5 if unit in title.lower() else 0), accepted=accepted is not None))
    return sorted(sections, key=lambda r: (-r["score"], r["line"]))[:3]


def brief(unit: str, query: str = "", root: Path | None = None) -> list[str]:
    root = root or common.ROOT
    lines = ["## Read first: prior learning and known blockers", "",
             "These are retrieval leads, not approvals or new matcher verdicts. Read the linked evidence before reusing an idiom.", "",
             "- Canonical design: accepted main's `docs/design/WHITEPAPER.md` (especially 3.6 and the subsystem sections below).",
             "- Prior art/licences: `docs/reference/prior-art.md`. Restricted code is read-only; other builds' addresses never apply.",
             "- Reusable compiler probes: `tools/re/tp_idioms/`; `make learn UNIT=%s QUERY=<symptom>` before creating another probe." % unit,
             "- Current decisions: accepted main's `work/blockers.md`. A known human-held limitation is not solved by spending more model tokens.", ""]
    for row in search(unit, query, root):
        lines += ["### [%s] %s (%s)" % (row["confidence"], row["title"], row["id"]),
                  row["lesson"], "Evidence: " + ", ".join("`%s`" % p for p in row["evidence"]), ""]
    for section in whitepaper_sections(unit, root):
        lines += ["### Whitepaper: %s" % section["title"],
                  "Read `docs/design/WHITEPAPER.md:%d` through line %d%s. Preview (may be truncated):" % (
                      section["line"], section["end"],
                      " from `git show main:docs/design/WHITEPAPER.md` (local worktree may be stale)" if section["accepted"] else ""),
                  section["excerpt"], ""]
    return lines


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--unit", default="")
    ap.add_argument("--query", default="")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    try:
        if a.check:
            print("learning: %d durable evidence-linked lessons" % len(lessons()))
        else:
            print("\n".join(brief(a.unit, a.query)))
        return 0
    except (ValueError, OSError) as e:
        print("learning: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

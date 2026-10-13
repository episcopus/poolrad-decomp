#!/usr/bin/env python3
"""Non-destructive integration checks. Never merge, reset, stash or rewrite a registry.

  make safety-check                   branch ownership and current merge preservation
  make merge-check                    check HEAD's two-parent merge
  make merge-check STAGED=1            check a resolved merge before committing
  make merge-check COMMIT=<sha>        audit a historical merge

Intentional deletions made on an input branch are distinguished from entries lost while resolving a
merge. Ambiguous values still need evidence and make check; this is not a TOML auto-merger.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common

TABLES = {"re/symbols.toml": ("routine", "id"), "re/dseg.toml": ("global", "name"),
          "re/renames.toml": ("rename", "old")}
MISSING = object()


def blob(revision: str, path: str) -> str:
    present = common.git("ls-tree", "--name-only", revision, "--", path) if revision else \
        common.git("ls-files", "--stage", "--", path)
    if not present:
        return ""
    return common.git("show", "%s:%s" % (revision, path))


def entries(text: str, table: str, key: str) -> dict:
    out = {}
    for row in tomllib.loads(text).get(table, []):
        if key not in row or row[key] in out:
            raise ValueError("%s has a missing or duplicate %s" % (table, key))
        out[row[key]] = row
    return out


def retained_keys(base: dict, left: dict, right: dict) -> set:
    """Keep additions from either side and everything both sides kept from the base."""
    return (set(left) - set(base)) | (set(right) - set(base)) | (set(left) & set(right))


def table_findings(path: str, base: dict, left: dict, right: dict, merged: dict) -> list[str]:
    out = []
    for key in sorted(retained_keys(base, left, right), key=str):
        if key not in merged:
            out.append("%s: merge lost entry %s" % (path, key))
            continue
        old, a, b, result = base.get(key, {}), left.get(key, {}), right.get(key, {}), merged[key]
        for field in a.keys() | b.keys():
            av, bv, ov = a.get(field, MISSING), b.get(field, MISSING), old.get(field, MISSING)
            if field not in result:
                out.append("%s: merge lost %s.%s" % (path, key, field))
                continue
            # A non-conflicting change must survive, not silently revert to the merge base.
            expected = av if bv is MISSING or av == bv or bv == ov else \
                (bv if av is MISSING or av == ov else MISSING)
            if expected is not MISSING and result[field] != expected:
                out.append("%s: merge discarded non-conflicting change to %s.%s" % (path, key, field))
            if isinstance(av, list) and isinstance(bv, list):
                original = ov if isinstance(ov, list) else []
                required = [v for v in av + bv if v not in original or (v in av and v in bv)]
                if not isinstance(result[field], list) or any(v not in result[field] for v in required):
                    out.append("%s: merge lost list evidence in %s.%s" % (path, key, field))
    return out


def declarations(text: str) -> dict[str, str]:
    # Top-level POOLVARS declarations use two spaces; record fields use deeper indentation.
    text = re.sub(r"\{.*?\}|\(\*.*?\*\)", "", text, flags=re.S)
    return {m[1].lower(): " ".join(m[2].split()) for m in
            re.finditer(r"^  ([A-Za-z_]\w*)\s*([:=][^\n]*)", text, re.M)}


def preservation(base: str, left: str, right: str, merged: str) -> list[str]:
    out = []
    for path, (table, key) in TABLES.items():
        snapshots = []
        for rev in (base, left, right, merged):
            try:
                snapshots.append(entries(blob(rev, path), table, key))
            except ValueError as e:
                raise ValueError("%s at %s: %s" % (path, rev or "index", e)) from e
        out += table_findings(path, *snapshots)
    path = "src/POOLVARS.PAS"
    old, a, b, result = [declarations(blob(rev, path)) for rev in (base, left, right, merged)]
    out += ["%s: merge lost declaration %s" % (path, name)
            for name in sorted(retained_keys(old, a, b) - result.keys())]
    return out


def merge_findings(commit: str = "HEAD", staged: bool = False) -> list[str]:
    commit = common.git("rev-parse", "--verify", commit + "^{commit}")
    if staged:
        path = Path(common.git("rev-parse", "--git-path", "MERGE_HEAD"))
        if not path.is_absolute():
            path = common.ROOT / path
        if not path.exists():
            raise ValueError("STAGED=1 requires an in-progress merge")
        heads = path.read_text().splitlines()
        if len(heads) != 1:
            raise ValueError("only one branch at a time; octopus merges are not supported")
        if common.git("diff", "--name-only", "--diff-filter=U"):
            raise ValueError("resolve every conflict before merge-check")
        if common.git("diff", "--name-only"):
            raise ValueError("stage every resolution before merge-check")
        left, right, result = commit, common.git("rev-parse", heads[0] + "^{commit}"), ""
    else:
        parents = common.git("show", "-s", "--format=%P", commit).split()
        if len(parents) < 2:
            return []
        if len(parents) != 2:
            raise ValueError("only two-parent merges are supported")
        left, right = parents
        result = commit
    base = common.git("merge-base", left, right)
    return preservation(base, left, right, result)


def branch_findings(branch: str | None = None) -> list[str]:
    branch = branch or common.git("branch", "--show-current")
    if branch == "main" or branch.startswith("integrate/"):   # make integrate checks a merge of main in a temporary branch
        return []
    if not branch.startswith(("unit/", "review/", "task/")):
        return ["work must be on a claimed unit/, review/ or task/ branch"]
    base = common.git("merge-base", "main", "HEAD")
    # The branch's own changes: files that differ both from the merge base and from main's tip. A file
    # main changed and the branch merged (identical to main now) is not the worker's change; a file main
    # changed that the branch has not merged yet is not either (identical to the base).
    paths = sorted(set(common.git("diff", "--name-only", base, "--").splitlines())
                   & set(common.git("diff", "--name-only", "main", "--").splitlines()))
    approved = set()
    if branch.startswith("task/"):
        grant = common.common_dir() / "poolrad-task-approvals" / (common.identifier(branch[5:]) + ".json")
        if grant.exists():
            approval = json.loads(grant.read_text())
            if approval.get("branch") != branch or not approval.get("reason") or not approval.get("base"):
                raise ValueError("invalid task approval")
            common.git("merge-base", "--is-ancestor", approval["base"], "HEAD")
            approved = set(approval["paths"])
    out = []
    reserved = {"work/status.md", "work/blockers.md", "docs/design/CHANGELOG.md"}
    for path in paths:
        if path in reserved:
            out.append("%s is orchestrator-owned; do not commit or overwrite it" % path)
        if path.startswith(("poolrad/", "build/", "tools/vendor/")):
            out.append("%s is a pinned/generated/proprietary input, not agent output" % path)
        if path not in approved and (path in {"docs/spec/SPEC.md", "re/state.toml"} or path.startswith(("docs/spec/ADR", "tests/sessions/"))):
            out.append("%s requires a separately authorized human decision" % path)
        probe_prefix = "tools/re/tp_idioms/" + branch.split("/", 1)[1] + "/"
        new_probe = path.startswith(probe_prefix) and path.upper().endswith(".PAS") and not blob(base, path)
        if branch.startswith("unit/") and not new_probe and (path.startswith("tools/") or path.startswith("tests/") or path == "Makefile"):
            out.append("%s is tooling; escalate it rather than changing it as a decompiler" % path)
        if branch.startswith("review/") and not (path.startswith("work/reviews/") or path == "re/symbols.toml"):
            out.append("%s is not reviewer output; reviewers never edit the code they review" % path)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--merge-only", action="store_true")
    ap.add_argument("--commit", default="HEAD")
    ap.add_argument("--staged", action="store_true")
    a = ap.parse_args(argv)
    try:
        findings = ([] if a.merge_only else branch_findings()) + merge_findings(a.commit, a.staged)
        for finding in findings:
            print("safety: " + finding)
        print("safety: %s" % ("FAILED (%d findings)" % len(findings) if findings else "clean"))
        return 1 if findings else 0
    except (ValueError, RuntimeError, OSError) as e:
        print("safety: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

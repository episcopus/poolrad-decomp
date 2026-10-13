#!/usr/bin/env python3
"""merge_shared.py: a git merge driver for the shared registries and src/POOLVARS.PAS.

  tools/agent/merge_shared.py %O %A %B %P        how git calls it (`make merge-driver` registers it
                                                  for the paths listed in .gitattributes)
  .venv/bin/python tools/agent/merge_shared.py BASE OURS THEIRS [PATH]

The merged result is written into OURS. Exit 0 on a clean merge, 1 when a conflict remains (git
conflict markers around the record), 2 on a usage error.

Two branches conflict only when they change the same record (SYSTEM-REVIEW-2026-10-12, 6.3):

- TOML record files (re/symbols.toml `routine` by `id`, re/dseg.toml `global` by `name`,
  re/renames.toml `rename` by `old`, re/learnings/*.toml `lesson` by `id`) are merged record by
  record and, inside a record changed on both sides, field by field. A list changed on both sides
  is the union (ours first, then theirs' additions; an item one side removed from the base stays
  removed); a `notes` string changed on both sides is joined with "; " when neither contains the
  other. A field changed differently on both sides is a conflict: that record is written twice
  between conflict markers (ours' value and theirs' value, the other fields merged in both), the
  rest of the file is merged normally.
- src/POOLVARS.PAS: the `var` section is merged declaration by declaration (one entry = its
  leading comment lines and the declaration up to its closing `;` and trailing comment); the head
  (`type`, `const`) and the tail (`implementation` ... `end.`) are merged as text by git merge-file.
- Any other path falls back to git merge-file.

Every raw line is preserved: a merge adds, removes or replaces whole records, so `git diff` after
a merge shows only real changes. The result is parsed back before it is written; a result that
does not parse falls back to the plain git merge-file form with conflict markers (exit 1).
"""
from __future__ import annotations

import fnmatch
import json
import re
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

OURS, THEIRS = "<<<<<<< ours", ">>>>>>> theirs"
SEPARATOR = "======="


class MergeError(ValueError):
    """The structured merge cannot be trusted for this input; fall back to git merge-file."""


# ---------------------------------------------------------------- sort keys

def routine_sort_key(r: dict):
    m = re.fullmatch(r"([0-9A-Za-z]+):([0-9A-Fa-f]{1,4})", str(r.get("addr", "")))
    if not m or "unit" not in r:
        raise MergeError("routine without unit/addr")
    return (str(r["unit"]), int(m.group(2), 16))


def global_sort_key(r: dict):
    if not isinstance(r.get("offset"), int):
        raise MergeError("global without offset")
    return r["offset"]


@dataclass(frozen=True)
class TomlSpec:
    table: str
    key: str
    sort_key: object = None            # callable(record dict) -> comparable, or None


TOML_SPECS = {
    "re/symbols.toml": TomlSpec("routine", "id", routine_sort_key),
    "re/dseg.toml": TomlSpec("global", "name", global_sort_key),
    "re/renames.toml": TomlSpec("rename", "old"),
    "re/learnings/*.toml": TomlSpec("lesson", "id"),
}
POOLVARS = "src/POOLVARS.PAS"


def classify(path: str | None):
    """The spec for a path: a TomlSpec, POOLVARS, or None (plain text merge)."""
    if not path:
        return None
    p = path.replace("\\", "/")
    for pattern, spec in TOML_SPECS.items():
        if fnmatch.fnmatch(p, pattern) or fnmatch.fnmatch(p, "*/" + pattern):
            return spec
    if p == POOLVARS or p.endswith("/" + POOLVARS):
        return POOLVARS
    return None


def sniff(text: str):
    """When git gives no path (%P needs git 2.44), recognise the file by its content."""
    m = re.search(r"^\[\[(\w+)\]\]\s*$", text, re.M)
    if m:
        for spec in TOML_SPECS.values():
            if spec.table == m.group(1):
                return spec
    if re.match(r"\s*unit\s+POOLVARS\s*;", text, re.I):
        return POOLVARS
    return None


# ---------------------------------------------------------------- git merge-file

def merge_file(base: str, ours: str, theirs: str) -> tuple[str, int]:
    """Three-way text merge by git merge-file: (merged text, number of conflicts)."""
    with tempfile.TemporaryDirectory(prefix="merge_shared.") as d:
        paths = []
        for name, text in (("ours", ours), ("base", base), ("theirs", theirs)):
            p = Path(d) / name
            with open(p, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            paths.append(str(p))
        r = subprocess.run(["git", "merge-file", "-p", "-L", "ours", "-L", "base", "-L", "theirs", *paths],
                           capture_output=True)
    if r.returncode < 0 or r.returncode > 127:
        raise MergeError("git merge-file failed: %s" % r.stderr.decode("utf-8", "replace").strip())
    return r.stdout.decode("utf-8"), r.returncode


# ---------------------------------------------------------------- records

@dataclass
class Record:
    key: object
    lines: list[str]
    fields: list = field(default_factory=list)      # TOML only: list[Field]
    lead: list[str] = field(default_factory=list)   # TOML only: comment lines and the [[table]] line
    value: dict = field(default_factory=dict)       # TOML only: the parsed record

    @property
    def text(self) -> str:
        return "\n".join(self.lines)


@dataclass
class Field:
    name: str
    lines: list[str]       # the value line(s)
    trailer: list[str]     # blank and comment lines after the value, up to the next field
    value: object

    @property
    def text(self) -> str:
        return "\n".join(self.lines)

    @property
    def all_lines(self) -> list[str]:
        return self.lines + self.trailer


@dataclass
class Document:
    head: list[str]
    records: list[Record]
    tail: list[str]
    newline: bool = True

    def by_key(self) -> dict:
        out = {}
        for r in self.records:
            if r.key in out:
                raise MergeError("duplicate key %r" % (r.key,))
            out[r.key] = r
        return out


FIELD_RE = re.compile(r"^([A-Za-z0-9_][A-Za-z0-9_.-]*)\s*=")
COMMENT_RE = re.compile(r"^\s*(#.*)?$")


def parse_toml(text: str, spec: TomlSpec) -> Document:
    lines = text.split("\n")
    newline = text.endswith("\n")
    if newline:
        lines.pop()
    table_re = re.compile(r"^\[\[\s*%s\s*\]\]\s*(#.*)?$" % re.escape(spec.table))
    if any(re.match(r"^\s*\[", l) and not table_re.match(l) for l in lines):
        raise MergeError("a table other than [[%s]]" % spec.table)
    starts = [i for i, l in enumerate(lines) if table_re.match(l)]
    if not starts:
        return Document(lines, [], [], newline)
    # Comment lines directly above a [[table]] line belong to that record.
    leads = []
    for s in starts:
        i = s
        while i > 0 and lines[i - 1].strip().startswith("#"):
            i -= 1
        leads.append(i)
    head = lines[:leads[0]]
    records = []
    for n, s in enumerate(starts):
        end = leads[n + 1] if n + 1 < len(starts) else len(lines)
        body = lines[leads[n]:end]
        rec = parse_record(body, s - leads[n], spec)
        records.append(rec)
    return Document(head, records, [], newline)


def parse_record(body: list[str], table_at: int, spec: TomlSpec) -> Record:
    try:
        parsed = tomllib.loads("\n".join(body))
    except tomllib.TOMLDecodeError as e:
        raise MergeError("record does not parse: %s" % e) from e
    rows = parsed.get(spec.table, [])
    if len(rows) != 1 or spec.key not in rows[0]:
        raise MergeError("record without a %s" % spec.key)
    value = rows[0]
    fields_at = [i for i in range(table_at + 1, len(body)) if FIELD_RE.match(body[i])]
    lead = body[:fields_at[0]] if fields_at else body
    fields = []
    for n, i in enumerate(fields_at):
        end = fields_at[n + 1] if n + 1 < len(fields_at) else len(body)
        chunk = body[i:end]
        last = len(chunk)
        while last > 1 and COMMENT_RE.match(chunk[last - 1]):
            last -= 1
        name = FIELD_RE.match(chunk[0]).group(1)
        if name not in value:
            raise MergeError("field %s is not a plain key of the record" % name)
        fields.append(Field(name, chunk[:last], chunk[last:], value[name]))
    if len({f.name for f in fields}) != len(fields):
        raise MergeError("duplicate field in record %r" % (value[spec.key],))
    return Record(value[spec.key], body, fields, lead, value)


# ---------------------------------------------------------------- TOML values

def toml_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ", ".join(toml_value(x) for x in v) + "]"
    raise MergeError("cannot write a %s" % type(v).__name__)


def list_union(base, ours, theirs) -> list:
    """Ours first, then theirs' additions; an item one side removed from the base stays removed."""
    base = base if isinstance(base, list) else []
    out = [x for x in ours if x in theirs or x not in base]
    out += [x for x in theirs if x not in out and x not in base]
    return out


def join_notes(a: str, b: str) -> str:
    if a in b:
        return b
    if b in a:
        return a
    return "%s; %s" % (a, b)


# ---------------------------------------------------------------- field merge

def ordered_names(ours: list, theirs: list) -> list:
    """Ours' order, theirs' additions after their predecessor in theirs."""
    out = list(ours)
    prev = None
    for name in theirs:
        if name not in out:
            at = out.index(prev) + 1 if prev in out else len(out)
            out.insert(at, name)
        prev = name
    return out


def merge_fields(base: Record | None, ours: Record, theirs: Record) -> tuple[list[str], list[str] | None]:
    """Merge a record changed on both sides. Returns (lines, None) when clean, or (ours variant,
    theirs variant) when a field conflicts; the variants differ only in the conflicting fields."""
    fb = {f.name: f for f in base.fields} if base else {}
    fa = {f.name: f for f in ours.fields}
    fc = {f.name: f for f in theirs.fields}
    lead = ours.lead
    if base and ours.lead == base.lead and theirs.lead != base.lead:
        lead = theirs.lead
    mine, other = list(lead), list(lead)
    conflict = False
    for name in ordered_names([f.name for f in ours.fields], [f.name for f in theirs.fields]):
        a, b, c = fa.get(name), fb.get(name), fc.get(name)
        if a and c:
            if a.text == c.text or a.value == c.value:
                take = a.all_lines
            elif b and (a.text == b.text or a.value == b.value):
                take = c.lines + (a.trailer if a.trailer else c.trailer)
            elif b and (c.text == b.text or c.value == b.value):
                take = a.all_lines
            elif isinstance(a.value, list) and isinstance(c.value, list):
                merged = list_union(b.value if b else [], a.value, c.value)
                take = ["%s = %s" % (name, toml_value(merged))] + a.trailer
            elif name == "notes" and isinstance(a.value, str) and isinstance(c.value, str):
                take = ["%s = %s" % (name, toml_value(join_notes(a.value, c.value)))] + a.trailer
            else:
                conflict = True
                mine += a.all_lines
                other += c.lines + (a.trailer if a.trailer else c.trailer)
                continue
        elif a:                                              # theirs has no such field
            if b is None:
                take = a.all_lines                           # ours added it
            elif a.text == b.text or a.value == b.value:
                take = a.trailer                             # theirs deleted it, ours kept it
            else:
                conflict = True
                mine += a.all_lines
                other += a.trailer
                continue
        else:                                                # ours has no such field
            if b is None:
                take = c.all_lines
            elif c.text == b.text or c.value == b.value:
                take = c.trailer
            else:
                conflict = True
                mine += c.trailer
                other += c.all_lines
                continue
        mine += take
        other += take
    if conflict:
        return mine, other
    return mine, None


# ---------------------------------------------------------------- record merge

def conflict_block(ours: list[str], theirs: list[str]) -> list[str]:
    return [OURS, *ours, SEPARATOR, *theirs, THEIRS]


def sorted_by(records: list[Record], key) -> bool:
    try:
        keys = [key(r.value) for r in records]
    except MergeError:
        return False
    return all(keys[i] <= keys[i + 1] for i in range(len(keys) - 1))


def merge_records(base: Document, ours: Document, theirs: Document, merge_changed,
                  sort_key=None) -> tuple[list[tuple[object, list[str]]], int]:
    """Three-way merge of ordered records. `merge_changed(base, ours, theirs)` resolves a record
    changed on both sides and returns (lines, None) or (ours variant, theirs variant)."""
    B, A, C = base.by_key(), ours.by_key(), theirs.by_key()
    out: list[tuple[object, list[str]]] = []
    conflicts = 0
    for key, a in A.items():
        b, c = B.get(key), C.get(key)
        if c is None:
            if b is None:
                out.append((key, a.lines))                   # added by ours
            elif a.text == b.text:
                continue                                     # deleted by theirs, untouched by ours
            else:
                conflicts += 1
                out.append((key, conflict_block(a.lines, [])))
        elif a.text == c.text:
            out.append((key, a.lines))
        elif b is not None and a.text == b.text:
            out.append((key, c.lines))
        elif b is not None and c.text == b.text:
            out.append((key, a.lines))
        else:
            mine, other = merge_changed(b, a, c)
            if other is None:
                out.append((key, mine))
            else:
                conflicts += 1
                out.append((key, conflict_block(mine, other)))
    use_sort = sort_key is not None and sorted_by(ours.records, sort_key) and sorted_by(theirs.records, sort_key)
    keys_at = lambda: [k for k, _ in out]
    prev, new = None, set()
    for key, c in C.items():
        if key in A:
            prev = key
            continue
        b = B.get(key)
        if b is not None and c.text == b.text:
            continue                                         # deleted by ours, untouched by theirs
        lines = c.lines if b is None else conflict_block([], c.lines)
        if b is not None:
            conflicts += 1
        at = None
        if use_sort and b is None:
            k = sort_key(c.value)
            at = len(out)
            for i, (okey, _) in enumerate(out):
                if okey in A and sort_key(A[okey].value) > k:
                    at = i
                    break
        if at is None:
            keys = keys_at()
            at = keys.index(prev) + 1 if prev in keys else (0 if prev is None else len(out))
        out.insert(at, (key, lines))
        prev = key
        new.add(key)
    return separated(out, ours.records, new), conflicts


def separated(out: list[tuple[object, list[str]]], ours: list[Record], new: set) -> list[tuple[object, list[str]]]:
    """Keep ours' record separator convention around the records theirs added: when ours' records
    end with a blank line, an inserted record and the record before it do too, and the last record
    ends like ours' last record. Records ours already had keep their lines as they are."""
    if not ours or not out:
        return out
    blank_after = sum(bool(r.lines) and r.lines[-1].strip() == "" for r in ours) * 2 > len(ours)
    last_blank = bool(ours[-1].lines) and ours[-1].lines[-1].strip() == ""
    fixed = []
    for n, (key, lines) in enumerate(out):
        is_last = n == len(out) - 1
        touched = key in new or (not is_last and out[n + 1][0] in new) or (is_last and key != ours[-1].key)
        if touched:
            lines = list(lines)
            if is_last and not last_blank:
                while lines and lines[-1].strip() == "":
                    lines.pop()
            elif (last_blank if is_last else blank_after) and (not lines or lines[-1].strip() != ""):
                lines.append("")
        fixed.append((key, lines))
    return fixed


# ---------------------------------------------------------------- TOML files

def merge_toml(base: str, ours: str, theirs: str, spec: TomlSpec) -> tuple[str, int]:
    db, da, dc = (parse_toml(t, spec) for t in (base, ours, theirs))
    conflicts = 0
    if da.head == dc.head or dc.head == db.head:
        head = da.head
    elif da.head == db.head:
        head = dc.head
    else:
        text, n = merge_file(*("\n".join(d.head) + "\n" for d in (db, da, dc)))
        head, conflicts = text.split("\n")[:-1], conflicts + n
    merged, n = merge_records(db, da, dc, merge_fields, spec.sort_key)
    conflicts += n
    lines = head + [l for _, block in merged for l in block]
    text = "\n".join(lines) + ("\n" if da.newline or dc.newline else "")
    if not conflicts:
        try:
            parsed = tomllib.loads(text)
        except tomllib.TOMLDecodeError as e:
            raise MergeError("merged result does not parse: %s" % e) from e
        keys = [r.get(spec.key) for r in parsed.get(spec.table, [])]
        if sorted(map(str, keys)) != sorted(str(k) for k, _ in merged):
            raise MergeError("merged result lost or duplicated a record")
    return text, conflicts


# ---------------------------------------------------------------- POOLVARS.PAS

DECL_RE = re.compile(r"^  ([A-Za-z_]\w*)(\s*,\s*[A-Za-z_]\w*)*\s*[:=]")
TRAIL_RE = re.compile(r"^\s{3,}\{")


def comment_end(lines: list[str], i: int, depth: int = 0) -> tuple[int, int]:
    """Scan from line i: the index after the line where every `{` opened so far is closed, and the
    depth left (0 unless the file ends inside a comment)."""
    while i < len(lines):
        for ch in lines[i]:
            if ch == "{":
                depth += 1
            elif ch == "}" and depth:
                depth -= 1
        i += 1
        if depth == 0:
            return i, 0
    return i, depth


def declaration_end(lines: list[str], i: int) -> int:
    """The index after the last line of the declaration starting at line i: the line with its `;`
    outside braces, plus the `{ ... }` comment that follows it on that line (which may continue
    over lines), plus any comment-only lines indented deeper than the declaration."""
    depth, closed = 0, False
    while i < len(lines):
        for ch in lines[i]:
            if ch == "{":
                depth += 1
            elif ch == "}" and depth:
                depth -= 1
            elif ch == ";" and depth == 0:
                closed = True
        i += 1
        if closed and depth == 0:
            break
    while i < len(lines) and TRAIL_RE.match(lines[i]):
        i, _ = comment_end(lines, i)
    return i


def split_poolvars(text: str) -> Document:
    lines = text.split("\n")
    newline = text.endswith("\n")
    if newline:
        lines.pop()
    var_at = next((i for i, l in enumerate(lines) if re.fullmatch(r"var\s*", l)), None)
    if var_at is None:
        raise MergeError("no var line")
    impl_at = next((i for i in range(var_at + 1, len(lines)) if re.match(r"implementation\b", lines[i])), None)
    if impl_at is None:
        raise MergeError("no implementation line")
    head, tail = lines[:var_at + 1], lines[impl_at:]
    records, pending, keys = [], [], set()
    i = var_at + 1
    while i < impl_at:
        m = DECL_RE.match(lines[i])
        if not m:
            pending.append(lines[i])
            i += 1
            continue
        end = min(declaration_end(lines, i), impl_at)
        key = m.group(1).lower()
        if key in keys:
            raise MergeError("duplicate declaration %s" % key)
        keys.add(key)
        records.append(Record(key, pending + lines[i:end]))
        pending, i = [], end
    return Document(head, records, pending + tail, newline)


_offsets: dict | None = None


def global_offsets() -> dict[str, int]:
    """Name -> DS offset from the working tree's re/dseg.toml (empty when it cannot be read)."""
    global _offsets
    if _offsets is None:
        _offsets = {}
        try:
            for g in tomllib.loads((ROOT / "re/dseg.toml").read_text(encoding="utf-8")).get("global", []):
                if isinstance(g.get("name"), str) and isinstance(g.get("offset"), int):
                    _offsets[g["name"].lower()] = g["offset"]
        except (OSError, tomllib.TOMLDecodeError, UnicodeDecodeError):
            pass
    return _offsets


def declaration_offset(key: str) -> int:
    m = re.fullmatch(r"ds([0-9a-f]{4})", key)
    if m:
        return int(m.group(1), 16)
    if key in global_offsets():
        return global_offsets()[key]
    raise MergeError("no offset for %s" % key)


def merge_poolvars(base: str, ours: str, theirs: str) -> tuple[str, int]:
    db, da, dc = (split_poolvars(t) for t in (base, ours, theirs))
    conflicts = 0
    parts = []
    for region in ("head", "tail"):
        b, a, c = (getattr(d, region) for d in (db, da, dc))
        if a == c or c == b:
            parts.append(a)
        elif a == b:
            parts.append(c)
        else:
            text, n = merge_file(*("\n".join(x) + "\n" for x in (b, a, c)))
            parts.append(text.split("\n")[:-1])
            conflicts += n
    for d in (db, da, dc):
        for r in d.records:
            r.value = {"key": r.key}
    merged, n = merge_records(db, da, dc, lambda b, a, c: (a.lines, c.lines),
                              lambda v: declaration_offset(v["key"]))
    conflicts += n
    lines = parts[0] + [l for _, block in merged for l in block] + parts[1]
    text = "\n".join(lines) + ("\n" if da.newline or dc.newline else "")
    if not conflicts:
        check = split_poolvars(text)
        if sorted(r.key for r in check.records) != sorted(k for k, _ in merged):
            raise MergeError("merged result lost or duplicated a declaration")
    return text, conflicts


# ---------------------------------------------------------------- entry points

def merge_texts(base: str, ours: str, theirs: str, path: str | None) -> tuple[str, int]:
    """Merge three versions of `path`: (merged text, number of conflicts). Falls back to the
    plain text merge when the structured merge cannot be trusted."""
    spec = classify(path) or sniff(ours)
    try:
        if spec == POOLVARS:
            return merge_poolvars(base, ours, theirs)
        if isinstance(spec, TomlSpec):
            return merge_toml(base, ours, theirs, spec)
    except MergeError as e:
        print("merge_shared: %s: %s; falling back to git merge-file" % (path or "?", e), file=sys.stderr)
        text, n = merge_file(base, ours, theirs)
        return text, max(n, 1)
    return merge_file(base, ours, theirs)


def read(path: str) -> str:
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) not in (3, 4):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    base, ours, theirs = (read(p) for p in argv[:3])
    path = argv[3] if len(argv) == 4 else None
    try:
        text, conflicts = merge_texts(base, ours, theirs, path)
    except (MergeError, OSError, RuntimeError) as e:
        print("merge_shared: %s" % e, file=sys.stderr)
        return 2
    with open(argv[1], "w", encoding="utf-8", newline="") as f:
        f.write(text)
    if conflicts:
        print("merge_shared: %s: %d conflict(s) left for a human" % (path or argv[1], conflicts), file=sys.stderr)
    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main())

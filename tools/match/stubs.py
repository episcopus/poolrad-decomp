#!/usr/bin/env python3
"""stubs.py: keep every `{@stub}` header equal to its re/symbols.toml record (signature and name).

  .venv/bin/python tools/match/stubs.py [UNIT ...] [--write]
  make stubs [UNIT="<id ...>"] [WRITE=1]

A unit's source declares every routine not decompiled yet as a stub: `{@stub} procedure X; begin end;`
in the implementation part and the same header in the interface part (tools/match/skeleton.py). When a
caller's decompiler settles a callee's signature, it records it in re/symbols.toml (`signature`); this
tool copies it into the callee's file, so nobody edits a stub line in another unit's file by hand and
two branches never conflict on one (SYSTEM-REVIEW-2026-10-12, 6.3). A stub whose routine was renamed in
the registry is renamed too. A routine that is not a `{@stub}` is never touched.

Without --write it prints every header that differs and exits 1 (a gate); with --write it rewrites them
and exits 0. The registry record is found by the stub's name (case-insensitive), then by `c_name`, then
by the `<unit>_fn_<offset>` form of the name.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
SYMBOLS = ROOT / "re/symbols.toml"
LINE_LIMIT = 126                      # Turbo Pascal 6.0 reads at most 126 characters of a line
STUB_RE = re.compile(r"^\{@stub\}\s*(procedure|function)\s+([A-Za-z_]\w*)", re.I)
MARKED_RE = re.compile(r"^\{@stub\}\s*(.*?);\s*begin\s+end;(.*)$", re.S)
NOT_PROGRAM = ("POOL.PAS", "POOLVARS.PAS")


@dataclass
class Change:
    start: int                 # first line index (0-based) of the replaced span
    end: int                   # index after the last line
    old: list[str]
    new: list[str]
    why: str


def registry(path: Path = SYMBOLS) -> list[dict]:
    return tomllib.loads(path.read_text(encoding="utf-8"))["routine"]


def lookup(routines: list[dict], uid: str, name: str) -> dict | None:
    """The registry record of a stub of unit `uid` named `name`."""
    low, uid = name.lower(), uid.lower()
    for key in ("name", "c_name"):
        for r in routines:
            if str(r.get(key, "")).lower() == low and str(r.get("unit", "")).lower() == uid:
                return r
    m = re.fullmatch(r"(\w+?)_fn_([0-9a-f]{4})", low)
    if m and m.group(1) == uid:
        for r in routines:
            if str(r.get("unit", "")).lower() == uid and str(r.get("addr", "")).lower().endswith(":" + m.group(2)):
                return r
    return None


def header_from_signature(r: dict) -> str | None:
    """`procedure NAME(...)` / `function NAME(...): T` from the recorded signature with the registry
    name (as skeleton.py writes it), or None when the record has no signature."""
    sig = str(r.get("signature") or "").strip()
    m = re.match(r"^(procedure|function)\s+\w+\s*(.*)$", sig, re.I | re.S)
    if not m:
        return None
    return "%s %s%s" % (m.group(1).lower(), r["name"], " ".join(m.group(2).split()).rstrip(";"))


def rename_header(header: str, name: str) -> str:
    return re.sub(r"^(procedure|function)(\s+)\w+", lambda m: "%s%s%s" % (m.group(1).lower(), m.group(2), name),
                  header, count=1, flags=re.I)


def normalise(header: str) -> str:
    return " ".join(header.split()).rstrip(";").strip()


def wrap(prefix: str, header: str, suffix: str) -> list[str]:
    """`prefix + header + suffix` on one line when it fits, else wrapped after parameter groups
    (`; `) or parameters (`, `), continuation lines indented two spaces."""
    text = prefix + header + suffix
    if len(text) <= LINE_LIMIT:
        return [text]
    pieces = []
    for group in re.split(r"(?<=; )", header):
        if len(group) + 2 > LINE_LIMIT:
            pieces += re.split(r"(?<=, )", group)
        else:
            pieces.append(group)
    lines, current = [], prefix
    for n, piece in enumerate(pieces):
        tail = suffix if n == len(pieces) - 1 else ""
        if current.strip() and len(current + piece + tail) > LINE_LIMIT:
            lines.append(current.rstrip())
            current = "  "
        current += piece
    lines.append(current + suffix)
    return lines


def stub_spans(lines: list[str], start: int) -> list[tuple[int, int, str, str, str]]:
    """(first line, line after the last, name, header, trailer) of every `{@stub}` of the
    implementation part starting at line `start`."""
    out = []
    i = start
    while i < len(lines):
        m = STUB_RE.match(lines[i])
        if not m:
            i += 1
            continue
        j = i
        while j < len(lines) and not re.search(r"\bbegin\s+end\s*;", lines[j]):
            j += 1
            if j - i > 12 or j >= len(lines):
                raise ValueError("line %d: stub %s has no `begin end;` within 12 lines" % (i + 1, m.group(2)))
        full = MARKED_RE.match(" ".join(l.strip() if k else l for k, l in enumerate(lines[i:j + 1])))
        if not full:
            raise ValueError("line %d: stub %s is not `{@stub} HEADER; begin end;`" % (i + 1, m.group(2)))
        out.append((i, j + 1, m.group(2), full.group(1), full.group(2)))
        i = j + 1
    return out


def interface_span(lines: list[str], first: int, last: int, name: str) -> tuple[int, int] | None:
    """The declaration of `name` in the interface part (lines first..last): (start, end)."""
    pat = re.compile(r"^(procedure|function)\s+%s\b" % re.escape(name), re.I)
    for i in range(first, last):
        if pat.match(lines[i]):
            j = i
            while not re.sub(r"\{[^}]*\}\s*$", "", lines[j]).rstrip().endswith(";"):
                j += 1
                if j >= last or j - i > 12:
                    return None
            return i, j + 1
    return None


BUILTIN_TYPES = {"byte", "shortint", "word", "integer", "longint", "boolean", "char", "string", "pointer",
                 "real", "single", "double", "extended", "comp", "text", "file"}


def declared_in_interface(lines: list[str]) -> tuple[set[str], list[str]]:
    """(lower-case identifiers declared `Name = ...` in the interface part, units of its uses clause)."""
    try:
        iface, impl = parts(lines)
    except ValueError:
        return set(), []
    names, units = set(), []
    for l in lines[iface:impl]:
        m = re.match(r"^\s*([A-Za-z_]\w*)\s*=", l)
        if m:
            names.add(m.group(1).lower())
        m = re.match(r"^\s*uses\s+([^;]+);", l, re.I)
        if m:
            units += [u.strip().lower() for u in m.group(1).split(",")]
    return names, units


def invisible_types(signature: str, lines: list[str], src: Path | None = None) -> list[str]:
    """Type names of `signature` that neither the unit's interface part nor the interface part of a
    unit it uses declares (a used unit without source, a library unit, is trusted)."""
    names, units = declared_in_interface(lines)
    visible = BUILTIN_TYPES | names
    trusted = False
    for u in units:
        path = (src or SRC) / (u.upper() + ".PAS")
        if not path.exists():
            trusted = True
            continue
        visible |= declared_in_interface(path.read_text(encoding="utf-8").split("\n"))[0]
    wanted = {m.group(1) for m in re.finditer(r":\s*([A-Za-z_]\w*)", signature)}
    return [] if trusted else sorted(t for t in wanted if t.lower() not in visible)


def parts(lines: list[str]) -> tuple[int, int]:
    """(index of the interface line, index of the implementation line)."""
    iface = next((i for i, l in enumerate(lines) if re.match(r"\s*interface\b", l, re.I)), None)
    impl = next((i for i, l in enumerate(lines) if re.match(r"\s*implementation\b", l, re.I)), None)
    if iface is None or impl is None or impl < iface:
        raise ValueError("no interface/implementation parts")
    return iface, impl


def plan(text: str, uid: str, routines: list[dict], src: Path | None = None) -> tuple[list[Change], list[str]]:
    """The edits that make every stub of `text` (unit `uid`) equal to its registry record (a header
    whose signature cannot be applied is listed with `old == new`), and the notes about stubs that
    could not be checked or applied. `src` is the directory of the unit sources (SRC)."""
    lines = text.split("\n")
    iface, impl = parts(lines)
    changes, notes = [], []
    for start, end, name, header, trailer in stub_spans(lines, impl):
        r = lookup(routines, uid, name)
        if r is None:
            notes.append("%s: no re/symbols.toml record for stub %s" % (uid, name))
            continue
        want_name = str(r["name"])
        want = header_from_signature(r)
        if want is None:
            if want_name == name:
                continue
            want = rename_header(header, want_name)
        if normalise(want) == normalise(header):
            continue
        why = "%s %s: " % (r["id"], want_name)
        why += "renamed from %s" % name if want_name != name else "signature"
        missing = invisible_types(want, lines, src)
        if missing:
            notes.append("%s: stub %s keeps its header: the registry signature needs %s, not visible in the "
                         "interface part (add the unit declaring it to the interface uses clause first)"
                         % (uid, name, ", ".join(missing)))
            changes.append(Change(start, end, lines[start:end], lines[start:end], why + " (not applied)"))
            continue
        if want_name != name:
            others = len(re.findall(r"(?<![\w@])%s(?!\w)" % re.escape(name), text, re.I)) - 2
            if others > 0:
                notes.append("%s: %s is still used %d more time(s) in the file after the rename; "
                             "`make rename APPLY=1` renames the uses" % (uid, name, others))
        changes.append(Change(start, end, lines[start:end], wrap("{@stub} ", want, "; begin end;" + trailer), why))
        span = interface_span(lines, iface, impl, name)
        if span is None:
            notes.append("%s: stub %s has no interface declaration" % (uid, name))
        else:
            changes.append(Change(span[0], span[1], lines[span[0]:span[1]], wrap("", want, ";"), why + " (interface)"))
    return changes, notes


def apply(text: str, changes: list[Change]) -> str:
    lines = text.split("\n")
    for c in sorted(changes, key=lambda c: c.start, reverse=True):
        assert lines[c.start:c.end] == c.old
        lines[c.start:c.end] = c.new
    return "\n".join(lines)


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def unit_files(units: list[str]) -> list[Path]:
    if units:
        return [SRC / (u.upper() + ".PAS") for u in units]
    return sorted(p for p in SRC.glob("*.PAS") if p.name not in NOT_PROGRAM)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("units", nargs="*", help="unit ids (default: every unit source)")
    ap.add_argument("--write", action="store_true", help="rewrite the differing headers")
    a = ap.parse_args(argv)
    routines = registry()
    differing, kept, files, notes = 0, 0, 0, []
    for path in unit_files(a.units):
        if not path.exists():
            print("stubs: %s does not exist" % rel(path))
            return 2
        text = path.read_text(encoding="utf-8")
        try:
            changes, unit_notes = plan(text, path.stem.lower(), routines, SRC)
        except ValueError as e:
            print("stubs: %s: %s" % (rel(path), e))
            return 2
        notes += unit_notes
        if not changes:
            continue
        files += 1
        for c in changes:
            if "(interface)" in c.why:
                continue
            differing += 1
            kept += c.new == c.old
            print("stubs: %s line %d: %s" % (rel(path), c.start + 1, c.why))
            for l in c.old:
                print("  - " + l)
            for l in (c.new if c.new != c.old else []):
                print("  + " + l)
        if a.write and any(c.new != c.old for c in changes):
            path.write_text(apply(text, changes), encoding="utf-8")
    for note in notes:
        print("stubs: note: " + note)
    if not differing:
        print("stubs: every stub header matches re/symbols.toml")
        return 0
    if a.write:
        print("stubs: rewrote %d header(s) in %d file(s)%s" % (
            differing - kept, files, "; %d kept (see the notes)" % kept if kept else ""))
        return 0                                   # a kept header is a note for the unit's decompiler, not a failure
    print("stubs: %d header(s) in %d file(s) differ from re/symbols.toml (WRITE=1 rewrites them)" % (differing, files))
    return 1


if __name__ == "__main__":
    sys.exit(main())

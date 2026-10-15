#!/usr/bin/env python3
"""stub_order.py: put each overlay unit's interface in the order of the original's stub entries (playbook 50).

  .venv/bin/python tools/re/stub_order.py [--write] [UNIT ...]
  make stub-order [WRITE=1]

Turbo Pascal builds an overlay unit's stub from its interface: entry k is the k-th routine declared there.
The original's order is not the order of the code (the unit's interface listed its routines in another
order), and every call from another unit goes through `stub:entry offset`, so the rebuilt overlay
differs from the original in those operands until the interface lists the routines in the original's
order. The order is the original's own, read from build/re/overlays.json (`make overlays`): each entry's
code offset names a routine of re/symbols.toml, and src/OVLnn.PAS declares that routine.

The tool rewrites only the order of the declarations in the interface section (a declaration keeps the
comment lines written directly above it); it refuses a unit whose interface and the original's entries do not
name the same routines.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class StubOrderError(Exception):
    pass


def split_interface(text: str):
    """(head through the declarations before the first routine, [chunks], tail from `implementation`). A
    chunk is a routine header with the comment lines written above it."""
    m = re.search(r"^interface\b", text, re.M | re.I)
    t = re.search(r"^implementation\b", text, re.M | re.I)
    if not m or not t:
        raise StubOrderError("no interface/implementation")
    lines = text[m.end():t.start()].split("\n")
    chunks: list[list[str]] = []
    head: list[str] = []
    cur: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r"^(procedure|function)\s", line, re.I):
            hdr = [line]
            while not _complete(" ".join(hdr)):
                i += 1
                hdr.append(lines[i])
            chunks.append(cur + hdr)
            cur = []
        elif chunks:
            if line.strip() and not line.lstrip().startswith("{") and not cur_in_comment(cur, line):
                raise StubOrderError("%r between routine declarations of the interface" % line.strip()[:40])
            cur.append(line)
        else:
            head.append(line)
        i += 1
    if any(l.strip() for l in cur):
        raise StubOrderError("text after the last declaration of the interface: %r" % cur[0][:50])
    return text[:m.end()] + "\n".join(head), chunks, text[t.start():]


def cur_in_comment(cur: list[str], line: str) -> bool:
    """True while a multi-line `{ ... }` comment is open above `line`."""
    open_ = False
    for l in cur:
        for ch in l:
            if ch == "{":
                open_ = True
            elif ch == "}":
                open_ = False
    return open_


def _complete(header: str) -> bool:
    depth = 0
    for c in header:
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif c == ";" and depth == 0:
            return True
    return False


def header_name(chunk: list[str]) -> str:
    for l in chunk:
        m = re.match(r"^(?:procedure|function)\s+(\w+)", l, re.I)
        if m:
            return m.group(1)
    raise StubOrderError("no routine header in a chunk")


def original_order(unit: str, symbols: list[dict], overlays: dict) -> list[str]:
    n = int(unit[3:])
    o = next(x for x in overlays["overlays"] if x["overlay"] == n)
    names = {}
    for r in symbols:
        if r["unit"] == unit:
            names[int(r["addr"].split(":")[1], 16)] = r["name"]
    out = []
    for e in sorted(o["entries"], key=lambda e: e["index"]):
        off = e["code_offset"]
        if e["index"] == 0:
            continue                                  # entry 0 is the unit's initialisation part
        if off not in names:
            raise StubOrderError("%s: entry %d at code offset %04X names no routine of the registry" % (
                unit, e["index"], off))
        out.append(names[off])
    return out


def run(units: list[str], write: bool) -> int:
    symbols = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
    overlays = json.loads((ROOT / "build/re/overlays.json").read_text())
    rc = 0
    for u in units:
        path = ROOT / "src" / (u.upper() + ".PAS")
        text = path.read_text()
        try:
            head, chunks, tail = split_interface(text)
            want = original_order(u, symbols, overlays)
            have = [header_name(c) for c in chunks]
            lower = [h.lower() for h in have]
            missing = [w for w in want if w.lower() not in lower]
            if missing:
                raise StubOrderError("%s: the original's stub exports %s, which the interface does not declare" % (
                    u, ", ".join(missing)))
            # the linker keeps a stub entry only for a routine another unit calls; those routines take the
            # slots they already occupy in the interface, in the original's order, everything else stays
            slots = [i for i, h in enumerate(lower) if h in {w.lower() for w in want}]
            current = [lower[i] for i in slots]
            if current == [w.lower() for w in want]:
                continue
            order = list(range(len(chunks)))
            by_name = {lower[i]: i for i in slots}
            for slot, w in zip(slots, want):
                order[slot] = by_name[w.lower()]
            print("%s: interface reordered (%d exported routines)" % (u, len(want)))
            if write:
                new = "\n".join("\n".join(chunks[i]) for i in order)
                path.write_text(head + "\n" + new + "\n" + tail)
        except StubOrderError as e:
            print("%s: %s" % (u, e))
            rc = 1
    return rc


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("units", nargs="*", help="overlay unit ids (default: every overlay unit)")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args(argv)
    units = a.units or ["ovl%02d" % i for i in range(35)]
    return run(units, a.write)


if __name__ == "__main__":
    sys.exit(main())

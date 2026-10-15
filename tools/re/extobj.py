#!/usr/bin/env python3
"""extobj.py: an OMF object file for the code the original linked from an `.OBJ` (SPEC 8.3, playbook 50).

  .venv/bin/python tools/re/extobj.py UNIT [-o FILE]       e.g. res03

Some units end with code that is not Pascal: res03's sound driver was assembled separately and linked with
`{$L}` after the unit's initialisation part (`re/units.toml` `external_from`, the registry's
`external = true`). The matcher keeps those bytes as the original's; the rebuild (`make rebuild`) needs an
object file for the linker. This tool writes one from the original image: one code segment holding the bytes
from `external_from` to the end of the unit, a public name per routine of the registry, and a segment-base
fixup for every word the original's relocation table marks inside it (each is a reference to the unit's
own segment, which is what lets the linker put the word in the new relocation table).

It is a stand-in for the assembly source Phase 5 will write: the bytes come from poolrad/start-unpack.exe at
build time, nothing of the original is stored in the repository, and the object is kept in build/. When the
driver has a source that assembles to the same bytes, `make rebuild` links that and this tool is retired.
"""
from __future__ import annotations

import argparse
import struct
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))
sys.path.insert(0, str(ROOT / "tools/re"))


class ObjError(Exception):
    pass


def record(rtype: int, data: bytes) -> bytes:
    body = bytes([rtype]) + struct.pack("<H", len(data) + 1) + data
    return body + bytes([(-sum(body)) & 0xFF])


def name(s: str) -> bytes:
    b = s.encode("ascii")
    if len(b) > 255:
        raise ObjError("name too long")
    return bytes([len(b)]) + b


def omf(module: str, seg_len: int, publics: list[tuple[str, int]], data: bytes, seg_fixups: list[int]) -> bytes:
    """One 16-bit code segment named CODE (byte aligned, public) with `publics` and segment-base fixups at
    `seg_fixups` (offsets of the words that hold the segment's own paragraph)."""
    out = [record(0x80, name(module))]                                   # THEADR
    out.append(record(0x96, name("") + name("CODE")))                    # LNAMES: 1 = '', 2 = CODE
    out.append(record(0x98, bytes([0x28]) + struct.pack("<H", seg_len) + bytes([2, 2, 1])))   # SEGDEF 1
    # a record holds at most 1024 bytes
    chunk, size = [], 0
    for n, off in publics:
        item = name(n) + struct.pack("<H", off) + b"\x00"
        if size + len(item) > 900:
            out.append(record(0x90, b"\x00\x01" + b"".join(chunk)))
            chunk, size = [], 0
        chunk.append(item)
        size += len(item)
    if chunk:
        out.append(record(0x90, b"\x00\x01" + b"".join(chunk)))
    fixes = sorted(seg_fixups)
    pos = 0
    while pos < len(data):
        n = min(1024, len(data) - pos)
        out.append(record(0xA0, bytes([1]) + struct.pack("<H", pos) + data[pos:pos + n]))
        mine = [f for f in fixes if pos <= f < pos + n]
        if mine:
            fx = b""
            for f in mine:
                rel = f - pos
                fx += bytes([0x80 | 0x40 | (2 << 2) | (rel >> 8 & 3), rel & 0xFF, 0x04, 1, 1])
            out.append(record(0x9C, fx))
        pos += n
    out.append(record(0x8A, b"\x00"))                                    # MODEND
    return b"".join(out)


def external_part(unit: str):
    """(bytes of the external code, [(public name, offset in it)], [fixup offsets in it], base offset)."""
    import match  # noqa: E402

    units = tomllib.loads((ROOT / "re/units.toml").read_text())
    u = next((x for x in units["resident"] if x["id"] == unit), None)
    if u is None or not u.get("external_from"):
        raise ObjError("%s has no external object (re/units.toml external_from)" % unit)
    seg_s, off_s = u["external_from"].split(":")
    base = int(off_s, 16)
    orig = match.Original()
    code, seg = orig.segment(unit)
    start = seg * 16
    syms = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
    publics = []
    for r in syms:
        if r["unit"] == unit and r.get("external"):
            off = int(r["addr"].split(":")[1], 16)
            if off < base:
                raise ObjError("%s: external routine %s at %04X is below external_from %04X" % (unit, r["name"], off, base))
            publics.append((r["name"], off - base))
    if not publics:
        raise ObjError("%s: the registry flags no routine external" % unit)
    ext = bytes(code[base:])
    total = len(ext)
    trimmed = ext.rstrip(b"\x00")
    # the compiler pads the unit to a paragraph; keep enough zeros that the padded length is the original's
    need = -((-(base + len(trimmed))) // 16) * 16 - base
    if base + total != -((-(base + total)) // 16) * 16:
        raise ObjError("%s: segment length %d is not a paragraph multiple" % (unit, base + total))
    trimmed += bytes(max(0, need - len(trimmed)))
    if base + len(trimmed) != base + total and (base + len(trimmed) + 15) // 16 != (base + total) // 16:
        trimmed = ext
    relocs = [r - start - base for r in sorted(orig.relocs) if start + base <= r < start + base + len(trimmed)]
    for f in relocs:
        v = trimmed[f] | trimmed[f + 1] << 8
        if v != seg:
            raise ObjError("%s: relocated word at +%04X holds %04X, not the unit's own segment %04X" % (
                unit, f + base, v, seg))
    return trimmed, publics, relocs, base


def build_object(unit: str) -> bytes:
    data, publics, fixups, base = external_part(unit)
    return omf(unit.upper() + "X", len(data), publics, data, fixups)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("unit")
    ap.add_argument("-o", "--out")
    a = ap.parse_args(argv)
    try:
        obj = build_object(a.unit)
    except ObjError as e:
        print("extobj: %s" % e)
        return 1
    out = Path(a.out) if a.out else ROOT / "build/rebuild" / (a.unit.upper() + "X.OBJ")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(obj)
    print("extobj: wrote %s (%d bytes)" % (out, len(obj)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

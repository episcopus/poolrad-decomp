#!/usr/bin/env python3
"""gen_dseg.py: generate src/include/gen/dseg.h from re/dseg.toml (SPEC 7.3).

The DGROUP mirror is one struct of 64 KB with the known globals at their
DS-relative offsets; unknown regions stay u8 filler until identified.
Every named field gets a STATIC_ASSERT on its offset.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DSIZE = 0x10000


def parse_toml(path: Path) -> list[dict]:
    d = tomllib.loads(path.read_text())
    return sorted(d.get("global", []), key=lambda g: g["offset"])


def c_type(t: str, size: int) -> str:
    if t in ("u8", "s8", "u16", "s16", "u32", "s32"):
        return t
    if t == "u16_dup":
        return "u16"
    raise ValueError("gen_dseg: unsupported type %r (size %d)" % (t, size))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="exit 1 when the header is out of date (for make check)")
    args = ap.parse_args(argv[1:])
    globals_ = parse_toml(ROOT / "re/dseg.toml")
    out = ROOT / "src/include/gen/dseg.h"

    lines = [
        "/* dseg.h: DGROUP mirror, GENERATED from re/dseg.toml by tools/re/gen_dseg.py.",
        " * Do not edit by hand; edit re/dseg.toml and regenerate. */",
        "#ifndef POOLRAD_GEN_DSEG_H",
        "#define POOLRAD_GEN_DSEG_H",
        "",
        '#include "../types.h"',
        "#include <stddef.h>",
        "",
        "typedef struct {",
    ]
    pos = 0
    pad_n = 0
    fields: list[tuple[str, int]] = []
    for g in globals_:
        off, size = g["offset"], g["size"]
        name = re.sub(r"[^A-Za-z0-9_]", "_", g["name"])
        if off < pos:
            raise ValueError("gen_dseg: overlapping global %s at %#x" % (name, off))
        if off > pos:
            lines.append("    u8 _pad%d[0x%X];" % (pad_n, off - pos))
            pad_n += 1
            pos = off
        t = c_type(g["type"], size)
        if size == {"u8": 1, "s8": 1, "u16": 2, "s16": 2, "u32": 4, "s32": 4}[t]:
            lines.append("    %s %s;" % (t, name))
        else:
            lines.append("    %s %s[%d];" % (t, name, size // {"u8": 1, "s8": 1, "u16": 2,
                                                               "s16": 2, "u32": 4, "s32": 4}[t]))
        fields.append((name, off))
        pos = off + size
    if pos < DSIZE:
        lines.append("    u8 _pad%d[0x%X];" % (pad_n, DSIZE - pos))
    lines += ["} pool_dgroup_t;", "", "extern pool_dgroup_t G;", ""]
    for name, off in fields:
        lines.append("POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, %s) == 0x%X, %s);" % (name, off, name))
    lines += ["", "#endif /* POOLRAD_GEN_DSEG_H */", ""]
    text = "\n".join(lines)
    if args.check:
        if not out.exists() or out.read_text() != text:
            print("gen_dseg: %s is out of date (run tools/re/gen_dseg.py)" % out, file=sys.stderr)
            return 1
        print("gen_dseg: up to date (%d globals)" % len(fields))
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    print("gen_dseg: wrote %s (%d globals)" % (out, len(fields)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

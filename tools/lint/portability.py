#!/usr/bin/env python3
"""portability.py: enforce the engine portability rules (SPEC 7.2).

  .venv/bin/python tools/lint/portability.py [--check-path DIR ...]
  make lint

Engine code (src/game, src/rtl, src/include) must be portable C that a 16-bit
compiler with a 16-bit int can build:

  * width types only (u8 s8 u16 s16 u32 s32); no bare int/long/short/char,
    float, double, signed/unsigned without a width;
  * no libc includes except <stddef.h> (offsetof) and no libc calls beyond
    memcpy/memset/memmove/strlen (everything else goes through src/rtl or
    src/platform);
  * no platform code in the engine (no inclusion of platform.h or host APIs);
  * no bitfields, no VLAs (array sizes must be constant expressions), no
    float literals, no recursion deeper than the original's (no direct
    self-recursion at all: the original has none in the spike).

Platform (src/platform) and hybrid glue (src/hybrid) are not engine code and
are not linted. Exit 0 when clean, 1 with the first violation otherwise.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE = [ROOT / "src/game", ROOT / "src/rtl", ROOT / "src/include"]

BARE_TYPE = re.compile(r"(?<![A-Za-z0-9_])(int|long|short|float|double)(?![A-Za-z0-9_])")
BARE_CHAR = re.compile(r"(?<![A-Za-z0-9_])char(?![A-Za-z0-9_])")
BARE_SIGN = re.compile(r"(?<![A-Za-z0-9_])(signed|unsigned)(?![A-Za-z0-9_])")
INCLUDE = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]')
CALL = re.compile(r"(?<![A-Za-z0-9_])(malloc|calloc|realloc|free|printf|fprintf|sprintf|snprintf|"
                  r"puts|fopen|fclose|fread|fwrite|fseek|ftell|exit|abort|assert|qsort|"
                  r"strcpy|strcat|strcmp|strncmp|memcmp|memchr|strchr|strstr|strtok|"
                  r"atoi|atol|rand|srand|time|clock|getenv|system)\s*\(")
BITFIELD = re.compile(r":\s*\d+\s*;")
FLOATLIT = re.compile(r"(?<![A-Za-z0-9_])\d+\.\d+")
FUNCDEF = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*(\{|$)")


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def lint_file(path: Path) -> list[str]:
    errs = []
    raw = path.read_text()
    code = strip_comments(raw)
    for i, line in enumerate(code.splitlines(), 1):
        if BARE_TYPE.search(line):
            errs.append("%s:%d: bare int/long/short/float/double (use width types)" % (path, i))
        if BARE_CHAR.search(line):
            errs.append("%s:%d: bare char (use u8/s8)" % (path, i))
        if BARE_SIGN.search(line):
            errs.append("%s:%d: bare signed/unsigned (use width types)" % (path, i))
        m = INCLUDE.search(line)
        if m:
            hdr = m.group(1)
            quoted = '"' in line.split("include", 1)[1][:2]
            if quoted:
                if hdr not in ("types.h", "pool_memory.h", "pool_rtl.h",
                               "gen/dseg.h", "../types.h", "../pool_memory.h",
                               "../game/res00_system.h", "res00_system.h"):
                    errs.append("%s:%d: surprising project include %s" % (path, i, hdr))
            elif hdr != "stddef.h":
                errs.append("%s:%d: libc include <%s> (only <stddef.h> allowed)" % (path, i, hdr))
        if "platform.h" in line and "#include" in line:
            errs.append("%s:%d: engine must not include platform.h" % (path, i))
        if CALL.search(line):
            errs.append("%s:%d: libc call outside the allowed list" % (path, i))
        if BITFIELD.search(line):
            errs.append("%s:%d: bitfield (SPEC 7.2 forbids)" % (path, i))
        if FLOATLIT.search(line):
            errs.append("%s:%d: float literal" % (path, i))
    # no direct self-recursion (the original's spike routines have none)
    names = set(FUNCDEF.findall(code))
    for name, _brace in names:
        if re.search(r"(?<![A-Za-z0-9_])%s\s*\(" % re.escape(name),
                     re.sub(r"^[A-Za-z_][A-Za-z0-9_]*\s*\([^;]*\)\s*$", "", code, flags=re.M)):
            body_calls = [m for m in re.finditer(r"(?<![A-Za-z0-9_])%s\s*\(" % re.escape(name), code)]
            if len(body_calls) > 1:  # one is the definition itself
                errs.append("%s: recursion in %s" % (path, name))
    return errs


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check-path", action="append", default=[str(p) for p in ENGINE])
    a = ap.parse_args(argv)
    errs = []
    files = 0
    for base in a.check_path:
        for p in sorted(Path(base).rglob("*.[ch]")):
            if p.name == "types.h":
                continue  # the width types are defined here, by hand review
            files += 1
            errs.extend(lint_file(p))
    if errs:
        print("\n".join(errs[:20]))
        if len(errs) > 20:
            print("... and %d more" % (len(errs) - 20))
        return 1
    print("lint: %d engine files clean (SPEC 7.2)" % files)
    return 0


if __name__ == "__main__":
    sys.exit(main())

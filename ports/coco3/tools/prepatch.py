#!/usr/bin/env python3
"""prepatch.py: take the dead initialisation out of the translation before the DGROUP layout is made (HEAP-STUDY.md, option 3).

  prepatch.py GEN_DIR      GEN_DIR from pas2c --profile coco (edited in place)

StartGame (ovl11) fills tables of the PC's video hardware that the CoCo never reads (the engine owns the screen): the dirty-row
tables of the EGA planes and the scanline tables of the CGA, EGA and Tandy modes. Nothing but that routine names them, but
because it does, mkplan puts 800 bytes of them in native memory (they are written 200 times each: a high count of references)
and mkvm gives the rest 1,176 + 400 bytes of paged space. With the stores gone no unit names the globals, and mkvm drops them.
The patterns are matched exactly: a change of the translator that moves them is an error here, not a silent miss."""
import re
import sys
from pathlib import Path

ROWS = [("PA_u8_168", "4A28", "0xA8", "0"), ("PA_u16_168", "4AD0", "0x150", "0"),
        ("PA_u16_168", "4C20", "0x150", "0xFF"), ("PA_u16_168", "4D70", "0x150", "0")]
LOOP = re.compile(r"  \{\n    \{\n      LoaderLoopIndex = 0;\n      for \(;;\) \{\n"
                  r"          if \(LoaderLoopIndex & 1\) \{\n            CgaScanlineSegments.*?"
                  r"        if \(LoaderLoopIndex == LastScanline\) break;\n        LoaderLoopIndex\+\+;\n      \}\n    \}\n  \}\n", re.S)


def strip_dead_init(text):
    for ty, addr, n, v in ROWS:
        line = "  rtl_FillChar((void *)((struct %s *)(pool_ds + 0x%s)), %s, %s);\n" % (ty, addr, n, v)
        if text.count(line) != 1:
            raise SystemExit("prepatch: the FillChar of DS:%s is not in StartGame once" % addr)
        text = text.replace(line, "")
    m = LOOP.search(text)
    if not m:
        raise SystemExit("prepatch: the scanline table loop of StartGame is not where it was")
    body = m.group(0)
    for name in ("CgaScanlineSegments", "EgaScanlineOffsets", "TandyScanlineSegments"):
        if name not in body:
            raise SystemExit("prepatch: %s is not stored in the loop" % name)
    return text[:m.start()] + text[m.end():]


def main(argv):
    f = Path(argv[1]) / "ovl11.c"
    t = f.read_text()
    f.write_text(strip_dead_init(t))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""scr4png.py IN.scr4 OUT.png: a 4bpp screen dump (32,000 bytes packed 4 bits a pixel, high nibble left, then the
16 EGA palette register values) as a PNG, to look at a golden."""
import sys

sys.path.insert(0, __file__.rsplit("/ports/", 1)[0] + "/tools")
from oracle.ega import ega_rgb, write_png  # noqa: E402

d = open(sys.argv[1], "rb").read()
pal = [ega_rgb(v) for v in d[32000:32016]]
rgb = bytearray()
for b in d[:32000]:
    rgb += bytes(pal[b >> 4]) + bytes(pal[b & 15])
write_png(sys.argv[2], 320, 200, bytes(rgb))

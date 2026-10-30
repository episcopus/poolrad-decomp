#!/usr/bin/env python3
"""sheet.py: the shots of a func.py run side by side, labelled, in one PNG (for looking at a session quickly).

  .venv/bin/python ports/dos/tools/sheet.py build/func/ref/<session> [-o out.png]"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

d = Path(sys.argv[1])
out = Path(sys.argv[sys.argv.index("-o") + 1]) if "-o" in sys.argv else d.with_suffix(".sheet.png")
shots = sorted(d.glob("*.png"), key=lambda p: p.stat().st_mtime)
cols = 3
w, h = 320, 214
sheet = Image.new("RGB", (cols * w, ((len(shots) + cols - 1) // cols) * h), "white")
draw = ImageDraw.Draw(sheet)
for i, p in enumerate(shots):
    x, y = (i % cols) * w, (i // cols) * h
    sheet.paste(Image.open(p).convert("RGB"), (x, y + 14))
    draw.text((x + 4, y + 1), p.stem, fill="black")
sheet.save(out)
print(out)

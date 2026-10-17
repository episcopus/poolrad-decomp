#!/usr/bin/env python3
"""montage.py: several screenshots in one picture (fewer images to look at).  montage.py OUT.png A.png B.png ..."""
import sys
from PIL import Image, ImageDraw

out, files = sys.argv[1], sys.argv[2:]
imgs = [Image.open(f).convert("RGB") for f in files]
w, h = imgs[0].size
cols = 2 if len(imgs) > 1 else 1
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w * 2, rows * (h * 2 + 12)), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(zip(files, imgs)):
    x, y = (i % cols) * w * 2, (i // cols) * (h * 2 + 12)
    sheet.paste(im.resize((w * 2, h * 2), Image.NEAREST), (x, y + 12))
    d.text((x + 2, y), f.rsplit("/", 1)[-1], fill=(255, 255, 0))
sheet.save(out)

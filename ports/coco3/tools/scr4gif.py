#!/usr/bin/env python3
"""scr4gif.py PREFIX OUT.gif: the screens the harness kept (PREFIX-sNN.scr4, lua/watch.lua) as an animated GIF, in the order the game
showed them, twice the size, with the labels of the golden's screens when PREFIX names a session (make game-view). Needs Pillow."""
import glob
import sys

sys.path.insert(0, __file__.rsplit("/ports/", 1)[0] + "/tools")
from oracle.ega import ega_rgb  # noqa: E402
from PIL import Image  # noqa: E402


def frame(path):
    d = open(path, "rb").read()
    pal = [ega_rgb(v) for v in d[32000:32016]]
    rgb = bytearray()
    for b in d[:32000]:
        rgb += bytes(pal[b >> 4]) + bytes(pal[b & 15])
    return Image.frombytes("RGB", (320, 200), bytes(rgb)).resize((640, 400), Image.NEAREST)


def main():
    prefix, out = sys.argv[1], sys.argv[2]
    files = sorted(glob.glob(prefix + "-s*.scr4"))
    if not files:
        raise SystemExit("scr4gif: no screens under " + prefix)
    frames = [frame(f) for f in files]
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=900, loop=0)
    print("scr4gif: %d screens -> %s" % (len(frames), out))


if __name__ == "__main__":
    main()

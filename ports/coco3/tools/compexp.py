#!/usr/bin/env python3
"""compexp.py: what compression would make of every entry of the image (step 8.10c), as sizes: the input of the layout experiments (tools/mklayout.py --sizes).

  compexp.py MODEL.json IMAGE OUT.json      (inside the toolchain: needs `zx0`; the image is the one without shared blocks the model describes)

For every entry (file/id):
  none     the bytes as the image stores them (a DAX block run length coded by the original, a bank or the core raw)
  zx0      those bytes through ZX0 (the decoder of tools/zxbench: 68 cycles an output byte on the 6809)
  zx0raw   a DAX block unpacked first and then through ZX0 (what a build that replaced the original's RLE would store); the same as zx0 for what is raw
  raw      the unpacked size (what the game gets)"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, os.path.join(os.environ.get("REPO", str(HERE.parent.parent.parent)), "tools/re"))
import dax  # noqa: E402


def zx0(data, tmp):
    if not data:
        return 0
    src = Path(tmp) / "in.bin"
    dst = Path(tmp) / "in.bin.zx0"
    src.write_bytes(data)
    dst.unlink(missing_ok=True)
    subprocess.run(["zx0", "-f", str(src), str(dst)], check=True, capture_output=True)
    return dst.stat().st_size


def main(model_path, image_path, out):
    model = json.loads(Path(model_path).read_text())
    img = Path(image_path).read_bytes()
    res = {}
    with tempfile.TemporaryDirectory() as tmp:
        for e in model["entries"]:
            blk = img[e["off"]:e["off"] + e["size"]]
            raw = blk if e["kind"] == 1 or e["file"] == "DGROUP" else dax.unrle(blk)
            res["%s/%d" % (e["file"], e["id"])] = dict(none=e["size"], zx0=zx0(blk, tmp), zx0raw=zx0(raw, tmp), raw=len(raw))
    Path(out).write_text(json.dumps(res))
    tot = {k: sum(v[k] for v in res.values()) for k in ("none", "zx0", "zx0raw", "raw")}
    print("compexp: %d entries; bytes: stored %d, ZX0 of the stored %d, ZX0 of the unpacked %d, unpacked %d" % (len(res), tot["none"], tot["zx0"], tot["zx0raw"], tot["raw"]))


if __name__ == "__main__":
    main(*sys.argv[1:4])

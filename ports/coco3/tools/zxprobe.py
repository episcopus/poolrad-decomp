#!/usr/bin/env python3
"""zxprobe.py SAMPLE...: make build/run/zx/zxdata.h for probes/zxbench.c from one sample file (compressed by the zx0 of the coco-dev image, build/run/zx/run.sh),
or, after `make probe P=zxbench`, read the checkpoint times of the run and print the decoder's speed.
  zxprobe.py make FILE            FILE and FILE.zx0 -> the header (the sum of the raw bytes is what the probe must find)
  zxprobe.py time FILE            FILE as above plus build/run/zxbench-mame.cp -> cycles per output byte at 1.789773 MHz"""
import sys

mode, f = sys.argv[1], sys.argv[2]
raw = open(f, "rb").read()
if mode in ("makelz4", "timelz4"):                      # a block of `lz4 -9 -c --no-frame-crc FILE > FILE.lz4`: magic, FLG, BD, HC (7 bytes, no content size), then size and data
    d = open(f + ".lz4", "rb").read()
    n = int.from_bytes(d[7:11], "little")
    comp = d[11:11 + n]
    mode = mode[:-3] if mode == "timelz4" else "make"
    if sys.argv[1] == "timelz4":
        mode = "time"
else:
    comp = open(f + ".zx0", "rb").read()
if mode == "make":
    h = ["#define ZX_RAW %d" % len(raw), "#define ZX_COMP %d" % len(comp), "#define ZX_SUM %d" % (sum(raw) & 0xFFFF),
         "static const unsigned char zx_comp[] = {"]
    for i in range(0, len(comp), 16):
        h.append(",".join("%d" % b for b in comp[i:i + 16]) + ",")
    h.append("};")
    open("build/run/zx/zxdata.h", "w").write("\n".join(h) + "\n")
    print("raw %d, compressed %d, sum %d (%04X)" % (len(raw), len(comp), sum(raw) & 0xFFFF, sum(raw) & 0xFFFF))
else:
    t = {}
    for line in open("build/run/%s-mame.cp" % ("lz4bench" if sys.argv[1] == "timelz4" else "zxbench")):
        c, s = line.split()
        t[int(c)] = float(s)
    dt = (t[3] - t[2]) / 50
    print("one decode %.4f s = %.0f cycles = %.1f cycles per output byte, %.1f KB/s of output, %.1f KB/s of input" % (
        dt, dt * 1789772.7, dt * 1789772.7 / len(raw), len(raw) / 1024 / dt, len(comp) / 1024 / dt))

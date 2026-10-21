#!/bin/bash
cd $(dirname "$0")/../..
lz4 -9 -c --no-frame-crc "$1" > "$1.lz4"
python3 tools/zxprobe.py makelz4 "$1" || exit 1
rm -f build/probe/lz4bench.o build/probe/lz4bench.bin build/probe/lz4bench.dsk
make probe P=lz4bench 2>&1 | grep -E "ERROR|TIMEOUT|status 1|  r[013] " | head -5
python3 tools/zxprobe.py timelz4 "$1"

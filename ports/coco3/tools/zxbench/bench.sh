#!/bin/bash
# bench.sh FILE: time the ZX0 decoder on a sample (FILE and FILE.zx0 exist)
cd $(dirname "$0")/../..
python3 tools/zxprobe.py make "$1" || exit 1
rm -f build/probe/zxbench.o build/probe/zxbench.bin build/probe/zxbench.dsk
make probe P=zxbench 2>&1 | grep -E "ERROR|TIMEOUT|status 1|  r[013] " | head -5
python3 tools/zxprobe.py time "$1"

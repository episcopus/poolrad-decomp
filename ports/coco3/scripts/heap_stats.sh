#!/usr/bin/env bash
# DGROUP and heap measurements over the recorded sessions (step 8.1, host side).
# Builds a heap-stats copy of the Phase 7 C game (build/cmake-heap in the repository root: the
# opt-in POOL_HEAP_STATS code of c/rtl/heap.c), replays every session of build/c/replay (run
# `make c-golden` in the repository root first if that directory is empty) and prints the heap
# peak, the live blocks at exit and which DGROUP bytes the sessions changed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
ls build/c/replay/*.rpl >/dev/null 2>&1 || { echo "no replay files: run 'make c-golden' in $ROOT first" >&2; exit 1; }
cmake -S . -B build/cmake-heap -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS=-DPOOL_HEAP_STATS >/dev/null
cmake --build build/cmake-heap -j --target poolrad_replay >/dev/null 2>&1
mkdir -p build/c/heapstats
for f in build/c/replay/*.rpl; do
  n="$(basename "$f" .rpl)"
  echo "-- $n"
  POOL_DGROUP_DUMP="build/c/heapstats/$n.dgroup" build/cmake-heap/poolrad_replay \
    --data poolrad --save build/c/save "$f" 2>&1 >/dev/null | grep -E "HEAPSTATS (peak|live at exit)" | cut -c1-260
done
python3 ports/coco3/tools/dgroup_stats.py . build/c/heapstats/*.dgroup

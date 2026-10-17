#!/usr/bin/env bash
# Build the profiling copy of the C game and replay the recorded sessions on it (step 8.1c, host).
# Writes build/prof/<session>.prof in the repository root; tools/prof_report.py reads them.
# Needs build/c/replay/*.rpl (run `make c-golden` in the repository root once).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
ls build/c/replay/*.rpl >/dev/null 2>&1 || { echo "no replay files: run 'make c-golden' in $ROOT first" >&2; exit 1; }
python3 ports/coco3/tools/mkprof.py . build/prof
FLAGS="-O2 -w -std=gnu11 -fno-strict-aliasing -fwrapv -DPOOL_PROFILE -DPOOL_HEAP_STATS -Ibuild/prof/include -Ic/include -Ibuild/prof/game"
mkdir -p build/prof/obj
objs=()
build() {   # build SRC [extra flags]
  local o="build/prof/obj/$(echo "$1" | tr '/' '_').o"
  clang $FLAGS ${2:-} -c "$1" -o "$o" && objs+=("$o")
}
for f in c/rtl/core.c c/rtl/heap.c c/rtl/file.c c/rtl/crt.c c/rtl/ega.c c/rtl/sha256.c c/rtl/soundtrace.c \
         c/driver/res03_driver.c c/platform/replay.c ports/coco3/prof/prof_rt.c; do build "$f"; done
for f in build/prof/game/*.c; do
  case "$f" in */image.c) build "$f";; *) build "$f" -finstrument-functions;; esac
done
clang "${objs[@]}" -lm -o build/prof/poolrad_prof
for f in build/c/replay/*.rpl; do
  n="$(basename "$f" .rpl)"
  POOL_PROF_OUT="build/prof/$n.prof" build/prof/poolrad_prof --data poolrad --save build/c/save "$f" 2>&1 \
    | grep -E "ok:|diverged" | cut -c1-160 || true
done
ls -l build/prof/*.prof | awk '{print $5, $9}'

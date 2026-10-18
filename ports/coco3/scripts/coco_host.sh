#!/usr/bin/env bash
# The CoCo profile on the host (step 8.2): translate with `pas2c.py --profile coco`, build the game with clang
# against the host runtime and replay every recorded session. Passing means the profile's output computes what
# the PC profile's does (the full state of the game is compared at every checkpoint, as in Phase 7).
# Needs build/c/replay/*.rpl (run `make c-golden` in the repository root once).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
ls build/c/replay/*.rpl >/dev/null 2>&1 || { echo "no replay files: run 'make c-golden' in $ROOT first" >&2; exit 1; }
PY=python3; [ -x .venv/bin/python ] && PY=.venv/bin/python
rm -rf build/gen-pc && $PY tools/c/pas2c.py --out build/gen-pc >/dev/null
diff -rq build/gen-pc c/game >/dev/null && echo "the PC profile still writes c/game exactly" || { echo "the PC profile's output differs from c/game" >&2; exit 1; }
$PY tools/c/pas2c.py --profile coco --out build/gen-coco | tail -1
cmake -S . -B build/cmake-coco -DCMAKE_BUILD_TYPE=Release -DPOOLRAD_GAME_DIR="$ROOT/build/gen-coco" >/dev/null
cmake --build build/cmake-coco -j --target poolrad_replay 2>&1 | grep -E "error|warning: unused" || true
rc=0
for f in build/c/replay/*.rpl; do
  build/cmake-coco/poolrad_replay --data poolrad --save build/c/save "$f" 2>&1 | tail -1 | cut -c1-150 || rc=1
done
exit $rc

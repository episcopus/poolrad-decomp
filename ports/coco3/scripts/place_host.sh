#!/usr/bin/env bash
# The CoCo placement model on the host (step 8.2): translate with --profile coco --placement, build with
# -DPOOL_PLACEMENT (the mapped heap inside the DGROUP segment, FPB counting window maps) and replay the sessions.
# The memory layout of the game differs from the original's on purpose, so what is compared is what the player and the
# disk see: the reads in order, the screen at every checkpoint, the Random calls and the files written (poolrad_replay
# --screens-only skips only the byte comparison of the game's state).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
# the replay files of the placement model: the same recordings with the heap pointer fields of saved records masked
# (tools/c/export_replay.py --pointer-masks; the oracle takes about a minute a session)
if ! ls build/c/replay-place/*.rpl >/dev/null 2>&1; then
  PYX=python3; [ -x .venv/bin/python ] && PYX=.venv/bin/python
  for f in tests/sessions/*.keys; do $PYX tools/c/export_replay.py "$(basename "$f" .keys)" --out-dir build/c/replay-place --pointer-masks; done
fi
PY=python3; [ -x .venv/bin/python ] && PY=.venv/bin/python
$PY tools/c/pas2c.py --profile coco --placement ports/coco3/placement.toml --out build/gen-place | tail -2
cmake -S . -B build/cmake-place -DCMAKE_BUILD_TYPE=Release -DPOOLRAD_GAME_DIR="$ROOT/build/gen-place" -DCMAKE_C_FLAGS=-DPOOL_PLACEMENT -DCMAKE_C_FLAGS_RELEASE=-O2 >/dev/null   # -O3 exposes a latent out-of-bounds read (ovl25:115, index -1) as a crash in parley-combat
cmake --build build/cmake-place -j --target poolrad_replay 2>&1 | grep -E "error" || true
mkdir -p build/c/g4
rc=0
for f in build/c/replay-place/*.rpl; do
  n="$(basename "$f" .rpl)"
  POOL_PLACEMENT_STATS=1 build/cmake-place/poolrad_replay --data poolrad --save build/c/save --screens-only \
    --screens4 "build/c/g4/$n.place.s4" "$f" 2>&1 | grep -E "ok:|FAIL|diverged|PLACEMENT|error" | cut -c1-200 || rc=1
  cmp -s "build/c/g4/$n.place.s4" "ports/coco3/goldens/4bpp/$n.s4" && echo "[$n] the 4bpp screens equal the goldens" || { echo "[$n] the 4bpp screens DIFFER from the goldens" >&2; rc=1; }
done
exit $rc

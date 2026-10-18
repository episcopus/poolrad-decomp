#!/usr/bin/env bash
# The CoCo layout of DGROUP on the host (step 8.5b): translate with --profile coco --placement, lay the globals out
# (tools/mkplan.py chooses the native ones from the profiles, tools/mkvm.py rewrites the game), build with
# -DPOOL_PLACEMENT -DPOOL_VM (c/rtl/vm.c models the two data windows and counts the accessor calls) and replay the sessions.
# As in place_host.sh what is compared is what the player and the disk see: the reads in order, the screen at every
# checkpoint, the Random calls and the files written, and the 4bpp screens against ports/coco3/goldens/4bpp.
# NATIVE_BUDGET (default 6000) is the size of the globals kept in native memory.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
PY=python3; [ -x .venv/bin/python ] && PY=.venv/bin/python
if ! ls build/c/replay-place/*.rpl >/dev/null 2>&1; then
  for f in tests/sessions/*.keys; do $PY tools/c/export_replay.py "$(basename "$f" .keys)" --out-dir build/c/replay-place --pointer-masks; done
fi
$PY tools/c/pas2c.py --profile coco --placement ports/coco3/placement.toml --out build/gen-vm0 | tail -1
python3 ports/coco3/tools/mkplan.py "$ROOT" build/gen-vm0 "${NATIVE_BUDGET:-6000}" > ports/coco3/placement-vm.toml
$PY ports/coco3/tools/mkvm.py build/gen-vm0 ports/coco3/placement-vm.toml build/gen-vm
cmake -S . -B build/cmake-vm -DCMAKE_BUILD_TYPE=Release -DPOOLRAD_GAME_DIR="$ROOT/build/gen-vm" -DCMAKE_C_FLAGS="-DPOOL_PLACEMENT -DPOOL_VM" -DCMAKE_C_FLAGS_RELEASE=-O2 >/dev/null
cmake --build build/cmake-vm -j --target poolrad_replay 2>&1 | grep -E "error" || true
mkdir -p build/c/g4
rc=0
for f in build/c/replay-place/*.rpl; do
  n="$(basename "$f" .rpl)"
  POOL_VM_STATS=1 POOL_PLACEMENT_STATS=1 build/cmake-vm/poolrad_replay --data poolrad --save build/c/save --screens-only \
    --screens4 "build/c/g4/$n.vm.s4" "$f" 2>&1 | grep -E "ok:|FAIL|diverged|PLACEMENT|VMSTATS|error|fatal" | cut -c1-200 || rc=1
  cmp -s "build/c/g4/$n.vm.s4" "ports/coco3/goldens/4bpp/$n.s4" && echo "[$n] the 4bpp screens equal the goldens" || { echo "[$n] the 4bpp screens DIFFER from the goldens" >&2; rc=1; }
done
exit $rc

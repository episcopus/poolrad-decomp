#!/usr/bin/env bash
# Build the game of the CoCo port (step 8.5c), inside the toolchain: translate the Pascal with the coco profile and the
# placement, lay DGROUP out (tools/mkplan.py, tools/mkvm.py), compile, split and link (tools/mkgame.py).
# Output: build/game/ (core.bin, bankNN images through banks.json, the map, missing.txt: what is not written yet).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO="${REPO:-../..}"
GEN="${GEN:-build/gen}"
mkdir -p "$GEN"
python3 "$REPO/tools/c/pas2c.py" --profile coco --placement placement.toml --peek-pointers --out "$GEN/pre" | tail -1
python3 tools/prepatch.py "$GEN/pre"   # the dead initialisation of the PC's video tables (docs/HEAP-STUDY.md): 2,000 bytes of DGROUP less
python3 tools/mkplan.py "$REPO" "$GEN/pre" "${NATIVE_BUDGET:-1300}" > placement-coco.toml
REPO="$REPO" python3 tools/mkvm.py --coco "$GEN/pre" placement-coco.toml "$GEN/vm"
REPO="$REPO" python3 tools/mkgame.py "$GEN/vm" build/game --link

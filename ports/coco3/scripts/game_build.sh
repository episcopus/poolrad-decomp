#!/usr/bin/env bash
# Build the game of the CoCo port (step 8.5c), inside the toolchain: translate the Pascal with the coco profile and the
# placement, lay DGROUP out (tools/mkplan.py, tools/mkvm.py), compile, split and link (tools/mkgame.py).
# Output: build/game/ (core.bin, bankNN images through banks.json, the map, missing.txt: what is not written yet).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO="${REPO:-../..}"
GEN="${GEN:-build/gen}"
mkdir -p "$GEN"
python3 "$REPO/tools/c/pas2c.py" --profile coco --placement placement.toml --out "$GEN/pre" | tail -1
python3 tools/mkplan.py "$REPO" "$GEN/pre" "${NATIVE_BUDGET:-6000}" > placement-vm.toml
REPO="$REPO" python3 tools/mkvm.py "$GEN/pre" placement-vm.toml "$GEN/vm"
REPO="$REPO" python3 tools/mkgame.py "$GEN/vm" build/game --link

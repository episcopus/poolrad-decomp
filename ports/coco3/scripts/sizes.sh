#!/usr/bin/env bash
# Translate the Pascal with the coco profile and compile every unit with CMOC, tabulating the 6809 sizes (steps 8.1, 8.2).
# Runs inside the toolchain (`make sizes` does that): the shim and the translated units go to build/m, the tables to
# build/m/table-*.txt. Variants: base (-O2), fofp (-fomit-frame-pointer), o1 (-O1) and place (the placement of
# placement.toml: mapped pointers are native 16-bit addresses, banked ones go through an accessor).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO="${REPO:-../..}"
mkdir -p build/m/shim
python3 tools/mkshim.py "$REPO/c/include/pool.h" build/m/shim/pool.h
translate() { python3 "$REPO/tools/c/pas2c.py" --profile coco ${1:+--placement "$PWD/placement.toml"} --out build/m/game | tail -1; }
variant() {  # tag flags
  echo "### CMOC -O2 $2  (tag $1)"
  CMOC_EXTRA="$2" SIZES_TAG="-$1" python3 tools/unitsizes.py "$REPO" build/m > "build/m/table-$1.txt" 2>&1 || true
  grep -E "^(total|FAILED)" "build/m/table-$1.txt" || true
}
translate ""
variant fofp "-fomit-frame-pointer"
variant o1 "-O1"
variant base ""
python3 tools/unitgraph.py build/m "$REPO" | tee build/m/graph.txt
translate place
variant place ""
echo "tables: build/m/table-{base,fofp,o1,place}.txt; graph: build/m/graph.txt"

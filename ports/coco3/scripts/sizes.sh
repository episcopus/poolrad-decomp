#!/usr/bin/env bash
# Compile every generated unit of ../../c/game with CMOC and tabulate the 6809 sizes (step 8.1).
# Runs inside the toolchain (`make sizes` does that): the shim and the transformed units go to
# build/m, the table to build/m/sizes-*.tsv.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO="${REPO:-../..}"
mkdir -p build/m/shim
python3 tools/mkshim.py "$REPO/c/include/pool.h" build/m/shim/pool.h
python3 tools/cmocify.py "$REPO/c/game" build/m/game
for spec in "base|" "fofp|-fomit-frame-pointer" "o1|-O1"; do
  tag="${spec%%|*}"; fl="${spec##*|}"
  echo "### CMOC -O2 $fl  (tag $tag)"
  CMOC_EXTRA="$fl" SIZES_TAG="-$tag" python3 tools/unitsizes.py "$REPO" build/m > "build/m/table-$tag.txt" 2>&1 || true
  grep -E "^(total|FAILED)" "build/m/table-$tag.txt" || true
done
# the objects of the last variant are -O1: rebuild the base ones the graph tool reads
python3 tools/unitsizes.py "$REPO" build/m > build/m/table-base.txt 2>&1 || true
python3 tools/unitgraph.py build/m "$REPO" | tee build/m/graph.txt
echo "tables: build/m/table-base.txt, table-fofp.txt, table-o1.txt; graph: build/m/graph.txt"

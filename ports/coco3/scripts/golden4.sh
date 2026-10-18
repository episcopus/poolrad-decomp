#!/usr/bin/env bash
# The 4bpp screen goldens of the port (step 8.2): per session, per checkpoint, the SHA-256 of the screen as the CoCo 3
# shows it (32,000 bytes packed 4 bits a pixel + the 16 palette register values), in goldens/4bpp/<session>.s4.
#   golden4.sh record   write them from the PC-profile host build (its screens equal the original's at every
#                       checkpoint: that is what poolrad_replay checks), then check them with the coco-profile build
#   golden4.sh check    replay every session on the PC-profile and the coco-profile host builds and compare
# Needs build/c/replay/*.rpl in the repository root (`make c-golden` there) and both host builds (`make coco-host`).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
mode="${1:-check}"
G=ports/coco3/goldens/4bpp
mkdir -p "$G" build/c/g4
cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build/cmake -j --target poolrad_replay >/dev/null 2>&1
bad=0
for f in build/c/replay/*.rpl; do
  n="$(basename "$f" .rpl)"
  for b in cmake cmake-coco; do
    [ -x "build/$b/poolrad_replay" ] || { echo "build/$b/poolrad_replay missing (make coco-host)" >&2; exit 1; }
    out="build/c/g4/$n.$b.s4"
    "build/$b/poolrad_replay" --data poolrad --save build/c/save --screens4 "$out" "$f" >/dev/null 2>&1 || { echo "$n: the replay on $b failed" >&2; bad=1; }
  done
  cmp -s "build/c/g4/$n.cmake.s4" "build/c/g4/$n.cmake-coco.s4" || { echo "$n: the PC and coco profiles show different screens" >&2; bad=1; }
  if [ "$mode" = record ]; then
    cp "build/c/g4/$n.cmake.s4" "$G/$n.s4"
    echo "$n: $(wc -l < "$G/$n.s4" | tr -d ' ') checkpoints recorded"
  else
    cmp -s "$G/$n.s4" "build/c/g4/$n.cmake-coco.s4" && echo "$n: $(wc -l < "$G/$n.s4" | tr -d ' ') checkpoints equal" || { echo "$n: the screens differ from goldens/4bpp/$n.s4" >&2; bad=1; }
  fi
done
exit $bad

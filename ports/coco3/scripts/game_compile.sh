#!/usr/bin/env bash
# Compile every unit of the CoCo build of the game with CMOC (step 8.5c), inside the toolchain: build/game/obj/<unit>.o and a
# size table. Needs build/gen-vm (scripts/vm_host.sh translates and lays out). Usage: game_compile.sh [unit ...]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
GEN="${GEN:-../../build/gen-vm}"
OUT=build/game
mkdir -p $OUT/obj $OUT/inc
cp "$GEN"/game.h "$GEN"/vmlayout.h $OUT/inc/
cp src/game/pool.h src/game/coco_map.h $OUT/inc/
units=("$@")
[ ${#units[@]} -eq 0 ] && units=($(cd "$GEN" && ls *.c | sed 's/\.c$//' | grep -v -E '^(image|poolvars)$'))
fail=0
for u in "${units[@]}"; do
  if cmoc -c --void-target --no-relocate -O2 -fomit-frame-pointer -w -Ishim -I$OUT/inc -I"$GEN" -o $OUT/obj/$u.o "$GEN/$u.c" > $OUT/obj/$u.log 2>&1; then
    printf "%-10s %6d\n" "$u" "$(lwobjdump $OUT/obj/$u.o | python3 -c 'import sys,re; print(sum(int(m,16) for m in re.findall(r"CODE ([0-9A-Fa-f]+) bytes", sys.stdin.read())))')"
  else
    echo "$u FAILED"; grep -i error $OUT/obj/$u.log | head -3; fail=1
  fi
done
exit $fail

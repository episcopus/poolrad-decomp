#!/usr/bin/env bash
# Run the game in headless XRoar (fast: a few seconds) until the engine or the game stops (mb_halt) and keep the RAM dump.
# Usage: scripts/game_xroar.sh out.ram [vol numbers...]   (program disk in drive 0, volumes in drives 1..)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
run_toolchain python3 -I tools/mkgamedisk.py build/game build/gen/vm/DGROUP.IMG build/game/pool.dsk > /dev/null
out="${1:?out.ram}"; shift || true
vols=(${@+"$@"}); [[ $# -gt 0 ]] || vols=(0)
fin=$(grep "^Symbol: ${XROAR_TRAP:-_eng_halt} " build/game/pool.map | sed 's/.*= //')
extra=(); n=1
for v in ${vols[@]+"${vols[@]}"}; do extra+=(-load-fd$n "build/data/vol$v.dsk"); n=$((n + 1)); done
rm -f "$out"
xroar -ui null -ao null -m coco3 -rompath roms -ram 512 -ram-init clear -tv-input rgb -no-ratelimit -cart rsdos \
  -no-disk-write-back -load-fd0 build/game/pool.dsk ${extra[@]+"${extra[@]}"} -load-fd2 build/game/bank1.dsk -load-fd3 build/game/bank2.dsk -type 'LOADM"POOL":EXEC\r' \
  -trap "pc=0x$fin" -trap-snap "$out" -trap-timeout 0 -timeout "${XROAR_SECONDS:-120}" >/dev/null 2>&1 || true
[[ -f "$out" ]] || { echo "game_xroar: the program never reached mb_halt" >&2; exit 1; }

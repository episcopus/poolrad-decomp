#!/usr/bin/env bash
# How long the game takes to boot from the floppy set in XRoar at its own speed (headless, real time): the wall clock seconds to the end of LOADM
# (the engine's `main`), to the game's first screen set-up (`gfx_init`) and to the first request for a disk (`prompt`; with disks 1 to 4 in the four
# drives). The emulated machine is deterministic, so the seconds are the player's. Usage: scripts/xroar_boot_times.sh [DISKDIR]   (default build/floppy/disks)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
d="${1:-build/floppy/disks}"
for sym in main gfx_init prompt; do
  a=$(grep -h "^Symbol: _$sym " build/game/pool.map | sed 's/.*= //')
  s=$(date +%s)
  xroar -ui null -ao null -m coco3 -rompath roms -ram 512 -ram-init clear -tv-input rgb -cart rsdos -no-disk-write-back \
    -load-fd0 "$d/POOL01.DSK" -load-fd1 "$d/POOL02.DSK" -load-fd2 "$d/POOL03.DSK" -load-fd3 "$d/POOL04.DSK" -type 'LOADM"POOL":EXEC\r' \
    -trap "pc=0x$a" -trap-timeout 0 -timeout 300 >/dev/null 2>&1 || true
  printf '%-9s %3d s\n' "$sym" $(( $(date +%s) - s ))
done

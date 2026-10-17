#!/usr/bin/env bash
# Run a DECB .bin in headless XRoar (coco3, 512K, cleared RAM) until the program reaches
# mb_halt, then keep XRoar's raw RAM dump. Usage: scripts/xroar_run.sh prog.bin prog.map out.ram
# The dump is physical memory in address order; tools/mbdump.py --ram reads the mailbox from it.
# Exit 77: xroar is not installed (the caller skips).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin="${1:?bin}"; map="${2:?linker map}"; out="${3:?out.ram}"
command -v xroar >/dev/null 2>&1 || { echo "xroar_run: xroar is not installed (brew install xroar), skipped" >&2; exit 77; }
[[ -f "$ROOT/roms/coco3.rom" ]] || { echo "roms/coco3.rom missing (README, ROMs)" >&2; exit 1; }
fin=$(grep '^Symbol: _mb_halt ' "$ROOT/$map" | sed 's/.*= //')
[[ -n "$fin" ]] || { echo "xroar_run: _mb_halt not in $map" >&2; exit 1; }
unlink "$ROOT/$out" 2>/dev/null || true
xroar -ui null -ao null -m coco3 -rompath "$ROOT/roms" -ram 512 -ram-init clear -tv-input rgb \
  -no-ratelimit -no-cart -run "$ROOT/$bin" -trap "pc=0x$fin" -trap-snap "$ROOT/$out" \
  -trap-timeout 0 -timeout "${XROAR_SECONDS:-60}" >/dev/null 2>&1 || true
[[ -f "$ROOT/$out" ]] || { echo "xroar_run: the program never reached mb_halt" >&2; exit 1; }

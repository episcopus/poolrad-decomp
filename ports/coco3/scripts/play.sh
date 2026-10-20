#!/usr/bin/env bash
# Play the game in a MAME window on the host (step 8.8b): scripts/play.sh [--fast N] [--fresh]
#   the program disk and the container image are built by `make play` first; the host needs MAME (brew install mame) and roms/coco3.zip.
#   --fast N   overclock the CPU N times (MAME's -oc): the game's animations and the AI's turns take 5 to 8 s on a real 1.79 MHz machine
#   --fresh    forget the saved games (deletes build/play/saves.ovl)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
oc=(); fresh=
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) oc=(-oc ":maincpu" "$2"); shift 2 ;;
    --fresh) fresh=1; shift ;;
    *) echo "usage: scripts/play.sh [--fast N] [--fresh] " >&2; exit 2 ;;
  esac
done
command -v mame >/dev/null 2>&1 || { echo "MAME is not on the host's PATH (brew install mame)" >&2; exit 1; }
[ -f build/game/pool.dsk ] && [ -f build/game/pool.img ] || { echo "build/game/pool.dsk or pool.img missing: run make play" >&2; exit 1; }
mkdir -p build/play/cfg build/play/nvram
[ -z "$fresh" ] || unlink build/play/saves.ovl 2>/dev/null || true
echo "Playing. The code wheel question: its code word is printed here. Keys: the host keyboard is the CoCo's (arrows, Enter, Esc = BREAK). Close the window to quit; saved games are kept in build/play/saves.ovl."
syms=$(for n in kq kq_tail wheel_pick; do printf '%s=%s,' $n $(grep -h "^Symbol: _$n " build/game/pool.map build/game/core.map | head -1 | sed 's/.*= //'); done)
MB_IMG="$ROOT/build/game/pool.img" MB_OVL="$ROOT/build/play/saves.ovl" MB_SYMS="$syms" \
  exec mame coco3 -rompath "$ROOT/roms" -ramsize 512K -flop1 "$ROOT/build/game/pool.dsk" \
    -window -nomaximize -skip_gameinfo -nvram_directory "$ROOT/build/play/nvram" -cfg_directory "$ROOT/build/play/cfg" \
    ${oc[@]+"${oc[@]}"} -autoboot_script "$ROOT/lua/play.lua"

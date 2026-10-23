#!/usr/bin/env bash
# Play the game in a MAME window on the host (step 8.8b): scripts/play.sh [--cpu 6809|6309] [--fast N] [--fresh] [--keylog]
#   the program disk and the container image are built by `make play` first; the host needs MAME (brew install mame) and roms/coco3.zip.
#   --cpu 6309 MAME's HD6309 machine (coco3h) instead of the stock 6809 (coco3): the same disk and image, the engine finds the 6309 at boot and runs it
#              in native mode (step 8.9h); the splash says which CPU it found. For judging the speed: play the same thing on both.
#   --fast N   overclock the CPU N times (MAME's -oc): the game's animations and the AI's turns take 5 to 8 s on a real 1.79 MHz machine
#   --keylog   print every key code the game is given (to tell what was pressed from what the game received)
#   --fresh    forget the saved games (deletes build/play/saves.ovl)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
oc=(); fresh=; keylog=; machine=coco3
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) oc=(-oc ":maincpu" "$2"); shift 2 ;;
    --cpu) case "$2" in 6809) machine=coco3 ;; 6309) machine=coco3h ;; *) echo "--cpu is 6809 or 6309" >&2; exit 2 ;; esac; shift 2 ;;
    --fresh) fresh=1; shift ;;
    --keylog) keylog=1; shift ;;
    *) echo "usage: scripts/play.sh [--cpu 6809|6309] [--fast N] [--fresh] [--keylog]" >&2; exit 2 ;;
  esac
done
command -v mame >/dev/null 2>&1 || { echo "MAME is not on the host's PATH (brew install mame)" >&2; exit 1; }
[ -f build/game/pool.dsk ] && [ -f build/game/pool.img ] || { echo "build/game/pool.dsk or pool.img missing: run make play" >&2; exit 1; }
mkdir -p build/play/cfg build/play/nvram
if [ "$machine" = coco3h ]; then       # MAME's coco3h does not find the ROMs in coco3.zip: a folder named after it, made once from the same ROMs
  if [ ! -f roms/coco3h/coco3.rom ] || [ ! -f roms/coco3h/disk11.rom ]; then
    mkdir -p roms/coco3h
    if [ -f roms/coco3.rom ] && [ -f roms/disk11.rom ]; then cp roms/coco3.rom roms/disk11.rom roms/coco3h/
    elif [ -f roms/coco3.zip ]; then unzip -o -q roms/coco3.zip coco3.rom disk11.rom -d roms/coco3h || { echo "play: roms/coco3.zip lacks coco3.rom or disk11.rom" >&2; exit 1; }
    else echo "play: roms/coco3.rom and roms/disk11.rom (or coco3.zip) are needed for --cpu 6309" >&2; exit 1; fi
  fi
  echo "Machine: coco3h (HD6309): the engine should run it in native mode (the splash says so)."
fi
[ -z "$fresh" ] || unlink build/play/saves.ovl 2>/dev/null || true
# the monitor type is a saved setting too: composite (MAME's default) turns the game's RGB palette into pink and green
for cfg in build/play/cfg/coco3.cfg build/play/cfg/coco3h.cfg; do if [ -f "$cfg" ]; then sed -i.bak 's/\(tag=":screen_config"[^>]*value=\)"0"/\1"1"/' "$cfg"; rm -f "$cfg.bak"; fi; done
# the saved games must still fit the image (tools/savecheck.py); a warning, not a stop: --fresh forgets them
if [ -s build/play/saves.ovl ] && head -c 4 build/play/saves.ovl | grep -q POVL; then
  python3 tools/savecheck.py build/game/pool.img build/play/saves.ovl || echo "play: the saved games above do not match the game's save area: start with --fresh (make play FRESH=1) if the game misbehaves" >&2
fi
echo "Playing. The code wheel question: its code word is printed here. Keys: the host keyboard is the CoCo's (arrows, Enter, Esc = BREAK). Close the window to quit; saved games are kept in build/play/saves.ovl."
syms=$(for n in kq kq_tail wheel_pick; do printf '%s=%s,' $n $(grep -h "^Symbol: _$n " build/game/pool.map build/game/core.map | head -1 | sed 's/.*= //'); done)
exec env MB_IMG="$ROOT/build/game/pool.img" MB_OVL="$ROOT/build/play/saves.ovl" MB_SYMS="$syms" ${keylog:+MB_KEYLOG=1} \
  mame $machine -rompath "$ROOT/roms" -ramsize 512K -flop1 "$ROOT/build/game/pool.dsk" \
    -window -nomaximize -skip_gameinfo -nvram_directory "$ROOT/build/play/nvram" -cfg_directory "$ROOT/build/play/cfg" \
    ${oc[@]+"${oc[@]}"} -autoboot_script "$ROOT/lua/play.lua"

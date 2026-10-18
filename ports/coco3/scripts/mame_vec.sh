#!/usr/bin/env bash
# One-off: what MAME's CPU sees in the vector page after BASIC has booted (lua/vec.lua).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
run_toolchain mame coco3 -rompath /work/roms -pluginspath /usr/local/share/mame/plugins -ramsize 512K -flop1 /work/build/eng/t_gfx.dsk \
  -video none -sound none -nothrottle -skip_gameinfo -nvram_directory /tmp/nvram -cfg_directory /tmp/cfg \
  -autoboot_script /work/lua/vec.lua -seconds_to_run 10 2>&1 | grep -E "FEE0|FFF0"

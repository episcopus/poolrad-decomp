#!/usr/bin/env bash
# A session of the game from the IDE card file on MAME's own Glenside IDE adapter (not lua/watch.lua's model of it: scripts/ide_run.sh does that), in headless MAME:
# `-ext ide` takes the cartridge slot (no Disk BASIC), the card file is a hard disk image (a CHD made from build/ide-xroar/POOLIDE.IMG by chdman) and the engine is
# put into memory by lua/watch.lua (MB_BIN). Needs `make ide-xroar-build` (the card file from sector 0). Usage: scripts/ide_mame_run.sh OUT-PREFIX   Environment: MB_SESSION, MB_LIMIT, MB_MACHINE
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
out="${1:?output prefix}"
cd "$ROOT"
d=build/ide-xroar
[ -f "$d/POOLIDE.IMG" ] || { echo "ide_mame_run: $d/POOLIDE.IMG missing: run make ide-xroar-build" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
rm -f "$out"-s*.scr4 "$out.mbx"
limit="${MB_LIMIT:-120}"
# a private copy of the card (the game writes its saves into it)
run_toolchain sh -c "rm -f $out-card.chd; chdman createhd -i $d/POOLIDE.IMG -o $out-card.chd -chs 60,1,63 -ss 512 >/dev/null 2>&1"
syms=$(for n in kq kq_head kq_tail rand_seed wheel_pick pics pic_live eng_idx; do printf '%s=%s,' $n $(grep -h "^Symbol: _$n " $d/engine/pool.map build/game/core.map | head -1 | sed 's/.*= //'); done)
tr=$(grep '^Symbol: _eng_tr ' $d/engine/pool.map | sed 's/.*= //'); tn=$(grep '^Symbol: _eng_tn ' $d/engine/pool.map | sed 's/.*= //')
run_toolchain env MB_BIN="/work/$d/engine/POOL.BIN" MB_TRACE=$((16#$tr)) MB_TRACEN=$((16#$tn)) MB_SYMS="$syms" ${MB_SESSION:+MB_SESSION=$MB_SESSION} ${MB_STILL:+MB_STILL=$MB_STILL} ${MB_SNAPAT:+MB_SNAPAT=$MB_SNAPAT} MB_OUT="/work/$out" MB_LIMIT="$limit" \
  mame ${MB_MACHINE:-coco3} -rompath /work/roms -pluginspath /usr/local/share/mame/plugins \
    -ramsize 512K -ext ide -hard3 "/work/$out-card.chd" -video soft -sound none ${MB_THROTTLE:--nothrottle} \
    -skip_gameinfo -nvram_directory /tmp/nvram -cfg_directory /tmp/cfg \
    -snapshot_directory "/work/$(dirname "$out")" \
    -autoboot_script /work/lua/watch.lua -seconds_to_run "${MB_SECONDS:-$((limit + 30))}" 2>&1 \
  | grep -v -E '^ALSA lib|^Average speed' || true
python3 -I tools/mbdump.py "$out.mbx" 2>&1 | head -40 || true

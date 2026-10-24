#!/usr/bin/env bash
# A session of the game from the CoCo SDC's single file (step 8.10b), in headless MAME with lua/watch.lua's model of the SDC's command mode (MB_SDC): the file
# (build/sdc/POOL.DSK, `make sdc`) is a 35 track disk in drive 0, which Disk BASIC boots POOL.BIN from, and the image after it.
# Usage: scripts/sdc_run.sh OUT-PREFIX   Environment: MB_SESSION, MB_LIMIT, MB_MACHINE as scripts/game_run.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
out="${1:?output prefix}"
cd "$ROOT"
file="${MB_SDCFILE:-build/sdc/POOL.DSK}"
[ -f "$file" ] || { echo "sdc_run: $file missing: run make sdc" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
rm -f "$out"-s*.scr4 "$out.mbx"
limit="${MB_LIMIT:-120}"
head -c 161280 "$file" > "$out-boot.dsk"          # (MAME's drive takes a 35 track disk: the first 630 sectors; the model of the SDC (lua/watch.lua MB_SDC) has the whole file)
syms=$(for n in kq kq_head kq_tail rand_seed wheel_pick pics pic_live eng_idx; do printf '%s=%s,' $n $(grep -h "^Symbol: _$n " build/game/pool.map build/game/core.map | head -1 | sed 's/.*= //'); done)
tr=$(grep '^Symbol: _eng_tr ' build/game/pool.map | sed 's/.*= //'); tn=$(grep '^Symbol: _eng_tn ' build/game/pool.map | sed 's/.*= //')
run_toolchain env MB_SDC="/work/$file" MB_TRACE=$((16#$tr)) MB_TRACEN=$((16#$tn)) MB_SYMS="$syms" ${MB_SESSION:+MB_SESSION=$MB_SESSION} ${MB_STILL:+MB_STILL=$MB_STILL} ${MB_SNAPAT:+MB_SNAPAT=$MB_SNAPAT} ${MB_PEEK:+"MB_PEEK=$MB_PEEK"} ${MB_PEEK_T:+MB_PEEK_T=$MB_PEEK_T} MB_OUT="/work/$out" MB_LIMIT="$limit" \
  mame ${MB_MACHINE:-coco3} -rompath /work/roms -pluginspath /usr/local/share/mame/plugins \
    -ramsize 512K -flop1 "/work/$out-boot.dsk" -video soft -sound none ${MB_THROTTLE:--nothrottle} \
    -skip_gameinfo -nvram_directory /tmp/nvram -cfg_directory /tmp/cfg \
    -snapshot_directory "/work/$(dirname "$out")" \
    -autoboot_script /work/lua/watch.lua -seconds_to_run "${MB_SECONDS:-$((limit + 30))}" 2>&1 \
  | grep -v -E '^ALSA lib|^Average speed' || true
python3 -I tools/mbdump.py "$out.mbx" 2>&1 | head -40 || true

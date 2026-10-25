#!/usr/bin/env bash
# A session of the game from the SuperIDE build's card file (step 8.12, docs/PHASE-8.12.md), in headless MAME with lua/watch.lua's model of the IDE interface (MB_IDE):
# the boot disk (build/ide/POOLBOOT.DSK: POOL.BIN of the IDE build) is the floppy that Disk BASIC loads the engine from, the game's sectors come from the card file
# (build/ide/POOLIDE.IMG, `make ide`) through the registers at $FF50.
# Usage: scripts/ide_run.sh OUT-PREFIX   Environment: MB_SESSION, MB_LIMIT, MB_MACHINE as scripts/game_run.sh; MB_IDE_SLAVE=1 (the card is the slave),
# MB_IDE_NO8=1 (the card refuses 8 bit transfers), IDE_LBA0 and IDE_LBA_BASE (the card sectors the file and the image start at: the Makefile's, `make ide` prints them)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
out="${1:?output prefix}"
cd "$ROOT"
card="${MB_IDEFILE:-build/ide/POOLIDE.IMG}"
[ -f "$card" ] || { echo "ide_run: $card missing: run make ide" >&2; exit 1; }
if [ -f build/ide/ide.env ]; then e_lba0="${IDE_LBA0:-}"; e_base="${IDE_LBA_BASE:-}"; source build/ide/ide.env; IDE_LBA0="${e_lba0:-$IDE_LBA0}"; IDE_LBA_BASE="${e_base:-$IDE_LBA_BASE}"; fi   # (the environment wins: a test of a card that is not the game's)
: "${IDE_LBA0:?IDE_LBA0 (make ide writes build/ide/ide.env)}"
: "${IDE_LBA_BASE:?IDE_LBA_BASE}"
mkdir -p "$(dirname "$out")"
rm -f "$out"-s*.scr4 "$out.mbx"
limit="${MB_LIMIT:-120}"
cp build/ide/POOLBOOT.DSK "$out-boot.dsk"
syms=$(for n in kq kq_head kq_tail rand_seed wheel_pick pics pic_live eng_idx; do printf '%s=%s,' $n $(grep -h "^Symbol: _$n " build/ide/engine/pool.map build/game/core.map | head -1 | sed 's/.*= //'); done)
tr=$(grep '^Symbol: _eng_tr ' build/ide/engine/pool.map | sed 's/.*= //'); tn=$(grep '^Symbol: _eng_tn ' build/ide/engine/pool.map | sed 's/.*= //')
run_toolchain env MB_IDE="/work/$card" MB_IDE_LBA0="$IDE_LBA0" MB_IDE_BASE="$IDE_LBA_BASE" ${MB_IDE_SLAVE:+MB_IDE_SLAVE=1} ${MB_IDE_NO8:+MB_IDE_NO8=1} \
  MB_TRACE=$((16#$tr)) MB_TRACEN=$((16#$tn)) MB_SYMS="$syms" ${MB_SESSION:+MB_SESSION=$MB_SESSION} ${MB_STILL:+MB_STILL=$MB_STILL} ${MB_SNAPAT:+MB_SNAPAT=$MB_SNAPAT} ${MB_PEEK:+"MB_PEEK=$MB_PEEK"} ${MB_PEEK_T:+MB_PEEK_T=$MB_PEEK_T} MB_OUT="/work/$out" MB_LIMIT="$limit" \
  mame ${MB_MACHINE:-coco3} -rompath /work/roms -pluginspath /usr/local/share/mame/plugins \
    -ramsize 512K -flop1 "/work/$out-boot.dsk" -video soft -sound none ${MB_THROTTLE:--nothrottle} \
    -skip_gameinfo -nvram_directory /tmp/nvram -cfg_directory /tmp/cfg \
    -snapshot_directory "/work/$(dirname "$out")" \
    -autoboot_script /work/lua/watch.lua -seconds_to_run "${MB_SECONDS:-$((limit + 30))}" 2>&1 \
  | grep -v -E '^ALSA lib|^Average speed' || true
python3 -I tools/mbdump.py "$out.mbx" 2>&1 | head -40 || true

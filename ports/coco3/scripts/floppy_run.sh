#!/usr/bin/env bash
# A session of the game on the floppy disks (step 8.10), in headless MAME: the disks of `make floppy` (build/floppy/disks/POOLnn.DSK) are
# copied (MAME writes the saves into the image it holds), disk 1 goes into drive 0 and disk MB_D1 (default 2) into drive 1; when the game asks
# for another disk (src/engine/flop.c) lua/watch.lua mounts it and answers the prompt, and prints "swap" lines.
# Usage: scripts/floppy_run.sh OUT-PREFIX   Environment: MB_SESSION (a tests/sessions/*.keys), MB_LIMIT (emulated seconds), MB_D1, MB_FLOPPIES,
# MB_MACHINE (coco3 or coco3h), MB_DEBUG... as scripts/game_run.sh. MB_FDTYPE=525qd: 80 track drives (the disks of make floppy80 in MB_FLOPPIES).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
out="${1:?output prefix}"
cd "$ROOT"
src="${MB_FLOPPIES:-build/floppy/disks}"
[ -f "$src/POOL01.DSK" ] || { echo "floppy_run: $src/POOL01.DSK missing: run make floppy" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
work="$out-disks"
rm -rf "$work"; mkdir -p "$work"; cp "$src"/POOL*.DSK "$work"/
rm -f "$out"-s*.scr4 "$out.mbx"
limit="${MB_LIMIT:-120}"
d1="${MB_D1:-2}"
[ -f "$work/POOL$(printf %02d "$d1").DSK" ] || d1=1
syms=$(for n in kq kq_head kq_tail rand_seed wheel_pick pics pic_live eng_idx; do printf '%s=%s,' $n $(grep -h "^Symbol: _$n " build/game/pool.map build/game/core.map | head -1 | sed 's/.*= //'); done)
tr=$(grep '^Symbol: _eng_tr ' build/game/pool.map | sed 's/.*= //'); tn=$(grep '^Symbol: _eng_tn ' build/game/pool.map | sed 's/.*= //')
flop2=(); [ "$d1" != 1 ] && flop2=(-flop2 "/work/$work/POOL$(printf %02d "$d1").DSK")
run_toolchain env MB_FLOP="/work/$work" ${MB_FDTYPE:+MB_FDTYPE=$MB_FDTYPE} ${MB_DSKLOG:+MB_DSKLOG=1} MB_TRACE=$((16#$tr)) MB_TRACEN=$((16#$tn)) MB_SYMS="$syms" ${MB_SESSION:+MB_SESSION=$MB_SESSION} ${MB_STILL:+MB_STILL=$MB_STILL} ${MB_KEYGAP:+MB_KEYGAP=$MB_KEYGAP} ${MB_SNAPAT:+MB_SNAPAT=$MB_SNAPAT} ${MB_FLOP_WRONG:+MB_FLOP_WRONG=1} ${MB_FLOP_KEY:+MB_FLOP_KEY=1} ${MB_PCLOG:+MB_PCLOG=$MB_PCLOG} ${MB_BANKLOG:+MB_BANKLOG=$MB_BANKLOG} ${MB_ITRACE:+MB_ITRACE=$MB_ITRACE} ${MB_WATCH:+MB_WATCH=$MB_WATCH} ${MB_WATCH_N:+MB_WATCH_N=$MB_WATCH_N} ${MB_PEEK:+"MB_PEEK=$MB_PEEK"} ${MB_PEEK_T:+MB_PEEK_T=$MB_PEEK_T} MB_OUT="/work/$out" MB_LIMIT="$limit" ${MB_KEYS:+"MB_KEYS=$MB_KEYS"} \
  mame ${MB_MACHINE:-coco3} -rompath /work/roms -pluginspath /usr/local/share/mame/plugins \
    -ramsize 512K ${MB_FDTYPE:+-ext:fdc:wd17xx:0 $MB_FDTYPE -ext:fdc:wd17xx:1 $MB_FDTYPE} -flop1 "/work/$work/POOL01.DSK" ${flop2[@]+"${flop2[@]}"} ${MB_DEBUGGER:+-debug -debugger none} -video soft -sound none ${MB_THROTTLE:--nothrottle} \
    -skip_gameinfo -nvram_directory /tmp/nvram -cfg_directory /tmp/cfg \
    -snapshot_directory "/work/$(dirname "$out")" \
    -autoboot_script /work/lua/watch.lua -seconds_to_run "${MB_SECONDS:-$((limit + 30))}" 2>&1 \
  | grep -v -E '^ALSA lib|^Average speed' || true
python3 -I tools/mbdump.py "$out.mbx" 2>&1 | head -40 || true

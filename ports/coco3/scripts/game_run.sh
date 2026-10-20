#!/usr/bin/env bash
# Play the game in headless MAME (step 8.5e): program disk in drive 0, the data volumes after it, lua/watch.lua keeps the
# screens. Usage: scripts/game_run.sh OUT-PREFIX [vol-numbers...]   (default: BASE only). Environment: MB_LIMIT (emulated s),
# MB_KEYS ("t:text;..."), MB_SECONDS (wall clock limit of MAME, default LIMIT+30).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
out="${1:?output prefix}"; shift || true
vols=()
cd "$ROOT"
if [ -z "${MB_NOBUILD:-}" ]; then     # MB_NOBUILD=1: the disk and the image are already made (runs in parallel must not rewrite them under each other)
  run_toolchain python3 -I tools/mkgamedisk.py build/game build/gen/vm/DGROUP.IMG build/game/pool.dsk
  run_toolchain python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG build/game/pool.img
fi
mkdir -p "$(dirname "$out")"
rm -f "$out"-s*.scr4 "$out.mbx"
extra=(); n=2   # -flop2 is drive 1 (the volume), -flop3 and -flop4 the development bank disks (drives 2 and 3)
for v in ${vols[@]+"${vols[@]}"}; do extra+=(-flop$n "/work/build/data/vol$v.dsk"); n=$((n + 1)); done
limit="${MB_LIMIT:-120}"
syms=$(for n in kq kq_head kq_tail rand_seed wheel_pick pics pic_live eng_idx; do printf '%s=%s,' $n $(grep -h "^Symbol: _$n " build/game/pool.map build/game/core.map | head -1 | sed 's/.*= //'); done)
tr=$(grep '^Symbol: _eng_tr ' build/game/pool.map | sed 's/.*= //'); tn=$(grep '^Symbol: _eng_tn ' build/game/pool.map | sed 's/.*= //')
run_toolchain env ${MB_DAC:+MB_DAC=1} ${MB_WTAP:+MB_WTAP=$MB_WTAP} ${MB_NOTAP:+MB_NOTAP=1} ${MB_SECLOG:+MB_SECLOG=1} MB_IMG=/work/build/game/pool.img MB_TRACE=$((16#$tr)) MB_TRACEN=$((16#$tn)) MB_SYMS="$syms" ${MB_SESSION:+MB_SESSION=$MB_SESSION} ${MB_WATCH:+MB_WATCH=$MB_WATCH} ${MB_WATCH_N:+MB_WATCH_N=$MB_WATCH_N} ${MB_WATCH_IGNORE:+MB_WATCH_IGNORE=$MB_WATCH_IGNORE} ${MB_PCLOG:+MB_PCLOG=$MB_PCLOG} ${MB_BANKLOG:+MB_BANKLOG=$MB_BANKLOG} ${MB_DUMPRAM:+MB_DUMPRAM=$MB_DUMPRAM} ${MB_RLOG:+MB_RLOG=$MB_RLOG} ${MB_ITRACE:+MB_ITRACE=$MB_ITRACE} ${MB_PEEK:+"MB_PEEK=$MB_PEEK"} ${MB_PEEK_T:+MB_PEEK_T=$MB_PEEK_T} ${MB_WATCH_AFTER:+MB_WATCH_AFTER=$MB_WATCH_AFTER} ${MB_STILL:+MB_STILL=$MB_STILL} ${MB_KEYGAP:+MB_KEYGAP=$MB_KEYGAP} MB_OUT="/work/$out" MB_LIMIT="$limit" ${MB_KEYS:+"MB_KEYS=$MB_KEYS"} \
  mame coco3 -rompath /work/roms -pluginspath /usr/local/share/mame/plugins \
    -ramsize 512K -flop1 /work/build/game/pool.dsk ${extra[@]+"${extra[@]}"} ${MB_DEBUGGER:+-debug -debugger none} -video soft -sound none ${MB_THROTTLE:--nothrottle} \
    -skip_gameinfo -nvram_directory /tmp/nvram -cfg_directory /tmp/cfg \
    -snapshot_directory "/work/$(dirname "$out")" \
    -autoboot_script /work/lua/watch.lua -seconds_to_run "${MB_SECONDS:-$((limit + 30))}" 2>&1 \
  | grep -v -E '^ALSA lib|^Average speed' || true
python3 -I tools/mbdump.py "$out.mbx" 2>&1 | head -40 || true

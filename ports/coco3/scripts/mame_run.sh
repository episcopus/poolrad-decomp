#!/usr/bin/env bash
# Run a DECB .bin from a disk image in headless MAME (coco3, 512K, RGB) and dump the mailbox.
# Usage: scripts/mame_run.sh build/x/x.dsk PROGRAM-NAME out-prefix   (paths relative to ports/coco3)
# Writes <prefix>.mbx and <prefix>.png. Needs roms/coco3.zip (README, "ROMs").
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

dsk="${1:?disk image}"; prog="${2:?program name on the disk}"; out="${3:?output prefix}"
[[ -f "$ROOT/roms/coco3.zip" ]] || { echo "roms/coco3.zip missing (README, ROMs)" >&2; exit 1; }
mkdir -p "$ROOT/$(dirname "$out")"
unlink "$ROOT/$out.mbx" 2>/dev/null || true
unlink "$ROOT/$out.png" 2>/dev/null || true
# MB_FLOPS: more disk images (paths relative to ports/coco3) for drives 1, 2, 3: -flop2, -flop3, -flop4
extra=(); n=2
for f in ${MB_FLOPS:-}; do extra+=(-flop$n "/work/$f"); n=$((n + 1)); done
run_toolchain env ${MB_DAC:+MB_DAC=1} ${MB_WTAP:+MB_WTAP=$MB_WTAP} MB_OUT="/work/$out" MB_CMD="LOADM\"$prog\":EXEC" ${MB_SCREENS:+MB_SCREENS=1} ${MB_KEYS:+"MB_KEYS=$MB_KEYS"} ${MB_KEYS_CP:+MB_KEYS_CP=$MB_KEYS_CP} MB_LIMIT="${MB_LIMIT:-90}" \
  mame coco3 -rompath /work/roms -pluginspath /usr/local/share/mame/plugins \
    -ramsize 512K -flop1 "/work/$dsk" ${extra[@]+"${extra[@]}"} -video soft -sound none -nothrottle \
    -skip_gameinfo -nvram_directory /tmp/nvram -cfg_directory /tmp/cfg \
    -snapshot_directory "/work/$(dirname "$out")" \
    -autoboot_script /work/lua/mailbox.lua -seconds_to_run "${MB_SECONDS:-120}" 2>&1 \
  | grep -v -E '^ALSA lib|^Average speed' || true
[[ -f "$ROOT/$out.mbx" ]] || { echo "mame_run: no mailbox dump" >&2; exit 1; }

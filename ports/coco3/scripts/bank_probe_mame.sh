#!/usr/bin/env bash
# The banks a run needs on the program disk, found in MAME: run, and while the game stops on a bank that is not on the disk
# (mailbox r29 = 1, r31 = the bank) add it to build/game/bootbanks.txt and run again. Usage: scripts/bank_probe_mame.sh [limit]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
for i in $(seq 1 25); do
  MB_LIMIT="${1:-300}" scripts/game_run.sh build/run/probe > build/run/probe.out 2>&1
  w=$(python3 -I tools/mbdump.py build/run/probe.mbx 2>/dev/null)
  r29=$(echo "$w" | awk '$1=="r29"{print $2}'); r31=$(echo "$w" | awk '$1=="r31"{print $2}')
  if [[ "${r29:-0}" == "1" && -n "${r31:-}" ]] && ! grep -qw "$r31" build/game/bootbanks.txt; then
    echo "bank $r31 added"; echo " $r31" >> build/game/bootbanks.txt
  else
    echo "stopped:"; echo "$w" | grep -E "status|r(28|29|30|31) "; break
  fi
done
tr '\n' ' ' < build/game/bootbanks.txt; echo

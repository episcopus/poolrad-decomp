#!/usr/bin/env bash
# Find the code banks a session needs on the program disk (step 8.5e): run the game in XRoar, and while it stops on a missing
# bank file (mailbox r29 = 1, r31 = the bank) add that bank to build/game/bootbanks.txt and run again.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
for i in $(seq 1 40); do
  scripts/game_xroar.sh build/run/probe.ram "$@" || { echo "no stop"; break; }
  w=$(python3 -I tools/mbdump.py build/run/probe.ram --ram)
  r29=$(echo "$w" | awk '$1=="r29"{print $2}'); r31=$(echo "$w" | awk '$1=="r31"{print $2}')
  if [[ "${r29:-0}" == "1" && -n "${r31:-}" ]] && ! grep -qw "$r31" build/game/bootbanks.txt; then
    echo "bank $r31 missing: added"; echo " $r31" >> build/game/bootbanks.txt
  else
    echo "stopped:"; echo "$w" | grep -E "status|r(29|3[01]) "; break
  fi
done
tr '\n' ' ' < build/game/bootbanks.txt; echo

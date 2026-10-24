#!/usr/bin/env bash
# Every session on the floppy set (step 8.10), five at a time, then the verdicts: the labelled screens against the goldens (tools/gamecheck.py),
# the files the game wrote against the development run's (tools/floppycheck.py), the swaps the player would have made (lua/watch.lua prints them).
# Usage: scripts/floppy_all.sh [session...]   (default: every session of the baseline)
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [ $# -gt 0 ]; then sessions="$*"; else
  sessions=$(ls ../../tests/sessions/*.keys | xargs -n1 basename | sed 's/\.keys$//' | grep -v create-elf-mage)
fi
chmod +x scripts/floppy_one.sh
printf '%s\n' $sessions | xargs -P 5 -n 1 scripts/floppy_one.sh
bad=0
printf '%-18s %-26s %6s %s\n' session screens swaps saves
for s in $sessions; do
  scr=$(python3 -I tools/gamecheck.py $s build/run/floppy-$s 2>&1 | tail -1 | sed "s/^$s: //; s/ shown in order.*//")
  case "$scr" in *"$(echo "$scr" | sed 's/ of .*//') of "*) ;; esac
  ok=$(python3 -I tools/gamecheck.py $s build/run/floppy-$s 2>&1 | tail -1 | grep -c "^$s: \([0-9]*\) of \1 labelled")
  [ "$ok" = 1 ] || bad=1
  sw=$(grep -a -c '^swap ' build/run/floppy-$s.out)
  if [ -f build/run/game-$s.saves ]; then
    sv=$(python3 -I tools/floppycheck.py build/floppy/pool.img build/run/floppy-$s-disks build/game/pool.img build/run/game-$s.saves 2>&1 | tail -1)
    case "$sv" in *"development run's"*) ;; *) bad=1;; esac
  else sv="(no development run)"; fi
  printf '%-18s %-26s %6s %s\n' "$s" "$scr" "$sw" "$sv"
done
exit $bad

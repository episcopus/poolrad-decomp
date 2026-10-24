#!/usr/bin/env bash
# Every session from the CoCo SDC's file (step 8.10b) on lua/watch.lua's model of the SDC, five at a time, then the verdicts: the labelled screens against the
# goldens and the sectors the game wrote against the development run's (the same session on the harness' storage, build/run/game-S.saves).
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [ $# -gt 0 ]; then sessions="$*"; else
  sessions=$(ls ../../tests/sessions/*.keys | xargs -n1 basename | sed 's/\.keys$//' | grep -v create-elf-mage)
fi
chmod +x scripts/sdc_one.sh
printf '%s\n' $sessions | xargs -P 5 -n 1 scripts/sdc_one.sh
bad=0
printf '%-18s %-44s %s\n' session screens saves
for s in $sessions; do
  line=$(python3 -I tools/gamecheck.py $s build/run/sdc-$s 2>&1 | tail -1)
  scr=$(echo "$line" | sed "s/^$s: //; s/ golden screens shown in order.*//")
  echo "$line" | grep -q "^$s: \([0-9]*\) of \1 labelled" || bad=1
  if [ -f build/run/game-$s.saves ]; then
    sv=$(python3 -I - build/run/sdc-$s.saves build/run/game-$s.saves <<'PY'
import struct, sys
def load(p):
    d = open(p, "rb").read()
    return {struct.unpack(">I", d[i:i + 4])[0]: d[i + 4:i + 260] for i in range(0, len(d) - 259, 260)}
a, b = load(sys.argv[1]), load(sys.argv[2])
print("the sectors written are the development run's (%d)" % len(a) if a == b else "DIFFERENT: %d against %d sectors written" % (len(a), len(b)))
PY
)
    case "$sv" in DIFFERENT*) bad=1;; esac
  else sv="(no development run)"; fi
  printf '%-18s %-44s %s\n' "$s" "$scr" "$sv"
done
exit $bad

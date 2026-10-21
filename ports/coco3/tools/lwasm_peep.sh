#!/bin/sh
# The assembler CMOC calls (mkgame passes --lwasm=this): the peephole pass of tools/peep.py on the .s file CMOC has just written, then lwasm itself.
# PEEP_OFF=1 in the environment of the container turns the pass off.
d="$(dirname "$0")"
mkdir -p "$d/../build/run" 2>/dev/null
if [ -z "$PEEP_OFF" ] && [ ! -f "$d/../build/run/peep_off" ]; then
  for a in "$@"; do
    case "$a" in
      *.s) python3 "$d/peep.py" "$a" 2>>"$d/../build/run/peep.log" ;;
    esac
  done
fi
exec lwasm "$@"

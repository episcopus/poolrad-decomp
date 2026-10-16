#!/bin/sh
# check_c.sh: translate and syntax-check the generated C (a quick loop while developing the translator)
cd "$(dirname "$0")/../.." || exit 1
.venv/bin/python tools/c/pas2c.py --out build/c/game 2>&1 | tail -5
cd build/c/game
for f in *.c; do clang -fsyntax-only -std=gnu11 -I../../../c/include -I. -w -ferror-limit=0 $f 2>&1; done > ../errors.txt
grep -c "error:" ../errors.txt

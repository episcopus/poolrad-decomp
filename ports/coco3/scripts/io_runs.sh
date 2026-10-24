#!/usr/bin/env bash
# Every session once on the development backend with the storage log on (MB_SECLOG), five at a time, to build/run/io-<session>.out (tools/iobudget.py reads them).
# Usage: scripts/io_runs.sh [session...]   Environment: MB_LIMIT (emulated seconds, default 2500).
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
run_toolchain python3 -I tools/mkgamedisk.py build/game build/gen/vm/DGROUP.IMG build/game/pool.dsk > /dev/null
run_toolchain python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG build/game/pool.img > /dev/null
if [ $# -gt 0 ]; then sessions="$*"; else sessions=$(ls ../../tests/sessions/*.keys | xargs -n1 basename | sed 's/\.keys$//' | grep -v create-elf-mage); fi
printf '%s\n' $sessions | xargs -P 5 -n 1 scripts/io_one.sh

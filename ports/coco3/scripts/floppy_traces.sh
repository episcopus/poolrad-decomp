#!/usr/bin/env bash
# The storage trace of every session (MB_SECLOG) on the development backend with the image that has no shared block, so that a sector tells one entry (tools/mklayout.py
# profile turns them into data/floppy_runs.json). The game and `make floppy-model` come first; the disk image of the engine (build/game/pool.dsk) is made here.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh
mkdir -p build/trace/runs
run_toolchain python3 -I tools/mkgamedisk.py build/game build/gen/vm/DGROUP.IMG build/game/pool.dsk > /dev/null
chmod +x scripts/floppy_trace_one.sh
ls ../../tests/sessions/*.keys | xargs -n1 basename | sed 's/\.keys$//' | grep -v create-elf-mage | xargs -P 5 -n 1 scripts/floppy_trace_one.sh
echo "traces in build/trace/runs: make floppy-profile keeps them as data/floppy_runs.json"

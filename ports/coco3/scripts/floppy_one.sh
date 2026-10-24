#!/usr/bin/env bash
# one session on the floppy set, for floppy_all.sh (xargs): scripts/floppy_one.sh SESSION
cd "$(dirname "${BASH_SOURCE[0]}")/.."
s="$1"
MB_SESSION=/repo/tests/sessions/$s.keys MB_LIMIT=${MB_LIMIT:-4500} scripts/floppy_run.sh build/run/floppy-$s > build/run/floppy-$s.out 2>&1

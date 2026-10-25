#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")/.."
s="$1"
MB_SESSION=/repo/tests/sessions/$s.keys MB_LIMIT=${MB_LIMIT:-4500} scripts/ide_run.sh build/run/ide-$s > build/run/ide-$s.out 2>&1

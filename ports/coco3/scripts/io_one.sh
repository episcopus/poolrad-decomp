#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")/.."
s=$1
MB_SECLOG=1 MB_NOBUILD=1 MB_SESSION=/repo/tests/sessions/$s.keys MB_LIMIT=${MB_LIMIT:-2500} scripts/game_run.sh build/run/io-$s > build/run/io-$s.out 2>&1

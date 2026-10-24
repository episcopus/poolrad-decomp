#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")/.."
s="$1"
MB_SESSION=/repo/tests/sessions/$s.keys MB_LIMIT=${MB_LIMIT:-4500} scripts/sdc_run.sh build/run/sdc-$s > build/run/sdc-$s.out 2>&1

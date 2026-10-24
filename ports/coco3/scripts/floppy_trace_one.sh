#!/usr/bin/env bash
# one session's storage trace on the image without shared blocks (scripts/floppy_traces.sh runs this for every session)
cd "$(dirname "${BASH_SOURCE[0]}")/.."
s=$1; lim=2500; [ "$s" = boot-title ] && lim=300
MB_IMGFILE=/work/build/trace/pool-nodedupe.img MB_SECLOG=1 MB_NOBUILD=1 MB_SESSION=/repo/tests/sessions/$s.keys MB_LIMIT=$lim scripts/game_run.sh build/trace/runs/$s > build/trace/runs/$s.out 2>&1

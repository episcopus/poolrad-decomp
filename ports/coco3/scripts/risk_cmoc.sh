#!/usr/bin/env bash
# Compile every unit of the game build with CMOC's warnings on (the build runs it with -w) and keep them: build/risk/cmoc-warnings.txt.
# The warnings that matter are the ones that say CMOC evaluates something differently from Standard C (byte-sized arithmetic, signedness).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
cd "$ROOT"
mkdir -p build/risk
run_toolchain bash -c '
  cd /work
  : > build/risk/cmoc-warnings.txt
  for f in build/game/src/ovl*.c build/game/src/res*.c build/game/src/pool.c; do
    case "$f" in *_[0-9].c|*_syms.c) continue;; esac
    cmoc -c --void-target --no-relocate -O2 -fomit-frame-pointer -Ishim -Ibuild/game/inc -Isrc/engine -o /tmp/risk.o "$f" 2>&1 | grep -E "warning" >> build/risk/cmoc-warnings.txt || true
  done
  wc -l build/risk/cmoc-warnings.txt'

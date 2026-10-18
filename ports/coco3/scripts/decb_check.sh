#!/usr/bin/env bash
# Every volume image read back by ToolShed's decb (a second implementation of RS-DOS) must hold the container bytes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
tmp="$(mktemp -d)"
for n in 0 1 2 3 4 5 6 7 8; do
  decb copy -2 -b "build/data/vol$n.dsk,POOLVOL.DAT" "$tmp/v$n.bin" >/dev/null
  cmp "$tmp/v$n.bin" "build/data/vol$n.bin"
done
echo "decb_check: decb reads the container of all nine volumes unchanged"

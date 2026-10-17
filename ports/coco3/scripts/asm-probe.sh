#!/usr/bin/env bash
# Compile probes/asm/NAME.c with the port's CMOC flags and print the assembly without
# comment lines. Run inside the toolchain (make asm-probe does that). Output stays in build/probe/asm.
set -euo pipefail
name="${1:?probe name}"
mkdir -p build/probe/asm
cmoc -S --void-target --no-relocate -O2 -Wgives-byte --intdir=build/probe/asm "probes/asm/$name.c"
grep -v '^\*' "build/probe/asm/$name.s" | cat -s

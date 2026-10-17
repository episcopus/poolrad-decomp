#!/usr/bin/env bash
# Compile probes/asm/NAME.c with the port's CMOC flags and print the assembly without comment
# lines; then assemble it and say so if lwasm rejects it. Run inside the toolchain (make asm-probe
# does that). Output stays in build/probe/asm.
set -uo pipefail
name="${1:?probe name}"
mkdir -p build/probe/asm
cmoc -S --void-target --no-relocate -O2 -Wgives-byte --intdir=build/probe/asm "probes/asm/$name.c" 2>&1 | head -5
grep -v '^\*' "build/probe/asm/$name.s" | cat -s
echo "--- lwasm"
lwasm --6809 -fobj -o "build/probe/asm/$name.o" "build/probe/asm/$name.s" 2>&1 | head -5 && echo "(assembled)"

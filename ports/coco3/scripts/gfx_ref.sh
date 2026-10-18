#!/usr/bin/env bash
# The reference for the engine's text, tile and blit goldens (step 8.3c): build test/gfx_ref.c against the Phase 7 C
# engine (the PC profile, EGA screen model) and run it in the original game's folder. Prints one `label sha256` line
# per checkpoint and compares them with goldens/engine/t_gfx.s4; with --write rewrites that file instead.
# Needs the C engine library: cmake -S ../.. -B ../../build/cmake && cmake --build ../../build/cmake --target poolrad_engine
# (done here when it is missing). POOLRAD_DATA is the original game folder (default ../../poolrad).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$ROOT/../.."
DATA="${POOLRAD_DATA:-$REPO/poolrad}"
LIB="$REPO/build/cmake/libpoolrad_engine.a"
OUT="$ROOT/build/gfxref"
mkdir -p "$OUT"
if [[ ! -f "$LIB" ]]; then
  cmake -S "$REPO" -B "$REPO/build/cmake" >/dev/null
  cmake --build "$REPO/build/cmake" --target poolrad_engine >/dev/null
fi
cc -O1 -w -I"$REPO/c/include" -I"$REPO/c/game" -o "$OUT/gfx_ref" "$ROOT/test/gfx_ref.c" "$REPO/c/platform/null.c" "$LIB" -lm
(cd "$DATA" && "$OUT/gfx_ref") > "$OUT/t_gfx.s4"
if [[ "${1:-}" == "--write" ]]; then
  cp "$OUT/t_gfx.s4" "$ROOT/goldens/engine/t_gfx.s4"
  echo "gfx_ref: goldens/engine/t_gfx.s4 rewritten"
elif cmp -s "$OUT/t_gfx.s4" "$ROOT/goldens/engine/t_gfx.s4"; then
  echo "gfx_ref: the Phase 7 engine still draws the six checkpoints of goldens/engine/t_gfx.s4"
else
  diff "$OUT/t_gfx.s4" "$ROOT/goldens/engine/t_gfx.s4" || true
  echo "gfx_ref: DIFFERENT from goldens/engine/t_gfx.s4" >&2
  exit 1
fi

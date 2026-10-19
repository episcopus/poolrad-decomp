#!/usr/bin/env bash
# risk_clang.sh: the comparisons clang can prove tautological in the translated game (c/game), whether a session runs the code or not.
# A `< 0` on an unsigned expression is the signature of a translator that lost a signed type (Integer(WordVar) < 0 was one: the spells
# window never opened); a `0 <=` on one is Pascal range checks of a Byte that the original keeps too (listed, not an error).
# Usage: tools/c/risk_clang.sh   (prints the always-false ones first)
set -uo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp)"
for f in c/game/*.c; do
  clang -fsyntax-only -Ic/include -Ic/game -Ic/rtl -Wtautological-compare -Wtautological-unsigned-zero-compare -Wtautological-constant-out-of-range-compare "$f" 2>&1 | grep "warning:" >> "$tmp"
done
echo "== comparisons that are always false or out of range (read each: a QUIRK note in the source explains the known ones) =="
grep -E "always false|out of range" "$tmp" | grep -v "pointer-to-int" | sed 's/^/  /' || true
echo "== comparisons that are always true (Byte >= 0 and the like; listed by count) =="
grep -c "always true" "$tmp" | sed 's/^/  /'
rm -f "$tmp"

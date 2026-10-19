#!/usr/bin/env bash
# explore_run.sh SCRIPT [OUT] [WATCH]: play a key script on the C translation (poolrad_explore) and turn the screens into PNGs next to it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
s="$1"; out="${2:-build/explore/$(basename "$s" .keys)}"
EXPLORE_WATCH="${3:-}" build/cmake-trace/poolrad_explore --data poolrad --save build/explore/save --script "$s" --out "$out" --max-polls "${MAXPOLLS:-12000000}" 2>&1 | tail -${TAIL:-6}
python3 - "$out" <<'PY'
import glob, sys
from PIL import Image
for f in glob.glob(sys.argv[1] + "-*.ppm"):
    Image.open(f).save(f[:-4] + ".png")
PY

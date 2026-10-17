#!/usr/bin/env bash
# Check everything the dev workflow needs. Exits 1 when a required piece is missing.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
bad=0
ok()   { echo "ok      $*"; }
miss() { echo "MISSING $*"; bad=1; }
command -v docker >/dev/null 2>&1 && ok "docker $(docker --version | cut -d' ' -f3 | tr -d ,)" || miss "docker"
docker info >/dev/null 2>&1 && ok "docker daemon" || miss "docker daemon not running"
docker image inspect "$IMAGE" >/dev/null 2>&1 && ok "image $IMAGE" || miss "image $IMAGE (docker pull $IMAGE)"
[[ -f "$ROOT/roms/coco3.zip" ]] && ok "roms/coco3.zip (headless MAME)" || miss "roms/coco3.zip"
[[ -f "$ROOT/roms/coco3.rom" ]] && ok "roms/coco3.rom (XRoar)" || miss "roms/coco3.rom"
[[ -f "$ROOT/roms/disk11.rom" ]] && ok "roms/disk11.rom (XRoar disk boot)" || echo "absent  roms/disk11.rom (only needed to boot a disk in XRoar)"
command -v xroar >/dev/null 2>&1 && ok "xroar" || echo "absent  xroar (optional: brew install xroar)"
command -v python3 >/dev/null 2>&1 && ok "python3 (host tools)" || miss "python3"
exit $bad

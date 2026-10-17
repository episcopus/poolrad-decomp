#!/usr/bin/env bash
# Run a command in the toolchain: in this process when already inside coco-dev, else in a
# container with ports/coco3 mounted at /work.  Usage: scripts/tc.sh command [args...]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"
run_toolchain "$@"

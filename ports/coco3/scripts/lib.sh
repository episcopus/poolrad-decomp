#!/usr/bin/env bash
# Shared helpers. ports/coco3 is the root of the CoCo 3 dev workflow: every path
# is relative to it. Compilers run in the jamieleecho/coco-dev image; XRoar runs
# on the host; headless MAME runs in the image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${COCO_DEV_IMAGE:-jamieleecho/coco-dev:latest}"

# True when this shell is already inside the coco-dev image.
inside_coco_dev() {
  command -v lwasm >/dev/null 2>&1 \
    && command -v cmoc >/dev/null 2>&1 \
    && command -v decb >/dev/null 2>&1 \
    && [[ -d /usr/local/share/mame/plugins ]]
}

# Run a command in coco-dev with ports/coco3 mounted at /work.
docker_run() {
  command -v docker >/dev/null 2>&1 || { echo "docker is not on PATH" >&2; exit 1; }
  docker info >/dev/null 2>&1 || { echo "the docker daemon is not running" >&2; exit 1; }
  docker run --rm -i \
    -v "$ROOT:/work" -w /work -e HOME=/tmp -e SDL_VIDEODRIVER=dummy -e SDL_AUDIODRIVER=dummy \
    --user "$(id -u):$(id -g)" "$IMAGE" "$@"
}

# Run in this process when already inside coco-dev, else in a container.
run_toolchain() {
  if inside_coco_dev; then "$@"; else docker_run "$@"; fi
}

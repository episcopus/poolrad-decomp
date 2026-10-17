#!/usr/bin/env bash
# Print what the coco-dev image provides (run inside it; `make toolchain` does that).
set -u
echo "arch: $(uname -m)"
for t in cmoc lwasm lwlink lwar decb os9 writecocofile install-coco-boot-loader zx0 dzx0 mame python3; do
  p=$(command -v "$t" || true)
  if [[ -z "$p" ]]; then echo "$t: MISSING"; continue; fi
  case "$t" in
    cmoc) v=$(cmoc --version 2>&1 | head -1);;
    lwasm|lwlink|lwar) v=$("$t" --version 2>&1 | head -1);;
    mame) v=$(mame -h 2>&1 | head -1);;
    python3) v=$(python3 --version 2>&1);;
    *) v="present";;
  esac
  echo "$t: $v ($p)"
done
echo "usim (simulator for cmoc --usim): $(command -v usim || echo 'not installed; the image has only its libraries libcmoc-*-usim.a')"
echo "cmoc libraries: $(ls /usr/local/share/cmoc/lib | tr '\n' ' ')"

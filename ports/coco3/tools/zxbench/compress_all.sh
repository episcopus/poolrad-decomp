#!/bin/sh
cd /w
ls banks/*.raw dax/*.raw | xargs -P 8 -I{} sh -c 'zx0 -f {} {}.zx0 >/dev/null 2>&1 || true'

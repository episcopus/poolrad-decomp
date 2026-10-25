#!/bin/sh
cd "$(dirname "$0")" || exit 1
exec mame coco3 -ramsize 512K -ext ide -hard3 POOLIDE.chd -autoboot_script mame-boot.lua "$@"

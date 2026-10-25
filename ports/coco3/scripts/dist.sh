#!/usr/bin/env bash
# the distribution folder (build/dist): one sub folder per kind of build with its README, and a README at the top. Run by `make dist` after it has built everything;
# the texts are tools/pack/dist/. The folder holds the game's data: for the maintainer's testers, not to be published (docs/DISTRIBUTION.md).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
d=build/dist
rm -rf "$d"; mkdir -p "$d"/{01-floppy-35track,02-floppy-80track-xroar,03-coco-sdc,04-superide-card,05-xroar-ide,06-mame-ide}
cp tools/pack/dist/README-top.md "$d/README.md"
cp build/floppy/disks/POOL*.DSK "$d/01-floppy-35track/";            cp tools/pack/dist/README-01.txt "$d/01-floppy-35track/README.txt"
cp build/floppy80/disks/POOL*.DSK "$d/02-floppy-80track-xroar/";    cp tools/pack/dist/README-02.txt "$d/02-floppy-80track-xroar/README.txt"
cp build/sdc/POOL.DSK "$d/03-coco-sdc/";                             cp tools/pack/dist/README-03.txt "$d/03-coco-sdc/README.txt"
cp build/ide/POOLIDE.IMG build/ide/POOLBOOT.DSK build/ide/ide.env tools/ide_card.py "$d/04-superide-card/"; cp tools/pack/dist/README-04.txt "$d/04-superide-card/README.txt"
cp -R build/pool-xroar/. "$d/05-xroar-ide/";                         mv "$d/05-xroar-ide/README-xroar.txt" "$d/05-xroar-ide/README.txt"
cp -R build/pool-mame/. "$d/06-mame-ide/";                           mv "$d/06-mame-ide/README-mame.txt" "$d/06-mame-ide/README.txt"
( cd "$d" && find . -type f ! -name SHA256SUMS | sort | xargs shasum -a 256 > SHA256SUMS )
du -sh "$d"/*/ | sed 's/^/  /'
echo "dist: $d ready ($(cd "$d" && find . -type f | wc -l | tr -d ' ') files)"

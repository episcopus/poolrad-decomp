#!/usr/bin/env bash
# the distribution folder (build/dist): one sub folder per kind of build with its README, and a README at the top. Run by `make dist` after it has built everything;
# the texts are tools/pack/dist/. The folder holds the game's data: for the maintainer's testers, not to be published (docs/DISTRIBUTION.md).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
d=build/dist
rm -rf "$d"; mkdir -p "$d"/{01-floppy-35track,02-floppy-80track-xroar,03-coco-sdc,04-superide-card,05-xroar-ide,06-mame-ide}
# the version (docs/VERSIONING.md): VERSION as make dist released it, a line under the title of every README, the changelog in every folder (the site and the
# testers get the folders one zip at a time) and as data for the site's page (changelog.json)
python3 -I tools/changelog.py check > /dev/null
v=$(python3 -I tools/changelog.py version)
vdate=$(sed -n "s/^## $v - \(.*\)$/\1/p" CHANGELOG.md)
stamp() {   # stamp <readme>: the version line after the two line title
  awk -v line="Version $v ($vdate). What changed in each version: $2." 'NR==3{print; print line; print ""; next} {print}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
cp tools/pack/dist/README-top.md "$d/README.md"
cp build/floppy/disks/POOL*.DSK "$d/01-floppy-35track/";            cp tools/pack/dist/README-01.txt "$d/01-floppy-35track/README.txt"
cp build/floppy80/disks/POOL*.DSK "$d/02-floppy-80track-xroar/";    cp tools/pack/dist/README-02.txt "$d/02-floppy-80track-xroar/README.txt"
cp build/sdc/POOL.DSK "$d/03-coco-sdc/";                             cp tools/pack/dist/README-03.txt "$d/03-coco-sdc/README.txt"
cp build/ide/POOLIDE.IMG build/ide/POOLBOOT.DSK build/ide/ide.env tools/ide_card.py "$d/04-superide-card/"; cp tools/pack/dist/README-04.txt "$d/04-superide-card/README.txt"
cp -R build/pool-xroar/. "$d/05-xroar-ide/";                         mv "$d/05-xroar-ide/README-xroar.txt" "$d/05-xroar-ide/README.txt"
cp -R build/pool-mame/. "$d/06-mame-ide/";                           mv "$d/06-mame-ide/README-mame.txt" "$d/06-mame-ide/README.txt"
{ head -1 "$d/README.md"; echo; echo "Version $v ($vdate). What changed in each version: \`CHANGELOG.md\`."; tail -n +2 "$d/README.md"; } > "$d/README.tmp" && mv "$d/README.tmp" "$d/README.md"
cp CHANGELOG.md "$d/CHANGELOG.md"; echo "$v" > "$d/VERSION"; python3 -I tools/changelog.py json "$d/changelog.json" > /dev/null
for f in "$d"/0*/; do cp CHANGELOG.md "$f/CHANGELOG.txt"; stamp "$f/README.txt" CHANGELOG.txt; done
( cd "$d" && find . -type f ! -name SHA256SUMS | sort | xargs shasum -a 256 > SHA256SUMS )
du -sh "$d"/*/ | sed 's/^/  /'
echo "dist: $d ready, version $v ($(cd "$d" && find . -type f | wc -l | tr -d ' ') files)"

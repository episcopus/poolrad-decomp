# Distribution of the CoCo 3 port

Date: 2026-10-25. Written when `make dist` was added, as the answer to "how should this be shared". It is advice and a plan, not legal advice: the owner of the game should ask somebody who is qualified before anything is published.

## 1. What `make dist` makes (build/dist, for testers)

`make dist` builds every distribution of the port and puts each in its own folder of `build/dist` (ignored by git), with a README of its own for the person who plays, and one at the top that says what each is:

| Folder | Build | Medium |
|---|---|---|
| `01-floppy-35track` | `make floppy` | 12 standard disks, a few swaps (`docs/PHASE-8.10.md`, `PHASE-8.11.md`) |
| `02-floppy-80track-xroar` | `make floppy80` | 5 disks of 80 tracks, XRoar and 80 track drives |
| `03-coco-sdc` | `make sdc` | one file for the CoCo SDC |
| `04-superide-card` | `make ide` | the card file for a SuperIDE (for one card's offset) and `tools/ide_card.py` |
| `05-xroar-ide` | `make ide-xroar-pack` | one data file and a launcher for XRoar |
| `06-mame-ide` | `make ide-mame-pack` | one data file, the Lua that starts it and a launcher for MAME |

The texts are `tools/pack/dist/`, `tools/pack/README-xroar.txt` and `README-mame.txt`; `scripts/dist.sh` copies them and writes `SHA256SUMS`. **Everything in `build/dist` carries the game's data (art, maps, text) and the game's translated code: it is a copy of the game.**

## 2. Why that folder must not be what the public gets

The repository as it is cannot go public, and what the builds contain is the reason a release of them would be the same problem:

* `poolrad/` (186 files, 16 MB: the original DAX files, the executable, the overlay file) **is tracked in git**, in every one of the 1,686 commits. The README says so: never push this repository to a public remote. Today the only remote is a folder in Dropbox.
* Every disk, card file and CHD contains those data files (the image is a repacking of them) and the banks are a translation of the original's code. Whoever receives them has the game.
* `tests/sessions/golden` holds PNG screenshots of the game and recordings of its behaviour.
* `docs/` holds about 250 tracked files of other people's material (`docs/dos-decomp-projects`, `art-of-assembly`, `decomp-tools`, handbooks and PDFs). `docs/reference/prior-art.md` lists licences that range from MIT to GPL-3.0 and RRSAL (non-commercial); some of those projects are marked read only.
* Not a problem: the firmware (`ports/coco3/roms` holds only `.gitkeep`) and the Turbo Pascal compiler (`build/toolchain` is ignored).

## 3. What other decompilation projects do, and what I would do

The practice that works (Super Mario 64, Zelda and the other matching decompilations, OpenRCT2, the engine reimplementations): **publish the code and the tools, never the game's files; the user brings a legally obtained copy and the build makes the disks on their own machine.** `make inputs` already pins the sha256 of every original file, which is the check those projects use.

For this project:

1. **A clean public repository, not this one.** `git filter-repo` can strip `poolrad/`, the screenshots and the third party documents from the history, but one mistake leaves the data in a pack file for ever, and the working history is full of agent traffic. The safer way is a new repository made by an export script that copies an allow list (the decompiled sources are the owner's decision; the tools, the engine, the process docs) and starts a new history. This repository stays private.
2. **A LICENSE** for what is original (the tools, the engine in `ports/coco3/src/engine`, the docs), and a README that says what the repository does not contain and where the game comes from (the original files from a purchase of the game; the sha256 list).
3. **A `docs/` audit**: keep your own notes, drop or replace by links the copied third party material; the GPL and non-commercial sources of `prior-art.md` are already marked read only and must not be quoted.
4. **A decision about the decompiled source** (`src/*.PAS`, the C translation, the ports): it is a derivative of a commercial program. The usual projects publish it and accept the risk without publishing assets; some do not. That is the owner's call and the reason to ask a lawyer.
5. **Taking things down**: a CONTACT and a promise to remove on request, as every such project has.

## 4. Releases and CI

**Use GitHub Releases and Actions, for what has no game data in it.**

* **CI on every push** (Actions, a Linux runner, the public `jamieleecho/coco-dev` image for CMOC and LWTOOLS): the tests and checks that need no original data (the Python tests of the tools, lint, `make readability`, the engine tests that run in the toolchain, a build of the engine and the runtime). What needs the original files (the translation, the goldens, every session) does **not** run on a public runner: there are no files there and they must not be put there as a secret or a cache. It runs on the maintainer's machine, or on a self hosted runner that holds the files, with the result reported as a badge.
* **A release on a tag** that attaches: the source archive, the checksums of the expected inputs, the docs, and a **builder kit** (the scripts and tools to run `make dist` with `DATA=/path/to/original/files`). Optionally the **C port's programs for Windows, macOS and Linux** that read the player's own data folder (the way OpenRCT2 and ScummVM work), if the owner is comfortable that their code is a translation of the original's.
* **Not attached**: any `.DSK`, `.IMG`, `.chd`, card file, POOL.BIN or zip of `build/dist`. Testers get those privately from the maintainer (a link to a private storage), as today.
* **Versioning**: a `VERSION` file and the same number in the engine's splash and the README of every folder, so a bug report says which build it came from (the quality of life step has started this: `ports/coco3/VERSION`).
* **A `make dist DATA=...` for the player**: today `make dist` takes the originals from `poolrad/` of the working tree. For the public builder it should take a path, check the hashes and say what is missing. That is a small change to `tools/mkimage.py` and the Makefile and is worth doing with the release.

## 5. What to do first

1. Decide the policy of section 3 (publish the sources or not; the licence).
2. Make the export script and a dry run into a scratch repository; read what is in it.
3. Add the data free CI workflow and the release workflow (a draft, to try on the scratch repository first).
4. Only then `git remote add` anything public.

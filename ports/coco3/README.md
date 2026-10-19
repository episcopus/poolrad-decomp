# ports/coco3: Pool of Radiance for the Tandy Color Computer 3 (Phase 8)

This directory is the root of the CoCo 3 port's dev workflow: the Makefile, the scripts, the
sources, the probes and the build output all live here and use paths relative to it. The research and the
plan are in `../../docs/coco/` (start with `README.md` and `PORTING-GUIDE.md` there); the
result of each step of the plan is recorded in `docs/`.

Status: steps 8.0 (toolchain baseline), 8.1 (measure), 8.1c (data model study), 8.2 (translator profile,
placement model, 4bpp goldens), 8.3 (the engine core), 8.4 (the data pipeline), 8.5 (first light) and 8.6 (exploration) are done, see `docs/PHASE-8.0.md` ... `docs/PHASE-8.6.md`.
Step 8.6: `walk-explore` (the 3D view and the area map) and `camp-save` (camp, saving the party and the game) play on the emulated CoCo and match
the goldens on screen and state (`make exploration`): the saved files are the ones the original wrote, byte for byte except record pointers.
Combat is the next step (8.7).
Step 8.5: the game itself, translated, runs on the emulated CoCo 3 (`make first-light`, headless MAME). `boot-title` shows the original's
ssi-logo, title and credits screens bit for bit; `create-character` plays the whole session (wheel, race, sex, class, alignment, the
rolled sheet, head and body, the icon editor, the save) and its labelled screens are equal to the goldens, the character record and
the character list it wrote are equal to the original's, and 391 places of DGROUP are equal (58 differ for reasons written down in
`data/state_ignore.txt`: pointers, the PC's System variables). The game's storage is one container image behind `sec_io` (decision D13);
the development backend is the harness' own, so there is no window to play in yet (`make game-view` shows what a session showed).
The engine (`src/engine`) boots the machine, runs the frame clock and the keyboard, unpacks DAX pictures, draws text, tiles and blits, and serves
the game through a call gate between two MMU tasks; the game's 48 code banks load on demand.

## Quick start

```sh
cd ports/coco3
make doctor        # docker, the coco-dev image, ROMs, xroar
make test          # builds the banked demo, runs it in headless MAME and XRoar, checks the mailbox
make probe P=byte-arith    # run a CMOC probe on the emulated CoCo 3 and print its results
make sizes         # 8.1: compile every generated unit with CMOC and tabulate the 6809 sizes
make heap-stats    # 8.1: heap peak and DGROUP use over the recorded sessions (needs `make c-golden` once)
make prof          # 8.1c: references to data per key by routine and unit, on a profiling build of the C game
make coco-host     # 8.2: translate with --profile coco, build on the host, replay the sessions (full state compared)
make place-host    # 8.2: the placement model (mapped 16-bit heap, banked windows) on the host
make golden4       # 8.2: the 4bpp screen goldens on both host builds
make eng-tests     # 8.3: every engine test on the emulated CoCo 3 (MAME and XRoar), screens compared with the goldens
make eng-test T=t_scene   # one test; t_scene draws a picture, text and tiles from a .DSK (build/run/t_scene-mame.png)
make game          # 8.5: translate, lay out DGROUP, compile and link the game (core, banks, engine); build/game
make game-run S=create-character   # 8.5: run a session in MAME, keep the screens (build/run/game-<S>-sNN.scr4), check them against goldens/4bpp
make game-state S=create-character # 8.5: the files it wrote and DGROUP against the host's (needs `make host` and `make c-golden` once)
make first-light   # 8.5: both sessions, screens and state
make exploration   # 8.6: walk-explore and camp-save, screens and state
make game-view S=create-character  # 8.5: play a session and open what it showed as an animated GIF
make data          # 8.4: the nine volumes (build/data/*.dsk); make data-verify checks them, make vol-tests reads every block on the CoCo
make gfx-ref       # 8.3: rerun the Phase 7 C engine on the t_gfx script and compare with goldens/engine
make help
```

## What runs where

| Piece | Where | Why |
|---|---|---|
| CMOC 0.1.100, LWTOOLS 4.25 (`lwasm`, `lwlink`), ToolShed (`decb`) | container `jamieleecho/coco-dev` (`make` starts it per command, ports/coco3 mounted at `/work`) | pinned toolchain, same on every machine |
| Headless MAME 0.287 with Lua | the same container | scripted tests (`lua/mailbox.lua`) |
| XRoar | the host (`brew install xroar`), `-ui null` for tests, windowed for `make run-demo` | second emulator, raw RAM dumps |
| Host tools (`tools/*.py`) | host or container, standard library only | symbol export, DECB packing, mailbox dump |

Inside the container (for example a devcontainer) `make` builds in place instead of starting a container.

## ROMs

The firmware is copyrighted and is never committed (`roms/` is ignored by git). Put these in `roms/`:

| File | Used by |
|---|---|
| `coco3.zip` (a MAME romset holding `coco3.rom`) | headless MAME |
| `coco3.rom` (32,768 bytes, Super Extended BASIC), `disk11.rom` (8,192 bytes, RS-DOS cartridge) | XRoar |

`make doctor` says what is missing. The zip from the older `coco3-test` project works (it holds both ROMs).

## Layout

| Path | What |
|---|---|
| `Makefile` | the front door (`make help`) |
| `scripts/` | shell behind the targets: `lib.sh` (container helpers), `mame_run.sh`, `xroar_run.sh`, `doctor.sh`, `toolchain-report.sh`, `asm-probe.sh`, `sizes.sh`, `heap_stats.sh`, `prof_run.sh`, `coco_host.sh`, `place_host.sh`, `golden4.sh`, `gfx_ref.sh` (the host reference of 8.3), `mame_vec.sh` (what MAME's CPU sees in the vector page) |
| `tools/` | step 8.0: `symexport.py` (core symbols for banks), `mkdecb.py` (DECB packing), `mbdump.py` (mailbox results), `maplimit.py`, `bankcheck.py`, `cpbench.py`; step 8.1: `mkshim.py` (the CMOC shim of `pool.h`; the translator's own `--profile coco` replaced `cmocify.py`), `unitsizes.py`, `unitgraph.py`, `dgroup_stats.py`; step 8.1c: `mkprof.py`, `prof_report.py`, `constplace.py` |
| `prof/` | `prof_rt.c`, the runtime of the profiling build (call edges, DGROUP references, far pointer dereferences per key) |
| `shim/` | stand-ins for the C library headers CMOC lacks (`stdint.h`, `stddef.h`, `string.h`) |
| `placement.toml`, `goldens/4bpp/`, `goldens/engine/` | step 8.2: where each pointer type's blocks live (mapped, banked, engine); the 4bpp screen digests of the seven sessions; step 8.3: the digests of the engine script (`t_gfx.s4`) |
| `lua/mailbox.lua` | MAME autoboot script: types the LOADM command, waits for the mailbox, dumps it and a screenshot |
| `src/engine/` | the engine: `boot.asm` (takeover), `mmu.asm`, `farcall.asm` (far-call trampoline, bank loader), `disk.asm` + `rsdos.c` (DSKCON, RS-DOS), `rle.asm` + `dax.c`, `vol.c` (volumes), `gfx.c` + `kernels.asm` (screen, text, pictures, blits), `irq.asm` (frame clock, tick, keyboard), `eng.h`, `mailbox.*`, link scripts |
| `data/volumes.json`, `tools/mkvolumes.py`, `tools/rsdos.py` | step 8.4: which files go on which volume; the packer; the RS-DOS image writer and reader |
| `src/engtest/`, `test/` | the engine tests (`t_disk t_pic t_gfx t_gfxv t_irq t_perf t_scene t_skew t_vol t_vol2`, run by `make eng-test T=`) and the host reference `test/gfx_ref.c` |
| `src/game/`, `src/engine/api.c`, `engcall.asm`, `gameboot.c`, `img.c` | step 8.5: the game's side (the CoCo runtime in C: strings, heaps, paging, system, files, the wrappers of the engine's routines, the game's start) and the engine's side of the call gate, its API, its loader and the sector interface |
| `tools/mkgame.py`, `mkvm.py`, `mkplan.py`, `mkimage.py`, `mkgamedisk.py`, `gamecheck.py`, `statecheck.py`, `scr4gif.py`, `dis6809.py`, `data/state_ignore.txt`, `lua/watch.lua`, `scripts/game_*.sh` | step 8.5: the build of the game (split into banks, stubs, link, the engine), the DGROUP layout and image, the container image and the program disk, the screen and state checks against the goldens and the host, a 6809 disassembler, the MAME harness that serves the storage, plays the session script and keeps screens and memory |
| `src/demo/` | the banked hello world: a resident core and two code banks |
| `probes/` | CMOC probes: runtime ones (`*.c`, run on the CoCo) and generated-code ones (`asm/*.c`) |
| `docs/` | one report per step of the plan |
| `build/`, `roms/` | generated and local, ignored by git |

## The test mailbox

Every test program ends in `mb_finish()`. Results go through a mailbox at logical `$1000` (physical
`$71000`, block `$38`; Disk BASIC's RAM vectors and disk variables below `$0E00` must stay intact for DSKCON): magic `PRAD`, a checkpoint counter, a status byte (1 pass, 2 fail), a failure
count, the acknowledge byte of `mb_hold` and 32 result words (`src/engine/mailbox.inc`). MAME's Lua script polls it and writes 80
bytes; XRoar stops at `_mb_halt` (address from the linker map) and writes a raw 512 KB RAM dump in
physical address order. `tools/mbdump.py` reads both. This is the checkpoint protocol of
`../../docs/coco/research/08-emulators-testing-workflow.md` section 5 in its first, small form.

## Conventions

- Source for the CoCo is built with `cmoc --void-target --no-relocate -O2 -Wgives-byte -Wsign-compare`
  and assembly with `lwasm --6809` (no 6309 opcode may slip in).
- Banks are linked at `$8000` with no CMOC library: they see the core only through absolute symbols
  generated from the core's map (`tools/symexport.py`), and fail to link if the core lacks one.
- Same writing rules as the rest of the repository (`../../AGENTS.md`): evidence tagged **[V]**,
  **[S]**, **[E]**, **[?]**; no em or en dashes; small commits with the `p8:` prefix.
- Proprietary material (ROMs, SSI data, the compiler of the Pascal build) is never committed.

# ports/coco3/Makefile: front door of the CoCo 3 port's dev workflow. This directory is the
# root: every path below is relative to it, the toolchain container mounts it as /work.
# Public targets run the compilers in the jamieleecho/coco-dev image (or in place when this
# shell is already inside it) and the emulators headless; `make help` lists them.

SHELL := /bin/bash
HAVE_TC := $(shell command -v lwasm >/dev/null 2>&1 && command -v cmoc >/dev/null 2>&1 && echo yes)
TC := $(if $(HAVE_TC),,scripts/tc.sh)
# the make that runs inside the toolchain (the host's path does not exist in the container)
IMAKE := $(if $(HAVE_TC),$(MAKE),make)

CMOCLIB := /usr/local/share/cmoc/lib
# CMOC for the bare-metal takeover: the void target has no ROM dependencies; no relocation.
CC := cmoc -c --void-target --no-relocate -O2 -Wgives-byte -Wsign-compare -Isrc/engine -Ibuild/game/inc
AS := lwasm --6809 -fobj -Isrc/engine
LINKLIBS := -L$(CMOCLIB) -lcmoc-crt-void -lcmoc-std-void

ENGINE_OBJ := build/obj/boot.o build/obj/mailbox.o
P ?= byte-arith

.PHONY: ide ide-run ide-check ide-card floppy80 floppy-xroar80 routine-profile code-profile rebank io-budget floppy-xroar sdc sdc-run floppy-check floppy floppy-model floppy-traces floppy-layout floppy-run perf-run perf-all step-check bank-groups play snd-check snd-wav game-wav stress game help doctor toolchain eng-data eng-test eng-tests gfx-ref data data-verify vol-test vol-tests sizes heap-stats prof coco-host place-host golden4 golden4-record demo test-demo run-demo probe probes asm-probe bench test clean risk-scan baseline
.DEFAULT_GOAL := help

help:
	@echo "ports/coco3: CoCo 3 port dev workflow (root of the port)"
	@echo "  make doctor         check docker, the image, ROMs, xroar"
	@echo "  make toolchain      print the toolchain versions (in the container)"
	@echo "  make eng-test T=t_disk   step 8.3: build an engine test (src/engtest), its .DSK, run in MAME and XRoar, check"
	@echo "                      t_disk t_pic (8.3a, b: disk, DAX, title screens) t_gfx (c: text, tiles, blits) t_irq (d: frame clock, keys)"
	@echo "                      t_perf (e: what drawing costs) t_scene (a picture, text and tiles from one disk)"
	@echo "                      t_gfxv (8.4: the same screens from a volume) t_vol2 (two volumes at once) t_skew (disk speed)"
	@echo "  make data           8.4: build the volumes (build/data: nine .dsk images, the containers, manifest, headers)"
	@echo "  make data-verify    8.4: rebuild (bytes must be identical), read the images back, compare with tools/re/dax.py, decb reads them"
	@echo "  make vol-test VOL=n 8.4: every block of volume n read from its image on the emulated CoCo, MAME and XRoar"
	@echo "  make vol-tests      the nine volumes"
	@echo "  make eng-tests      every engine test"
	@echo "  make snd-check      8.8: the CoCo's sound driver on the host against the oracle's golden (clang, no emulator)"
	@echo "  make snd-wav        8.8: the twenty tunes as WAV files, the host model's and the emulated CoCo's (needs MAME)"
	@echo "  make game-wav S=x   8.8: a session of the game with its sound as a WAV (build/run/game-x.wav)"
	@echo "  make gfx-ref        rerun the Phase 7 C engine on the t_gfx script and compare with goldens/engine (WRITE=1 rewrites)"
	@echo "  make sizes          compile every generated unit of ../../c/game with CMOC, tabulate the sizes (step 8.1)"
	@echo "  make heap-stats     replay the sessions on a heap-stats build of the C game: heap peak, DGROUP use"
	@echo "  make prof           who references which data per key: profile build of the C game, report (step 8.1c)"
	@echo "  make coco-host      step 8.2: translate with the coco profile, build on the host, replay the sessions"
	@echo "  make place-host     step 8.2: the placement model (mapped 16-bit heap, banked accessor) on the host, sessions replayed"
	@echo "  make golden4        check the 4bpp screen goldens (goldens/4bpp) on the PC and coco profile host builds"
	@echo "  make golden4-record rewrite them from the verified PC profile build"
	@echo "  make demo           build the banked hello world (build/demo/demo.bin, demo.dsk)"
	@echo "  make test-demo      build, run in headless MAME and XRoar, check the mailbox"
	@echo "  make run-demo       run the demo in a windowed XRoar (interactive look)"
	@echo "  make probe P=name   build probes/name.c, run it in MAME and XRoar, print results"
	@echo "  make probes         run every probe"
	@echo "  make bench          far-call cost against a resident call, measured in MAME"
	@echo "  make asm-probe P=name   compile probes/asm/name.c to 6809 assembly and print it"
	@echo "  make floppy         step 8.10: the game as a set of 35 track disks (build/floppy/disks/POOLnn.DSK), the entries laid out for the fewest swaps"
	@echo "  make floppy-check   every session on the disks in MAME (the harness swaps the disks the engine asks for): screens, files written, swaps"
	@echo "  make floppy-traces  record the sessions' storage reads again (then make floppy-profile keeps them as data/floppy_runs.json)"
	@echo "  make ide            step 8.12: the SuperIDE build (build/ide/POOLIDE.IMG for the card, build/ide/POOLBOOT.DSK); make ide-run S=boot-title plays one on the model of the card; make ide-check all 16"
	@echo "  make sdc            step 8.10: the CoCo SDC's single file (build/sdc/POOL.DSK); make sdc-run S=boot-title plays one on the model of the SDC"
	@echo "  make test           everything above that has a pass or fail"
	@echo "  make clean"

doctor:
	@scripts/doctor.sh

toolchain:
	@$(TC) scripts/toolchain-report.sh

sizes:
	@$(TC) scripts/sizes.sh

heap-stats:
	@scripts/heap_stats.sh

prof:
	@scripts/prof_run.sh >/dev/null
	@python3 tools/prof_report.py ../..

# the static checks for the classes of defect steps 8.5 to 8.7 met (docs/RISKS.md): run after `make game`; section 8 needs the CMOC warnings
risk-scan:
	@scripts/risk_cmoc.sh
	@python3 -I tools/riskscan.py --write
	@python3 -I tools/winscan.py
	@echo 'report: build/risk/report.md'

coco-host:
	@scripts/coco_host.sh

place-host:
	@scripts/place_host.sh

golden4:
	@scripts/golden4.sh check

golden4-record:
	@scripts/golden4.sh record

demo:
	@$(TC) $(IMAKE) --no-print-directory build/demo/demo.dsk

test-demo: demo
	@scripts/mame_run.sh build/demo/demo.dsk DEMO build/run/demo-mame
	@echo "--- demo in MAME"; python3 -I tools/mbdump.py build/run/demo-mame.mbx --check
	@scripts/xroar_run.sh build/demo/demo.bin build/demo/core.map build/run/demo-xroar.ram; rc=$$?; \
	  if [ $$rc -eq 77 ]; then echo "xroar skipped"; elif [ $$rc -ne 0 ]; then exit $$rc; \
	  else echo "--- demo in XRoar"; python3 -I tools/mbdump.py build/run/demo-xroar.ram --ram --check; fi

run-demo: demo
	xroar -m coco3 -rompath roms -ram 512 -ram-init clear -tv-input rgb -no-cart -run build/demo/demo.bin

probe:
	@$(TC) $(IMAKE) --no-print-directory build/probe/$(P).dsk build/probe/$(P).bin
	@scripts/mame_run.sh build/probe/$(P).dsk PROBE build/run/$(P)-mame
	@echo "--- $(P) in MAME"; python3 -I tools/mbdump.py build/run/$(P)-mame.mbx probes/$(P).c
	@scripts/xroar_run.sh build/probe/$(P).bin build/probe/$(P).map build/run/$(P)-xroar.ram; rc=$$?; \
	  if [ $$rc -eq 77 ]; then echo "xroar skipped"; elif [ $$rc -ne 0 ]; then exit $$rc; \
	  else echo "--- $(P) in XRoar"; python3 -I tools/mbdump.py build/run/$(P)-xroar.ram --ram probes/$(P).c; fi

# Probes that are answered by the generated code, not by running it (make asm-probe P=name).
asm-probe:
	@$(TC) scripts/asm-probe.sh $(P)

PROBES := $(filter-out zxbench lz4bench,$(patsubst probes/%.c,%,$(wildcard probes/*.c)))      # (the two decoder benchmarks need a sample: build/run/zx/bench.sh, docs/PHASE-8.9b.md)
probes:
	@for p in $(PROBES); do $(MAKE) --no-print-directory probe P=$$p || exit 1; done

# Far-call cost on the emulated machine: 1000 far calls against 1000 resident calls.
bench: demo
	@scripts/mame_run.sh build/demo/demo.dsk DEMO build/run/demo-mame
	@python3 -I tools/cpbench.py build/run/demo-mame.cp

test: test-demo eng-tests gfx-ref data-verify vol-tests

gfx-ref:
	@scripts/gfx_ref.sh $(if $(WRITE),--write)

clean:
	rm -rf build/eng build/gfxref build/demo build/obj build/probe build/run build/exp

# ---------------------------------------------------------------- builds (inside the toolchain)

build/obj/%.o: src/engine/%.asm src/engine/mailbox.inc src/engine/banks.inc
	@mkdir -p $(@D); $(AS) -DENG_TEST=1 -o $@ $<
build/obj/%.o: src/engine/%.c src/engine/mailbox.h
	@mkdir -p $(@D); $(CC) -DENG_TEST -o $@ $<

# Probes: one C file, the engine boot, no code banks.
build/probe/%.o: probes/%.c src/engine/mailbox.h
	@mkdir -p $(@D); $(CC) -o $@ $<
build/probe/%.bin build/probe/%.map: build/probe/%.o $(ENGINE_OBJ) build/obj/nobanks.o src/engine/core.link
	lwlink --format=decb --script=src/engine/core.link --map=build/probe/$*.map \
	  -o build/probe/$*.bin $(ENGINE_OBJ) build/obj/nobanks.o build/probe/$*.o $(LINKLIBS)
	python3 -I tools/stripbin.py build/probe/$*.bin
build/probe/%.dsk: build/probe/%.bin
	rm -f $@; decb dskini $@; decb copy -2 -b $< $@,PROBE.BIN

# The banked demo: the core, two code banks at $8000, staged at $4000/$5000 by LOADM.
build/demo/%.o: src/demo/%.c src/engine/mailbox.h
	@mkdir -p $(@D); $(CC) -o $@ $<
build/demo/%.o: src/demo/%.asm src/engine/banks.inc
	@mkdir -p $(@D); $(AS) -o $@ $<
build/demo/core.bin build/demo/core.map: build/obj/boot.o build/obj/farcall.o build/demo/demoload.o build/demo/farstubs.o \
    build/demo/core.o build/obj/mailbox.o src/engine/core.link
	lwlink --format=decb --script=src/engine/core.link --map=build/demo/core.map \
	  -o build/demo/core.bin build/obj/boot.o build/obj/farcall.o build/demo/demoload.o build/demo/farstubs.o \
	  build/demo/core.o build/obj/mailbox.o $(LINKLIBS)
	python3 -I tools/maplimit.py build/demo/core.map program_end 3FFF
	python3 -I tools/stripbin.py build/demo/core.bin
# A bank sees the core only through the absolute symbols it references (tools/symexport.py).
build/demo/bank%syms.asm: build/demo/core.map build/demo/bank%_entries.o build/demo/bank%.o
	python3 -I tools/symexport.py build/demo/core.map $@ build/demo/bank$*_entries.o build/demo/bank$*.o
build/demo/bank%.raw: build/demo/bank%_entries.o build/demo/bank%.o build/demo/bank%syms.o src/engine/bank.link
	lwlink --format=raw --script=src/engine/bank.link --map=build/demo/bank$*.map -o $@ \
	  build/demo/bank$*_entries.o build/demo/bank$*.o build/demo/bank$*syms.o
	python3 -I tools/bankcheck.py build/demo/bank$*.map
build/demo/bank%syms.o: build/demo/bank%syms.asm
	$(AS) -o $@ $<
build/demo/demo.bin: build/demo/core.bin build/demo/bank1.raw build/demo/bank2.raw
	python3 -I tools/mkdecb.py -o $@ --base build/demo/core.bin \
	  --seg 4000:build/demo/bank1.raw:4096 --seg 5000:build/demo/bank2.raw:4096
build/demo/demo.dsk: build/demo/demo.bin
	rm -f $@; decb dskini $@; decb copy -2 -b $< $@,DEMO.BIN
.SECONDARY:

# ---------------------------------------------------------------- engine tests (step 8.3)
POOLRAD_DATA ?= ../../poolrad
ENG_OBJ := build/obj/boot.o build/obj/mailbox.o build/obj/mmu.o build/obj/disk.o build/obj/irq.o build/obj/snd.o build/obj/rsdos.o build/obj/rle.o build/obj/kernels.o build/obj/vol.o build/obj/dax.o build/obj/gfx.o build/obj/nobanks.o
ENG_TESTS := $(filter-out t_vol,$(patsubst src/engtest/%.c,%,$(wildcard src/engtest/t_*.c)))
T ?= t_disk
ENG_LIMIT_t_skew := 400
VOL ?= 0
ENG_LIMIT_t_vol := 600
ENG_FLOPS_t_vol = build/data/vol$(VOL).dsk
ENG_FLOPS_t_vol2 = build/data/vol0.dsk
ENG_FLOPS_t_gfxv = build/data/vol0.dsk
ENG_KEYS_t_irq := 12 !A\\n

eng-data:
	@python3 -I tools/engdata.py $(POOLRAD_DATA) build/eng
	@$(if $(filter t_snd,$(T)),tools/snd_check.sh expect)

eng-test: eng-data data
	@$(TC) $(IMAKE) --no-print-directory build/eng/$(T).dsk build/eng/$(T).bin
	@$(if $(ENG_FLOPS_$(T)),MB_FLOPS="$(ENG_FLOPS_$(T))") $(if $(ENG_LIMIT_$(T)),MB_LIMIT=$(ENG_LIMIT_$(T)) MB_SECONDS=$(ENG_LIMIT_$(T))) MB_SCREENS=1 $(if $(ENG_KEYS_$(T)),MB_KEYS="$(ENG_KEYS_$(T))" MB_KEYS_CP=5) scripts/mame_run.sh build/eng/$(T).dsk TEST build/run/$(T)-mame
	@echo "--- $(T) in MAME"; python3 -I tools/mbdump.py build/run/$(T)-mame.mbx --check
	@$(if $(ENG_FLOPS_$(T)),XROAR_FLOPS="$(ENG_FLOPS_$(T))") $(if $(ENG_LIMIT_$(T)),XROAR_SECONDS=$(ENG_LIMIT_$(T))) scripts/xroar_run.sh build/eng/$(T).bin build/eng/$(T).map build/run/$(T)-xroar.ram build/eng/$(T).dsk; rc=$$?; \
	  if [ $$rc -eq 77 ]; then echo "xroar skipped"; elif [ $$rc -ne 0 ]; then exit $$rc; \
	  else echo "--- $(T) in XRoar"; python3 -I tools/mbdump.py build/run/$(T)-xroar.ram --ram --check; \
	  fi
	@echo "--- $(T) screens"; python3 -I tools/engcheck.py $(T)

# ---------------------------------------------------------------- the game (step 8.5)
game:
	@$(TC) scripts/game_build.sh

# Look at it. The game reads its storage through sec_io (decision D13); the development backend is the harness' own, a write tap
# of MAME's Lua, so there is no window to play in until a backend XRoar or a real CoCo can serve (DriveWire, after 8.9).
# Until then: play a session headless and watch what the game showed, as an animated GIF (every screen that stayed for
# a moment, in order) opened in the default viewer. S=<session> (boot-title, create-character), LIMIT=<emulated seconds>.
game-view: game
	MB_SESSION=$(or $(KEYS),/repo/tests/sessions/$(S).keys) MB_LIMIT=$(or $(LIMIT),$(if $(filter create-character,$(S)),700,300)) scripts/game_run.sh build/run/game-$(S) > /dev/null
	python3 -I tools/scr4gif.py build/run/game-$(S) build/run/game-$(S).gif
	@if command -v open >/dev/null 2>&1; then open build/run/game-$(S).gif; else echo "open build/run/game-$(S).gif"; fi

run-game:
	@echo "make run-game: the game's storage is the harness' (D13): use 'make play' (a MAME window on the host) or 'make game-view S=create-character'" >&2; exit 2

# step 8.8b: play the game in a MAME window (needs MAME on the host: brew install mame). make play [CPU=6309] [FAST=2] [FRESH=1]
play: game
	$(TC) python3 -I tools/mkgamedisk.py build/game build/gen/vm/DGROUP.IMG build/game/pool.dsk
	$(TC) python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG build/game/pool.img
	scripts/play.sh $(if $(CPU),--cpu $(CPU)) $(if $(FAST),--fast $(FAST)) $(if $(FRESH),--fresh) $(if $(KEYLOG),--keylog)

# ---------------------------------------------------------------- the floppy set (step 8.10, docs/PHASE-8.10.md)
# The image of `make game` cut into 35 track disks (build/floppy/disks/POOLnn.DSK, boot disk 01): which entry goes on which disk is a layout
# (tools/mklayout.py) optimised for the swaps of the sessions' reads (data/floppy_runs.json, the profile). `make floppy` does all of it from the build of `make game`.
# After a change of the game: `make floppy-traces` records every session again on an image without shared blocks (a few minutes) and `make floppy-profile` keeps it.
floppy-model:
	@mkdir -p build/trace build/floppy
	@$(TC) python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG build/trace/pool-nodedupe.img --nodedupe --model build/trace/model.json

floppy-traces: floppy-model
	@mkdir -p build/trace/runs; rm -f build/trace/runs/*.out
	@scripts/floppy_traces.sh

floppy-profile:
	@python3 tools/mklayout.py profile --runs data/floppy_runs.json

floppy-layout: floppy-model
	@python3 tools/mklayout.py $(if $(NAIVE),naive,make) --out build/floppy/layout.json

# the interleave of the data files on the disks (1 = none; 5 and 7 are the others that fit; see docs/PHASE-8.10.md section 8)
IL ?= 1
floppy: game floppy-layout
	@rm -rf build/floppy/disks
	@$(TC) python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG build/floppy/pool.img --layout build/floppy/layout.json --floppies build/floppy/disks --interleave $(IL)

# play the set in a window of XRoar (brew install xroar): four drives, disks 1 to 4 in them (XRoar numbers the drives 1 to 4, Disk BASIC 0 to 3), the rest asked for on the CoCo's
# screen: eject the disk in the drive the game names (XRoar: File, Drive n, Insert disk...). The disks are copied first (the game saves into them): build/floppy/xroar/
floppy-xroar: floppy
	@rm -rf build/floppy/xroar; mkdir -p build/floppy/xroar; cp build/floppy/disks/*.DSK build/floppy/xroar/
	xroar -m coco3 -rompath roms -ram 512 -ram-init clear -tv-input rgb -cart rsdos -load-fd0 build/floppy/xroar/POOL01.DSK -load-fd1 build/floppy/xroar/POOL02.DSK -load-fd2 build/floppy/xroar/POOL03.DSK -load-fd3 build/floppy/xroar/POOL04.DSK -type 'LOADM"POOL":EXEC\r'

# The same set on four disks of 80 tracks (XRoar and 80 track drives; docs/PHASE-8.11.md section 7): the game's data is 1.36 MB, an 80 track disk holds 364 KB, so four
# disks, one in each of XRoar's four drives, never have to be swapped; the saves are a fifth disk, asked for when the game saves or loads.
floppy80: game floppy-model
	@mkdir -p build/floppy80
	@TRACKS=80 python3 tools/mklayout.py make --drives 4 --extra 0 --out build/floppy80/layout.json
	@rm -rf build/floppy80/disks
	@$(TC) env TRACKS=80 python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG build/floppy80/pool.img --layout build/floppy80/layout.json --floppies build/floppy80/disks

floppy-xroar80: floppy80
	@rm -rf build/floppy80/xroar; mkdir -p build/floppy80/xroar; cp build/floppy80/disks/*.DSK build/floppy80/xroar/
	xroar -m coco3 -rompath roms -ram 512 -ram-init clear -tv-input rgb -cart rsdos -load-fd0 build/floppy80/xroar/POOL01.DSK -load-fd1 build/floppy80/xroar/POOL02.DSK -load-fd2 build/floppy80/xroar/POOL03.DSK -load-fd3 build/floppy80/xroar/POOL04.DSK -type 'LOADM"POOL":EXEC\r'

# step 8.11: what the sessions ask of the storage (docs/PHASE-8.11.md): every session once with the storage log, then kilobytes by kind, bank loads, the worst 30 s of code
# traffic and the seconds of reading on each medium, against data/io_budget.json. make io-budget [NORUN=1] [CHECK=1] [WRITE=1]
io-budget: game
	@$(if $(NORUN),:,scripts/io_runs.sh)
	@python3 tools/iobudget.py $(if $(CHECK),--check) $(if $(WRITE),--write)

# step 8.11, code residency: the routines each session runs in the original (oracle, build/profile/<session>.json and .seq), the routines of the banked
# units with their sizes and the static call graph (build/profile/code.json, needs the last `make game`), and the banks chosen from both
# (data/routine_banks.json, read by tools/mkgame.py). make rebank WRITE=1 [SLOTS=7] [LIMIT=15600]
routine-profile:
	cd ../.. && ls tests/sessions/*.keys | xargs -n1 basename | sed 's/\.keys$$//' | grep -v create-elf-mage | xargs -P 5 -n 1 .venv/bin/python ports/coco3/tools/routine_profile.py
code-profile:
	$(TC) python3 -I tools/codeprof.py
rebank:
	python3 tools/rebank.py $(if $(WRITE),--write) $(if $(SLOTS),--slots $(SLOTS)) $(if $(LIMIT),--limit $(LIMIT)) $(if $(SHOW),--show)

# every session on the disks, five at a time, then the screens, the files written and the swaps counted (docs/PHASE-8.10.md)
floppy-check:
	@scripts/floppy_all.sh

# a session on the disks (MAME headless; lua/watch.lua mounts the disks the game asks for): make floppy-run S=boot-title
floppy-run:
	MB_SESSION=/repo/tests/sessions/$(S).keys MB_LIMIT=$(or $(LIMIT),300) scripts/floppy_run.sh build/run/floppy-$(S)

# the CoCo SDC's single file (docs/PHASE-8.10.md): a 35 track disk with POOL.BIN in front of the game's image, read through the SDC's command mode
sdc: game
	@mkdir -p build/sdc
	@$(TC) python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG build/sdc/pool.img --sdc build/sdc/POOL.DSK

# the SuperIDE build (docs/PHASE-8.12.md): the engine with the IDE driver in place of the disks' and the SDC's (POOL.BIN in build/ide/engine, the rest of the game is
# `make game`'s), the game's image laid out for the card (two sectors in a card sector, tools/mkimage.py --ide), and the boot drive that HDB-DOS loads POOL.BIN from.
# The card sector of the image's sector 0 is the first sector of HDB-DOS virtual drive IDE_DRIVE+1: HDB-DOS offset of the card + IDE_DRIVE * 630 + 630. The defaults are the
# user's 256 MB card (HDB-DOS offset $052DDC = 339420). IDE_ADDR is the interface's base address ($FF50 = 65360).
IDE_HDB_OFFSET ?= 339420
IDE_DRIVE ?= 200
IDE_ADDR ?= 65360
IDE_LBA0 = $(shell expr $(IDE_HDB_OFFSET) + $(IDE_DRIVE) \* 630)
IDE_LBA_BASE = $(shell expr $(IDE_HDB_OFFSET) + $(IDE_DRIVE) \* 630 + 630)
IDE_OUT ?= build/ide
ide: game
	@mkdir -p $(IDE_OUT)
	$(TC) env IDE=1 IDE_LBA_BASE=$(IDE_LBA_BASE) IDE_ADDR=$(IDE_ADDR) IDE_SLOW=$(IDE_SLOW) python3 tools/mkgame.py --engine $(IDE_OUT)/engine build/game
	$(TC) python3 -I tools/mkimage.py /repo/poolrad build/game build/gen/vm/DGROUP.IMG $(IDE_OUT)/pool.img --ide $(IDE_OUT)/POOLIDE.IMG --pool-bin $(IDE_OUT)/engine/POOL.BIN --ide-boot $(IDE_OUT)/POOLBOOT.DSK
	@printf 'IDE_LBA0=%s\nIDE_LBA_BASE=%s\nIDE_DRIVE=%s\nIDE_HDB_OFFSET=%s\n' $(IDE_LBA0) $(IDE_LBA_BASE) $(IDE_DRIVE) $(IDE_HDB_OFFSET) > $(IDE_OUT)/ide.env
	@echo "ide: boot drive $(IDE_DRIVE) at card sector $(IDE_LBA0), the image from card sector $(IDE_LBA_BASE); $(IDE_OUT)/POOLIDE.IMG goes to the card (tools/ide_card.py, docs/PHASE-8.12.md)"

# The same for XRoar's Glenside IDE cartridge (docs/PHASE-8.12.md section 7): the card file is the whole hard disk (offset 0, boot drive 0, the image from sector 630) in
# build/ide-xroar, so that the build of the real card in build/ide is left as it is. One file, build/ide-xroar/POOLIDE.IMG (a raw image of 512 byte sectors), and the
# engine, which XRoar runs without a DOS; the game saves into a copy of the file (build/ide-xroar/run.img).
ide-xroar-build:
	$(MAKE) ide IDE_OUT=build/ide-xroar IDE_HDB_OFFSET=0 IDE_DRIVE=0

# A folder to give to somebody who has XRoar: the card file, the engine, a double-click launcher and the instructions (build/pool-xroar, and the zip beside it). The CoCo 3 ROM is not in it.
ide-xroar-pack: ide-xroar-build
	@rm -rf build/pool-xroar; mkdir -p build/pool-xroar/roms
	@cp build/ide-xroar/POOLIDE.IMG build/ide-xroar/engine/POOL.BIN tools/pack/README-xroar.txt build/pool-xroar/
	@printf '%s\n' '#!/bin/sh' 'cd "$$(dirname "$$0")" || exit 1' 'exec xroar -m coco3 -ram-init clear -tv-input rgb -rompath "$$PWD/roms:$$HOME/.xroar/roms:/opt/homebrew/share/xroar/roms:/usr/local/share/xroar/roms" -cart ide -load-hd0 POOLIDE.IMG -run POOL.BIN "$$@"' > build/pool-xroar/Play.command
	@chmod +x build/pool-xroar/Play.command; touch build/pool-xroar/roms/PUT-coco3.rom-HERE
	@cd build && rm -f pool-xroar.zip && zip -q -r pool-xroar.zip pool-xroar && ls -l pool-xroar.zip

ide-xroar: ide-xroar-build
	cp build/ide-xroar/POOLIDE.IMG build/ide-xroar/run.img
	xroar -m coco3 -rompath roms -ram 512 -ram-init clear -tv-input rgb -cart ide -load-hd0 build/ide-xroar/run.img -run build/ide-xroar/engine/POOL.BIN

# a session from the SuperIDE file on the model of the interface (MAME headless, lua/watch.lua MB_IDE): make ide-run S=boot-title
ide-run:
	MB_SESSION=/repo/tests/sessions/$(S).keys MB_LIMIT=$(or $(LIMIT),300) scripts/ide_run.sh build/run/ide-$(S)

# every session on it, five at a time, against the goldens and the development run's saves
ide-check:
	@scripts/ide_all.sh

# a session from it (MAME headless, lua/watch.lua's model of the SDC): make sdc-run S=boot-title
sdc-run:
	MB_SESSION=/repo/tests/sessions/$(S).keys MB_LIMIT=$(or $(LIMIT),300) scripts/sdc_run.sh build/run/sdc-$(S)

# The game on the emulated CoCo 3 (MAME, headless): S=session; the screens it shows against goldens/4bpp (tools/gamecheck.py)
S ?= boot-title
game-run: game
	MB_SESSION=$(or $(KEYS),/repo/tests/sessions/$(S).keys) MB_LIMIT=$(or $(LIMIT),300) scripts/game_run.sh build/run/game-$(S)
	python3 -I tools/gamecheck.py $(S) build/run/game-$(S)

# the state of a session's end against the host's (the files it wrote, DGROUP): needs `make host` and `make c-golden` once
game-state:
	python3 -I tools/statecheck.py $(S) build/run/game-$(S)

# step 8.5: both sessions on the CoCo (MAME, headless), screens and state
first-light:
	$(MAKE) game-run S=boot-title LIMIT=300
	$(MAKE) game-run S=create-character LIMIT=700
	$(MAKE) game-state S=create-character

# step 8.7: the combat sessions on the CoCo, screens (state of camp-rest-combat too)
combat:
	$(MAKE) game-run S=camp-rest-combat LIMIT=800
	$(MAKE) game-state S=camp-rest-combat
	$(MAKE) game-run S=parley-combat LIMIT=800
	$(MAKE) game-state S=parley-combat

# step 8.7b: every session on the CoCo, five at a time (one disk image: built first), then the verdicts (docs/PHASE-8.7b.md)
BASELINE_SESSIONS := $(filter-out create-elf-mage,$(patsubst ../../tests/sessions/%.keys,%,$(wildcard ../../tests/sessions/*.keys)))
# step 8.7c: the proof that no encounter can fill the banked heap: a build in which every group an ECL script adds is N times as large (up to the 63 members
# of MaxEncounterMembers), one session played on it, the heaps' high water read from the run (docs/HEAP-STUDY.md). A test build: `make game` makes the game again.
#   make stress N=3 S=council-guards
stress:
	@$(TC) env POOL_STRESS=$(N) scripts/game_build.sh >/dev/null
	@MB_SESSION=/repo/tests/sessions/$(S).keys MB_LIMIT=$(or $(LIMIT),6000) scripts/game_run.sh build/run/game-$(S)-stress$(N) > build/run/game-$(S)-stress$(N).out 2>&1
	@python3 -I tools/mbdump.py build/run/game-$(S)-stress$(N).mbx | grep -E "status|r(22|23|24|29|30) "
	@python3 -I tools/heaptab.py build/run/game-$(S)-stress$(N).core
	@echo "this was a test build: run 'make game' before anything else"

baseline: game
	@MB_SESSION=/repo/tests/sessions/boot-title.keys MB_LIMIT=300 scripts/game_run.sh build/run/game-boot-title > /dev/null 2>&1
	@printf '%s\n' $(filter-out boot-title,$(BASELINE_SESSIONS)) | xargs -P 5 -I{} sh -c 'MB_NOBUILD=1 MB_SESSION=/repo/tests/sessions/{}.keys MB_LIMIT=2500 scripts/game_run.sh build/run/game-{} > build/run/game-{}.out 2>&1'
	@for s in $(BASELINE_SESSIONS); do printf '%-18s ' $$s; python3 -I tools/gamecheck.py $$s build/run/game-$$s 2>&1 | tail -1; done
	@for s in $(BASELINE_SESSIONS); do printf '%-18s ' $$s; python3 -I tools/savecheck.py build/game/pool.img build/run/game-$$s.saves 2>&1 | tail -1; done

# step 8.9: where the time goes (docs/PHASE-8.9a.md). perf-run plays one session with the program counter sampled every frame, every far call
# logged and every storage request logged, then prints: busy time by unit and by engine call, the bank pool under other sizes and policies, and
# what was read from the image. perf-all does it for every session (five at a time, the image built first); bank-groups chooses which banks
# share a bank from those logs (WRITE=1 writes data/bank_groups.json, which `make game` reads).
perf-run: game
	MB_PCLOG=0-$(or $(LIMIT),2500) MB_BANKLOG=0-$(or $(LIMIT),2500) MB_SECLOG=1 MB_SESSION=/repo/tests/sessions/$(S).keys MB_LIMIT=$(or $(LIMIT),2500) scripts/game_run.sh build/run/prof-$(S) > build/run/prof-$(S).out 2>&1
	python3 -I tools/prof_pc.py build/run/prof-$(S).out --unit --top 12
	python3 -I tools/prof_pc.py build/run/prof-$(S).out --api --top 25
	python3 -I tools/bankpool_sim.py build/run/prof-$(S).banklog
	python3 -I tools/seclog.py build/run/prof-$(S).out --rate 12.6

perf-all: game
	@MB_SESSION=/repo/tests/sessions/boot-title.keys MB_LIMIT=300 scripts/game_run.sh build/run/game-boot-title > /dev/null 2>&1
	@printf '%s\n' $(BASELINE_SESSIONS) | xargs -P 5 -I{} sh -c 'MB_PCLOG=0-2500 MB_BANKLOG=0-2500 MB_SECLOG=1 MB_NOBUILD=1 MB_SESSION=/repo/tests/sessions/{}.keys MB_LIMIT=2500 scripts/game_run.sh build/run/game-{} > build/run/game-{}.out 2>&1'
	@echo "logs in build/run/game-*.out and game-*.banklog (the files the baseline writes, with the profile logs on): make bank-groups, tools/baseline_table.py, tools/stepmetrics.py"

# step 8.9c: one run that proves a step and measures it: every session with the profile logs on, then the screens, the state and the save area against the goldens,
# then the numbers (tools/stepmetrics.py) under LABEL. The image is built first by perf-all. Exit 1 if a labelled screen or the state fails.
step-check: perf-all
	@bad=0; for s in $(BASELINE_SESSIONS); do python3 -I tools/gamecheck.py $$s build/run/game-$$s 2>&1 | tail -1 | grep -q "^$$s: \([0-9]*\) of \1 labelled" || { echo "SCREENS FAIL: $$s"; bad=1; }; done; \
	  for s in $(BASELINE_SESSIONS); do python3 -I tools/savecheck.py build/game/pool.img build/run/game-$$s.saves | grep -q ": ok" || { echo "SAVE AREA FAIL: $$s"; bad=1; }; done; \
	  python3 -I tools/baseline_table.py 2>&1 | awk -F'|' 'NR>2 {print $$2,$$3,$$5,$$6}'; \
	  python3 -I tools/baseline_table.py 2>&1 | grep -E "[1-9][0-9]* open|[1-9][0-9]* differ" | grep -v "0 differ" ; \
	  python3 -I tools/stepmetrics.py "$(LABEL)"; exit $$bad

bank-groups:
	python3 -I tools/bankgroup.py 'build/run/game-*.banklog' --slots 6 --policy lru $(if $(WRITE),--write data/bank_groups.json)

# step 8.8: the sound (docs/PHASE-8.8.md)
snd-check:
	@tools/snd_check.sh

# the twenty tunes as WAV files: the host model's (build/snd/host-reference.wav) and the emulated CoCo's (build/run/t_snd-mame.wav, from the DAC writes)
snd-wav: snd-check
	@build/snd/snd_ref ideal --dac build/snd/ideal.dac 2>/dev/null; python3 -I tools/dac2wav.py build/snd/ideal.dac build/snd/host-reference.wav --units
	@MB_DAC=1 $(MAKE) --no-print-directory eng-test T=t_snd | grep -E "status|MAME"
	@python3 -I tools/dac2wav.py build/run/t_snd-mame.dac build/run/t_snd-mame.wav; python3 -I tools/snd_compare.py build/run/t_snd-mame

# a session of the game with its sound: make game-wav S=combat-spells  ->  build/run/game-<S>.wav
game-wav: game
	MB_DAC=1 MB_SESSION=$(or $(KEYS),/repo/tests/sessions/$(S).keys) MB_LIMIT=$(or $(LIMIT),300) scripts/game_run.sh build/run/game-$(S) > /dev/null
	python3 -I tools/dac2wav.py build/run/game-$(S).dac build/run/game-$(S).wav --squeeze --rate 22050

# step 8.6: the exploration sessions on the CoCo, screens and state
exploration:
	$(MAKE) game-run S=walk-explore LIMIT=500
	$(MAKE) game-state S=walk-explore
	$(MAKE) game-run S=camp-save LIMIT=500
	$(MAKE) game-state S=camp-save

# ---------------------------------------------------------------- data pipeline (step 8.4)
data:
	@python3 -I tools/mkvolumes.py $(POOLRAD_DATA) build/data >/dev/null

data-verify:
	@python3 -I tools/mkvolumes.py $(POOLRAD_DATA) build/data --verify | tail -1
	@$(TC) scripts/decb_check.sh

vol-test: data eng-data
	@mkdir -p build/eng; printf '#include "expect$(VOL).h"\n#define VOLNUM $(VOL)\n' > build/eng/expectvol.h
	@$(MAKE) --no-print-directory eng-test T=t_vol VOL=$(VOL)

vol-tests:
	@for n in 0 1 2 3 4 5 6 7 8; do $(MAKE) --no-print-directory vol-test VOL=$$n || exit 1; done

eng-tests:
	@for t in $(ENG_TESTS); do $(MAKE) --no-print-directory eng-test T=$$t || exit 1; done

build/eng/%.o: src/engtest/%.c src/engine/eng.h src/engine/mailbox.h
	@mkdir -p $(@D); $(CC) -Ibuild/eng -Ibuild/data -o $@ $<
build/eng/t_vol.o: build/eng/expectvol.h
build/eng/t_snd.o: src/snd/snd.h src/snd/snd_core.c src/snd/snd_driver.c build/eng/snd_expect.h
# t_snd links the interrupts and the sound only (the driver and its tunes are 8 KB of the test)
ENG_OBJ_t_snd := build/obj/boot.o build/obj/mailbox.o build/obj/mmu.o build/obj/irq.o build/obj/snd.o build/obj/nobanks.o
build/eng/t_snd.bin build/eng/t_snd.map: build/eng/t_snd.o $(ENG_OBJ_t_snd) src/engine/core.link
	lwlink --format=decb --script=src/engine/core.link --map=build/eng/t_snd.map \
	  -o build/eng/t_snd.bin $(ENG_OBJ_t_snd) build/eng/t_snd.o $(LINKLIBS)
	python3 -I tools/maplimit.py build/eng/t_snd.map program_end 7BFF
	python3 -I tools/stripbin.py build/eng/t_snd.bin
build/eng/%.bin build/eng/%.map: build/eng/%.o $(ENG_OBJ) src/engine/core.link
	lwlink --format=decb --script=src/engine/core.link --map=build/eng/$*.map \
	  -o build/eng/$*.bin $(ENG_OBJ) build/eng/$*.o $(LINKLIBS)
	python3 -I tools/maplimit.py build/eng/$*.map program_end 7BFF
	python3 -I tools/stripbin.py build/eng/$*.bin
# t_vol2: the program rides on the SET 2 volume itself (drive 0), BASE is drive 1
build/eng/t_vol2.dsk: build/eng/t_vol2.bin build/data/vol2.dsk
	cp build/data/vol2.dsk $@; decb copy -2 -b build/eng/t_vol2.bin $@,TEST.BIN
build/eng/%.dsk: build/eng/%.bin
	rm -f $@; decb dskini $@; decb copy -2 -b $< $@,TEST.BIN
	for f in build/eng/disk/*; do decb copy -2 -b $$f $@,$$(basename $$f); done

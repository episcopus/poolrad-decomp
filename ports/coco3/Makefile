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

.PHONY: game help doctor toolchain eng-data eng-test eng-tests gfx-ref data data-verify vol-test vol-tests sizes heap-stats prof coco-host place-host golden4 golden4-record demo test-demo run-demo probe probes asm-probe bench test clean
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

PROBES := $(patsubst probes/%.c,%,$(wildcard probes/*.c))
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
	@mkdir -p $(@D); $(AS) -o $@ $<
build/obj/%.o: src/engine/%.c src/engine/mailbox.h
	@mkdir -p $(@D); $(CC) -o $@ $<

# Probes: one C file, the engine boot, no code banks.
build/probe/%.o: probes/%.c src/engine/mailbox.h
	@mkdir -p $(@D); $(CC) -o $@ $<
build/probe/%.bin build/probe/%.map: build/probe/%.o $(ENGINE_OBJ) build/obj/nobanks.o src/engine/core.link
	lwlink --format=decb --script=src/engine/core.link --map=build/probe/$*.map \
	  -o build/probe/$*.bin $(ENGINE_OBJ) build/obj/nobanks.o build/probe/$*.o $(LINKLIBS)
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
ENG_OBJ := build/obj/boot.o build/obj/mailbox.o build/obj/mmu.o build/obj/disk.o build/obj/irq.o build/obj/rsdos.o build/obj/rle.o build/obj/kernels.o build/obj/vol.o build/obj/img.o build/obj/dax.o build/obj/gfx.o build/obj/nobanks.o
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
	MB_SESSION=/repo/tests/sessions/$(S).keys MB_LIMIT=$(or $(LIMIT),$(if $(filter create-character,$(S)),700,300)) scripts/game_run.sh build/run/game-$(S) > /dev/null
	python3 -I tools/scr4gif.py build/run/game-$(S) build/run/game-$(S).gif
	@if command -v open >/dev/null 2>&1; then open build/run/game-$(S).gif; else echo "open build/run/game-$(S).gif"; fi

run-game:
	@echo "make run-game: the game's storage is the harness' (D13): use 'make game-view S=create-character' for now" >&2; exit 2

# The game on the emulated CoCo 3 (MAME, headless): S=session; the screens it shows against goldens/4bpp (tools/gamecheck.py)
S ?= boot-title
game-run: game
	MB_SESSION=/repo/tests/sessions/$(S).keys MB_LIMIT=$(or $(LIMIT),300) scripts/game_run.sh build/run/game-$(S)
	python3 -I tools/gamecheck.py $(S) build/run/game-$(S)

# the state of a session's end against the host's (the files it wrote, DGROUP): needs `make host` and `make c-golden` once
game-state:
	python3 -I tools/statecheck.py $(S) build/run/game-$(S)

# step 8.5: both sessions on the CoCo (MAME, headless), screens and state
first-light:
	$(MAKE) game-run S=boot-title LIMIT=300
	$(MAKE) game-run S=create-character LIMIT=700
	$(MAKE) game-state S=create-character

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
build/eng/%.bin build/eng/%.map: build/eng/%.o $(ENG_OBJ) src/engine/core.link
	lwlink --format=decb --script=src/engine/core.link --map=build/eng/$*.map \
	  -o build/eng/$*.bin $(ENG_OBJ) build/eng/$*.o $(LINKLIBS)
	python3 -I tools/maplimit.py build/eng/$*.map program_end 5FFF
# t_vol2: the program rides on the SET 2 volume itself (drive 0), BASE is drive 1
build/eng/t_vol2.dsk: build/eng/t_vol2.bin build/data/vol2.dsk
	cp build/data/vol2.dsk $@; decb copy -2 -b build/eng/t_vol2.bin $@,TEST.BIN
build/eng/%.dsk: build/eng/%.bin
	rm -f $@; decb dskini $@; decb copy -2 -b $< $@,TEST.BIN
	for f in build/eng/disk/*; do decb copy -2 -b $$f $@,$$(basename $$f); done

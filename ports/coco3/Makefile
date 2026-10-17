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
CC := cmoc -c --void-target --no-relocate -O2 -Wgives-byte -Wsign-compare -Isrc/engine
AS := lwasm --6809 -fobj -Isrc/engine
LINKLIBS := -L$(CMOCLIB) -lcmoc-crt-void -lcmoc-std-void

ENGINE_OBJ := build/obj/boot.o build/obj/mailbox.o
P ?= byte-arith

.PHONY: help doctor toolchain demo test-demo run-demo probe probes asm-probe bench test clean
.DEFAULT_GOAL := help

help:
	@echo "ports/coco3: CoCo 3 port dev workflow (root of the port)"
	@echo "  make doctor         check docker, the image, ROMs, xroar"
	@echo "  make toolchain      print the toolchain versions (in the container)"
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

test: test-demo

clean:
	rm -rf build/demo build/obj build/probe build/run build/exp

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
build/demo/core.bin build/demo/core.map: build/obj/boot.o build/obj/farcall.o build/demo/farstubs.o \
    build/demo/core.o build/obj/mailbox.o src/engine/core.link
	lwlink --format=decb --script=src/engine/core.link --map=build/demo/core.map \
	  -o build/demo/core.bin build/obj/boot.o build/obj/farcall.o build/demo/farstubs.o \
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

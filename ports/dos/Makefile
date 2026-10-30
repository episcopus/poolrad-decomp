# ports/dos/Makefile: the DOS port, the original PC game rebuilt from the decompiled Pascal (src/) with this
# port's patches (patches/series), for the original machines (EGA, CGA or Tandy; 8088 and up). Run from here
# or with `make -C ports/dos <target>`. src/, `make rebuild` and the other ports are never touched: the build
# stages a copy of src/ under build/.

ROOT := ../..
PY := $(if $(wildcard $(ROOT)/.venv/bin/python),$(ROOT)/.venv/bin/python,python3)

.PHONY: help game faithful sessions tandy test play dist clean
.DEFAULT_GOAL := help

help:
	@echo "ports/dos: the PC game from the decompiled Pascal, with this port's patches (README.md)"
	@echo "  make game          build/game/START.EXE and GAME.OVR (the patches of patches/series; ONLY=name.patch for one)"
	@echo "  make faithful      the same build with no patch: must link the original program byte for byte"
	@echo "  make sessions      replay every session of tests/sessions on the port against the original in the oracle (SESSION=name, SOUND=T|P|S); the gate for speed patches, about 15 min"
	@echo "  make tandy         Tandy 1000 check in DOSBox-X, headless: titles, then the menu, never the wheel"
	@echo "  make test          faithful, game and tandy (about 90 s): enough while the patches change single routines"
	@echo "  make play          the port's game in a DOSBox-X window (Tandy machine, about 1000 EX speed); opens a window"
	@echo "  make dist          build/dist: the two files to copy onto the machine, with INSTALL.TXT"
	@echo "  make clean"

game:
	$(PY) tools/build.py $(if $(ONLY),--only $(ONLY))

faithful:
	$(PY) tools/build.py --faithful

sessions:
	$(PY) tools/sessions.py $(if $(SESSION),--session $(SESSION)) $(if $(SOUND),--sound $(SOUND))

tandy:
	$(PY) tools/tandy.py

# the faithful build first (it proves the pipeline), then the game and its behaviour on the Tandy machine.
# `make sessions` is not part of it: it is the gate for patches whose code can no longer be compared byte for byte
test: faithful game tandy

play:
	$(PY) tools/tandy.py --play

dist: game
	rm -rf build/dist && mkdir -p build/dist
	cp build/game/START.EXE build/game/GAME.OVR build/dist/
	perl -pe 's/\r?\n/\r\n/' INSTALL.TXT > build/dist/INSTALL.TXT
	cd build/dist && shasum -a 256 START.EXE GAME.OVR | perl -pe 's/\r?\n/\r\n/' > SHA256.TXT
	@echo "dist: build/dist (START.EXE, GAME.OVR, INSTALL.TXT, SHA256.TXT)"

clean:
	rm -rf build

# ports/dos/Makefile: the DOS port, the original PC game rebuilt from the decompiled Pascal (src/) with this
# port's patches (patches/series), for the original machines (EGA, CGA or Tandy; 8088 and up). Run from here
# or with `make -C ports/dos <target>`. src/, `make rebuild` and the other ports are never touched: the build
# stages a copy of src/ under build/.

ROOT := ../..
PY := $(if $(wildcard $(ROOT)/.venv/bin/python),$(ROOT)/.venv/bin/python,python3)

.PHONY: help game faithful ref func prof sessions sound-patches sound-check tandy tandy-deep test play dist clean
.DEFAULT_GOAL := help

help:
	@echo "ports/dos: the PC game from the decompiled Pascal, with this port's patches (README.md)"
	@echo "  make game          build/game/START.EXE and GAME.OVR (the patches of patches/series; ONLY=name.patch for one)"
	@echo "  make faithful      the same build with no patch: must link the original program byte for byte"
	@echo "  make ref           build/ref: the series without its speed patches (patches/speed/), the behaviour they must keep"
	@echo "  make func          the gate for speed patches: the suite (sessions/suite.txt) on ref and game in Tandy video and sound, compared (SESSION=name), about 3 min"
	@echo "  make prof          the 8088 profile of the game, and its gain over ref, per session (SESSION=name, ACTIONS=1 for what each key costs)"
	@echo "  make sessions      replay every session of tests/sessions on ref against the original in the oracle (SESSION=name, SOUND=T|P|S): the behaviour patches, about 15 min"
	@echo "  make sound-patches patches/tandy-sound.patch and tandy-strike.patch from sound/designs.py and sound/picks.json"
	@echo "  make sound-check   every tune of the game's Tandy driver in the oracle against what the listening page played (10 s)"
	@echo "  make tandy         Tandy 1000 check in DOSBox-X, headless: titles, then the menu, never the wheel"
	@echo "  make tandy-deep    DOSBox-X again, ref against game past the titles: a saved game, the 3D view, a character sheet, the area map (2.5 min)"
	@echo "  make test          faithful, game, ref, func, sound-check and tandy (about 6 min)"
	@echo "  make play          the port's game in a DOSBox-X window (Tandy machine, about 1000 EX speed); opens a window"
	@echo "  make dist          build/dist: the two files to copy onto the machine, with INSTALL.TXT"
	@echo "  make clean"

game:
	$(PY) tools/build.py $(if $(ONLY),--only $(ONLY))

faithful:
	$(PY) tools/build.py --faithful

ref:
	$(PY) tools/build.py --ref

func: game ref
	$(PY) tools/func.py $(if $(SESSION),--session $(SESSION))

prof: game ref
	$(PY) tools/prof.py --build ref $(if $(SESSION),--session $(SESSION))
	$(PY) tools/prof.py --build game $(if $(SESSION),--session $(SESSION))
	$(PY) tools/prof.py --diff ref game $(if $(SESSION),--session $(SESSION))
	$(if $(ACTIONS),$(PY) tools/prof.py --build game --actions --in-order --detail 5 $(if $(SESSION),--session $(SESSION)))

# the replay cannot follow the sound patches (tandy-sound grows res03, which moves DGROUP and every pointer in it;
# tandy-strike adds a wait, which changes the clock readings): the reference it replays leaves them out, and
# sound-check proves the driver instead
SOUND_PATCHES := tandy-sound.patch tandy-strike.patch

sessions:
	$(PY) tools/build.py --ref $(foreach p,$(SOUND_PATCHES),--without $(p))
	$(PY) tools/sessions.py $(if $(SESSION),--session $(SESSION)) $(if $(SOUND),--sound $(SOUND))

sound-patches:
	$(PY) sound/port.py

sound-check: game
	$(PY) sound/capture.py
	$(PY) sound/capture.py --build build/link --out port.json
	$(PY) sound/check.py

tandy:
	$(PY) tools/tandy.py

tandy-deep: game ref
	$(PY) tools/tandy.py --deep

# the faithful build first (it proves the pipeline), then the game, the speed patches' behaviour against the
# reference (func), the Tandy driver (sound-check), and the game on the Tandy machine. `make sessions` (the reference against the original, 15 min)
# is for changes to the behaviour patches.
test: faithful game ref func sound-check tandy

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

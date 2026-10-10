# Pool of Radiance decompilation: every command humans and agents use.
# Targets marked (Pn) are delivered in that phase of docs/spec/SPEC.md; until then they say so.

PY ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
EXE := poolrad/start-unpack.exe
OVR := poolrad/GAME.OVR

PACKED := poolrad/START.EXE

.PHONY: help setup doctor inputs unexepack overlays map dax smoke status next ghidra p1-check \
        tp-install tp-probe tp-compare tp-pin tpc emu2 \
        packet lock unlock \
        oracle-run oracle-dosbox golden sessions host hybrid fuzz test check review-pass dos coco3

help:
	@echo "Available now:  setup doctor inputs unexepack overlays map dax smoke"
	@echo "Phase 1:        status next ghidra p1-check packet lock unlock"
	@echo "Turbo Pascal:   emu2 tp-install tp-probe tp-compare tp-pin tpc (docs/setup/SETUP-tp.md)"
	@echo "Data codecs:    make dax (all playbook-20 formats); make test (pytest)"
	@echo "Phase 2:        oracle-run oracle-dosbox golden"
	@echo "Phase 3:        host hybrid fuzz sessions check review-pass"
	@echo "Later:          dos (P8) coco3 (P7)"
	@echo "See AGENTS.md and docs/spec/SPEC.md."

setup:            ## install the toolchain on macOS (see docs/setup/SETUP-macos.md)
	sh tools/setup/setup-macos.sh

doctor:           ## check the environment and pinned inputs
	bash tools/setup/doctor.sh

inputs:           ## verify hashes of poolrad/ against re/inputs.toml
	$(PY) tools/setup/inputs.py --check

unexepack:        ## reproduce start-unpack.exe from START.EXE (EXEPACK) and check byte match
	$(PY) tools/re/unexepack.py $(PACKED) --check $(EXE)

overlays:         ## regenerate the overlay manifest and extract overlay code to build/re
	$(PY) tools/re/tpovl.py $(EXE) $(OVR) -o build/re/overlays.json --extract build/re/overlays

map: overlays     ## fill units.toml ranges, enumerate routines, tag RTL/names (playbook 10)
	$(PY) tools/re/update_units.py
	$(PY) tools/re/enumerate_routines.py --merge
	$(PY) tools/re/name_units.py
	$(PY) tools/re/rtl_ident.py
	$(PY) tools/agent/status.py

dax:              ## verify DAX container + all playbook-20 codecs over pinned files
	$(PY) tools/re/dax.py verify poolrad/
	$(PY) tools/re/geo.py verify poolrad/
	$(PY) tools/re/ecl.py verify poolrad/
	$(PY) tools/re/pic.py verify poolrad/
	$(PY) tools/re/walldef.py verify poolrad/
	$(PY) tools/re/records.py verify poolrad/
	$(PY) tools/re/items.py verify poolrad/
	$(PY) tools/re/save.py verify poolrad/SAVE

smoke:            ## run the original code in Unicorn up to its first interrupts (de-risks P2)
	$(PY) tools/oracle/smoke.py $(EXE)

status:           ## regenerate work/status.md from re/ inventory
	$(PY) tools/agent/status.py

next:             ## print the next unit from work/queue.toml
	$(PY) tools/agent/next.py

ghidra: map       ## rebuild the Ghidra project (build/ghidra/, not committed)
	@test -n "$$GHIDRA_INSTALL_DIR" || (echo 'ghidra: source tools/setup/env.local.sh first'; exit 1)
	$(PY) tools/ghidra/import_tp.py

p1-check:         ## verify Phase 1 exit criteria (SPEC section 10)
	$(PY) tools/agent/p1_check.py

# Turbo Pascal version pin (WHITEPAPER 2.2, docs/setup/SETUP-tp.md). Compiler archives are
# never committed: they live in build/toolchain/dist/.
emu2:             ## build the headless DOS emulator used by tp-probe (tools/vendor/emu2)
	sh tools/setup/build-emu2.sh

tp-install:       ## verify build/toolchain/dist/ hashes and extract TPC.EXE + TURBO.TPL per version
	$(PY) tools/re/tp_toolchain.py install

tp-probe:         ## compile tools/re/tp_probe/SINK.PAS with each installed compiler
	$(PY) tools/re/tp_toolchain.py probe

tp-compare:       ## align our System/Crt/Dos/Overlay code with each probe; build/toolchain/compare.md
	$(PY) tools/re/tp_toolchain.py compare

tp-pin: tp-install tp-probe tp-compare  ## all of the above

tpc:              ## compile SRC=<file.pas> with the pinned TP 6.0 (VER=, DISASM=1, OPTS='/$$R+') into build/tpc/
	@test -n "$(SRC)" || (echo 'tpc: usage: make tpc SRC=path/FILE.PAS [DISASM=1] [VER=tp70] [OPTS=...]'; exit 2)
	$(PY) tools/re/tp_toolchain.py tpc $(SRC) $(if $(VER),--version $(VER)) $(if $(DISASM),--disasm) $(if $(OPTS),--opts $(OPTS))

packet:           ## write build/packets/<id>.md for UNIT= or FN=
	$(PY) tools/agent/packet.py --unit "$(UNIT)" --fn "$(FN)"

lock:             ## claim a unit: make lock UNIT=ovl00
	UNIT=$(UNIT) $(PY) tools/agent/lock.py

unlock:           ## release a unit lock (FORCE=1 to break stale)
	UNIT=$(UNIT) FORCE=$(FORCE) $(PY) tools/agent/unlock.py

define todo
	@echo "make $@: not built yet; delivered in $(1) (docs/spec/SPEC.md section $(2))."; exit 2
endef

oracle-run:       ## run the original in the oracle: SCRIPT=tests/sessions/x.keys [OUT=dir] [TRACE=ints,calls,files,ports] [MAX=n]
	$(PY) tools/oracle/run.py $(if $(SCRIPT),--script $(SCRIPT)) $(if $(OUT),--out $(OUT)) $(if $(TRACE),--trace $(TRACE)) $(if $(MAX),--max-insns $(MAX))

oracle-dosbox:    ## compare the oracle's title screens with DOSBox-X frames pixel for pixel (needs dosbox-x, ffmpeg)
	$(PY) tools/oracle/dosbox_ref.py
golden:           ## record goldens (each session twice, must match): SESSION=name (default all); CHECK=1 verifies committed goldens
	$(PY) tools/oracle/golden.py $(if $(SESSION),--session $(SESSION)) $(if $(CHECK),--check)
host:        ; $(call todo,Phase 3,11)
hybrid:      ; $(call todo,Phase 3,8.4)
fuzz:        ; $(call todo,Phase 3,8.3)
sessions:    ; $(call todo,Phase 3,8.5)
test:              ## Python unit tests (DAX/GEO/ECL codecs, toolchain probes)
	$(PY) -m pytest -q tests/unit
check:       ; $(call todo,Phase 3,9.6)
review-pass: ; $(call todo,Phase 4,8.1 and playbook 70)
coco3:       ; $(call todo,Phase 7,11)
dos:         ; $(call todo,Phase 8,11)

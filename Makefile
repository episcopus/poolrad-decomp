# Pool of Radiance decompilation: every command humans and agents use.
# Targets marked (Pn) are delivered in that phase of docs/spec/SPEC.md; until then they say so.

PY ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
EXE := poolrad/start-unpack.exe
OVR := poolrad/GAME.OVR

PACKED := poolrad/START.EXE

.PHONY: help setup doctor inputs unexepack overlays map dax smoke status next ghidra p1-check \
        packet lock unlock \
        oracle-run golden sessions host hybrid fuzz test check review-pass dos coco3

help:
	@echo "Available now:  setup doctor inputs unexepack overlays map dax smoke"
	@echo "Phase 1:        status next ghidra p1-check packet lock unlock"
	@echo "Phase 2:        oracle-run golden"
	@echo "Phase 3:        host hybrid fuzz sessions test check review-pass"
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

dax:              ## verify every .DAX archive (container layout and RLE sizes)
	$(PY) tools/re/dax.py verify poolrad/

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

packet:           ## write build/packets/<id>.md for UNIT= or FN=
	$(PY) tools/agent/packet.py --unit "$(UNIT)" --fn "$(FN)"

lock:             ## claim a unit: make lock UNIT=ovl00
	UNIT=$(UNIT) $(PY) tools/agent/lock.py

unlock:           ## release a unit lock (FORCE=1 to break stale)
	UNIT=$(UNIT) FORCE=$(FORCE) $(PY) tools/agent/unlock.py

define todo
	@echo "make $@: not built yet; delivered in $(1) (docs/spec/SPEC.md section $(2))."; exit 2
endef

oracle-run:  ; $(call todo,Phase 2,8.2 and playbook 25)
golden:      ; $(call todo,Phase 2,8.5 and playbook 40)
host:        ; $(call todo,Phase 3,11)
hybrid:      ; $(call todo,Phase 3,8.4)
fuzz:        ; $(call todo,Phase 3,8.3)
sessions:    ; $(call todo,Phase 3,8.5)
test:        ; $(call todo,Phase 2 to 3,8)
check:       ; $(call todo,Phase 3,9.6)
review-pass: ; $(call todo,Phase 4,8.1 and playbook 70)
coco3:       ; $(call todo,Phase 7,11)
dos:         ; $(call todo,Phase 8,11)

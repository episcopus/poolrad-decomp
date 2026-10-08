# Pool of Radiance decompilation: every command humans and agents use.
# Targets marked (Pn) are delivered in that phase of docs/spec/SPEC.md; until then they say so.

PY ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
EXE := poolrad/start-unpack.exe
OVR := poolrad/GAME.OVR

.PHONY: help setup doctor inputs overlays dax smoke status next ghidra packet lock unlock \
        oracle-run golden sessions host hybrid fuzz test check review-pass dos coco3

help:
	@echo "Available now:  setup doctor inputs overlays dax smoke"
	@echo "Phase 1:        status next ghidra packet lock unlock"
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

overlays:         ## regenerate the overlay manifest and extract overlay code to build/re
	$(PY) tools/re/tpovl.py $(EXE) $(OVR) -o build/re/overlays.json --extract build/re/overlays

dax:              ## verify every .DAX archive (container layout and RLE sizes)
	$(PY) tools/re/dax.py verify poolrad/

smoke:            ## run the original code in Unicorn up to its first interrupts (de-risks P2)
	$(PY) tools/oracle/smoke.py $(EXE)

define todo
	@echo "make $@: not built yet; delivered in $(1) (docs/spec/SPEC.md section $(2))."; exit 2
endef

status:      ; $(call todo,Phase 1,9.4)
next:        ; $(call todo,Phase 1,9.4)
ghidra:      ; $(call todo,Phase 1,10 and playbook 10)
packet:      ; $(call todo,Phase 1,9.3)
lock:        ; $(call todo,Phase 1,9.4)
unlock:      ; $(call todo,Phase 1,9.4)
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

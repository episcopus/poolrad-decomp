# Pool of Radiance decompilation: every command humans and agents use.
# Targets marked (Pn) are delivered in that phase of docs/spec/SPEC.md; until then they say so.

PY ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
EXE := poolrad/start-unpack.exe
OVR := poolrad/GAME.OVR

PACKED := poolrad/START.EXE

.PHONY: help setup doctor inputs unexepack overlays map dax smoke status next ghidra p1-check \
        tp-install tp-probe tp-compare tp-pin tpc emu2 \
        packet claim lock locks unlock handoff handoffs handoff-done heartbeat agents watch-agents \
        oracle-run oracle-dosbox timing-scan golden match test test-slow check review-pass rebuild skeleton readability rename host coco3

help:
	@echo "Available now:  setup doctor inputs unexepack overlays map dax smoke"
	@echo "Phase 1:        status next ghidra p1-check packet lock unlock"
	@echo "Turbo Pascal:   emu2 tp-install tp-probe tp-compare tp-pin tpc (docs/setup/SETUP-tp.md)"
	@echo "Data codecs:    make dax (all playbook-20 formats); make test (pytest)"
	@echo "Phase 2:        oracle-run oracle-dosbox golden timing-scan"
	@echo "Phase 3/4:      match (UNIT= FN= WRITE=1) check test test-slow (review-pass in P4)"
	@echo "Later:          rebuild (P5) host (P7, branch track-c-hybrid) coco3 (P8)"
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

next:             ## print the next unit from work/queue.toml (REVIEW=1: the next unit waiting for review)
	$(PY) tools/agent/next.py $(if $(REVIEW),--review)

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
	$(PY) tools/agent/packet.py $(if $(UNIT),--unit $(UNIT)) $(if $(FN),--fn $(FN))

claim:            ## start work: lock the next unit (or UNIT=) and create its worktree: AGENT=<name> [UNIT=<id>] [REVIEW=1] [TASK=doc-<chapter>|map]
	$(PY) tools/agent/claim.py --agent "$(AGENT)" $(if $(UNIT),--unit $(UNIT)) $(if $(REVIEW),--review) $(if $(TASK),--task $(TASK))

lock:             ## claim a unit without a worktree: make lock UNIT=ovl00 [AGENT=name]
	$(PY) tools/agent/lock.py $(UNIT) $(if $(AGENT),--agent $(AGENT))

locks:            ## list the units locked by agents (shared by every worktree of this clone)
	$(PY) tools/agent/lock.py --list

handoff:          ## to the orchestrator: AGENT=<you> UNIT=<id> STATE=complete|partial|blocked|review-passed|review-failed|escalate NOTE="..." [CHANGELOG="<section> | <change> | <evidence>"]
	$(PY) tools/agent/handoff.py --agent "$(AGENT)" --unit "$(UNIT)" --state "$(STATE)" --note "$(NOTE)" --changelog "$(CHANGELOG)"

handoffs:         ## list what waits for the orchestrator: escalations first, then branches to merge
	$(PY) tools/agent/handoff.py --list

handoff-done:     ## after acting on a hand-off: UNIT=<key from make handoffs> [REVIEW=1]; adds its changelog row
	$(PY) tools/agent/handoff.py --unit "$(if $(REVIEW),review-)$(UNIT)" --done

heartbeat:        ## tell the human what you are doing: AGENT=<you> NOTE="<now, next>" [DONE=1 when you stop]; at each step and every 20 minutes
	$(PY) tools/agent/heartbeat.py --agent "$(AGENT)" --note "$(NOTE)" $(if $(DONE),--done)

agents:           ## every agent's last heartbeat, oldest first; QUIET = silent for more than 20 minutes
	$(PY) tools/agent/heartbeat.py --list

watch-agents:     ## live view for the operator: progress, agents, hand-offs, locks, queues; redrawn every 5 seconds (INTERVAL=n; Ctrl+C to stop)
	@$(PY) tools/agent/watch.py --interval $(or $(INTERVAL),5)

unlock:           ## release a unit lock (FORCE=1 to break stale)
	UNIT=$(UNIT) FORCE=$(FORCE) $(PY) tools/agent/unlock.py

define todo
	@echo "make $@: not built yet; delivered in $(1) (docs/spec/SPEC.md section $(2))."; exit 2
endef

oracle-run:       ## run the original in the oracle: SCRIPT=tests/sessions/x.keys [OUT=dir] [TRACE=ints,calls,files,ports] [MAX=n]
	$(PY) tools/oracle/run.py $(if $(SCRIPT),--script $(SCRIPT)) $(if $(OUT),--out $(OUT)) $(if $(TRACE),--trace $(TRACE)) $(if $(MAX),--max-insns $(MAX))

oracle-dosbox:    ## compare the oracle's title screens with DOSBox-X frames pixel for pixel (needs dosbox-x, ffmpeg)
	$(PY) tools/oracle/dosbox_ref.py
timing-scan:      ## find routines that wait on time or input (static; SESSIONS="boot-title create-character" adds the dynamic pass)
	$(PY) tools/re/timing_scan.py $(foreach s,$(SESSIONS),--dynamic $(s))

golden:           ## record goldens and their recordings (each session twice, must match): SESSION=name (default all); CHECK=1 verifies committed goldens
	$(PY) tools/oracle/golden.py $(if $(SESSION),--session $(SESSION)) $(if $(CHECK),--check)
match:            ## prove decompiled Pascal against the original (SPEC 8.3): UNIT=<id> [FN=<name>] [WRITE=1]; no UNIT: every unit with source
	$(PY) tools/match/match.py $(if $(UNIT),$(UNIT),--all) $(foreach f,$(FN),--routine $(f)) $(if $(WRITE),--write)

test:              ## Python unit tests, fast set (codecs, toolchain probes, matcher, oracle, replay)
	$(PY) -m pytest -q -m "not slow" tests/unit
test-slow:         ## the unit tests that boot the real game (minutes; not part of `make check`)
	$(PY) -m pytest -q -m slow tests/unit
check:             ## everything a commit must pass (SPEC 9.6): fast tests, every unit's match and readability, the rebuild links, golden check
	$(PY) -m pytest -q -m "not slow" tests/unit
	$(PY) tools/match/match.py --all
	$(PY) tools/match/readability.py
	$(PY) tools/match/rebuild.py
	$(PY) tools/oracle/golden.py --check
review-pass:       ## record a passed review (playbook 70): UNIT=<id> [CHECK=1 only checks]
	@test -n "$(UNIT)" || (echo 'review-pass: usage: make review-pass UNIT=<id> [CHECK=1]'; exit 2)
	$(PY) tools/agent/review.py $(UNIT) $(if $(CHECK),--check)

rebuild:           ## link the whole game from src/ and compare it with the original (SPEC 8.4)
	$(PY) tools/match/rebuild.py

readability:       ## the checkable readability rules of docs/process/READABILITY.md: UNIT=<id> (no UNIT: every unit with decompiled routines)
	$(PY) tools/match/readability.py $(UNIT)

rename:            ## give a routine or global its real name everywhere: OLD=<name> NEW=<Name> WHY="<evidence>"; APPLY=1 re-applies recorded renames
	$(if $(APPLY),$(PY) tools/match/rename.py --apply,$(PY) tools/match/rename.py "$(OLD)" "$(NEW)" --why "$(WHY)")

skeleton:          ## write src/<ID>.PAS for a unit with no source yet: UNIT=<id> (no UNIT: every game unit)
	$(PY) tools/match/skeleton.py $(if $(UNIT),$(UNIT),--all)
host:        ; $(call todo,Phase 7 (C translation; see branch track-c-hybrid),7.4)
coco3:       ; $(call todo,Phase 8,11)

# Pool of Radiance decompilation: every command humans and agents use.
# Targets marked (Pn) are delivered in that phase of docs/spec/SPEC.md; until then they say so.

PY ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
EXE := poolrad/start-unpack.exe
OVR := poolrad/GAME.OVR

PACKED := poolrad/START.EXE
# Refresh the heartbeat of the agent holding the lock on this branch (tools/agent/heartbeat.py --auto); never fails.
AUTOBEAT = -@$(PY) tools/agent/heartbeat.py --auto
# Keep operator notes literal (including Pascal $ directives), never interpolate them as shell code.
q = '$(subst ','\'',$(1))'

.PHONY: help setup doctor inputs unexepack overlays map dax smoke status next ghidra p1-check \
        tp-install tp-probe tp-compare tp-pin tpc emu2 \
        packet claim lock locks unlock handoff handoffs handoff-done integrate start-run stop-run run-add run-status heartbeat agents watch-agents worker inbox \
        agent-control agent-step safety-check merge-check hooks match-gate merge-driver \
        agent-register agent-usage agent-meter performance learn learning-check expert-budget expert-request expert-take expert-step expert-finish expert-result experts expert-scan expert-candidates task-approve \
        oracle-run oracle-dosbox timing-scan golden match test test-slow check review-pass rebuild skeleton stubs readability rename host coco3

help:
	@echo "Available now:  setup doctor inputs unexepack overlays map dax smoke"
	@echo "Phase 1:        status next ghidra p1-check packet lock unlock"
	@echo "Turbo Pascal:   emu2 tp-install tp-probe tp-compare tp-pin tpc (docs/setup/SETUP-tp.md)"
	@echo "Data codecs:    make dax (all playbook-20 formats); make test (pytest)"
	@echo "Phase 2:        oracle-run oracle-dosbox golden timing-scan"
	@echo "Phase 3/4:      match (UNIT= FN= WRITE=1) check test test-slow (review-pass in P4)"
	@echo "Agent safety:   agent-control agent-step safety-check merge-check merge-driver (docs/process/SAFETY.md)"
	@echo "Throughput:     agent-register agent-meter performance learn experts (docs/process/THROUGHPUT.md)"
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
	$(PY) tools/re/forced_starts.py --write
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
	$(AUTOBEAT) "make tpc $(SRC)"
	@test -n "$(SRC)" || (echo 'tpc: usage: make tpc SRC=path/FILE.PAS [DISASM=1] [VER=tp70] [OPTS=...]'; exit 2)
	$(PY) tools/agent/activity.py tpc -- tpc $(call q,$(value SRC)) $(if $(VER),--version $(call q,$(value VER))) $(if $(DISASM),--disasm) $(if $(OPTS),--opts $(foreach opt,$(value OPTS),$(call q,$(opt))))

packet:           ## write build/packets/<id>.md for UNIT= or FN=
	$(AUTOBEAT) "make packet $(UNIT)$(FN)"
	$(PY) tools/agent/activity.py packet -- $(if $(UNIT),--unit $(call q,$(value UNIT))) $(if $(FN),--fn $(call q,$(value FN)))

claim:            ## start work: lock the next unit (or UNIT=) and create its worktree: AGENT=<name> [UNIT=<id>] [REVIEW=1] [TASK=doc-<chapter>|map]
	$(PY) tools/agent/claim.py --agent $(call q,$(value AGENT)) $(if $(UNIT),--unit $(call q,$(value UNIT))) $(if $(REVIEW),--review) $(if $(TASK),--task $(call q,$(value TASK))) $(if $(HARNESS),--harness $(call q,$(value HARNESS))) $(if $(MODEL),--model $(call q,$(value MODEL))) $(if $(SESSION),--session $(call q,$(value SESSION))) $(if $(VARIANT),--variant $(call q,$(value VARIANT)))

lock:             ## claim a unit without a worktree: make lock UNIT=ovl00 [AGENT=name]
	$(PY) tools/agent/lock.py $(call q,$(value UNIT)) $(if $(AGENT),--agent $(call q,$(value AGENT)))

locks:            ## list the units locked by agents (shared by every worktree of this clone)
	$(PY) tools/agent/lock.py --list

handoff:          ## to the orchestrator: AGENT=<you> UNIT=<id> STATE=complete|partial|blocked|review-passed|review-failed|escalate NOTE="..." [CHANGELOG="<section> | <change> | <evidence>"]
	$(PY) tools/agent/handoff.py --agent $(call q,$(value AGENT)) --unit $(call q,$(value UNIT)) --state $(call q,$(value STATE)) --note $(call q,$(value NOTE)) --changelog $(call q,$(value CHANGELOG))

start-run:        ## admit the run and open one iTerm tab per session of work/roster.toml with its START-AGENT prompt [DRY=1]
	$(PY) tools/agent/run.py start $(if $(filter 1,$(DRY)),--dry)

stop-run:         ## graceful shutdown: drain, integrate what is handed off, release locks, reset state, close the sessions [WAIT=<minutes>]
	$(PY) tools/agent/run.py stop $(if $(WAIT),--wait $(call q,$(value WAIT)))

run-add:          ## start (or restart) one roster session in the running run: NAME=<roster name>
	$(PY) tools/agent/run.py add $(call q,$(value NAME))

run-status:       ## the roster's sessions: heartbeat state, process, locks, inbox
	$(PY) tools/agent/run.py status

integrate:        ## merge every waiting branch hand-off into main mechanically (temp worktree, check, fast-forward): [KEY=<hand-off key>] [DRY=1]
	$(PY) tools/agent/integrate.py $(if $(KEY),--key $(call q,$(value KEY))) $(if $(filter 1,$(DRY)),--dry)

handoffs:         ## list what waits for the orchestrator: escalations first, then branches to merge
	$(PY) tools/agent/handoff.py --list

handoff-done:     ## AGENT=orch UNIT=<key> [REVIEW=1]; requires merged commit and current check receipt; escalations need DECISION=
	$(PY) tools/agent/handoff.py --agent $(call q,$(value AGENT)) --unit $(call q,$(if $(REVIEW),review-)$(value UNIT)) --decision $(call q,$(value DECISION)) --done

heartbeat:        ## tell the human what you are doing: AGENT=<you> NOTE="<now, next>" [DONE=1 when you stop]; at each step and every 20 minutes
	$(PY) tools/agent/heartbeat.py --agent $(call q,$(value AGENT)) --note $(call q,$(value NOTE)) $(if $(DONE),--done)

agents:           ## every agent's last heartbeat, oldest first; QUIET = silent for more than 20 minutes
	$(PY) tools/agent/heartbeat.py --list

watch-agents:     ## live view: progress (units, routines, bytes on main and in unit worktrees), active agents (then by name), hand-offs, locks, queues; stopped and hour-lapsed heartbeats omitted (INTERVAL=n; Ctrl+C to stop)
	@$(PY) tools/agent/watch.py --interval $(or $(INTERVAL),5)

worker:           ## supervisor owning a lock, one model session per batch (docs/process/WORKER.md): AGENT=<name> ROLE=decompiler|reviewer [UNIT=] [BATCH=6] [SESSION_CMD=] [SESSION_MODEL=] [MAX_SESSIONS=] [TIMEOUT=min] [MAX_ATTEMPTS=2] [IDLE=300] [TIER=1|2] [COST_CAP=usd] [HARNESS= MODEL= SESSION= VARIANT=]
	$(PY) tools/agent/worker.py --agent $(call q,$(value AGENT)) --role $(call q,$(value ROLE)) $(if $(UNIT),--unit $(call q,$(value UNIT))) $(if $(BATCH),--batch $(call q,$(value BATCH))) $(if $(SESSION_CMD),--session-cmd $(call q,$(value SESSION_CMD))) $(if $(SESSION_MODEL),--session-model $(call q,$(value SESSION_MODEL))) $(if $(MAX_SESSIONS),--max-sessions $(call q,$(value MAX_SESSIONS))) $(if $(TIMEOUT),--timeout $(call q,$(value TIMEOUT))) $(if $(MAX_ATTEMPTS),--max-attempts $(call q,$(value MAX_ATTEMPTS))) $(if $(IDLE),--idle $(call q,$(value IDLE))) $(if $(HARNESS),--harness $(call q,$(value HARNESS))) $(if $(MODEL),--model $(call q,$(value MODEL))) $(if $(SESSION),--session $(call q,$(value SESSION))) $(if $(VARIANT),--variant $(call q,$(value VARIANT))) $(if $(TIER),--tier $(call q,$(value TIER))) $(if $(COST_CAP),--cost-cap $(call q,$(value COST_CAP)))

inbox:            ## everything waiting for a human, newest last, each with the command that resolves it [JSON=1]
	@$(PY) tools/agent/inbox.py $(if $(filter 1,$(JSON)),--json)

unlock:           ## main only: AGENT=orch UNIT=<key>; recovery: OPERATOR=1 FORCE=1 REASON=<human instruction>
	$(PY) tools/agent/unlock.py $(call q,$(value UNIT)) --agent $(call q,$(value AGENT)) $(if $(filter 1,$(OPERATOR)),--operator) $(if $(filter 1,$(FORCE)),--force) --reason $(call q,$(value REASON))

agent-control:    ## human: STATE=running|paused|draining|stopped OPERATOR=1 REASON=...; no args: display
	$(PY) tools/agent/control.py $(if $(STATE),--state $(call q,$(value STATE))) $(if $(filter 1,$(OPERATOR)),--operator) --reason $(call q,$(value REASON))

task-approve:     ## human: TASK=<name> PATHS=<exact reserved files> OPERATOR=1 REASON=<instruction>
	$(PY) tools/agent/control.py --approve-task $(call q,$(value TASK)) $(foreach p,$(PATHS),--path $(call q,$(p))) $(if $(filter 1,$(OPERATOR)),--operator) --reason $(call q,$(value REASON))

agent-register:   ## creation metadata only: AGENT= ROLE= HARNESS= MODEL= SESSION= [VARIANT=]; does not launch
	$(PY) tools/agent/identity.py --agent $(call q,$(value AGENT)) --role $(call q,$(value ROLE)) --harness $(call q,$(value HARNESS)) --model $(call q,$(value MODEL)) --session $(call q,$(value SESSION)) --variant $(call q,$(value VARIANT))

agent-usage:      ## import one measured usage interval from a harness export, not a guessed price
	$(PY) tools/agent/identity.py --agent $(call q,$(value AGENT)) --usage $(call q,$(value USAGE))

agent-meter:      ## read existing harness session counters only; no model prompt or session creation
	$(PY) tools/agent/meter.py --agent $(call q,$(value AGENT))

performance:      ## attributed tool/task/usage report; legacy/missing metadata remain unknown
	$(PY) tools/agent/performance.py $(if $(RUN),--run $(call q,$(value RUN))) $(if $(filter 1,$(JSON)),--json)

learn:            ## retrieve relevant verified lessons and prior-art guidance before another probe
	$(PY) tools/agent/learning.py --unit $(call q,$(value UNIT)) --query $(call q,$(value QUERY))

learning-check:   ## validate durable learning record shape and evidence pointers
	$(PY) tools/agent/learning.py --check

expert-budget:    ## human: configure one already registered expert and externally enforced billing cap
	$(PY) tools/agent/expert.py budget --agent $(call q,$(value AGENT)) $(if $(filter 1,$(OPERATOR)),--operator) --billing-cap-ref $(call q,$(value BILLING_CAP_REF)) --reason $(call q,$(value REASON))

expert-request:   ## orchestrator: bounded consultation after recorded failures; never launches agents
	$(PY) tools/agent/expert.py request --agent $(call q,$(value AGENT)) --unit $(call q,$(value UNIT)) --fn $(call q,$(value FN)) --category $(call q,$(or $(CATEGORY),codegen)) --question $(call q,$(value QUESTION))

expert-take:      ## approved expert: one active case; deterministic WAIT up to 300 seconds
	$(PY) tools/agent/expert.py take --agent $(call q,$(value AGENT)) --wait $(call q,$(or $(WAIT),0))

expert-step:      ## before more expert reasoning/tool use: deadline, pause and measured-cost guard
	$(PY) tools/agent/expert.py step --agent $(call q,$(value AGENT)) --case $(call q,$(value CASE))

expert-finish:    ## settle bounded advice and measured usage; unknown cost blocks further dispatch
	$(PY) tools/agent/expert.py finish --agent $(call q,$(value AGENT)) --case $(call q,$(value CASE)) --response $(call q,$(value RESPONSE))

expert-result:    ## read structured advice, not a proof verdict or human approval
	$(PY) tools/agent/expert.py result --case $(call q,$(value CASE))

experts:          ## queue/budget outcomes only; no agent/session creation
	$(PY) tools/agent/expert.py list

expert-candidates: ## deterministic triage of repeated failures; no spending or model calls
	$(PY) tools/agent/expert.py candidates

expert-scan:      ## approved orchestrator: automatically queue eligible bounded consultations
	$(PY) tools/agent/expert.py scan --agent $(call q,$(value AGENT))

agent-step:       ## agents: check shared stop/pause state before each routine and after waiting
	$(PY) tools/agent/control.py --step --agent $(call q,$(value AGENT))

safety-check:     ## check branch ownership and registry preservation, without modifying anything
	$(PY) tools/agent/safety.py

hooks:            ## install the per-clone git hooks (pre-commit guard for unit/ and review/ branches); make claim and make integrate do it too
	git config core.hooksPath tools/agent/hooks

match-gate:       ## the regression gate for a matcher change: every L2 routine still matched together and alone, negative fixtures still fail
	$(PY) tools/match/gate.py

merge-check:      ## check HEAD merge, COMMIT=<sha> or STAGED=1 before committing a resolved merge
	$(PY) tools/agent/safety.py --merge-only $(if $(COMMIT),--commit $(call q,$(value COMMIT))) $(if $(STAGED),--staged)

merge-driver:     ## register the record-level merge driver for the shared files of .gitattributes (git config is per clone)
	git config merge.poolrad-shared.name "record-level merge of the shared registries and POOLVARS (tools/agent/merge_shared.py)"
	git config merge.poolrad-shared.driver "$(PY) tools/agent/merge_shared.py %O %A %B %P"
	@echo "merge-driver: registered merge.poolrad-shared in $$(git rev-parse --git-common-dir)/config"

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
	$(AUTOBEAT) "make match $(UNIT)$(if $(FN), FN=$(FN))$(if $(WRITE), WRITE=1)"
	$(PY) tools/agent/activity.py match -- $(if $(UNIT),$(call q,$(value UNIT)),--all) $(foreach f,$(FN),--routine $(call q,$(f))) $(if $(WRITE),--write)

test:              ## Python unit tests, fast set (codecs, toolchain probes, matcher, oracle, replay)
	$(PY) -m pytest -q -m "not slow" tests/unit
test-slow:         ## the unit tests that boot the real game (minutes; not part of `make check`)
	$(PY) -m pytest -q -m slow tests/unit
check:             ## everything a commit must pass (SPEC 9.6): fast tests, every unit's match and readability, the rebuild links, golden check
	$(AUTOBEAT) "make check"
	$(PY) tools/agent/check.py $(if $(filter 1,$(FRESH)),--fresh)
review-pass:       ## record a passed review (playbook 70): UNIT=<id> [CHECK=1 only checks]
	@test -n "$(UNIT)" || (echo 'review-pass: usage: make review-pass UNIT=<id> [CHECK=1]'; exit 2)
	$(PY) tools/agent/review.py $(UNIT) $(if $(CHECK),--check)

rebuild:           ## link the whole game from src/ and compare it with the original (SPEC 8.4)
	$(PY) tools/match/rebuild.py

readability:       ## the checkable readability rules of docs/process/READABILITY.md: UNIT=<id> (no UNIT: every unit with decompiled routines)
	$(PY) tools/agent/activity.py readability -- $(if $(UNIT),$(call q,$(value UNIT)))

rename:            ## give a routine or global its real name everywhere: OLD=<name> NEW=<Name> WHY="<evidence>"; APPLY=1 re-applies recorded renames
	$(if $(APPLY),$(PY) tools/match/rename.py --apply,RENAME_WHY='$(subst ','\'',$(value WHY))' $(PY) tools/match/rename.py "$(OLD)" "$(NEW)")

skeleton:          ## write src/<ID>.PAS for a unit with no source yet: UNIT=<id> (no UNIT: every game unit)
	$(PY) tools/match/skeleton.py $(if $(UNIT),$(UNIT),--all)

stubs:             ## check every {@stub} header against re/symbols.toml (signature, name): UNIT="<id ...>" (no UNIT: every unit); WRITE=1 rewrites
	$(PY) tools/match/stubs.py $(if $(WRITE),--write) $(UNIT)
host:        ; $(call todo,Phase 7 (C translation; see branch track-c-hybrid),7.4)
coco3:       ; $(call todo,Phase 8,11)

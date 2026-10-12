# Throughput without weaker proof

## Read and reuse before probing

Work packets now put an evidence-linked learning brief before disassembly: relevant compiler lessons,
whitepaper sections with line pointers, prior-art/licence guidance and known human-held blockers.
`make learn UNIT=ovl28 QUERY="frame string with"` retrieves the WITH/temporary-lifetime finding that
several earlier agents rediscovered. The reader overlays accepted `main` lessons and the committed
whitepaper on a stale worktree; it does not read main's half-resolved merge files. A local new lesson
can be used as a lead, but accepted main wins over a stale local copy of the same id.

Before another probe or after the first unexplained mismatch:

1. Read the packet's brief and the linked subsystem section of `docs/design/WHITEPAPER.md`.
2. Search `make learn UNIT=<unit> QUERY="<first difference, type or compiler symptom>"`.
3. Check `tools/re/tp_idioms/` and `docs/reference/prior-art.md`. Prior-art claims stay H until proven on
   our build. Other builds' addresses do not apply, and restricted code is never copied.
4. Compile the smallest disputed expression. Save worthwhile **new** probes in
   `tools/re/tp_idioms/<unit>/<8-character-name>.PAS`; do not overwrite another unit's probe.
5. In the same routine commit, add a concise lesson to `re/learnings/<unit>.toml`, with a unique id,
   V/I/H/? confidence, tags, unit ids and durable evidence. Never paste full transcripts or build logs.
   Record failed approaches in blocked notes so the next agent does not repeat them.

Example lesson (a confidence label is a claim for the reviewer, not a machine-written L2 verdict):

```toml
[[lesson]]
id = "ovl00-example-idiom"
confidence = "H"
units = ["ovl00"]
tags = ["frame", "string"]
title = "What to test first"
lesson = "A short, specific diagnostic and the unsuccessful alternatives."
evidence = ["src/OVL00.PAS#RoutineName", "tools/re/tp_idioms/ovl00/PROBE.PAS"]
```

`make learning-check` validates record shape and evidence paths. Reviewers judge the claim itself.
Packets also use the existing forward-target-aware return finder: an early return or provisional map
boundary no longer truncates a routine's disassembly. Source switch directives are shown from the
actual unit, not guessed from an overlay/resident template.

## Attribute actual tasks and tools

At creation, the human/authorized launcher registers the **actual** harness, full provider/model id,
variant if selected, role and harness session id. No new agent is started by registration:

```sh
make agent-register AGENT=dec-1 ROLE=decompiler HARNESS=opencode MODEL=<provider/model> SESSION=<actual-id> VARIANT=<actual-variant>
```

Creation order for launchers: obtain the session id/model from the harness, register it, then deliver
the role prompt. Do not claim work while those values are unknown. `make claim` can also receive
HARNESS, MODEL, SESSION and VARIANT, or POOLRAD_* environment values, for the first registration.
Later claims use the registration. A change of session/harness/model/role creates another immutable
incarnation and cannot reuse a label that still holds work. This is attribution, not authentication.

Each claim gets a task id and immutable base commit. Locks, heartbeats, hand-offs and events carry the
agent incarnation and task id. Use `make match`, `tpc`, `packet` and `readability`, not ad hoc direct
Python calls: the wrappers record elapsed time, return codes, input revisions and actual matcher
results without changing acceptance. Accepted hand-offs attribute registry promotions and proven
code bytes to the submitter, not the orchestrator; review repairs/bookkeeping are not called new
decompilation. Tool time, task wall time and model/billing time are separate quantities.

```sh
make performance
make performance JSON=1 RUN=<run-id>
make agent-meter AGENT=dec-1
```

OpenCode V2 metering uses authenticated CLI `GET /api/session/{id}` from the documented API. It reads
cumulative cost/tokens, validates the registered model/session/variant and never prompts a model or
opens the credentials database. Registration attempts an automatic baseline; unavailable metering
is labelled unknown, not inferred from the model name. Meter after a hand-off and before stopping.
All samplers share a checkpoint, so intervals are not counted twice. The first sample establishes a
baseline; earlier spend remains unattributed. Harness-reported USD is not an invoice.

Other harnesses can import measured intervals through `make agent-usage AGENT=<name> USAGE=<export>`:

```json
{"session":"actual-id","source":"harness export reference","interval_id":"unique-interval",
 "cost_usd":0.30,"tokens":{"input":100,"output":20,"cache_read":0,"cache_write":0}}
```

Duplicates are idempotent; changed duplicates, negative/unknown costs and attribution injection are
rejected. Old labels/events stay legacy/unknown. Do not rank models by raw commits, init counts or
unmatched drafts. Compare accepted bytes, failed trials, repair rounds and measured spend on similar
assignments; the report is not a controlled benchmark and flags incomplete billing coverage.

## One pre-started big-brain expert, automatic bounded delegation

The human starts **one** expert worker per approved run, chooses its powerful model/harness and
registers ROLE=expert. The orchestrator submits cases to its queue; it never starts a replacement or a
subagent. Experts cannot claim game units, edit source/registries, record levels/review passes, approve
human-reserved changes or recursively consult another expert. They return bounded advice to the
original worker, which still must prove it with the pinned compiler and independent review.

Conservative limits approved for this system:

| Limit | Value |
|---|---|
| Active cases | 1 |
| Cases per run | 5 |
| Consultations | 1 per routine/problem/input revision |
| Case lease | 15 minutes, checked before further reasoning/tools |
| Case allocation | USD 10 |
| Run allocation | USD 50, including measured expert idle/overhead after budget baseline |

**Dollar allocations are not hard provider billing ceilings.** Usage is often reported after a model
turn; a turn can overshoot an allocation. Before enabling this queue, give the expert a dedicated
harness/provider budget cap of at most USD 50 and a tool/runtime timeout. Restrict its permissions to
read-only project/reference access and the narrow queue/meter endpoints (optional generated probe
scratch only, never game source). Protect policy, meter and usage files from workers. A lease does not
kill a process or interrupt an in-flight paid request. Without an external cap and trusted counters,
do not enable automatic paid advice. This avoids pretending shell scripts are a financial sandbox.

Human setup, once per run (after run admission and expert registration):

```sh
make expert-budget AGENT=expert-1 OPERATOR=1 BILLING_CAP_REF="<configured provider/harness cap reference>" REASON="human approved one expert, USD 50 cap"
```

The command requires a usable meter and pins the exact expert incarnation and run id. It refuses a
budget reset in the same run or replacement while a case is active/unsettled. Missing/stale/regressing
usage, deadline expiry or overage holds dispatch; unknown spend is never refunded as zero. A trusted
meter recovery can resume pre-dispatch outages. A paid case must finish with measured usage before
the queue resumes. Overages freeze the remaining run; no fallback model/session is launched.

For non-OpenCode harnesses, a trusted bridge must atomically publish cumulative samples at
`<git-common-dir>/poolrad-meter-bridge/<expert-agent-id>.json`:

```json
{"session":"actual-id","model":"provider/model","source":"trusted harness counters",
 "observed_at":1791840000,"cost_usd":1.20,"tokens":{"input":100,"output":20}}
```

Samples must be observed within 120 seconds and match the registered session/model. If a model
variant was selected, include the matching `variant` field too. Never estimate missing dollars from
remembered prices. A deployment without this bridge remains disabled.

Orchestrator loop, automatically after reading hand-offs/activity:

```sh
make expert-scan AGENT=orch
make experts
make expert-result CASE=<case-id>
```

The deterministic scanner finds three distinct recorded failed codegen revisions, or two consecutive
failed review rounds since the last passed review. It skips duplicate consultation revisions and
refuses known human-held decisions. A targeted request is also available:

```sh
make expert-request AGENT=orch UNIT=<unit> FN=<routine-id> CATEGORY=codegen QUESTION="<specific failure>"
```

Cases contain the failed history, current knowledge brief, bounded frozen routine source (possibly
uncommitted in its owner's worktree), input digest and main commit. Changed inputs since the last
trial require its preserved failed-draft snapshot, otherwise a current trial is required. The wrapper
archives failed drafts before they are stubbed for a safe hand-off, so an advisor does not reconstruct
lost experiments. Advice is stale if the relevant inputs changed: re-read
and re-prove it, never apply it automatically. After success, record a durable lesson backed by the
matched routine/probe so all other workers benefit. Pending/resolved cases are cheap to list.

Expert worker loop (use playbook 80): `expert-take WAIT=300` waits in Python, not in model reasoning.
`expert-step` checks the deadline/control/cost before more work. `expert-finish` accepts a small JSON
diagnosis, evidence and at most five suggested probes; it cannot accept a verdict or approval.
The worker never expands its quota or claims another case while one is unsettled.

## Reuse unchanged checks, not weakened verdicts

`make check` always reruns the Pascal matcher, tests, readability and rebuild link. Only the ORIGINAL
golden check can reuse a successful result for identical pinned files, sessions/goldens, unit map,
state definition, every project tool and runtime/dependency identity. It expires after 24 hours;
malformed caches miss, and `FRESH=1` forces reexecution. A changed oracle, game byte, golden, unit map
or state definition invalidates it. symbols.toml is still parsed before reuse. Names/levels/notes
are not used by the no-call-tracer original-golden path; any code change invalidates this assumption.

```sh
make check FRESH=1
make check
```

Receipts record which stage was cached and its key. Never cache `--write` verdict mutations or infer
Pascal correctness from original goldens. This removes a repeated approximately 33-second unchanged
oracle run per integration while retaining a fresh byte proof for every new source tree. Cached
reference evidence is still not a rebuilt-game playthrough, which remains a Phase 5 requirement.

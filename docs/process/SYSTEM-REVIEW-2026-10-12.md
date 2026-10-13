# System review: the decompilation process, 2026-10-12

Scope: the matching-decompilation system of this repository (matcher, coordination tools, roles,
documents), reviewed for resiliency, speed and the time to a working rebuilt Pool of Radiance.
Everything below cites a file, a command output or a commit; the state of the art section cites URLs.

## 1. Verdict in one page

The core is right and fast. The coordination layer around it is what costs you.

- **The proof is sound and cheap.** `make match UNIT=ovl21` takes 1.3 s for a 22-routine unit;
  `make check` takes 58 s, of which 55 s are the Python tests. The compiler-in-the-loop, compare-by-name
  design is the correct one for Turbo Pascal 6.0 (section 3 shows why the alternative you asked about,
  decompile everything and relink, is not available with this compiler).
- **Progress is real.** 316 of 1190 game routines at L2 (87.6 of 231 KB), 29 of 46 game units complete,
  28 reviewed, after about two days of parallel runs (`work/status.md`).
- **Every blocked routine is blocked by a tool rule, not by decompilation difficulty.** Of the 51
  `blocked` notes in `re/symbols.toml`, 29 cite the nested-routine comparison limit, 21 the res03 sound
  driver object file, 4 the cross-unit routine address. Zero say "could not find the Pascal". The five
  open escalations are the same gaps plus two text questions (O+ per unit, the literal `orch` name).
  AGENTS.md rule 2 (no matcher change without a human) turned each gap into a human interrupt and parked
  up to 50 routines and three units behind it for most of a day.
- **The integration path is the fragile part.** In two days: about 125 merge commits, 76 `status after`
  commits, 8 merges reverted, 3 "fix the merge: rebuilt as the union of both sides" repairs, 1 lost-records
  restore. The orchestrator merges with `--no-commit` on `main`, so `main` is dirty while a model thinks,
  and `make claim` refuses while it is (tools/agent/claim.py:76). The shared hand-edited files
  (`src/POOLVARS.PAS`, one 462 KB `re/symbols.toml`, `re/renames.toml`, stub lines in other units) are
  where every conflict and every lost record came from.
- **Locks and context.** Locks are held by model sessions, which end when their context runs out; every
  worker in `make agents` stopped after at most three units, several with locks still held, which only
  the operator path (`OPERATOR=1 FORCE=1`) can clear. That is the lock leak you saw; it is structural,
  not misbehaviour.
- **`make check` is red on `main` right now** (readability R5 on ds6F68/ds6F69; section 5.1). Nobody can
  hand off until it is green.

Recommendation in one line: keep the matcher and the per-routine loop; replace the model-driven
orchestrator with a deterministic integrator; generate the shared files instead of hand-editing them;
run each worker under a supervisor script that owns the lock and restarts model sessions on purpose;
move matcher changes from "human approves" to "machine proves nothing regressed". Details in section 6.

## 2. How the system works today (what the review is judging)

| Layer | What it is | Evidence |
|---|---|---|
| Proof | `tools/match/match.py` (1041 lines): compiles every `src/*.PAS` into a generated program twice (plain and padded), finds each routine from the map, compares instruction by instruction; address fields compared by what they name | SPEC 8.3; `make match` output |
| Runtime identification | `tp_toolchain.runtime_entries`: aligns POOL's System/Crt/Dos/Overlay bytes with the fresh build's, each routine votes for its entry; a masked body search for short routines was added 2026-10-12 | tools/re/tp_toolchain.py:311 |
| Work unit | one original unit per claim; a worktree and a branch `unit/<id>`; one lock per unit in `.git/poolrad-locks/` | tools/agent/claim.py |
| Integration | a model session ("orch") merges one branch at a time on `main` with `--no-commit`, runs `make check`, commits status and blockers, releases the lock | playbook 90 |
| Verdicts | only tools write L2 and review stamps | AGENTS.md rule 2 |
| Coordination | locks, hand-offs, heartbeats, identities, tasks, events, control state, meter checkpoints, expert queue: 14 directories and files under `.git/` | `ls .git` |
| Process text an agent is told to read first | AGENTS.md 14 KB, SPEC 45 KB, playbook 30 11 KB, READABILITY 6 KB, SAFETY 7 KB, THROUGHPUT 11 KB, WHITEPAPER 162 KB, prior-art 6 KB: 262 KB | `wc -c` |

## 3. The question you asked: decompile everything first, then link back and compare bytes?

Short answer: in the splat / dtk form that console decompilations use, no, not with Turbo Pascal 6.0.
The by-name comparison is the substitute this toolchain forces on us, and it is already the cheap part.

What the state of the art does (section 4): the original binary is split into per-function assembly;
every function not yet decompiled is **assembled** from that split and linked at its original address
by a linker script; the whole binary is therefore always byte-comparable, per-object diffs (objdiff)
give per-function feedback, and no "compare addresses by name" logic is needed because the layout never
changes. That needs two things we do not have: an assembler whose output the compiler's linker accepts
at an arbitrary position, and control over layout.

What Turbo Pascal 6.0 gives (probe `scratchpad/PLACEHL3.PAS`, compiled with `make tpc ... DISASM=1`
on 2026-10-12; the listing is in this review's evidence below):

1. An `assembler` procedure may consist of raw `db` bytes and gets no prologue (good), **but the compiler
   appends its own `retf` after every asm block**: `Pool` (10 bytes of `db`) came out as 11 bytes
   (`0000:000A cb`), and `Callee`, which already ends in `retf`, got a second one at `0000:0010`. Every
   placeholder would be one byte (or three, `retf n`) too long.
2. The compiler places a routine's literal pool immediately before the routine, from the string and set
   constants of **Pascal** code. An asm block cannot put bytes before its own entry, and a `db` inside an
   asm block lands inside the code, so the original `[pool][code]` order cannot be written for a routine
   that is not decompiled.
3. `dw seg Move` and `dw seg Randomize` are refused (`Error 160: Invalid symbol reference`); only our own
   routines' segments can be named. A placeholder cannot express a far call into a runtime helper with a
   relocation, and the runtime helpers (`0AF8:0B0B` and friends) have no exported symbol at all.
4. `{$L FILE.OBJ}` code appears after the unit's initialisation part in res03 (dec-14's finding, one
   observation, so [I]). If that holds in general, external objects cannot fill a gap in the middle of a
   unit either. This is the one point worth a probe before closing the question for good: a hand-built
   OMF module (a few dozen bytes of Python, no assembler needed) linked with `{$L}` between two Pascal
   routines, to see where TP puts it. If TP honoured the position, cm-recomp's blob method (section 4)
   would apply to the routines that have no literal pool; items 1 to 3 would still rule out the rest.
5. `push offset X` is refused under `$G-` (`Error 159`), which also tells you the original's `push imm`
   instructions come from the compiler, not from inline assembly.

So undecompiled routines cannot be carried as byte-exact placeholders, which means the rebuilt program
cannot have the original layout until every routine of every unit on the path is Pascal. The current
`make rebuild` confirms the other half of the problem: 4 of 51 segments identical, and complete units
such as ovl26 link to 5 bytes, because the smart linker drops every routine nothing calls yet. Two
consequences:

- The by-name comparison is not accidental complexity. It is what lets a routine be proven alone; it is
  fast; and its rules are small (global, routine, literal, routine-offset, segment: match.py docstring).
  Keep it. What hurt was not the rule set but that each missing rule needed a human.
- "Link back and match bytes as a post-process" is the right description of **Phase 5**, and it becomes
  possible exactly when the last routine lands, not earlier. Nothing is lost by deferring it, as long as
  the per-routine proof is trusted, which is what the regression gate in 6.3 is for.

What you *can* get early is behaviour, not bytes: the oracle already replays the goldens on the original.
A rebuild that mixes original overlay code with decompiled units at run time is the ADR-001 `orig_call`
design you already left on `track-c-hybrid`; I would not reopen it for Pascal.

## 4. State of the art compared

Researched 2026-10-12 (web, no code copied). Facts marked [V] were read on the cited pages.

| Project | Toolchain and gate | How partial progress links | How agents are run | What it says for us |
|---|---|---|---|---|
| decomp-toolkit, dtk-template, objdiff (GameCube/Wii) [V] https://github.com/encounter/decomp-toolkit | Original compiler; whole-binary SHA-1 of the linked output | Original binary split into relocatable objects; `NonMatching` objects are linked from the original bytes; linker script reproduces layout | Human or agent per function with objdiff | Needs a linker you control; TP 6.0 has none (section 3) |
| splat and asm-differ (N64, PSX) [V] https://github.com/ethteck/splat | Original compiler; ROM hash | Per-function `.s` files assembled and linked by a generated linker script | Same | Same |
| reccmp, LEGO Island [V] https://github.com/isledecomp/reccmp | MSVC 4.2; per-function similarity after address substitution; no whole-binary identity until the end | Recompiled binary at a different layout; functions paired **by name** from the PDB and `// FUNCTION: 0x...` comments; `STUB` markers excluded | Humans | The same design as our matcher; the published cost is the one we feel: everything rides on the address-normalisation rules |
| DX-Ball with rea [V] https://github.com/N0zoM1z0/dx-ball | VC++ 4.0; per-unit "exact" comparison after mapping COFF relocations to the original's symbols | By symbol mapping, like ours | Codex plus rea | Confirms that byte-exact work with rea still needs a hand-built per-function comparator with explicit address mapping |
| cm-recomp, Championship Manager (Borland C++ 3.1, TLINK 5.0, DOSBox-X) [V] https://github.com/mozvip/cm-recomp | Original compiler and linker; `make identity` must say IDENTICAL; 723 of 723 functions byte-identical | **Blobs**: the original is cut into OMF object modules of its own bytes with the original fixups, decompiled C replaces one function at a time, TLINK's relocation order reproduced; overlays as `OV??.OBJ` | Claude Opus 5.5; one overlay cut into ~3.5 KB chunks, one agent per chunk, mechanical merge; no locks; structural rules enforced by the tools, not prompts | The only DOS precedent of "assemble the rest". It works because TLINK consumes OMF at any position; TP 6.0 exposes only `{$L}` (section 3, item 4). Its chunk-per-agent split and mechanical merge are directly reusable (6.5) |
| Nigel and Snowboard Kids (N64, Chris Lewis, 2025-2026) [V] https://github.com/cdlewis/nigel, https://blog.chrislewis.au/ | IDO; `build-and-verify.sh` is the only verify entry point; warnings count as failure | splat | **One function per fresh headless session**; a scorer picks the next candidate; `reset_command` on failure, commit on success, `ignore.log` for exhausted candidates; shards by hash, one worktree per shard; PreToolUse hooks block edits to the hash, the asm, the splits and `--no-verify` | The lock registry, heartbeats and context-budget stops we have are replaced by disposable processes and deterministic ownership. 4.8% of matching commits needed an expert; the permuter was removed from the agent loop (agents treated its scores as signal) |
| Mizuchi benchmark (GBA) [V] https://github.com/macabeus/mizuchi | Agent sandboxed to submitting C; compile plus objdiff per submission; 12 attempts; stall detector | n/a | Fresh process per function with hard timeouts | After the third failed attempt the chance of eventual success fell to about a quarter: a bound of five attempts (ours) is in line |
| Echo (arXiv 2609.18706, 2026) [V] | | | Reports that batching several functions in one session lowers the per-function reasoning budget | Argues for one routine (or a small batch) per session |
| morluto/rea [V] https://github.com/morluto/rea | n/a | n/a | An MCP server over Hopper, Ghidra, IDA and other engines; no scheduler, no locks, no matching | Not an orchestration or matching tool. Its only transferable idea is paged evidence (summaries first, bodies on demand), which our packets could adopt |
| ghidra-delinker-extension [V] https://github.com/boricj/ghidra-delinker-extension | | Exports parts of a program as relocatable objects (COFF, ELF, OMF for 32-bit Borland only) | | No 16-bit real-mode OMF; not usable here today |

Turbo Pascal matching decompilations: none found. The by-name matcher is therefore not behind the state of
the art; it is the reccmp pattern, and cm-recomp shows what the alternative needs (a linker that takes
object modules at any position), which TP 6.0 does not offer. What is behind the state of the art is the
coordination layer: nobody surveyed runs cooperative locks held by model sessions with heartbeats; they
run disposable processes with deterministic ownership, reset-or-commit, and hooks that make the oracle
unarguable.

## 5. Findings, with evidence

### 5.1 `make check` is red on `main`

`make check` on 25e7518 fails at the readability stage with 8 findings, all R5 for `ds6F68` and
`ds6F69` (scratchpad `check.log`). Commit 0466e5b moved their comments from the declaration line to the
line above (`src/POOLVARS.PAS:489-492`); `tools/match/readability.py:132` reads the comment on the
declaration line only. Fix: put the comments back on the same line (two lines), or let R5 accept a
comment on the line above. Until then no hand-off can pass and `make claim` works but every worker's
`make check` is red.

### 5.2 All blocked routines and all open escalations are tool or text gaps

| Blocker | Routines | Status 2026-10-12 19:50 |
|---|---:|---|
| Nested routine compared byte-exact in the parent's pre-entry region | 29 (ovl10 10, ovl15 2, ovl25 3, res06 3, ovl20, others) | Matcher change landed on `main` in c7265b6 (tests in test_match_nested.py); escalation still open in `make handoffs`; the drafts sit in notes and old commits and must be re-applied by hand |
| res03 sound driver: 5.7 KB of TASM code linked with `{$L}` | 21 | Decision pending (escalate-res03) |
| Cross-unit `@ovl22_e4` stored in a global | 4 | Landed in c7265b6; ovl08's two routines matched on `main` in 25e7518 |
| Randomize not identified in single-unit builds | review of ovl11 | Masked body search landed in c7265b6 (tp_toolchain.py); escalate-ovl11 and task/tools-rtl2 still listed |
| O+ on a resident unit (res08, now also res07) | spec text | Whitepaper already says per unit; AGENTS.md and SPEC 3.6 still say "overlay units" |
| Orchestrator must be literally named `orch` | integration | `identity.is_orchestrator` added in c7265b6 |

Four of six are fixed in code on `main` and still show as open decisions, which is itself a symptom: the
escalation record and the fix live in different places and nothing closes one when the other lands.

### 5.3 Integration is where time and records are lost

- Two days of `git log --first-parent`: about 125 `Merge` commits, 76 `status after` commits, 15
  `rename APPLY=1` or `blockers:` commits. Four commits of `main` history per integrated unit.
- Eight merges reverted (ovl34 twice, tools-map, res08, ovl23, ovl28, ovl09), each with a blockers note
  and a status regeneration, each sending the unit back through a worker session.
- Three "rebuilt as the union of both sides" repairs (ovl10 POOLVARS, res06 dseg/renames) and one restore
  of 13 rename records lost in earlier merges (503d9b7). `make merge-check` was then written to catch
  this class of loss. It is a gate on a problem the file design creates.
- The ovl09 revert (2b9557e) was a type conflict (`Pad9E` narrowed by ovl07) that `make check` in the
  worker's worktree could not see because its base was older: a correct worker, a correct orchestrator,
  and still a round trip through a human-readable blockers note.
- Merging with `--no-commit` on `main` leaves `main` dirty between two model turns. `make claim` refuses
  a dirty `main` (claim.py:76), so each integration blocks every claim for as long as the orchestrator's
  reasoning takes, and a crashed orchestrator leaves `main` dirty until a human notices.

### 5.4 Locks leak because a model session is the lock holder

- `make agents` lists 36 agents; every decompiler stopped after one to three units with notes such as
  "session budget reached" (dec-4) or "session context budget is nearly used, so no dangling lock"
  (haiku-dec). The lifetime of a worker is the model's context window, not the unit's size.
- A worker that stops without `make handoff` leaves its lock. `make unlock` (unlock.py:23-35) refuses
  unless the orchestrator asks, the branch is merged, and the worktree is clean; everything else needs
  `OPERATOR=1 FORCE=1 REASON=`. That is correct as a safety rule and guarantees a human interrupt for
  every exhausted session. The 2026-10-12 events show three such operator unlocks in one batch.
- Nine worktrees exist for seven unmerged branches (ovl09, ovl17, ovl20, ovl30, res06, res07, review-ovl04,
  review-ovl11, tools-rtl2). Each holds drafts someone must remember.

### 5.5 Per-routine ceremony is heavier than the proof

Playbook 30's loop per routine: `agent-step`, read the packet, `match` (n times), `learn` before each
probe, `rename` with WHY for the routine and every global, named constants, a comment, `readability`,
`match WRITE=1`, a commit with a trailer, a heartbeat at each step, learnings in `re/learnings`, probes
in `tp_idioms`, then per unit a whitepaper section, `make check`, a hand-off with a changelog row. Plus
registration, identity, metering and expert-queue rules (THROUGHPUT.md, 11 KB) that add make targets
and prose but no proof. The playbook asks for a 55 s `make check` before every hand-off, which is fine;
it is the reading and writing around each routine that eats context. A packet for ovl12 is 463 KB
(10 911 lines) for 168 routines: no session can hold it, so the largest units (ovl12 168, ovl03 108,
ovl22 108, ovl16 107, ovl13 85, res12 64 routines) will each need a dozen sessions under today's rules.

### 5.6 Things that work and should be kept

- The matcher's address-kind model and the padded second compile (constants never move) are a clean
  idea and the reason a routine can be proven alone in a second.
- `make match WRITE=1` is the only writer of L2; `make review-pass` of reviews. Keep.
- The worktree-per-claim layout, the `Agent:` trailer, the hand-off record pinned to a commit.
- `make tpc` probes and `tools/re/tp_idioms/`: compiler questions settled by compiling.
- The oracle, goldens and record/replay (they are the Phase 5 and Phase 7 gate and need no change now).
- `make merge-check` as a gate, until the shared files are generated (then it has nothing to catch).

## 6. Recommendations

Ordered by return on effort. Items in 6.1 are hours; 6.2 to 6.5 are a few days of tooling each and pay
back within the first day of running.

### 6.1 Today

1. Make `main` green: restore the two POOLVARS comments on their declaration lines (or widen R5).
2. Close the escalations whose fix already landed (nested, cross-unit, Randomize, `orch` identity):
   `make handoff-done ... DECISION="landed in c7265b6"`. Drop `task/tools-rtl2` (superseded by the masked
   search). Amend AGENTS.md and SPEC 3.6 to say `$O+` is per unit (res07 and res08 prove it).
3. Decide res03: treat the 5.7 KB TASM driver as an external object matched by bytes, excluded from the
   unit-complete rule, with a later task to rebuild it from an assembly source (`{$L SOUND.OBJ}`, which
   TP places exactly where the original has it). This unblocks 21 routines and the unit at no proof cost.
4. Re-apply the parked drafts (ovl10, ovl15, ovl25, res06, ovl20) against the new matcher before anything
   else is claimed; they are the cheapest 29 routines in the project.
5. Merge or close the seven stale branches; remove their worktrees.

### 6.2 Replace the model orchestrator with a deterministic integrator

`make integrate` (a script, run by cron or by the human, no model): for each hand-off oldest first,
merge into a temporary worktree, run `make check` there, and only on green fast-forward `main`, write the
status and changelog in the same commit, clear the hand-off, release the lock, delete the worktree. On
red: leave `main` untouched, mark the hand-off `rejected` with the check log and the base commit, and
re-queue the unit with that note attached to its next claim. `main` is never dirty, nothing needs
reverting, and the only thing a model is ever asked to do is resolve a textual conflict (rare once 6.3 is
done). The orchestrator role shrinks to a human-readable report (`make inbox`, 6.6).

### 6.3 Stop hand-editing shared files

Every revert and repair in 5.3 came from `src/POOLVARS.PAS`, `re/symbols.toml`, `re/renames.toml` or
a stub line in another unit's file. Make all of them generated or append-only:

- `src/POOLVARS.PAS` generated by `make poolvars` from `re/dseg.toml` (offset, type, name, comment); a
  worker adds a global by adding a record, never by editing Pascal. Readability R5 then reads dseg.toml.
- `re/symbols.toml` split into `re/symbols/<unit>.toml`; a worker's branch touches only its own unit's
  file plus `signature` records of callees (small, additive).
- Stub lines regenerated from `signature` by `make stubs` at integration, so a stub signature set by a
  caller never conflicts with the callee's own file.
- Renames applied by the integrator from `re/renames.toml` records at merge time, not by workers.

With this, two branches conflict only when two workers decompile the same routine, which the lock
already prevents.

### 6.4 Matcher changes: machine-proved, human-reviewed afterwards

Replace AGENTS.md rule 2's "human approval before any matcher change" with a gate the tooling agent can
run: (a) every routine at L2 on `main` still matches, verdict for verdict, over `--all` and over each unit
alone; (b) a corpus of negative fixtures (a wrong global, a wrong callee, a wrong literal, a nested routine
with a wrong address, a cross-unit address to the wrong routine) still fails; (c) every new address kind
comes with its negative fixture. `tests/unit/test_match_*.py` already holds most of (b). A matcher change
that passes the gate merges like any branch; you read the diff when you like. Keep one standing tooling
agent for the matcher and route "matcher gap" escalations to it, not to you. Byte equality of code and
pools stays a hard invariant tested by code, which is stronger than a rule in prose.

Enforce the rest with harness hooks rather than prose, as the Snowboard Kids project does: a PreToolUse
hook in the worker's harness that refuses edits to `tools/match/`, `tests/`, `re/symbols` levels and
`poolrad/` from a decompiler session, and refuses `git commit --no-verify`. Their reported reason is the
one to expect here: an agent that cannot match edits the oracle. AGENTS.md rule 2 then describes what the
hooks do instead of asking the model to remember it.

### 6.5 Workers under a supervisor; sessions are disposable

Run each worker as a shell supervisor (`tools/agent/worker.sh`), not as a long model session:

- The supervisor claims the unit, holds the lock, posts heartbeats, and starts a **fresh model session
  per bounded task**: "match routines X..Y of unit U, commit each" (5 to 10 routines, or one unit when
  small). When the session ends, for any reason, the supervisor commits what is committed, runs `make
  handoff STATE=partial` and either starts the next session on the next batch or releases cleanly on
  exit (`trap`). No lock ever outlives its process; no draft is parked in a note.
- Context exhaustion becomes a planned restart, which is what you asked about: yes, restart workers, and
  make restart the normal mode rather than the failure mode. Packets become per batch (`make packet
  FN=...` already exists), so ovl12 is 20 batches, not one impossible session.
- Reviews and the readability pass run as separate bounded sessions on a routine range, so naming does
  not compete with matching for the same context.
- Ownership by range, not by cooperative lock, once 6.3 is in: cm-recomp cuts an overlay into chunks
  of about 3.5 KB at routine starts and gives one agent per chunk with a mechanical merge; Nigel shards
  candidates by hash with one worktree per shard. With per-unit symbol files and generated stubs, two
  workers on different routine ranges of ovl12 cannot conflict, so the big six units can be worked in
  parallel instead of serially behind one lock. Failed batches end in `git reset --hard` of the batch
  worktree (Nigel's `reset_command`), never in a parked draft, and exhausted routines go to a frontier
  list that the scheduler stops offering until the matcher or a human changes something.

### 6.6 Give the human one inbox, not a stream

`make inbox`: every pending decision as four lines (question, evidence pointer, recommended option, the
exact command that records the decision), newest last. A decision is taken by running the printed
command; the integrator closes the record. Blockers, status and changelog commits go away as separate
objects: `work/status.md` is generated on demand or by the integrator, never by hand.

### 6.7 Trim the process text to what changes a verdict

Keep AGENTS.md, SPEC 7 and 8, playbook 30, READABILITY. Fold SAFETY, THROUGHPUT, KICKOFF and START-AGENT
into the supervisor script and a one-page operator note: registration, metering, expert queue, budget
rules and heartbeat etiquette are then code, not reading. The whitepaper stays, but a worker reads the
packet's excerpt, not 162 KB.

### 6.8 Remove the mapper role

The compiler already knows every boundary; `make match WRITE=1` prints the corrections. Let it write
them to the unit's symbols file (it is a tool writing a verdict, rule 2 allows it), and let the
integrator run `make map` for forced starts. Boundary notes in hand-offs, the mapper queue and playbook 10
section 6 then have no work left.

## 7. What to expect after the changes

Remaining: 874 routines, 143 KB, concentrated in six units of 64 to 168 routines. With 6.1 done the 29
parked routines land in a day. With 6.2 to 6.5 the integration cost per unit drops from four commits,
a model turn and a possible revert to one scripted commit, and a worker's throughput is no longer
capped by its context. The remaining human work is the res03 decision, matcher diffs read after the
fact, and the Phase 5 link order, which is a real research question (SPEC 15.6) and the right place for
your attention.

## 8. Evidence appendix

- `make match UNIT=ovl21`: 22 matched, 1.306 s wall (scratchpad `match-ovl21.log`).
- `make check` on 25e7518: 57.7 s; tests 54.9 s; readability 8 findings, `no receipt written`.
- `make packet UNIT=ovl12`: 0.86 s, 463 181 bytes, 10 911 lines.
- `make rebuild`: 4 of 51 segments identical; load image 17 328 of 68 592 bytes; overlay 6 954 of 206 105.
- Blocked notes: `grep -c blocked re/symbols.toml` = 51; nested 29, sound driver 21, cross-unit 4.
- Commit mix since 2026-10-11 (subject keywords): decomp ~115, merge ~125, status ~76, reverts 8.
- Probe `PLACEHL3.PAS` listing (TP 6.0 June 1991): `Pool` db bytes at 0000:0000..0009 then `cb` at
  000A; `Callee` `55 89 E5 5D CB` then a second `CB` at 0010; `dw seg Placeholder` accepted;
  `dw seg Move` and `dw seg Randomize` refused with Error 160; `push offset Pool` refused with Error 159.

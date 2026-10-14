# Pool of Radiance (DOS) Decompilation: Process Specification

| | |
|---|---|
| Version | 0.6 (ADR-002; integration, worker lifecycle and matcher gate made mechanical after the 2026-10-12 system review, `docs/process/SYSTEM-REVIEW-2026-10-12.md`) |
| Date | 2026-10-12 |
| Target | SSI *Pool of Radiance*, DOS, the build in `poolrad/` (hashes in section 2) |
| Output | Turbo Pascal 6.0 source in `src/` that compiles to the original's machine code, a rebuild of the game from it, a living design doc in `docs/design/`; later a C translation for other platforms |
| Execution | AI-agent driven, harness agnostic (Claude Code, Cursor, OpenCode), human supervised |

This document says **what** we build, **how** we prove it is right, and **how agents do the work**. The agent operating manual is `AGENTS.md`; step-by-step procedures are in `docs/process/playbooks/`; environment setup is in `docs/setup/SETUP-macos.md` (the reference compiler in `docs/setup/SETUP-tp.md`); what we learn about the game goes in `docs/design/WHITEPAPER.md`.

The previous approach (ADR-001: behaviour-matching C, run routine by routine inside the emulator) is kept on the git branch `track-c-hybrid`, with its memory model, platform layer, hybrid library and fuzzing (section 4.4).

---

## 1. Outcomes

| ID | Outcome | Measure of done |
|---|---|---|
| O1 | Pascal source for the whole game in `src/` | Every original routine outside the Turbo Pascal runtime is Pascal that the pinned compiler turns into the original's instructions (level L2, section 8) |
| O2 | A rebuild of the game | `make rebuild` compiles `src/` with Turbo Pascal 6.0 into `START.EXE` and `GAME.OVR` that are identical to the originals, or differ only where a byte-identical link is shown to be impossible, and play the golden sessions identically in the oracle |
| O3 | A design doc that explains how the game works | `docs/design/WHITEPAPER.md` covers every subsystem with evidence-tagged claims and is updated as part of each unit's definition of done |
| O4 | Readable source | Meaningful names for units, routines, globals, parameters, constants and types, backed by evidence; a comment on every unit and routine; written unit by unit as part of decompiling (P4, `docs/process/READABILITY.md`), harmonised across units in P6 |
| O5 | A portable C version | A translation of the matched Pascal into portable C (Phase 7) that builds natively and on the way to the CoCo 3 (CMOC), proven against the Pascal rebuild by the oracle's session replays |

Non-goals for now: the CoCo 3 port itself, enhancements or bug fixes to game behaviour (allowed only in a later, separate build after O2).

---

## 2. Pinned inputs

All work targets exactly these files. Tools refuse to run on anything else (`make inputs` checks).

| File | Bytes | SHA-256 | Notes |
|---|---:|---|---|
| `poolrad/START.EXE` | 65,231 | `d825df2b174675c9088ba1489488bdeebe66ad2a22943f17d3a198e60b6a07bd` | Microsoft EXEPACK packed ("Packed file is corrupt" stub) |
| `poolrad/start-unpack.exe` | 71,152 | `8e60e2b00c0caec91cd47d06abb30f5269ffeec857a06cb67975f619b47c549e` | Unpacked image, 561 relocations; analysis input |
| `poolrad/GAME.OVR` | 206,105 | `14e2b132470cbae275d8d925ddeeb9e370fdc5a7cfd4564ea3212dd4956ca722` | Borland overlay file, `FBOV` header |
| `poolrad/*.DAX`, `ITEMS`, `SAVE/` | | recorded by `make inputs` | Game data, read-only |

`start-unpack.exe` is reproduced from `START.EXE` by `tools/re/unexepack.py` (`make unexepack`); the output matches the pinned file byte for byte.

**Pinned toolchain.** The program was compiled with **Turbo Pascal 6.0, June 1991 release** (whitepaper section 2.2). Its runtime units (System, Crt, Dos, Overlay) in our image are byte-identical, apart from link-time fields, to the same units linked by this compiler (`make tp-compare`). Under ADR-002 the compiler is on the critical path: it is how every routine is proven (section 8) and how the game is rebuilt. It is proprietary and is never committed: `make tp-install` checks the archives in `build/toolchain/dist/` against `tools/re/tp_toolchain.toml` and installs it under `build/toolchain/tp60-1991/` (`docs/setup/SETUP-tp.md`).

| File | Bytes | SHA-256 | Notes |
|---|---:|---|---|
| `TPC.EXE` | 69,278 | `03836c60d1a8e5ad4394462813bfd497d1d091913e533065c75fdf5cda97c563` | Command-line compiler; banner "Version 6.0 ... 1983,90"; files dated 1991-06-11 |
| `TURBO.TPL` | 45,344 | `19040e3914d1b32209f88754ece12d6bc1eafc0c9e7873b73bdeee95483931ff` | Runtime library; "Portions Copyright (c) 1983,91 Borland" |

The first TP 6.0 release (October 1990, runtime "1983,90") and TP 7.0 (runtime "1983,92") were compared and eliminated. `make tpc SRC=<file.pas>` compiles any Pascal file with the pinned compiler under emu2 (`make emu2`), a headless DOS emulator.

**Version caution.** Other Pool of Radiance projects analysed a different, earlier build: a 47,936-byte `START.EXE` with a 232,379-byte `GAME.OVR` in Turbo Pascal 5.x `TPOV` format with 38 overlays (wicanr2/Pool-of-Radiance-cht, `docs/re/dos-toolchain-baseline.md`). Ours has 35 overlays in `FBOV` format. Their findings are leads, never addresses we can reuse without re-proving them on our bytes.

---

## 3. What the binary is (verified facts that shape the approach)

Each item was checked against our files; details and evidence are in the whitepaper.

1. **Language: Turbo Pascal 6.0 (June 1991 release).** The unpacked image contains the Borland Pascal runtime error strings followed by "Portions Copyright (c) 1983,91 Borland", and its runtime units byte-match that compiler's (section 2). The entry point is a chain of 48 far calls, one per unit initialisation, which is how Turbo Pascal starts a program.
2. **Overlays.** `GAME.OVR` begins with `FBOV`. 35 overlay stub segments (INT 3Fh headers) in the load image describe 35 overlay units that tile the overlay file exactly, with 406 entry points and 197,641 bytes of code. The other 13 init calls go to resident units. Units without an initialisation part make no init call: the Borland Dos (`0A32`) and Overlay (`0AA2`) units are two of them, so there are 15 known resident units.
3. **Packing.** The shipped `START.EXE` is EXEPACK compressed; `make unexepack` unpacks it to the pinned `start-unpack.exe`.
4. **Data.** All 113 `.DAX` files are block archives with one header layout, and all 1,245 blocks decompress to their declared size with one RLE scheme (whitepaper, section 4.1).
5. **Memory.** DGROUP is paragraph `0C7C` in the load image (set by the System unit init), the stack segment is `14F2` with SP `4000`.
6. **Compiler switches** (whitepaper section 2.2): `$A-` (no word alignment of data and locals: proven by `make match` on res06), `$F+` (every routine far), `$S-`, `$R-`, `$G-`, no floating point; `$I+` only in resident unit res05; `$O+` is per unit: every overlay unit (string and set constants passed to routines are copied to the stack first, which the overlay code shows) and the resident units whose code shows the same copy, res08 (`OvrInit('GAME.OVR')`, `042B:00AF`) and res07 (`'.dax'` in `LoadDaxBlock`, `0464:0152`), proven by `make match`. TP 6.0 has no `$Q` and no `const` parameters.
7. **Code generation is simple and deterministic.** Turbo Pascal 6.0 does not optimise across statements, emits one prologue and one epilogue per routine, puts a routine's string and set constants in the code segment right before it, and lays out a unit's routines in source order. A routine written in the right Pascal compiles to the original's instructions exactly (section 8.3; proven on res04, ovl00 and res06).

Consequences:

- **A matching decompilation is possible in Pascal**, and it is the strongest proof there is: the compiler, not a test, says the source is the program.
- **The runtime library is free.** System, Crt, Dos and Overlay are the compiler's own units (`TURBO.TPL`). They are linked, never decompiled. About 9,400 bytes of the image need no work.
- The natural decomposition is the original one: **one source file per unit**, named after the unit's id until its real name is known. Unit boundaries also map well onto CoCo 3 memory banking later.

---

## 4. Approach decision

### 4.1 Options considered

| Option | What it gives | Assessment |
|---|---|---|
| A. Byte-matching C | | Impossible: no C compiler produced these bytes |
| **B. Matching Pascal, then translate to C (ADR-002, chosen 2026-10-11)** | Byte-level proof of every routine by the original compiler; the runtime for free; a rebuild that is the original program; a later C translation from source that is already understood | Two passes for the C (match, then translate), but the second is a translation of clean, proven source rather than a decompilation |
| C. Clean-room reimplementation | Fast to something playable | Not a decompilation; drifts from original behaviour |
| D. Static recompilation (x86 to C) | Exact behaviour quickly | Unreadable output |
| E. Behaviour-matching C with layered proof (ADR-001, 2026-10-07 to 2026-10-11) | Readable C early | Every routine needed hand-written marshalling, a differential fuzz harness and `orig_call` (C calling routines still in the original) before P4 could scale; proof by testing only. Kept on branch `track-c-hybrid` |

### 4.2 ADR-002: why Pascal first

1. **Proof by identity.** `make match` compiles the Pascal with the compiler that built the game and compares instructions. There is no input space to sample and no harness per routine.
2. **Independence of routines.** A routine is proven on its own: its callees only need their signatures (a stub), its globals only need names. There is no runtime mixing of original and decompiled code, so no calling glue, no `orig_call`, no timing model.
3. **The runtime is the compiler's.** Strings, sets, files, the heap, `Random`, the overlay manager: all exact by construction.
4. **A real rebuild.** When every unit matches, the program can be relinked from source and compared byte for byte with the original.
5. **A better start for C.** The C translation (Phase 7) works from named, typed, proven Pascal, and the oracle's record/replay sessions (kept on `main`) verify it against the rebuilt original.

### 4.3 What "matched" means here

- **Instructions match:** every byte of the routine and of the literal pool before it is identical, except address fields.
- **Addresses name the same things:** each address field refers to the same global, routine, literal or segment on both sides (section 8.3). Our build places things at other addresses until the whole program is rebuilt, so addresses are compared by what they name.
- **Units match:** when every routine of a unit is decompiled, the unit's whole code segment (routines, literal pools, initialisation part, paragraph padding) is covered exactly.
- **Data layout matches** at the rebuild (Phase 5): every global and record keeps its original offset, so saves and memory snapshots stay interchangeable.

### 4.4 The C track (ADR-001), kept for later

Branch `track-c-hybrid` (commit `1134647`) holds: the C memory model (DGROUP mirror, `farptr`), `src/rtl` with Move/FillChar/Random, the SDL3 host, the hybrid library loaded into the oracle, routine fuzzing, and the platform layer with its decisions on waits (`src/platform/platform.h`). Phase 7 starts from there. The oracle's record/replay of the outside world (`tools/oracle/replay.py`) and the goldens stay on `main`, since they verify any build of the game.

---

## 5. Architecture of the effort

```
 poolrad/ (pinned bytes)
     |
     v
 tools/re: unpack, overlay manifest, DAX tools  ---->  build/re/ (generated, never committed)
     |
     v
 Ghidra project (rebuilt from re/ text files)  <---->  re/ (source of truth for names, types, signatures)
     |                                                   |
     v                                                   v
 work packets (build/packets/*.md)  ---->  agents  ---->  src/*.PAS (Turbo Pascal 6.0)
                                              |              |
                                              v              v
                         make match: TP 6.0 compiles, instructions compared with the original (L2)
                                              |
                                              v
 tools/oracle: emulator running the original and the rebuild (sessions, goldens, L3)
     |
     v
 verdicts (re/symbols.toml, work/status.md) ----------->  docs/design/WHITEPAPER.md
```

Principles (adapted from Exhume's method and Rebrew's principles, `docs/decomp-tools/rebrew/PRINCIPLES.md`):

1. **Text is the source of truth.** Names, types, signatures and status live in text files under `re/` and `work/`. The Ghidra project is a disposable view rebuilt from them.
2. **Every step ends in a check a machine can repeat.** No routine is "done" on judgement alone.
3. **Evidence over recall.** Agents cite addresses, tool output and files. Claims from memory or prior art are leads until proven on our bytes.
4. **CLI first.** Every capability is a `make` target or a script with a non-zero exit code on failure.
5. **Small, reversible steps.** One routine or one unit per change, each committed with its verdict.

---

## 6. Repository layout

```
AGENTS.md                 agent operating manual (canonical, read by every harness)
CLAUDE.md                 imports AGENTS.md for Claude Code
Makefile                  every command agents and humans use
pyproject.toml            Python tool dependencies (uv)
poolrad/                  original game files (pinned, read-only, never edited)
docs/
  spec/SPEC.md            this document
  setup/                  environment setup; SETUP-tp.md for the compiler
  process/playbooks/      step-by-step procedures for each stage
  design/WHITEPAPER.md    how the game works (living document) + CHANGELOG.md
  reference/              prior art index and licence rules
re/                       reverse-engineering database (text, committed)
  units.toml              50 units: name, kind, segment/overlay, source file
  symbols.toml            every routine: address, size, name, signature, level, notes
  dseg.toml               names of DGROUP offsets (globals)
  types/                  record and enum notes (Pascal declarations live in src/)
  state.toml              what "game state" is, for checkpoint comparison
src/                      Turbo Pascal 6.0 source, one file per unit (section 7)
  README.md               conventions in short
  RES04.PAS ... OVL00.PAS one per original unit, named after its id
  POOLVARS.PAS            globals whose owning unit is not known yet
tests/
  unit/                   pytest: tools, data codecs, the matcher, the oracle
  sessions/               input scripts + golden digests and recordings (no game data)
tools/
  setup/                  setup-macos.sh, doctor.sh, build-emu2.sh
  re/                     tpovl.py, dax.py, unexepack.py, rtl_ident.py, tp_toolchain.py (install, probe,
                          compare, tpc), timing_scan.py
  match/                  match.py: the L2 proof (section 8.3)
  ghidra/                 PyGhidra scripts: import, apply re/, export
  oracle/                 the emulator harness (Unicorn): run, goldens, record/replay
  agent/                  packet.py, status.py, lock.py, next.py
work/                     status, queue and locks (committed, small text files)
build/                    everything generated (ignored by git); build/toolchain/ holds the compilers
```

---

## 7. The Pascal source

### 7.1 Shape of the code

- **One unit, one file.** `src/<ID>.PAS` holds unit `<ID>` (for example `RES04.PAS`, `unit RES04`). File and unit names stay the ids (8.3 names, and the matcher maps them to `re/units.toml`); the real name of a unit goes in its header comment and in `re/units.toml`.
- **The original's order.** Routines appear in the implementation part in the order of their addresses, since Turbo Pascal lays them out in source order. Each routine is declared in the interface (the compiler's map lists only interface symbols; declaring it there changes no code).
- **Directives.** Every unit starts with `{$A-,F+,S-,R-,G-,I-}`; overlay units add `O+` (`{$A-,O+,F+,S-,R-,G-,I-}`); res05 has `I+`; resident res08 also has `O+` (whitepaper 2.2). A unit whose evidence shows another switch documents it in its header comment.
- **Names.** A routine keeps its `re/symbols.toml` name (`res04_fn_0059`, `ovl00_e1`) until renamed there; a global is `dsXXXX` (its DS offset) until named in `re/dseg.toml`. The matcher resolves both forms (section 8.3), so renaming is a change in `re/` plus the source, never in the proof.
- **Skeletons and stubs.** Every game unit has source from the start: `make skeleton` wrote each one with every routine of `re/symbols.toml` declared in address order and a stub body (`{@stub}` at the start of the header line, an empty body, a comment with the frame the code shows). Decompiling replaces a stub by the routine. A stub's signature is evidence (the callers' pushes and the callee's `retf n`), recorded in `re/symbols.toml` `signature` (the full Pascal header, for example `procedure res06_fn_0BF5(Color: Byte; Text: String40)`) so that regenerated skeletons keep it. An initialisation part that does real work and is not decompiled yet is marked `{@stub-init}` on the line before its `begin`; an empty one (`begin end.`, 44 of the 46 game units) is already decompiled.
- **The main program** is `src/POOL.PAS`: its `uses` clause lists the units in the original initialisation order (the compiler emits one initialisation call per unit in that order), and its main block is the game's. `make match UNIT=main` proves it.
- **Globals** whose owning unit is not known yet live in `src/POOLVARS.PAS`. Their declarations do not affect the instructions (addresses are compared by name), so they can move to their unit when the rebuild needs the exact DGROUP layout (Phase 5).
- **Faithful first.** Same control flow, same evaluation order, original quirks kept (dead code after `Exit`, unassigned function results). Turbo Pascal leaves no other choice: a different program compiles differently.
- **Readable at once** (`docs/process/READABILITY.md`). The source is what every port starts from, so a routine is not finished until it is named, its parameters, locals, constants and the globals it uses are named for what they are (with evidence), and it carries a comment with its address and its meaning in game terms. Names never change the code, so they are never postponed; `make readability` checks that nothing was skipped (part of `make check`), the reviewer judges whether the names and comments are true. Routines and globals are renamed with `make rename`, which keeps `re/` and the source in step.

### 7.2 Turbo Pascal idioms

How Turbo Pascal 6.0 compiles an idiom is settled by compiling it, never by recall: `make tpc SRC=probe.pas DISASM=1` shows the code and names each runtime call by the POOL routine it matches. `tools/re/tp_idioms/` collects probes worth keeping. Playbook 30 lists the idioms found so far.

### 7.3 Memory and the rebuild

During Phase 4, units are compiled into a generated program (`build/match/`) where addresses differ from the original; the matcher compares addresses by name. Phase 5 arranges the declarations so that the linker places every global and routine where the original has them: units in the original link order, globals in their units in offset order, overlay units marked with `{$O ...}`, then `make rebuild` compares the linked `START.EXE` and `GAME.OVR` with the originals.

### 7.4 The C translation (Phase 7)

Translating matched Pascal to C reuses the decisions recorded on branch `track-c-hybrid`: width types, the DGROUP mirror and `farptr` memory model, a runtime library with Turbo Pascal semantics (strings, sets, `Random`, files, heap), and the platform layer with its waits. The portability rules for CMOC are set then.

---

## 8. Verification

### 8.1 The ladder

| Level | Name | Evidence required |
|---|---|---|
| L0 | Drafted | The routine is Pascal (not a stub) in its unit, and the unit compiles with the pinned TP 6.0 |
| L2 | Matched | `make match` passes: the routine's instructions and literal pool are identical to the original's, and every address names the same thing (8.3). Written by `make match WRITE=1` |
| L3 | Rebuilt | The routine's unit is byte-identical in the full rebuild, or the rebuilt program passes the golden sessions in the oracle (Phase 5) |

**Review** is recorded beside the level, not as a level: the matcher already proves the instructions, and the review checks what the compiler cannot (names, types, comments, evidence). `make review-pass UNIT=<id>` writes `review = "passed <date> by <reviewer>, <commit>"` on every routine of a complete unit when `work/reviews/<id>.md` names a reviewer who is not the decompiler and has no open must-fix finding (playbook 70). A unit is **done** when it is complete (every routine L2, `unit: complete`), readable (`make readability` clean, and the names and comments judged by the review) and reviewed.

Only tools write levels and reviews. A regression demotes a routine the next time the tool runs.

### 8.2 The oracle: running the original code

`tools/oracle` is a deterministic, headless PC built on Unicorn (x86 16-bit real mode), written in Python:

- Loads the unpacked `START.EXE` as DOS would and lets the program's own Turbo Pascal overlay manager load overlays from `GAME.OVR`, so overlay behaviour is real, not simulated.
- Implements the DOS and BIOS services the game uses, the timer interrupt, port I/O for the PIT, speaker and video, and an EGA model so screens can be captured.
- Runs in **virtual time**: the clock advances with executed instructions, never with the wall clock, so every run is repeatable.
- Records every read of the outside world (keyboard, time of day, BIOS tick, timer and retrace ports) with the golden, and replays it (`tools/oracle/replay.py`, Exhume's method), so a build of the game whose code takes a different number of instructions still makes the same decisions.
- Provides call tracing, memory watch points, state digests, screenshots, and an input script player.

In ADR-002 the oracle verifies whole programs: the original (goldens) and the rebuild (Phase 5), and later the C translation (Phase 7). It also answers questions about behaviour while decompiling (traces, watch points).

### 8.3 Matching (L2)

`make match UNIT=<id>` (tools/match/match.py):

1. Compiles every `src/*.PAS` with the pinned TP 6.0 inside a generated program that references each routine of the unit (variant A), and again with a padding variable and a padding procedure inserted first in every unit of ours (variant B).
2. Finds each routine in our build from the compiler's map: its entry, its code (to the return after every forward jump), the literal pool before it.
3. Compares with the original at the same entry, instruction by instruction. Every byte must be equal except address fields:
   - a DS operand (memory displacement or immediate) must be our global plus delta at the original's offset of that global plus delta (`re/dseg.toml` by name, or `dsXXXX`);
   - a near or far call must reach the same routine id (runtime library targets through `tp_toolchain.runtime_names`; overlay targets through the stub entry table);
   - a routine's address (`@Routine`) must name the same routine (for overlay code: its stub entry);
   - an offset into the code segment must be the same literal, at the same distance from the entry;
   - a segment fixup must name the same unit or DGROUP.
   An immediate counts as an address only if it moves between variants A and B; constants never move.
4. With no stubs left in the unit, also checks that routines, pools, the initialisation part and the paragraph padding cover the original segment exactly. A unit with an external object file (`re/units.toml` `external_from`: code the original linked from an `.OBJ` after its initialisation part, as res03's sound driver) is complete when its Pascal part tiles the original up to the object; the object's routines are flagged `external = true` in the registry, declared as stubs for their callers, and kept as the original's bytes until Phase 5 rebuilds them from an assembly source.

The first difference is reported with both instructions. `WRITE=1` records L2 for each matched routine and writes the compiler's boundaries into `re/symbols.toml` (a size the compiler disproves, a map entry inside matched code, a routine the map lacked), which retires the mapper role for boundaries.

**Changing the matcher** (`tools/match/`, `tools/re/tp_toolchain.py`) is a tooling task gated by `make match-gate`: every L2 routine still matched, together and alone, every negative fixture still rejected, a negative fixture for every new address kind. The human reads the diff after it merges. Worker sessions cannot edit the matcher: the pre-commit hook and the harness edit guard (`tools/agent/hooks/`) refuse it.

### 8.4 The rebuild (L3, Phase 5)

`make rebuild` (tools/match/rebuild.py) compiles `src/POOL.PAS` with every unit, adding `{$O OVLnn}` for the overlay units so the linker writes the overlay file, into `build/rebuild/POOL.EXE` and `POOL.OVR`. It compares segment by segment with `start-unpack.exe` and `GAME.OVR` (the main program, each resident unit, each overlay unit's code), ignoring relocation words on either side, and reports how many segments are identical and how large the image and the overlay file are. It runs in `make check` from P4 on as a gate on *linking* (every unit, decompiled or skeleton, must compile into one program); the comparison becomes the gate in Phase 5, which ends when the files are identical (or every difference is explained in the whitepaper) and the rebuilt program plays every golden session in the oracle. The smart linker drops routines nothing calls, so the rebuild converges only as callers are decompiled: until then it is a progress report.

### 8.5 Sessions and goldens

A session is a scripted sequence of inputs (`tests/sessions/<name>.keys`) from a defined start. The oracle runs it on the original code twice (must be identical) and stores digests of the canonical game state at every checkpoint, PNG screenshots at named points and the recording of the run's reads of the outside world, in `tests/sessions/golden/<name>/` (digests, our own screenshots and recordings of our own runs only; never game files). `re/state.toml` defines the canonical state: DGROUP, the Turbo Pascal heap, the video planes; the stack is diagnostic.

Initial session set (grow as units land): `boot-title`, `create-character`, then `phlan-walk`, `first-combat`, `shop-buy-sell`, `camp-memorize`, `save-load`, `level-up`, plus a long `main-quest` series built from saves along the game.

### 8.6 Data codecs

Every loader for game data (DAX blocks, maps, ECL scripts, monsters, items, saves) has a round-trip test over all of the pinned files: decode, re-encode where the game writes the format (saves), compare bytes.

---

## 9. Agentic workflow

### 9.1 Harness neutrality

- `AGENTS.md` is the single source of instructions. Claude Code reads it through `CLAUDE.md`; OpenCode and Cursor read `AGENTS.md` (Cursor also gets `.cursor/rules/poolrad.mdc`).
- Playbooks are plain Markdown in `docs/process/playbooks/`. Thin command wrappers exist for each harness (`.claude/commands/`, `.cursor/commands/`, `.opencode/commands/`) that only say "follow playbook X with arguments Y".
- Every tool is a CLI with deterministic output. No reliance on harness-specific features. Parallel work uses git worktrees, locks and hand-offs that any harness can manage, so agents in different harnesses work on the project at the same time.
- **The human operator creates and stops every agent**, choosing its harness; no agent starts or stops another. Agents coordinate only through the repository and the shared files: locks and hand-offs in the clone's git directory (`make locks`, `make handoffs`), the queues (`make next`), `work/status.md`. All agents therefore run on one machine, in one clone, where the compiler is installed (`docs/process/KICKOFF.md`).
  The orchestrator may delegate bounded cases to one expert already started and admitted by the human;
  submitting a queue item never creates a session or changes staffing. Parent/launcher sessions follow
  the same restriction. A general overnight/continuation instruction is not staffing authorization.

### 9.2 Roles

| Role | Does | Must not |
|---|---|---|
| Human operator | Starts and stops every agent in the harness of its choice; answers escalations; approves spec, ADR and `poolrad/` changes | |
| Integrator (`make integrate`, a script) | Merges hand-offs one at a time in a temporary worktree, runs `make check`, writes status and changelog row into one merge commit, fast-forwards `main`, releases locks, rejects what fails with the reason (`make inbox`) | Decide anything: an escalation is cleared only with a human's `DECISION=` |
| Worker supervisor (`make worker`, a script) | Claims, holds the lock, posts heartbeats, runs one fresh model session per batch of routines, hands off or releases when it stops | Reason about code: the model session does that, and only inside its batch |
| Mapper | Phase 1 mapping (Ghidra, units, runtime identification); boundaries are written by `make match WRITE=1` from Phase 4 on | Write unit source |
| Decompiler | Writes Pascal for one unit until `make match` passes | Edit another unit's routines (stub signatures excepted, 9.6); write levels by hand |
| Verifier | Sessions, goldens, oracle features, the rebuild; bisects failures | Change source to make a check pass without understanding why |
| Reviewer | Independent review of a complete unit with the checklist (playbook 70); files findings; `make review-pass` | Edit the code it reviews; review a unit it decompiled |
| Documentarian | Writes whitepaper chapters across units from verified findings, with evidence tags (playbook 60); the decompiler writes what its own unit taught | Add claims without evidence or an explicit hypothesis tag |
| Expert advisor | One human-started powerful-model worker; diagnoses recorded codegen/review failures through the bounded queue (playbook 80), reads prior learning and returns small evidence-linked probe suggestions | Start/replace/delegate agents; edit unit source or verdicts; pass reviews; approve human-reserved changes; exceed the approved budget or treat unknown usage as free |

One agent may play several roles over time, but **the reviewer of a routine is never its decompiler** (a fresh session at minimum).

### 9.3 Work packets

`make packet FN=<id>` (or `UNIT=<id>`) writes `build/packets/<id>.md`: each routine's disassembly with its calls and globals named (runtime routines, `re/symbols.toml`, `re/dseg.toml`), its literal pool decoded as strings, the current source (if any), relevant whitepaper sections, and pointers into prior art. Agents work from packets and `make match` output, not from memory.

Packets front-load searchable evidence-linked lessons in `re/learnings/`, accepted main's whitepaper
and the reference/licence index. Before new probes, agents search `make learn` and reusable TP idioms.
Verified fixes and failed approaches are recorded with the routine's evidence; a stale worktree must
not make another agent rediscover an already accepted result. Playbook 80 advice is a lead, not proof.

### 9.4 State tracking

- `re/symbols.toml` holds per routine: `id`, `unit`, `addr`, `size`, `name`, `signature`, `level`, `notes`, `evidence`.
- `work/status.md` is generated by `make status`: per unit counts by level, bytes covered.
- `work/queue.toml` orders units. The runtime units are library and never queued. Order: small and leaf units first (they build the stub signatures and global names others need), then data loaders, text and graphics primitives, the ECL interpreter, maps and movement, menus and character screens, items and shops, combat, magic, the rest. `make next` proposes the next item.
- Locks prevent two agents taking the same unit or review. They live in the clone's git directory (`$(git rev-parse --git-common-dir)/poolrad-locks/`), shared by every worktree of the clone and never committed, and are created atomically. `make claim AGENT=<name> [REVIEW=1]` takes the next unit (or review), locks it and creates its worktree; the same agent reclaiming its own lock reuses them. `make locks` lists them. A lock is released by `make integrate` when its branch is merged, by the worker's supervisor when its branch has no commits beyond `main`, or by the human (`make unlock UNIT=<id> OPERATOR=1 FORCE=1 REASON=`) for an agent that stopped with work on its branch; `make inbox` lists those. Parallel agents therefore share one machine and one clone; agents on several machines would need a shared lock store (not built).
- A hand-off that `make integrate` could not merge is marked `integrate = rejected` with the reason and a log; the unit goes back to its owner through `make claim`. Routines a worker's sessions failed twice go to the frontier (`.git/poolrad-frontier/`), which the scheduler skips until released.
- The shared files (`re/symbols.toml`, `re/dseg.toml`, `re/renames.toml`, `re/learnings/*.toml`, `src/POOLVARS.PAS`) merge record by record (`tools/agent/merge_shared.py`, `.gitattributes`); stub lines are regenerated from `signature` by `make stubs`; renames are applied at integration. Two branches therefore conflict only on the same record.
- At creation, register the actual role, harness, full model id/variant and harness session id. An
  immutable agent incarnation and per-claim task id bind locks, heartbeats, hand-offs and activity to
  that configuration and base commit. Changes of role/model/session require a new incarnation and
  cannot replace a holder with unsettled work. Missing historical metadata stays unknown.
- Fixed `make` tool wrappers record outcomes, input revisions, fresh match code bytes and elapsed
  tool time. Accepted tasks attribute registry promotions/proven code bytes to their submitter, not
  the merger; wall time, tool time and measured model usage are separate metrics. `make performance`
  reports them without pretending different assignments form a controlled benchmark.
- Trusted harness counters supply nonoverlapping measured usage intervals. OpenCode V2 has a read-only
  session API adapter; other harnesses need a trusted bridge/export. Missing USD is not zero and prices
  are never guessed from model names. Operator configuration, meter and budget files need protection
  outside workers' unrestricted shell access (THROUGHPUT.md); registry declarations are not authentication.

### 9.4.1 Bounded expert consultation

The human admits one expert with a selected powerful model and an external provider/harness spend
cap. The orchestrator's deterministic scan can queue advice after three distinct recorded failed
codegen revisions or two consecutive failed review rounds. It never launches an agent. Defaults:
one active case (at most two waiting), 50 cases/run, one consultation/problem/input revision, a
15-minute lease, USD 10 case allocation and USD 500 run allocation (raised tenfold by the human on
2026-10-13). A routine already at L2 on main or in its unit's worktree is never a codegen case; a
queued case whose routine reaches L2 is retired as obsolete and does not count against the run. Cases contain bounded frozen source, failure history and
retrieved prior learning. The original worker still proves the result; expert advice writes no level,
review pass, source change or human approval. Known human-held rule decisions are not paid retry loops.

Real cumulative counters and reserved active allocations govern dispatch. Unknown/regressing usage,
expired/unsettled cases and overages hold further spending; quotas cannot be reset in the same run or
evaded by replacing the session. Dollar allocations and tool-boundary deadlines are not hard billing
or process limits: the human must configure those in the harness/provider before enabling paid advice.
No missing-usage estimate is substituted. See playbook 80 and `docs/process/THROUGHPUT.md`.

### 9.5 The per-routine loop (summary; full detail in playbook 30)

1. `make worker AGENT=<name> ROLE=decompiler` runs the loop below with a fresh model session per batch of routines (`docs/process/WORKER.md`); by hand: `make claim AGENT=<name>`, the next unit is locked and its worktree created on branch `unit/<id>`.
2. `make packet UNIT=<id>`; read it and the relevant whitepaper sections.
3. Replace stubs in `src/<ID>.PAS` by routines; fix callee stub signatures (in any unit's file) and add names for new globals.
4. `make match UNIT=<id> FN=<name>` until it passes; when the compiler's choice is unclear, probe the idiom with `make tpc`. After 5 failed attempts on one routine, stop and write a `blocked` note with what was tried.
5. Make the routine readable (names with evidence through `make rename`, named constants, its comment), `make match` again and `make readability UNIT=<id>` clean.
6. `make match UNIT=<id> WRITE=1` records L2; commit with the routine id in the message.
7. When the unit is complete, or when stopping: update the whitepaper (playbook 60), commit on the unit branch, hand the branch off; `make integrate` merges it, runs `make check` and releases the lock, or rejects it with the reason (playbook 90).
8. A complete unit merged on `main` is reviewed by another agent (`make claim REVIEW=1`, playbook 70); must-fix findings send it back to step 1 (`make claim UNIT=<id>`).

### 9.6 Guardrails

- Never edit `poolrad/`. Never commit generated files from `build/`, never commit the compiler. Never paste code from repositories whose licence does not allow it (section 13).
- Never mark levels by hand; only tools write verdicts. A matcher change is a tooling task that passes `make match-gate` (8.3) with a written reason in the commit; worker sessions cannot make one (hooks).
- Shared files: `src/POOLVARS.PAS` (one declaration per line, kept in offset order), stub declarations in other units' files and `re/symbols.toml` `signature`/`notes` take small edits; the orchestrator resolves merge conflicts there (playbook 90). A stub's signature change must keep every matched caller matching (`make check`). `work/status.md` and `docs/design/CHANGELOG.md` are written by the orchestrator only (changelog rows come with the hand-offs).
- Escalation: a question an agent cannot settle from evidence, or a decision reserved for the human, goes to the orchestrator as `make handoff STATE=escalate`; the orchestrator takes it to the human and never merges it.
- No inline machine code (`inline(...)`, `asm` blocks of raw bytes) to force a match. Hand-written assembly routines of the original are written as Turbo Pascal `assembler` routines with real instructions, and say so in their header comment.
- Ask the human before: changing ADRs, the session set, `re/state.toml`, or anything in `poolrad/`.

---

## 10. Phases and milestones

| Phase | Goal | Exit criteria |
|---|---|---|
| P0 Bootstrap | Environment and pinned inputs | Done 2026-10-07 |
| P1 Map | Know the binary | Done 2026-10-09: units, routines, RTL, TP 6.0 pinned, DGROUP map started |
| P2 Oracle and data | Run the original deterministically; decode the data | Done 2026-10-10: oracle, goldens with recordings, data codecs |
| P3 Match harness | Prove ADR-002; ready for parallel agents | `make match` with tests; units decompiled to complete (res04, ovl00), the main program matched; skeletons for every unit; `make rebuild`, `make review-pass`, `make claim`; `make check` runs the unit tests, every unit's match, the rebuild link and the golden check. Done 2026-10-11 |
| P4 Match | All game units in readable Pascal | Every game unit done (complete, readable and reviewed); map boundaries corrected from the compiler's; whitepaper chapter per subsystem |
| P5 Rebuild | The original program from source | `make rebuild` byte-identical (or every difference explained); every golden session passes on the rebuild |
| P6 Consistency | One vocabulary across the whole game | Readability is done unit by unit in P4; P6 harmonises names across units once the whole game is known (the same thing has one name everywhere, record types shared), every routine still L2, reviewer sign-off per subsystem |
| P7 C translation | Portable C | C translated from the Pascal (starting from branch `track-c-hybrid`), native build plays the goldens through record/replay; portability rules for CMOC set |
| P8 CoCo 3 | Plan and prototype | CMOC builds the engine for 6809; memory banking by unit; GIME video mapping |

Milestones are reviewed by the human at each phase exit; the spec is updated (new version) when a phase teaches something that changes it.

### 10.1 Owners of each phase

Every phase has the human operator (starts and stops the agents, answers escalations, approves the phase exit) and the orchestrator (merges, `make check`, status, changelog, reports). The roles below do the work. Placeholders mark what is decided in principle but not built yet; each becomes a playbook and its tools before its phase starts.

| Phase | Produces (outcome) | Does the work | Proves or accepts | Ready? |
|---|---|---|---|---|
| P4 Match | O1, O3 (unit facts), O4 (unit by unit) | Decompilers (playbook 30, run by `make worker`), including readability (`docs/process/READABILITY.md`); documentarians for chapters across units (playbook 60); boundaries written by `make match WRITE=1` | `make match` (L2), `make readability`, reviewers judging names and comments (`make review-pass`, playbook 70), `make integrate`'s `make check` | Yes |
| P5 Rebuild | O2 | **Placeholder:** a verifier. Moves globals from `src/POOLVARS.PAS` into their owning units in the original order, puts the overlay directives into `src/POOL.PAS`, matches the original link order and the layout of `GAME.OVR` | `make rebuild` byte-identical (or every difference explained in the whitepaper); goldens passing on the rebuild | **No:** needs a verifier playbook, and `make golden CHECK=1` against the rebuilt EXE (the oracle runs only the original today). Due before P4 ends |
| P6 Consistency | O4 (across units) | **Placeholder:** decompilers and a documentarian, per subsystem: one name for one thing across units, shared record types | Every routine still L2 (`make check`); a reviewer signs off each subsystem | Partly: `make rename` and `make readability` exist; a consistency playbook is due late in P4 |
| P7 C translation | O5 | **Open decision for the human:** agents translating by hand, or a mechanical Pascal to C translator that agents then clean up. Either way it starts from branch `track-c-hybrid` (memory model, runtime, platform layer) | The oracle's record/replay sessions against the rebuild (`tools/oracle/replay.py`, on `main`) | **No:** decide late in P4 |
| P8 CoCo 3 | Beyond the outcomes above | To be planned after P7 | | No |

---

## 11. Build process

| Target | Toolchain | Command | Status |
|---|---|---|---|
| Match one unit | Turbo Pascal 6.0 (June 1991) under emu2 | `make match UNIT=<id> [FN=<name>] [WRITE=1]` | P3 |
| Compile any Pascal (probes) | same | `make tpc SRC=file.pas [DISASM=1]` | Available |
| Tests | Python (pytest) | `make test` (fast), `make test-slow` (boots the game) | Available |
| Everything a commit must pass | | `make check` | P3 |
| Rebuild the game | Turbo Pascal 6.0 | `make rebuild` (links from P4; byte-identical in Phase 5) | Available |
| C translation | clang, SDL3 (from branch `track-c-hybrid`) | `make host` | Phase 7 |
| CoCo 3 | CMOC + LWTOOLS | `make coco3` | Phase 8 |

---

## 12. The design doc (whitepaper)

`docs/design/WHITEPAPER.md` explains how Pool of Radiance works: architecture, data formats, the script interpreter, maps and movement, characters, items, combat, magic, user interface, sound, saves. Rules:

- Every claim carries a confidence tag: **[V]** verified (with an evidence pointer: address, test, tool output), **[I]** strong inference (with reasoning), **[H]** hypothesis, **[?]** open question. A matched routine is [V] evidence of what the code does.
- It is updated in the same change that proves the fact (playbook 60). Each update adds a line to `docs/design/CHANGELOG.md`.
- Prior-art claims enter as [H] or [I] with a citation and become [V] only when proven on our build.

---

## 13. Prior art and licences

Full index: `docs/reference/prior-art.md`. Summary of how each may be used:

| Source | What it offers | Licence | Use |
|---|---|---|---|
| abedegno/Exhume | Method, headless DOS runner, routine fuzzing, record/replay design | MIT | May reuse code with attribution |
| simeonpilgrim/coab | Curse of the Azure Bonds (same engine family) decompiled to C#, per-overlay files, IDA listing | None stated | Read for understanding; do not copy code |
| stdarg/OpenGold (OpenGoldBox) | Modern reimplementation reading Pool of Radiance data; format docs | MPL-2.0 | Leads; avoid copying code |
| wicanr2/Pool-of-Radiance-cht | Deep RE of the 1988 TP5 build | RRSAL-1.0 | Read for leads; addresses do not apply; do not copy |
| Jzatopa/SSI-Engine-Full-Play-ability, farmboy0/ssi-engine | Gold Box engine reconstruction work, ECL analysis | GPL-3.0 | Read only |
| tomtombombadil/CYD-BYOG-PoolRadSeries | Gold Box engine on an ESP32 | MIT | Useful for the CoCo 3 port design |
| Borland Turbo Pascal 6.0 / 7.0 | The compiler and runtime that built the game | Proprietary (Borland, now Embarcadero); never released as freeware | Local use under `build/toolchain/` only; never committed or pushed. A rebuilt `START.EXE` contains the Borland runtime and is never distributed |
| dmsc/emu2 | Headless DOS emulator that runs `TPC.EXE` | GPL-2.0 | Built locally into `tools/vendor/` (ignored by git); used as a tool |

Game data and the original executables are copyrighted; they stay in this private repository and are never pushed to a public remote.

---

## 14. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A routine that no Pascal reproduces (hand-written assembly, compiler quirks) | Cannot reach L2 in plain Pascal | Turbo Pascal `assembler` routines with real instructions (9.6); evidence in the whitepaper |
| The compiler is on the critical path and not redistributable | A new machine cannot match without it | Archive hashes and sources in `tools/re/tp_toolchain.toml` and `docs/setup/SETUP-tp.md` |
| Map boundaries wrong (`re/symbols.toml` merges routines, gives literal pools to the wrong routine, misses routines) | Wrong ids for routines | `make match WRITE=1` writes the compiler's boundaries; `make map` learns the TP 6.0 prologue `55 89 E5` |
| Shared files (`POOLVARS.PAS`, registries, stub declarations) | Merge conflicts between agents | Record-level merge driver, stubs regenerated from signatures, `make integrate` with `make check` before anything lands |
| A routine no Pascal reproduces because it was never Pascal (an `.OBJ` linked with `{$L}`) | Unit cannot be complete | `external_from` in `re/units.toml`: kept as the original's bytes, rebuilt from an assembly source in Phase 5 (res03) |
| A byte-identical link is out of reach (link order, overlay file layout) | O2 is "identical up to explained differences" | Sessions on the rebuild prove behaviour; every difference is documented |
| Agents drift or hallucinate | Bad names, wrong claims | Packets, evidence tags, tool-written verdicts, independent review |
| Scope (about 236 KB of game code) | Long project | Units in parallel worktrees; small units first |

---

## 15. Open questions

1. ~~Exact Turbo Pascal version.~~ Resolved 2026-10-09: TP 6.0, June 1991.
2. ~~Compiler directives.~~ Resolved for `$A`, `$F`, `$S`, `$R`, `$G`, `$I`, `$O` (section 3, item 6). Still open: `$B`, `$V`, `$X` (no evidence yet).
3. ~~Where `start-unpack.exe` came from.~~ Resolved: `make unexepack`.
4. Meaning of the overlay stub field at +0E and of the `POOL.CFG` third option (`F`/`N`).
5. How much of the resident code is hand-written assembly (Turbo Pascal `assembler` routines or external `.OBJ` files).
6. The original unit link order and whether `GAME.OVR` can be reproduced byte for byte (Phase 5).

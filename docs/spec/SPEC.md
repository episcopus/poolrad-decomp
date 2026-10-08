# Pool of Radiance (DOS) Decompilation: Process Specification

| | |
|---|---|
| Version | 0.1 (draft for review) |
| Date | 2026-10-07 |
| Target | SSI *Pool of Radiance*, DOS, the build in `poolrad/` (hashes in section 2) |
| Output | Readable C in `src/`, a build that reproduces the game, a living design doc in `docs/design/` |
| Execution | AI-agent driven, harness agnostic (Claude Code, Cursor, OpenCode), human supervised |

This document says **what** we build, **how** we prove it is right, and **how agents do the work**. The agent operating manual is `AGENTS.md`; step-by-step procedures are in `docs/process/playbooks/`; environment setup is in `docs/setup/SETUP-macos.md`; what we learn about the game goes in `docs/design/WHITEPAPER.md`.

---

## 1. Outcomes

| ID | Outcome | Measure of done |
|---|---|---|
| O1 | Readable C source for the whole game in `src/` | Every original routine outside the Turbo Pascal runtime has a C counterpart with a meaningful name, typed parameters and a provenance comment |
| O2 | A build that reproduces the game | `make host` builds a native macOS/Linux executable that plays Pool of Radiance start to finish from the original data files |
| O3 | Proof of correctness | Every routine at verification level L2 or higher, or L1 plus coverage by a passing L3 session (section 8); the golden session suite passes |
| O4 | A design doc that explains how the game works | `docs/design/WHITEPAPER.md` covers every subsystem with evidence-tagged claims and is updated as part of each unit's definition of done |
| O5 | Ready for a CoCo 3 port | The engine code obeys the portability rules (section 7.2) from day one; a portability lint passes in `make check` |
| O6 (stretch) | Reproduce on DOS | The same `src/` builds as a 16-bit DOS executable (Open Watcom) that runs in DOSBox-X |

Non-goals for now: a byte-identical rebuild (see section 4), the CoCo 3 port itself (planned as Phase 7), enhancements or bug fixes to game behaviour (allowed only behind a build flag after O3).

---

## 2. Pinned inputs

All work targets exactly these files. Tools refuse to run on anything else (`make inputs` checks).

| File | Bytes | SHA-256 | Notes |
|---|---:|---|---|
| `poolrad/START.EXE` | 65,231 | `d825df2b174675c9088ba1489488bdeebe66ad2a22943f17d3a198e60b6a07bd` | Microsoft EXEPACK packed ("Packed file is corrupt" stub) |
| `poolrad/start-unpack.exe` | 71,152 | `8e60e2b00c0caec91cd47d06abb30f5269ffeec857a06cb67975f619b47c549e` | Unpacked image, 561 relocations; analysis input |
| `poolrad/GAME.OVR` | 206,105 | `14e2b132470cbae275d8d925ddeeb9e370fdc5a7cfd4564ea3212dd4956ca722` | Borland overlay file, `FBOV` header |
| `poolrad/*.DAX`, `ITEMS`, `SAVE/` | | recorded by `make inputs` | Game data, read-only |

`start-unpack.exe` was produced earlier by hand. Phase 0 must reproduce it from `START.EXE` with our own unpacker (or document the differences) so the chain from the shipped file to the analysis input is repeatable.

**Version caution.** Other Pool of Radiance projects analysed a different, earlier build: a 47,936-byte `START.EXE` with a 232,379-byte `GAME.OVR` in Turbo Pascal 5.x `TPOV` format with 38 overlays (wicanr2/Pool-of-Radiance-cht, `docs/re/dos-toolchain-baseline.md`). Ours has 35 overlays in `FBOV` format. Their findings are leads, never addresses we can reuse without re-proving them on our bytes.

---

## 3. What the binary is (verified facts that shape the approach)

Each item was checked against our files on 2026-10-07; details and evidence are in the whitepaper.

1. **Language: Turbo Pascal, not C.** The unpacked image contains the Borland Pascal runtime error strings ("Runtime error ", " at ", ".") followed by "Portions Copyright (c) 1983,91 Borland". The entry point is a chain of 48 far calls, one per unit initialisation, which is how Turbo Pascal starts a program.
2. **Overlays.** `GAME.OVR` begins with `FBOV`. 35 overlay stub segments (INT 3Fh headers) in the load image describe 35 overlay units that tile the overlay file exactly, with 406 entry points and 197,641 bytes of code. The other 13 init calls go to resident units (the runtime and resident game units). `tools/re/tpovl.py` regenerates all of this.
3. **Packing.** The shipped `START.EXE` is EXEPACK compressed.
4. **Data.** All 113 `.DAX` files are block archives with one header layout, and all 1,245 blocks decompress to their declared size with one RLE scheme (whitepaper, section 4.1).
5. **Memory.** DGROUP is paragraph `0C7C` in the load image (set by the System unit init), the stack segment is `14F2` with SP `4000`.

Consequences:

- A byte-matching **C** decompilation is not possible: no C compiler produced these bytes.
- The natural decomposition is the original one: **48 units** (13 resident, 35 overlay), each a source module. We keep that boundary in `src/` (it also maps well onto CoCo 3 memory banking later).
- Turbo Pascal semantics (length-prefixed strings, sets, nested procedures, VAR parameters, the RTL's `Random`) must be reproduced exactly in C helpers, or behaviour will drift.

---

## 4. Approach decision (ADR-001)

**Decision: behaviour-matching C ("proven-equivalent decompilation"), verified routine by routine against the original machine code, and session by session against the original program.**

### 4.1 Options considered

| Option | What it gives | Why not chosen as primary |
|---|---|---|
| A. Byte-matching C | The strongest proof | Impossible: the original is Pascal |
| B. Byte-matching Pascal, then translate to C | Byte-level proof of the Pascal; Turbo Pascal's simple, non-optimising codegen makes matching plausible | Needs the exact compiler version (unconfirmed, user must own it), doubles the work (match, then translate), and the C translation still needs its own proof |
| C. Clean-room reimplementation (OpenGoldBox, wicanr2's remake, CYD) | Fast to something playable | Not a decompilation; drifts from original behaviour; no traceability to the binary |
| D. Static recompilation (machine translation of x86 to C) | Exact behaviour quickly | Unreadable output; fails outcome O1 |
| **E. Behaviour-matching C with layered proof (chosen)** | Readable C, one function per original routine, proven by differential testing on the original's own bytes | Proof is by testing, not identity: strong but not absolute. Mitigated by fuzzing on random and recorded inputs plus full-session replays |

### 4.2 What "behaviour-matching" means here

- **Structure matches:** one C function per original routine, same unit, same parameters and results, same calls in the same order. Names and comments are ours.
- **Effects match:** for any input state, the C function leaves the same memory, the same results, the same calls to the outside world (files, keyboard, timer, video, sound) and consumes the same random numbers as the original routine.
- **Data layout matches:** every record and global keeps its original byte layout, so saves, data files and memory snapshots are interchangeable between the original and our build.

### 4.3 Optional track M (Pascal matching)

If the Turbo Pascal version is pinned (Phase 1) and the user supplies that compiler, a unit may additionally be matched in Pascal to settle routines whose behaviour is hard to pin by testing. It is never on the critical path.

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
 work packets (build/packets/*.md)  ---->  agents  ---->  src/ (C) + tests/
                                              |              |
                                              v              v
 tools/oracle: emulator running the ORIGINAL code  <--->  hybrid + native builds
     |  (fuzz, traces, sessions, screenshots)               |
     v                                                       v
 verdicts (work/status) ------------------------------->  docs/design/WHITEPAPER.md
```

Principles (adapted from Exhume's method and Rebrew's principles, `docs/decomp-tools/rebrew/PRINCIPLES.md`):

1. **Text is the source of truth.** Names, types, signatures, struct layouts and status live in text files under `re/` and `work/`. The Ghidra project is a disposable view rebuilt from them, so parallel agents never merge binary databases.
2. **Every step ends in a check a machine can repeat.** No routine is "done" on judgement alone.
3. **Evidence over recall.** Agents cite addresses, test cases and files. Claims from memory or prior art are tagged as leads until proven on our bytes.
4. **CLI first.** Every capability is a `make` target or a script with JSON output and a non-zero exit code on failure. MCP servers are optional conveniences.
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
  setup/SETUP-macos.md    environment setup
  process/playbooks/      step-by-step procedures for each stage
  design/WHITEPAPER.md    how the game works (living document) + CHANGELOG.md
  reference/              prior art index and licence rules
  (existing reference material: dos-decomp-projects/, decomp-tools/, articles/, PDFs)
re/                       reverse-engineering database (text, committed)
  units.toml              48 units: name, kind, segment/overlay, source file
  symbols.toml            every routine and global: address, name, signature, status
  types/                  struct and enum definitions as C headers with offset asserts
  dseg.toml               DGROUP layout (globals by offset)
  state.toml              what "game state" is, for checkpoint comparison
src/
  include/                portable types, Pascal runtime helpers, generated headers
  rtl/                    Turbo Pascal runtime semantics (strings, sets, Random, files, heap)
  game/                   one file (or directory) per original unit
  platform/               host (SDL3), dos (later), coco3 (later)
  hybrid/                 glue that lets C routines run inside the emulator
tests/
  unit/                   C unit tests for helpers and data codecs
  fuzz/                   per-routine differential test specs
  sessions/               recorded input scripts + golden digests (no game data)
tools/
  setup/                  setup-macos.sh, doctor.sh
  re/                     tpovl.py and dax.py (done), unexepack.py, rtl_ident.py
  ghidra/                 PyGhidra scripts: import, apply re/, export
  oracle/                 the emulator harness (Unicorn based); smoke.py (done) proves the original runs
  agent/                  packet.py, status.py, lock.py
  lint/                   portability lint
work/                     status, queue and locks (committed, small text files)
build/                    everything generated (ignored by git)
```

---

## 7. The C codebase

### 7.1 Shape of the code

- **One routine, one function.** Named for what it does (`party_award_xp`), with the original address in a provenance comment:
  ```c
  /* ovl12:0A3C  (unit 'COMBAT', entry 7)  verified: L2 2026-10-12
   * Original: Pascal procedure, 2 params, nested procs: 1 (see combat_roll_init_inner). */
  ```
- **One unit, one module.** `src/game/<unit>.c` plus `<unit>.h`; unit names come from evidence (strings, behaviour, prior art) and start as `ovlNN` / `resNN` until named.
- **Two passes per unit.** First a *faithful* pass (same control flow, same evaluation order, original quirks kept) until it reaches L2. Then a *readability* pass (names, enums, comments, small refactors) that must keep every test green. Quirks are never "fixed"; they are documented and, if desired later, fixed behind `POOL_FIX_*` flags.

### 7.2 Portability rules (for DOS and CoCo 3 later)

The engine (`src/game`, `src/rtl`) must be portable C that a 16-bit compiler with a 16-bit `int` can build:

- Use only the project's width types (`u8 s8 u16 s16 u32 s32` from `src/include/types.h`); never bare `int`/`long` for game data.
- No floating point, no 64-bit integers, no VLAs, no recursion deeper than the original's, no bitfields, no dynamic allocation outside the RTL heap emulation.
- No host libc beyond a small allowed list (`memcpy memset memmove strlen`); everything else goes through `src/rtl` or `src/platform`.
- No platform code in the engine: video, input, timer, sound, files, time and randomness seeds go through `src/platform/platform.h`.
- Struct layouts are packed and asserted (`STATIC_ASSERT(offsetof(...))`) to the original byte offsets.

`tools/lint/portability.py` enforces these in `make check`. The exact C subset accepted by CMOC (the likely CoCo compiler) is to be confirmed in Phase 7; until then the rules above are deliberately conservative.

### 7.3 Memory model

Turbo Pascal programs keep globals in DGROUP and records on a heap reached by far pointers. To keep layouts identical and to allow hybrid execution (section 8.4):

- **Globals:** one struct mirroring DGROUP byte for byte, generated from `re/dseg.toml` into `src/include/gen/dseg.h`, accessed as `G.party_size`. Unknown regions are `u8 unk_XXXX[n]` until identified.
- **Heap and far data:** referenced by `farptr` handles (segment:offset as `u32`), dereferenced with `FP(Type, p)`. In the native build the handles index a 1 MB arena managed by a Turbo Pascal compatible heap (`src/rtl/heap.c`); in the hybrid build the same macro points into the emulator's memory. Handle-based memory is also the plan for CoCo 3 bank switching.
- **Locals and parameters** are ordinary C. VAR parameters become C pointers when they never escape the call; if the original stores them, they stay `farptr`.

Phase 3 starts with a spike that proves this model on two or three routines in both builds before any bulk lifting.

### 7.4 Turbo Pascal semantics in C (`src/rtl`)

| Pascal | C | Notes |
|---|---|---|
| Byte, ShortInt, Integer, Word, LongInt | u8, s8, s16, u16, s32 | Wraparound semantics preserved; range checks mirror `{$R}` settings found in Phase 1 |
| Boolean, Char | u8 | |
| `string[N]` | `u8 s[N+1]` with `pstr_*` helpers | Length byte first; truncation rules exactly as the RTL |
| `set of 0..255` | `u8 s[32]` with `set_*` helpers | Small sets keep their original byte size |
| Records | packed structs with offset asserts | |
| Nested procedures | static functions taking an explicit `frame` struct pointer | Replaces the static link |
| `Random`, `Randomize` | `rtl_random` | Must reproduce the RTL's generator and seed handling bit for bit (verify in Phase 1) |
| Files (`Assign/Reset/BlockRead`) | `rtl_file_*` over `platform_file_*` | DOS path rules, case-insensitive lookup on the host |
| `New/Dispose/GetMem/FreeMem/MaxAvail` | `rtl_heap_*` | Same block layout, so heap snapshots compare |

### 7.5 Platform layer

`platform.h` is the only boundary to the outside world. Every function that reads the outside world (keyboard, timer ticks, time of day, random seed source) is a **hook** that the replay system can record and replay, following Exhume's design (`docs/dos-decomp-projects/UW1Decomp/docs/BUILDING.md`, "Recording and replaying a session").

- Video: the engine draws into a 320x200 indexed framebuffer with a 16-entry palette (EGA mode first; CGA and Tandy paths are decompiled but may render through the same framebuffer). The host platform scales and presents it with SDL3.
- Input: BIOS-style key codes (scan code + ASCII), as the original reads them.
- Timer: an 18.2 Hz tick source plus whatever PIT reprogramming the game does (to be found).
- Sound: PC speaker and Tandy 3-voice tones, synthesised on the host.

---

## 8. Verification

### 8.1 The ladder

| Level | Name | Evidence required |
|---|---|---|
| L0 | Drafted | C compiles in both host and hybrid builds; signature recorded in `re/symbols.toml` |
| L1 | Reviewed | An independent reviewer agent compared the C with the disassembly using the review checklist and recorded no open findings |
| L2 | Fuzz-equivalent | Differential test passes: the original bytes in the emulator and the C function, started from the same state, end in the same state for every case (minimum 200 random cases plus every recorded case for that routine; more for routines with wide input spaces) |
| L3 | Session-equivalent | The routine is exercised by at least one golden session that passes with the routine running as C |
| M | Pascal-matched | Optional: Pascal source compiles to identical bytes (track M) |

A routine's level is the lowest level it has not failed. A regression demotes it automatically. Some routines (interrupt handlers, video plane tricks, timing loops) cannot sensibly be fuzzed; they need L1 plus L3 with a written justification in `re/symbols.toml`.

### 8.2 The oracle: running the original code

`tools/oracle` is a deterministic, headless PC built on Unicorn (x86 16-bit real mode), written in Python with performance-critical parts in C if needed:

- Loads the unpacked `START.EXE` as DOS would (PSP, relocations, environment) and lets the program's own Turbo Pascal overlay manager load overlays from `GAME.OVR` through INT 3Fh and INT 21h, so overlay behaviour is real, not simulated.
- Implements the DOS and BIOS services the game uses (INT 21h file and memory functions, INT 10h, INT 16h, INT 1Ah), the timer interrupt at a virtual 18.2 Hz, port I/O for the PIT, speaker and video, and an EGA model (planes, latches, write modes, palette) so screens can be captured.
- Runs in **virtual time**: the clock advances with executed instructions, never with the wall clock, so every run is repeatable.
- Provides: call tracing (every call and return with arguments), memory watch points, state snapshots, screenshots, and an input script player.

Unicorn is already proven on 16-bit Borland code for exactly this purpose by Exhume's routine fuzzing (`fuzzasm.py`). If an emulation gap blocks progress, DOSBox-X with its debugger is the fallback oracle for that case.

### 8.3 Routine fuzzing (L2)

For a routine, `make fuzz FN=<id>` generates input states (random values constrained by the routine's signature and the types of the globals it reads, plus every state captured when the routine ran in recorded sessions), runs the original bytes in the oracle and the C function in the hybrid library on identical copies, and compares registers that carry results, all memory writes, the sequence of hooked outside-world calls and the RNG state. The first difference is reported with the instruction address and the C line that diverged.

### 8.4 Hybrid execution

The hybrid build compiles `src/` as a shared library whose memory macros point into the oracle's memory. The oracle can replace any original routine with its C version (by intercepting the call and marshalling the Pascal calling convention from the routine's recorded signature). This allows:

- playing the game in the oracle with any mix of original and C routines, long before the native build is complete;
- bisecting a session failure to one routine by toggling routines between C and original;
- calls from C into routines not yet lifted (`orig_call`) during the transition.

### 8.5 Sessions and goldens (L3)

A session is a scripted sequence of inputs (`tests/sessions/<name>.keys`) from a defined start (fresh install or a save). The oracle runs it on the original code twice (must be identical) and stores digests of the canonical game state at every checkpoint (each keyboard read by default) plus PNG screenshots at named points, in `tests/sessions/golden/<name>/` (digests and our own screenshots of our own runs only; never game files). The C build replays the same inputs through its hooks and must produce the same digests. `re/state.toml` defines the canonical state: which DGROUP ranges, which heap records reachable from which roots, which ranges are masked and why.

Initial session set (grow as units land): `boot-title`, `create-party`, `phlan-walk`, `first-combat`, `shop-buy-sell`, `camp-memorize`, `save-load`, `level-up`, plus a long `main-quest` series built from saves along the game.

### 8.6 Data codecs

Every loader for game data (DAX blocks, maps, ECL scripts, monsters, items, saves) has a round-trip test over all of the pinned files: decode, re-encode where the game writes the format (saves), compare bytes.

---

## 9. Agentic workflow

### 9.1 Harness neutrality

- `AGENTS.md` is the single source of instructions. Claude Code reads it through `CLAUDE.md`; OpenCode and Cursor read `AGENTS.md` (Cursor also gets `.cursor/rules/poolrad.mdc`).
- Playbooks are plain Markdown in `docs/process/playbooks/`. Thin command wrappers exist for each harness (`.claude/commands/`, `.cursor/commands/`, `.opencode/commands/`) that only say "follow playbook X with arguments Y", so behaviour never forks between harnesses.
- Every tool is a CLI with deterministic output. Ghidra is driven headless through PyGhidra scripts; an MCP server (for example bethington/ghidra-mcp) is optional for interactive exploration.
- No reliance on harness-specific features (sub-agents, hooks, memory). Parallel work uses git worktrees and lock files that any harness can manage.

### 9.2 Roles

| Role | Does | Must not |
|---|---|---|
| Orchestrator | Picks work from `work/queue`, assigns units, merges, keeps `work/status.md` current | Lift code itself while orchestrating |
| Mapper | Ghidra analysis, names, types, signatures in `re/` | Write C |
| Lifter | Writes C for one unit, runs builds and fuzz until L2 | Edit another unit's files; mark its own work L1 |
| Verifier | Builds fuzz specs, sessions, goldens, oracle features; bisects failures | Change C to make a test pass without understanding why |
| Reviewer | Independent L1 review against disassembly with the checklist; files findings | Edit the code it reviews |
| Documentarian | Turns verified findings into whitepaper sections with evidence tags | Add claims without evidence or an explicit "hypothesis" tag |

One person or one agent may play several roles over time, but **the reviewer of a routine is never its lifter** (a fresh session at minimum).

### 9.3 Work packets

`make packet FN=<id>` (or `UNIT=<id>`) writes `build/packets/<id>.md`: disassembly with fixups resolved, Ghidra's decompilation as a hint, callers and callees with their current names and signatures, globals touched with their known types, strings referenced, recorded call samples from sessions, the current C (if any), relevant whitepaper sections, and pointers into prior art. Packets keep agent context small and grounded; agents work from packets, not from memory.

### 9.4 State tracking

- `re/symbols.toml` holds per routine: `id`, `unit`, `addr`, `size`, `name`, `signature`, `level`, `notes`, `justification` (for L1+L3 routines), `evidence` links.
- `work/status.md` is generated by `make status`: per unit counts by level, bytes covered, sessions passing.
- `work/queue.toml` orders units. Default order: runtime and leaf utilities, data loaders, text and graphics primitives, the ECL script interpreter, maps and movement, menus and character screens, items and shops, combat, magic and effects, the rest. `make next` proposes the next item.
- `work/locks/<unit>.lock` (agent id, branch, start time) prevents two agents taking the same unit; stale locks older than 24 hours may be broken by the orchestrator.

### 9.5 The per-routine loop (summary; full detail in playbook 30)

1. Lock the unit, create a worktree branch `unit/<id>`.
2. `make packet FN=...`; read it and the relevant whitepaper sections.
3. Write or update the signature in `re/symbols.toml` and the types in `re/types/`.
4. Write the faithful C. `make hybrid host` must build.
5. `make fuzz FN=...` until it passes; on failure read the first divergence, fix, repeat. After 5 failed iterations on one routine, stop and write a `blocked` note with what was tried.
6. Record the verdict (tools update `re/symbols.toml`), commit with the routine id in the message.
7. When the unit is at L2: request review (playbook 70), run the sessions (playbook 40), update the whitepaper (playbook 60), unlock, merge.

### 9.6 Guardrails

- Never edit `poolrad/`. Never commit generated files from `build/`. Never paste code from repositories whose licence does not allow it (section 13).
- Never weaken a test, mask a state range or raise a tolerance without a written reason in the same commit, reviewed by a human.
- Never mark levels by hand; only tools write verdicts.
- Ask the human before: changing ADRs, the memory model, the platform API, the session set, or anything in `poolrad/`.

---

## 10. Phases and milestones

| Phase | Goal | Exit criteria |
|---|---|---|
| P0 Bootstrap | Environment and pinned inputs | `make doctor` green on the Mac; `make inputs` verifies hashes; EXEPACK unpack reproduced from `START.EXE`; overlay manifest committed as `re/overlays.json` |
| P1 Map | Know the binary | Ghidra project rebuildable by `make ghidra`; all 48 units with code ranges in `re/units.toml`; every routine listed with size in `re/symbols.toml`; Turbo Pascal RTL routines identified and named; Turbo Pascal version pinned or bounded; DGROUP map started; calling convention notes verified on samples; initial names from strings and prior art |
| P2 Oracle and data | Run the original deterministically; decode the data | Oracle boots the original to the title screen and through character creation from a key script, twice identically; screenshots match DOSBox-X; DAX, map and ECL decoders with tests over all files; first goldens recorded |
| P3 Runtime and skeleton | A C program that can grow | Memory model spike passes (section 7.3); `src/rtl` with tests; SDL3 host platform; hybrid library loads into the oracle; `make check` runs build, lint, unit tests, fuzz and sessions |
| P4 Lift | All units in C | Every routine at least L2 (or justified L1+L3); unit by unit in queue order; whitepaper chapter per subsystem |
| P5 Native | Playable native build | `make host` plays all goldens with every routine in C; full-game session series passes; save files interchangeable with the original |
| P6 Readability | Source a person enjoys reading | Names, enums, comments, headers; no test regressions; reviewer sign-off per unit |
| P7 CoCo 3 readiness | Plan and prototype | CMOC builds `src/game` + `src/rtl` for 6809 (link not yet required); memory banking design by unit; GIME video mapping study |
| P8 (stretch) DOS | Reproduce on the original platform | Open Watcom 16-bit build runs in DOSBox-X and passes the sessions |

Milestones are reviewed by the human at each phase exit; the spec is updated (new version) when a phase teaches something that changes it.

---

## 11. Build process

| Target | Toolchain | Command | Status |
|---|---|---|---|
| Native host (primary) | clang, CMake, Ninja, SDL3 | `make host` -> `build/host/poolrad` | Phase 3 |
| Hybrid library | clang, shared library for the oracle | `make hybrid` | Phase 3 |
| Tests | Python (pytest), C unit tests | `make test`, `make fuzz`, `make sessions` | Phases 2 to 3 |
| Everything a commit must pass | | `make check` | Phase 3 |
| DOS (stretch) | Open Watcom v2, 16-bit large model, in a Linux container (no macOS host build exists) | `make dos` | Phase 8 |
| CoCo 3 (future) | CMOC + LWTOOLS, XRoar or MAME to run | `make coco3` | Phase 7 |

Running the native build needs the user's own game files: `build/host/poolrad --data poolrad/`.

---

## 12. The design doc (whitepaper)

`docs/design/WHITEPAPER.md` explains how Pool of Radiance works: architecture, data formats, the script interpreter, maps and movement, characters, items, combat, magic, user interface, sound, saves. Rules:

- Every claim carries a confidence tag: **[V]** verified (with an evidence pointer: address, test, tool output), **[I]** strong inference (with reasoning), **[H]** hypothesis, **[?]** open question.
- It is updated in the same change that proves the fact (playbook 60). Each update adds a line to `docs/design/CHANGELOG.md`.
- Prior-art claims enter as [H] or [I] with a citation and become [V] only when proven on our build.
- Diagrams are Mermaid or ASCII inside the Markdown so any tool can edit them.

---

## 13. Prior art and licences

Full index: `docs/reference/prior-art.md`. Summary of how each may be used:

| Source | What it offers | Licence | Use |
|---|---|---|---|
| abedegno/Exhume | Method, headless DOS runner, Unicorn routine fuzzing, record/replay design | MIT | May reuse code with attribution |
| simeonpilgrim/coab | Curse of the Azure Bonds (same engine family) decompiled to C#, per-overlay files, IDA listing | None stated | Read for understanding; do not copy code |
| stdarg/OpenGold (OpenGoldBox) | Modern reimplementation reading Pool of Radiance data; format docs (graphics, sound, scripts, maps) | MPL-2.0 | Formats and behaviour notes are leads; copying code brings MPL file obligations, so avoid |
| wicanr2/Pool-of-Radiance-cht | Deep RE of the 1988 TP5 build: overlay manifest, IDA exports per overlay, ECL specs | RRSAL-1.0 (non-commercial, source-available) | Read for leads; addresses do not apply to our build; do not copy |
| Jzatopa/SSI-Engine-Full-Play-ability, farmboy0/ssi-engine | Gold Box engine reconstruction work, ECL analysis | GPL-3.0 | Read only; copying would impose GPL |
| tomtombombadil/CYD-BYOG-PoolRadSeries | Gold Box engine on an ESP32 (constrained hardware) | MIT | Useful for the CoCo 3 port design |
| GaidamakUA/DungeonCraft | Gold Box style engine and editor | see repo | Background only |

The user's earlier IDA databases in `poolrad/` (`START.*`, `CFG.*`, `start-unpack.idb`) are a starting point for names; import what is useful into `re/` in Phase 1.

Game data and the original executables are copyrighted; they stay in this private repository and are never pushed to a public remote.

---

## 14. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Emulator gaps (EGA details, timer, overlay manager edge cases) | Oracle disagrees with real DOS | Compare oracle screenshots with DOSBox-X in P2; keep DOSBox-X as fallback oracle |
| Fuzzing misses a behaviour difference | Wrong C passes L2 | Recorded-state cases from sessions, coverage reports per routine, L3 sessions, reviewer checklist |
| Memory model friction (far pointers everywhere) | Hard-to-read C | Spike in P3 before bulk work; readability pass converts proven-local pointers |
| Agents drift or hallucinate | Bad names, wrong claims | Packets, evidence tags, tool-written verdicts, independent review |
| Hand-written assembly in resident units (graphics, sound, timer) | Hard to express in C | Lift as C over the platform layer with L1+L3 justification; document hardware semantics |
| Turbo Pascal version unknown | Track M blocked; RTL quirks unclear | Bound the version by RTL byte comparison in P1; behaviour is fuzzed regardless |
| Scope (about 270 KB of code) | Long project | Units in parallel worktrees; playable hybrid early keeps feedback tight |

---

## 15. Open questions (to resolve in P0/P1)

1. Exact Turbo Pascal version (runtime says 1983,91; overlay format `FBOV`).
2. Which compiler directives were used (`$R` range checks, `$S` stack checks, `$O` overlays, `$F` far calls), visible as RTL calls in the code.
3. Where `start-unpack.exe` came from and whether it matches a clean EXEPACK unpack.
4. Meaning of the overlay stub field at +0E and of the `POOL.CFG` third option (`F`/`N`).
5. How much of the resident code is hand-written assembly.
6. Which graphics modes must be supported at first (proposal: EGA only, CGA and Tandy in P5).

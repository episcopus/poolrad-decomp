# 50 The rebuild (Verifier, Phase 5)

**Inputs:** SPEC 8.4 and 8.5; `docs/process/playbooks/40-sessions.md` (goldens); a tree where `make check`
passes; `build/re/overlays.json` (`make overlays`); the pinned Turbo Pascal 6.0 (`make tp-pin`).

**Goal:** the program built from `src/` is the original: the same load image, the same relocation table, the
same overlay file, and every golden session plays on it exactly as on the original. P5 ends when
`make rebuild` says `IDENTICAL` and `make rebuild-golden` passes (both are stages of `make check`).

What "identical" means. A program is its load image, its relocation table and its overlay file. The EXE
header of `poolrad/start-unpack.exe` is the unpacker's output (a padded header, the packed file's
checksum word), not the program's, so it is not compared. `make rebuild` compares:

| What | How |
|---|---|
| each segment (main, 15 resident units, 35 overlay units) | bytes, apart from relocation words and overlay fixups; the unit's paragraph padding must be zero |
| the load image | every byte of `POOL.EXE` after its header against `start-unpack.exe` |
| the relocation table | the set of linear addresses |
| the overlay file | `POOL.OVR` against `GAME.OVR`, byte for byte |

## Why the Pascal that matches is not yet the program

`make match` compares code and literal pools and resolves every data address by name. A unit can match at
L2 while the whole program differs, because four things only the full link sees:

1. **Where each global is.** Turbo Pascal allocates data by declaration: every unit's typed constants
   (with their initial values), then System's block, then every unit's variables, units in reverse link
   order. The decompilers modelled tables as `var` and did not need the layout.
2. **Overlay stub order.** An overlay unit's stub lists the routines other units call in the order of the
   unit's interface. The original's order is not the order of the code.
3. **Link order.** Units are linked in the order of the uses graph; the code segments and the data blocks
   fall out of it.
4. **External objects.** The sound driver of res03 was assembled elsewhere and linked with `{$L}`.

## Steps

1. `make check`, then `make rebuild`. Read the table: `-` is a segment that differs. `make rebuild-diff`
   shows the bytes. A far call `9A off seg` whose offset differs is the stub order or the link order; a
   word that is a DS offset on one side only is the data layout; a whole unit missing is an external object.
2. **Data layout** (`tools/re/dgroup.py`, `make dgroup`). `src/POOLVARS.PAS` is one generated block after
   the types: the typed constants of `DS:0002` up to the Overlay unit's own (`DS:43DC`), each with its
   original value, in offset order, then the variables up to Crt's (`DS:84F0`). An object keeps its name
   and type; where another object overlaps it the bytes sit in a `dsXXXX` storage cell and both objects are
   `absolute` views of it. The tool checks itself: it compiles and every `dsXXXX` is where its name says.
   Run it again (`make dgroup WRITE=1`) whenever a global is added or its type changes; it starts from the
   declarations (`compact_poolvars`), so it is idempotent. What it refuses it reports (an object below
   `DS:0002`, where Turbo Pascal keeps two bytes of its own, is the code wheel table: it is declared at
   `ds0002`, record fields shifted by two).
3. **Matcher view.** The matcher compiles `compact_poolvars(POOLVARS)`: the same names and types without
   the typed constants' values and without the storage cells. TPC's 640K do not hold the full model beside
   every unit. The compact form keeps the layout's order and the unnamed bytes as plain arrays, so address
   arithmetic that runs past an object finds the same neighbour as in the original. Never edit the compact
   form; edit POOLVARS and regenerate.
4. **Stub order** (`tools/re/stub_order.py`, `make stub-order WRITE=1`). Reorders the interface of each
   overlay unit so the exported routines come in the order of the original's stub entries, read from
   `build/re/overlays.json`. Routines no other unit calls keep their place (the smart linker drops their
   entries).
5. **Link order.** `src/POOL.PAS`'s `uses` clause is the order of the original's init chain, with
   `Overlay, Crt, Dos` first: the library units are linked right after System in the original (their
   code segments sit at `0AA2`, `0A40`, `0A32`), which also puts the Overlay unit's typed constants after
   the game's and Crt's variables after the game's.
6. **External objects** (`tools/re/extobj.py`). For a unit with `external_from` in `re/units.toml` the
   rebuild writes an OMF object from the original image (one code segment, a public per routine of the
   registry, a segment-base fixup for each relocated word) and links it with `{$L}`. The bytes come from
   the pinned original at build time and nothing is stored. This is a stand-in for an assembly source of
   the driver; when that exists the rebuild links its object instead.
7. **Goldens on the rebuild.** `make rebuild-golden` (`golden.py --check --rebuilt --strict-state`) runs
   `build/rebuild/POOL.EXE` in the oracle with `POOL.OVR` served as GAME.OVR (`tools/oracle/layout.py`
   knows where System, DGROUP and the overlay stubs are in the build) and compares with the committed
   goldens in two tiers: **behaviour** (stop reason, instructions, virtual time, key reads, the Random
   sequence, files opened and written, every checkpoint's screen and time, the recording of every read of
   the outside world) and **state** (DGROUP, heap and memory digests; equal exactly when the layout is the
   original's). A divergence names the first difference; `tools/oracle/routines.py` and the trace
   (`make oracle-run TRACE=calls`) say where.
8. Add or change a decompiled routine, a global or an interface: run `make check`. It rebuilds and plays the
   goldens, so a change that moves a byte of the program fails there.

## Rules

- Everything the rebuild needs is generated from `src/`, `re/` and the pinned inputs; nothing generated is
  committed except `src/POOLVARS.PAS` (the layout is source, its values were read from the image once).
- The goldens and the matcher are not changed to make the rebuild pass (AGENTS.md rule 2). A tooling
  change merges when `make match-gate` passes.
- An object file or a layout that needs the original's bytes at build time is a stand-in and is listed in
  the whitepaper (section on the rebuild) with what replaces it.
- Do not move a global into a unit unless the byte comparison still passes: ownership by unit is a
  refinement for Phase 6, the layout does not need it.

## Done when

`make rebuild` prints `IDENTICAL`, `make rebuild-golden` passes for every session in `tests/sessions/`, and
`make check` passes with both stages. The whitepaper's rebuild section lists the stand-ins (the sound
driver object, the values of the typed constants read from the image) and the open work (an assembly
source for the driver, distributing globals to their units).

## Hand-off

`make heartbeat` as usual; the unit of work is the whole program, so a verifier works in its own worktree
branch and `make integrate` merges it. Report the output of `make rebuild` and `make rebuild-golden`.

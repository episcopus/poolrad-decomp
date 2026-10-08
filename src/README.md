# src/

The C reconstruction of Pool of Radiance. Empty until Phase 3 (docs/spec/SPEC.md section 10).

Planned layout (SPEC section 6 and 7):

| Directory | Contents |
|---|---|
| `include/` | `types.h` (u8 s16 ...), `pascal.h` (string, set, frame helpers), `platform.h` (the only boundary to the outside world), `gen/` (generated from `re/`: DGROUP mirror, record types) |
| `rtl/` | Turbo Pascal runtime semantics: strings, sets, Random, files, heap, range checks |
| `game/` | one module per original unit (`res03_<role>.c`, `ovl12_<role>.c` until renamed) |
| `platform/host/` | SDL3 implementation of `platform.h` |
| `platform/dos/`, `platform/coco3/` | later targets (P8, P7) |
| `hybrid/` | glue that runs C routines inside the oracle |

Rules: portability rules in SPEC 7.2, one function per original routine with a provenance comment (SPEC 7.1).

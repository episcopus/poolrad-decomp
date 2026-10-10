# src/

The C reconstruction of Pool of Radiance (SPEC 6 and 7).

P3 spike (green via `make check`): the memory model (SPEC 7.3), the RTL
cores it needs, one game unit started, the SDL3 host platform and the hybrid
glue. Bulk lifting is P4 in queue order (`work/queue.toml`).

| Directory | Contents | Spike state |
|---|---|---|
| `include/` | `types.h` (u8 s16 ...), `pool_memory.h` (farptr, FP, arena/bind), `pool_rtl.h`, `gen/` (dseg.h generated from `re/dseg.toml`) | done |
| `rtl/` | Turbo Pascal runtime semantics | Move, FillChar, Random/ Randomize formula only |
| `game/` | one module per original unit | `res00_system.c` (3 routines, L2) |
| `platform/` | `platform.h` (the only boundary to the outside world) | hooks, waits, video present |
| `platform/host/` | SDL3 implementation + spike main | builds, presents, exits |
| `hybrid/` | glue that runs C routines inside the oracle | 3 exports + DGROUP access |

Rules: portability rules in SPEC 7.2 (`make lint`), one function per original routine with a provenance comment (SPEC 7.1).

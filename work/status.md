# Project status

*(Hand-written until `make status` exists in Phase 1; then generated.)*

Updated: 2026-10-09

## Phase

**P0 Bootstrap: done** (environment green; unpack chain reproducible). Next: Phase 1 mapping (`make ghidra` / playbook 10), after human review of SPEC ADR-001 if desired.

| P0 exit criterion | State |
|---|---|
| `make doctor` green on the Mac | done (2026-10-09; required checks pass) |
| `make inputs` verifies hashes | done (168 files pinned in `re/inputs.toml`) |
| EXEPACK unpack reproduced from `START.EXE` | done (`make unexepack`: byte match vs `poolrad/start-unpack.exe`) |
| Overlay manifest | done (`make overlays`: 35 overlays, 406 entries, 48 unit inits) |
| DAX verify | done (`make dax`: 113 files, 1245 blocks) |
| Smoke (Unicorn) | done (`make smoke`: 25 INT calls, CS:IP 1A40:0611) |

## Inventory

| | Count | Notes |
|---|---:|---|
| Units | 48 | 13 resident, 35 overlay (`re/units.toml`) |
| Overlay code | 197,641 bytes | |
| Resident image | 68,592 bytes | includes stubs, runtime and initialised DGROUP |
| Routines | unknown | Phase 1 |

## Verification

No routines lifted yet.

## Environment

Host: Darwin arm64 (2026-10-09, `make doctor`).

| Tool | Version |
|---|---|
| git | 2.50.1 (Apple Git-155) |
| python | 3.12.11 (`.venv` via uv 0.11.0) |
| unicorn | 2.1.4 |
| capstone | 5.0.7 |
| java | openjdk 21.0.12.1 |
| ghidra | `~/opt/ghidra_12.1.4_PUBLIC` |
| pyghidra | 3.1.0 |
| dosbox-x | 2026.10.01 SDL2 |
| pillow | 12.3.0 |
| clang | Apple clang 17.0.0 |
| cmake | 4.4.4 |
| ninja | 1.13.2 |
| pkg-config | 3.0.7 |
| SDL3 | 3.4.18 |
| docker | 29.6.1 (optional) |
| xroar | 1.12.1 (optional) |
| cursor-agent | 2026.01.28-fd13201 |

Optional skips: `lwasm`, `cmoc`, `claude`, `opencode`.

## Blockers and decisions waiting for the human

- Review `docs/spec/SPEC.md` v0.1, especially ADR-001 (behaviour-matching C) and the memory model (section 7.3).

# Project status

*(Hand-written until `make status` exists in Phase 1; then generated.)*

Updated: 2026-10-07

## Phase

**P0 Bootstrap: in progress.**

| P0 exit criterion | State |
|---|---|
| `make doctor` green on the Mac | open (run after `tools/setup/setup-macos.sh --with-ghidra`) |
| `make inputs` verifies hashes | done (168 files pinned in `re/inputs.toml`) |
| EXEPACK unpack reproduced from `START.EXE` | open (`tools/re/unexepack.py` to write) |
| Overlay manifest | done (`make overlays`: 35 overlays, 406 entries, 48 unit inits) |

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

*(paste the `make doctor` output summary here after setup)*

## Blockers and decisions waiting for the human

- Review `docs/spec/SPEC.md` v0.1, especially ADR-001 (behaviour-matching C) and the memory model (section 7.3).

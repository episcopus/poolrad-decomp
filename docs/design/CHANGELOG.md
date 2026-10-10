# Design doc changelog

One line per update: date, section, change, evidence.

| Date | Section | Change | Evidence |
|---|---|---|---|
| 2026-10-09 | 2.2, 3.2 | Runtime units recorded in `re/units.toml` (`res13` Dos, `res14` Overlay, no init); res02 and res08 demoted to game units; `make tpc` added for codegen questions | `make map`, `make p1-check`, `tests/unit/test_tp_toolchain.py` |
| 2026-10-09 | 2.2, 3.2, 6 | TP version pinned to 6.0 (June 1991 release) by RTL byte comparison; TP 6.0 (1990) and 7.0 eliminated; runtime unit ranges corrected; directives `$S- $R- $G- $F+`, `$I+` in res05 | `make tp-pin` (`tools/re/tp_toolchain.py`), `tests/unit/test_tp_toolchain.py` |
| 2026-10-09 | 3.2, 3.2.1 | P1 complete: RTL entries named, 21 overlays named from strings, Dos [I], `make p1-check` green | `make map`, `make p1-check`, Capstone on System |
| 2026-10-09 | 2.2, 3.2, 3.4 | Phase 1 map seed: units/ranges, 1392 routines, System/Crt/Overlay named, CC samples, TP 6/7 bound | `make map`, `make ghidra`, Capstone samples |
| 2026-10-09 | 2.1, 3.1.1 | EXEPACK unpack chain reproduced; `start-unpack.exe` matches `START.EXE` byte for byte | `make unexepack` / `tools/re/unexepack.py --check` |
| 2026-10-07 | all | Document created and seeded from Phase 0 analysis | `tools/re/tpovl.py`, `tools/oracle/smoke.py`, `tools/setup/inputs.py`, `tools/re/dax.py verify` over all 113 files |

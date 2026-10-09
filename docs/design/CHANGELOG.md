# Design doc changelog

One line per update: date, section, change, evidence.

| Date | Section | Change | Evidence |
|---|---|---|---|
| 2026-10-09 | 3.2, 3.2.1 | P1 complete: RTL entries named, 21 overlays named from strings, Dos [I], `make p1-check` green | `make map`, `make p1-check`, Capstone on System |
| 2026-10-09 | 2.2, 3.2, 3.4 | Phase 1 map seed: units/ranges, 1392 routines, System/Crt/Overlay named, CC samples, TP 6/7 bound | `make map`, `make ghidra`, Capstone samples |
| 2026-10-09 | 2.1, 3.1.1 | EXEPACK unpack chain reproduced; `start-unpack.exe` matches `START.EXE` byte for byte | `make unexepack` / `tools/re/unexepack.py --check` |
| 2026-10-07 | all | Document created and seeded from Phase 0 analysis | `tools/re/tpovl.py`, `tools/oracle/smoke.py`, `tools/setup/inputs.py`, `tools/re/dax.py verify` over all 113 files |

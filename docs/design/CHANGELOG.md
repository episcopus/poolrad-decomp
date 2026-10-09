# Design doc changelog

One line per update: date, section, change, evidence.

| Date | Section | Change | Evidence |
|---|---|---|---|
| 2026-10-09 | 2.1, 3.1.1 | EXEPACK unpack chain reproduced; `start-unpack.exe` matches `START.EXE` byte for byte | `make unexepack` / `tools/re/unexepack.py --check` |
| 2026-10-07 | all | Document created and seeded from Phase 0 analysis | `tools/re/tpovl.py`, `tools/oracle/smoke.py`, `tools/setup/inputs.py`, `tools/re/dax.py verify` over all 113 files |

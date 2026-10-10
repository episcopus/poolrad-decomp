# Prior art and how we may use it

Checked 2026-10-07. Licences from each repository's metadata. "Read only" means: learn from it, cite it, re-prove every claim on our build, never copy code.

## Same game or same engine

| Project | What it is | Licence | Use | Most useful parts |
|---|---|---|---|---|
| [wicanr2/Pool-of-Radiance-cht](https://github.com/wicanr2/Pool-of-Radiance-cht) | Go remake of Pool of Radiance driven by deep RE of the **1988 TP 5.x build** (38 overlays, `TPOV`) | RRSAL-1.0 (non-commercial, source-available) | Read only | `docs/re/dos-toolchain-baseline.md`, `docs/audit/dos-ovr-manifest.json`, `docs/audit/ida-overlayNN-*.json` (function-level notes per overlay), `docs/spec/*` (ECL dialect, character creation, save formats). Addresses do not apply to our build. |
| [stdarg/OpenGold](https://github.com/stdarg/OpenGold) (OpenGoldBox) | C++20 / Godot engine that reads Pool of Radiance data; New Phlan and the Slums playable | MPL-2.0 | Leads; avoid copying code (file-level copyleft) | `docs/graphics-format.md`, `docs/sound-format.md`, `docs/SCRIPTS.md`, `docs/MAPS.md`, `docs/TECH.md`, `docs/script-source-audit.md` |
| [simeonpilgrim/coab](https://github.com/simeonpilgrim/coab) | Curse of the Azure Bonds (same engine family, 1989) decompiled to C#; one file per overlay (`engine/ovrNNN.cs`), shared state in `Classes/Gbl.cs`, an IDA listing (`coab_new.lst`) | none stated | Read only | ECL interpreter (`engine/ovr003.cs`, `VmOpp.cs`), DAX handling (`Classes/DaxFiles`), Pool of Radiance character import (`Classes/PoolRadPlayer.cs`), names for analogous routines |
| [DoktorCranium/coab](https://github.com/DoktorCranium/coab) | C and SDL port of coab | none stated | Read only | C idioms for the same engine |
| [Jzatopa/SSI-Engine-Full-Play-ability](https://github.com/Jzatopa/SSI-Engine-Full-Play-ability) | Java Gold Box engine reconstruction, ECL disassembly passes | GPL-3.0 | Read only | ECL analysis notes |
| [farmboy0/ssi-engine](https://gitlab.com/farmboy0/ssi-engine) | Java SSI engine | see repo | Read only | |
| [simeonpilgrim/goldboxexplorer](https://github.com/simeonpilgrim/goldboxexplorer) | Gold Box data viewer (C#) | none stated | Read only | data formats |
| [tomtombombadil/CYD-BYOG-PoolRadSeries](https://github.com/tomtombombadil/CYD-BYOG-PoolRadSeries) | Gold Box engine on ESP32 boards, reads original files | MIT | Reusable with attribution | design for constrained hardware (relevant to CoCo 3), `docs/SPEC.md` |
| [grannypron/PoR_L10n](https://github.com/grannypron/PoR_L10n) | Pool of Radiance localisation patches | Unlicense | Reusable | where text lives in the binaries |
| [GaidamakUA/DungeonCraft](https://github.com/GaidamakUA/DungeonCraft) | Gold Box style engine and editor (copied docs in `docs/goldbox-engine/`) | see repo | Background | |

## Method and tooling

| Project | What it is | Licence | Use |
|---|---|---|---|
| [abedegno/Exhume](https://github.com/abedegno/Exhume) | Toolkit and agent skills for byte-matching DOS decompilation; headless DOS runner, Unicorn routine fuzzing, record/replay port verification | MIT | Reuse with attribution; closest model for our oracle, fuzzing and session design |
| [abedegno/underworld-exhumed](https://github.com/abedegno/underworld-exhumed) (UW1/UW2 Decomp, docs in `docs/dos-decomp-projects/`) | Byte-matching decompilations of two DOS games plus native ports verified by replay | see repo | Method reference |
| [Wyrelade/KKND-Decomp](https://github.com/Wyrelade/KKND-Decomp) | Watcom matching decomp, agent learnings log | see repo | Method reference (`DECOMPILATION_LEARNINGS.md`) |
| [maci0/rebrew](https://github.com/maci0/rebrew) | Compiler-in-the-loop workbench; status model including `PROVEN` (semantic equivalence) | see repo | Principles (`docs/decomp-tools/rebrew/PRINCIPLES.md`, `MATCH_TYPES.md`) |
| [bethington/ghidra-mcp](https://github.com/bethington/ghidra-mcp) | Ghidra MCP server (v6.0.0, Ghidra 12.1.3) | see repo | Optional interactive access |
| [unicorn-engine/unicorn](https://github.com/unicorn-engine/unicorn) | CPU emulator (2.1.4) | GPL-2.0 (library) | Tool dependency (not linked into the game) |
| [NationalSecurityAgency/ghidra](https://github.com/NationalSecurityAgency/ghidra) | Ghidra 12.1.4 | Apache-2.0 | Tool |
| Borland Turbo Pascal 6.0 (June 1991), plus 6.0 (Oct 1990) and 7.0 for comparison | The compiler and runtime that built POOL (pinned 2026-10-09, `docs/setup/SETUP-tp.md`) | Proprietary (Borland, now Embarcadero); not freeware (only TP 1.0, 3.02 and 5.5 were released free); archive.org hosting is not a licence | Local reference tool under `build/toolchain/` only; never committed or pushed; runtime code never copied into `src/` |
| [dmsc/emu2](https://github.com/dmsc/emu2) | Headless DOS emulator that runs `TPC.EXE` (commit `9d8698d`) | GPL-2.0 | Tool, built into `tools/vendor/` (ignored by git); no code copied |

## Background reading

- Alex Bevilacqua, "Reverse Engineering a DOS Game with Ghidra and Codex" (2026): `docs/articles/`.
- Simeon Pilgrim, blog posts on Curse of the Azure Bonds and SSI game tools: https://simeonpilgrim.com/blog/curse-of-the-azure-bonds
- The Digital Antiquarian, "Opening the Gold Box" series: https://www.filfre.net/2017/03/opening-the-gold-box-part-5-all-that-glitters-is-not-gold/
- Turbo Pascal 6.0 Programmer's Guide and Library Reference (bitsavers, archive.org): the documentation for the compiler that built POOL. The 7.0 Programmer's Reference and Language Guide (bitsavers) are still useful for the runtime, overlay manager and calling conventions, but check any 7.0-only feature (`const` parameters, `$Q`, `Test8086`) against 6.0.

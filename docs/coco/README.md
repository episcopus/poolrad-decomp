# docs/coco: Phase 8 baseline (the CoCo 3 port)

Research and design baseline for porting Pool of Radiance to the Tandy Color Computer 3, written 2026-10-17 before any Phase 8 code. Load these files as context for Phase 8 work.

## Reading order

1. `PORTING-GUIDE.md`: the synthesis. Target machine, architecture, memory maps, module-by-module plan, CMOC rules, verification, the plan of work (8.0 to 8.9), the decisions waiting for the human (D1 to D10) and the consolidated open questions. Start here.
2. The research file for the module you are working on (`PORTING-GUIDE.md` section 11 maps topics to files).
3. `probes/`: small programs that settle compiler behaviour (CMOC's byte arithmetic so far).

## Contents

| Path | What it is |
|---|---|
| `PORTING-GUIDE.md` | Synthesis and proposals |
| `research/00-brief.md` | The brief every research file was written to (objective, game profile, rules) |
| `research/01-cpu-6809-6309.md` | 6809 and 6309: programming model, cycle tables, interrupts, optimisation idioms, inner-loop cookbook |
| `research/02-gime-video-memory-io-sound.md` | GIME registers, graphics modes, palette and EGA mapping, MMU, timer, PIAs and keyboard, DAC, GMC and other sound carts |
| `research/03-storage-os-runtime.md` | RS-DOS and DSKCON, CoCo SDC, DriveWire, OS-9 vs bare metal, large-program loaders, data packaging and load times |
| `research/04-cmoc-lwtools-toolchain.md` | CMOC language and code generation, LWASM and lwlink, banking with CMOC (Space Bandits method), alternatives, coding rules |
| `research/05-masters-hewlett-sockmaster.md` | Glen Hewlett, Sock Master, DynoSprite, Space Bandits, Nick Marentes and others: techniques and porting lessons |
| `research/06-prior-art-games.md` | Showcase CoCo 3 games, CoCo RPGs and 3D mazes, the C64 and Apple II Gold Box ports, capability envelope |
| `research/07-archive-reading-list.md` | 40 ranked documents from the Color Computer Archive with URLs and page pointers |
| `research/08-emulators-testing-workflow.md` | XRoar, MAME (Lua automation), golden tests, profiling, deployment |
| `research/09-factcheck-2026-10-17.md` | Independent fact check of `PORTING-GUIDE.md` (64 claims against the research files, 13 against primary sources); its corrections are applied, errata in guide section 13 |
| `probes/` | CMOC behaviour probes with recorded results |

## Conventions

- Tags as in the whitepaper: **[V]** verified on our bytes or by running a tool, **[S]** stated by a cited source, **[E]** estimate, **[?]** open. Research files mark unconfirmed points `[unverified]`.
- Sources are cited inline as `(src: URL)`; each research file ends with its source list.
- The research files are a snapshot of what the sources said on 2026-10-17. When Phase 8 work proves or disproves a claim, record the result in `PORTING-GUIDE.md` (and in the whitepaper when it concerns the game), not by silently editing the research file.
- Proprietary material (ROM images, SSI data, scanned books) is never committed here; the reading list links to the archive instead.

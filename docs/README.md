# docs index

| Folder | What it holds |
|---|---|
| `spec/` | `SPEC.md`: the process specification (goals, approach, verification ladder, phases, ADRs) |
| `design/` | `WHITEPAPER.md`: everything learned about the game and its engine; `CHANGELOG.md` |
| `process/` | Playbooks for each agent role, the worker and orchestrator, safety rules, readability rules |
| `setup/` | Setting up the tools on macOS; pinning the Turbo Pascal 6.0 compiler |
| `reference/` | `prior-art.md`: other projects on the Gold Box games, their licences and how we use them |
| `maps/` | The player maps of every area as PDFs, one page each, plus the world map; `make maps` rebuilds them from your game files |
| `coco/` | The CoCo 3 port's baseline: porting guide, hardware and toolchain research, probes |

The working repository also keeps a reference library gathered from elsewhere (other decompilation projects' docs, articles, books on x86 and DOS). It is not republished here; these are the sources it came from:

- Ultima Underworld I and II, byte-matching with Borland Turbo C++: https://github.com/abedegno/UW1Decomp, https://github.com/abedegno/UW2Decomp
- Krush Kill 'n Destroy, byte-identical with Watcom C: https://github.com/Wyrelade/KKND-Decomp
- dis86, 8086 disassembly and decompilation tooling: https://github.com/xorvoid/dis86
- SDLPoP, the Prince of Persia port: https://github.com/NagyD/SDLPoP
- The Ocarina of Time decompilation tutorial: https://github.com/zeldaret/oot
- asm-differ and decomp-permuter: https://github.com/simonlindholm/asm-differ, https://github.com/simonlindholm/decomp-permuter
- decomp-toolkit and objdiff: https://github.com/encounter/decomp-toolkit, https://github.com/encounter/objdiff
- rebrew, a compiler-in-the-loop workbench: https://github.com/maci0/rebrew
- DungeonCraft, an open Gold Box style engine: https://github.com/GaidamakUA/DungeonCraft
- Reverse engineering a DOS game with Ghidra and Codex: https://alexbevi.com/blog/2026/03/14/reverse-engineering-a-dos-game-with-ghidra-and-codex/
- MS-DOS reverse engineering notes: https://blog.klefz.com/notes/ms-dos-reverse-engineering/
- The ScummVM reverse engineering HOWTO: https://wiki.scummvm.org/index.php/HOWTO-Reverse_Engineering

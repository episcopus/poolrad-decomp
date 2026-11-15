# poolrad-decomp

A matching decompilation of SSI's Pool of Radiance for DOS, version 1.3 (the version its credits screen shows at boot), into Turbo Pascal 6.0, done largely by AI agents: every routine is Pascal that the original compiler turns back into the original's machine code, byte for byte, and `make match` proves it. From that source the project rebuilds the whole program identically (`make rebuild`), translates it to portable C with an SDL host, and ports it to the Tandy Color Computer 3.

This repository is the public companion to a series of videos and articles about the project. It holds the source, the tools, the process the agents follow and what was learned about the game. It does not hold the game.

Learn more at [anonymousformula.com/poolrad](https://anonymousformula.com/poolrad/), where the articles and the story of the project are published.

| Start here | |
|---|---|
| `docs/design/WHITEPAPER.md` | How the game works: engine, data formats, scripts, combat, the quirks of the original |
| `docs/spec/SPEC.md` | The process specification: goals, approach, verification ladder, phases |
| `AGENTS.md` | The operating manual the AI agents work from (Claude Code, Cursor, OpenCode) |
| `src/` | The decompiled program, one Turbo Pascal unit per original unit |
| `c/` | The C translation and its SDL host |
| `ports/coco3/`, `ports/dos/` | The CoCo 3 port (what changed in each version: `ports/coco3/CHANGELOG.md`); the DOS build with fixes and speed patches |
| `work/status.md` | Where the project stands |
| `make maps` | Player maps of every area, built from your game files (`tools/maps/`) |

## What you need to supply

Nothing copyrighted by others is in this repository. To build or verify anything you need:

1. Your own copy of Pool of Radiance for DOS, version 1.3. Put its files in `poolrad/` (see `poolrad/README.md`). `make inputs` checks them against the hashes in `re/inputs.toml`: the project targets this one release (built with Turbo Pascal 6.0, 35 overlays in `GAME.OVR`), and other releases will not match.
2. Turbo Pascal 6.0, June 1991 release, for matching and rebuilding. It is proprietary (Borland, now Embarcadero) and never part of this repository. `docs/setup/SETUP-tp.md` says how the project pins it by hash and where to put it.

Then, on macOS:

```sh
sh tools/setup/setup-macos.sh
. tools/setup/env.local.sh
make doctor inputs overlays dax
make tp-pin            # once the compiler archives are in build/toolchain/dist/
make check             # tests, every unit's match, golden check
```

The C translation builds without the compiler (`cmake -S . -B build/cmake && cmake --build build/cmake`) but needs the game files to run.

## Legal

This is an independent, non-commercial research and preservation project. It is not affiliated with or endorsed by Strategic Simulations, Inc., Wizards of the Coast, Hasbro, Ubisoft or Embarcadero. Pool of Radiance, Advanced Dungeons & Dragons and Forgotten Realms are trademarks of their owners and are used here only to identify the game studied.

No game data, executables, artwork, or compiler files are distributed here, and no build of the game is published. See `LICENSE` for what the licence covers and what it does not.

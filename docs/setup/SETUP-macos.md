# Setup on macOS (Apple Silicon)

Everything the project needs, by phase. The commands are what `tools/setup/setup-macos.sh` runs, so you can either run the script or follow along by hand. Versions were checked on 2026-10-07.

## 0. Quick path

```sh
cd ~/dev/poolrad-decomp
sh tools/setup/setup-macos.sh --dry-run          # see what it will do
sh tools/setup/setup-macos.sh --with-ghidra      # phases 0 to 3 plus Ghidra
. tools/setup/env.local.sh                       # JAVA_HOME, GHIDRA_INSTALL_DIR
make doctor && make inputs && make overlays && make dax && make smoke
```

`make doctor` prints `ok`, `missing` (required now) or `skip` (optional or later phase) for each tool.

## 1. What gets installed and why

| Tool | Version | Install | Used for | Phase |
|---|---|---|---|---|
| Xcode command line tools | current | `xcode-select --install` | clang, git, make | all |
| Homebrew | current | https://brew.sh | package manager | all |
| uv | current | `brew install uv` | Python 3.12 and the tool environment (`uv sync`, locked in `uv.lock`) | P0 |
| Python packages | see `pyproject.toml` | `uv sync --python 3.12` | unicorn 2.1.4 (oracle), capstone (disassembly), pyghidra (headless Ghidra), pillow, pytest | P0 to P3 |
| OpenJDK 21 | 21 | `brew install openjdk@21` | Ghidra 12 requires Java 21 or later | P1 |
| Ghidra | 12.1.4 | `setup-macos.sh --with-ghidra` (downloads the official zip into `~/opt`) | analysis database, headless scripts via PyGhidra | P1 |
| DOSBox-X | 2026.10.01 | `brew install dosbox-x` | cross-checking the oracle against a real DOS emulator, running the original by hand | P2 |
| emu2 | commit `9d8698d` | `make emu2` (clones and builds into `tools/vendor/emu2`) | headless DOS emulator that runs the Turbo Pascal compiler | P1 |
| Turbo Pascal 6.0 (June 1991) | `TPC.EXE` sha256 `03836c60...` | archives into `build/toolchain/dist/`, then `make tp-pin` (`docs/setup/SETUP-tp.md`); proprietary, never committed | reference compiler: version pin, runtime naming, codegen questions (`make tpc`) | P1 |
| CMake, Ninja, pkgconf | current | `brew install cmake ninja pkgconf` | native C build | P3 |
| SDL3 | current | `brew install sdl3` | host platform layer (window, input, audio) | P3 |

Optional:

| Tool | Install | Used for | Phase |
|---|---|---|---|
| Ghidra MCP server (bethington/ghidra-mcp 6.0.0, built against Ghidra 12.1.3) | see its INSTALLATION.md | interactive exploration from an agent; not required, all tools are CLI | P1+ |
| IDA (your own licence) | | your earlier databases in `poolrad/` (`START.*`, `start-unpack.idb`) can seed names | P1 |
| OrbStack or Docker Desktop | https://orbstack.dev | running Open Watcom v2 (Linux x64 build) for the 16-bit DOS build; Open Watcom ships no macOS host | P8 |
| LWTOOLS, XRoar | `brew install lwtools xroar` (or `setup-macos.sh --with-coco`) | 6809 assembler/linker and a CoCo 3 emulator | P7 |
| CMOC | build from source (sarrazip.com/dev/cmoc.html) | C compiler for the 6809 / CoCo | P7 |
| MAME | see mamedev.org | second CoCo 3 emulator | P7 |

## 2. Ghidra details

- Ghidra 12.1.4 needs JDK 21+ and supports Python 3.9 to 3.14 for PyGhidra (from its `application.properties`).
- `tools/setup/env.local.sh` exports `JAVA_HOME` (Homebrew's openjdk@21) and `GHIDRA_INSTALL_DIR`; PyGhidra uses the latter. Add `. ~/dev/poolrad-decomp/tools/setup/env.local.sh` to your shell profile if you like.
- The Ghidra project is generated (`make ghidra`, phase 1) under `build/`; do not commit it. Names and types live in `re/`.
- If you want the GUI: `$GHIDRA_INSTALL_DIR/ghidraRun`, then open the generated project.

## 3. AI harnesses

Nothing harness specific needs installing for the project to work: every instruction is in `AGENTS.md`, every procedure in `docs/process/playbooks/`.

| Harness | Reads | Playbook commands |
|---|---|---|
| Claude Code | `CLAUDE.md` (imports `AGENTS.md`) | `/pr-lift`, `/pr-map`, ... from `.claude/commands/` |
| OpenCode | `AGENTS.md` | `/pr-lift`, ... from `.opencode/commands/` |
| Cursor | `AGENTS.md`, `.cursor/rules/poolrad.mdc` | `/pr-lift`, ... from `.cursor/commands/` |

For parallel agents use git worktrees (`git worktree add ../poolrad-<unit> -b unit/<unit>`), one agent per worktree (playbook 90).

## 4. Running the original game (for your own reference)

Never run it inside `poolrad/` (it writes saves and `POOL.CFG`, which would break `make inputs`). Copy the folder first:

```sh
mkdir -p build/play && cp -R poolrad/ build/play/poolrad
dosbox-x -c "mount c $(pwd)/build/play" -c "c:" -c "cd poolrad" -c "start"
```

The bundled `POOL.BAT` and `CFG.EXE` (a third-party launcher) write `POOL.CFG`: video `E`/`C`/`T`, sound `P`/`T`/`S`, game path, save path, and a third option `F`/`N`.

## 5. Linux

The same tools exist on Linux: `uv`, `openjdk-21-jdk`, `cmake`, `ninja-build`, `pkg-config`, SDL3 (from source or your distribution), `dosbox-x` (Flatpak or source), Ghidra zip as above. Open Watcom v2 has native Linux x64 builds. `make doctor` works on both.

## 6. Verified in this environment

On 2026-10-07 the tool environment (`uv sync` with this `pyproject.toml`) resolved and imported cleanly (unicorn 2.1.4, capstone 5.0.x, pyghidra 3.1.0), and `make overlays`, `make inputs`, `make dax` and `tools/oracle/smoke.py` ran on the pinned files. The Homebrew steps were not executed here; run `make doctor` after setup to confirm on your Mac.

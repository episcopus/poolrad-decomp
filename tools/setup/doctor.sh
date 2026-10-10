#!/usr/bin/env bash
# doctor.sh: report whether this machine can run each phase of the project.
# Prints one line per check: ok / missing / skip (optional), then a summary.
# Exit code 1 if any REQUIRED check for the current phases is missing.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
REQ_MISSING=0
line() { printf "%-8s %-28s %s\n" "$1" "$2" "$3"; }
req()  { if eval "$2" >/dev/null 2>&1; then line ok "$1" "$(eval "$3" 2>/dev/null | head -1)"; else line missing "$1" "$4"; REQ_MISSING=1; fi; }
opt()  { if eval "$2" >/dev/null 2>&1; then line ok "$1" "$(eval "$3" 2>/dev/null | head -1)"; else line skip "$1" "$4"; fi; }

echo "== host"
line info "system" "$(uname -sm)"
[ -f tools/setup/env.local.sh ] && . tools/setup/env.local.sh
PY=python3; [ -x .venv/bin/python ] && PY=.venv/bin/python

echo "== P0/P1: analysis"
req "git"            "command -v git"     "git --version"                       "install Xcode command line tools"
req "python >= 3.11" "$PY -c 'import sys; assert sys.version_info >= (3,11)'" "$PY --version" "run tools/setup/setup-macos.sh (uv python)"
req "uv"             "command -v uv"      "uv --version"                        "brew install uv"
req "python venv"    "test -x .venv/bin/python" "echo .venv"                    "uv sync (creates .venv)"
req "unicorn (py)"   "$PY -c 'import unicorn'" "$PY -c 'import unicorn; print(\"unicorn\", unicorn.__version__)'" "uv sync"
req "capstone (py)"  "$PY -c 'import capstone'" "$PY -c 'import capstone; print(\"capstone\", capstone.__version__)'" "uv sync"
req "java 21+"       "java -version 2>&1 | grep -E 'version \"(2[1-9]|[3-9][0-9])'" "java -version 2>&1" "brew install openjdk@21 and set JAVA_HOME"
req "ghidra"         "test -x \"\${GHIDRA_INSTALL_DIR:-/nonexistent}/support/analyzeHeadless\"" "echo \$GHIDRA_INSTALL_DIR" "setup-macos.sh --with-ghidra, then export GHIDRA_INSTALL_DIR"
req "pyghidra (py)"  "$PY -c 'import pyghidra'" "$PY -c 'import importlib.metadata as m; print(\"pyghidra\", m.version(\"pyghidra\"))'" "uv sync"

echo "== P2: oracle cross-check"
opt "dosbox-x"       "command -v dosbox-x" "dosbox-x --version 2>&1 | grep -i -m1 dosbox" "brew install dosbox-x (needed in P2 to cross-check the oracle)"
opt "pillow (py)"    "$PY -c 'import PIL'" "$PY -c 'import PIL; print(\"pillow\", PIL.__version__)'" "uv sync"

echo "== Turbo Pascal version pin (optional; docs/setup/SETUP-tp.md)"
opt "emu2"           "test -x tools/vendor/emu2/emu2 || command -v emu2" "echo emu2 \$(git -C tools/vendor/emu2 rev-parse --short HEAD 2>/dev/null)" "make emu2"
opt "unzip (Info-ZIP)" "command -v unzip" "unzip -v 2>&1 | head -1" "ships with macOS; needed for PKZIP implode"
opt "TP compilers"   "test -f build/toolchain/tp60-1991/BIN/TPC.EXE" "echo installed: \$(ls build/toolchain/*/BIN/TPC.EXE | wc -l | tr -d ' ')" "put archives in build/toolchain/dist/, then make tp-install"

echo "== P3+: C builds"
opt "cc (clang)"     "command -v cc"      "cc --version"                        "xcode-select --install"
opt "cmake"          "command -v cmake"   "cmake --version"                     "brew install cmake"
opt "ninja"          "command -v ninja"   "echo ninja \$(ninja --version)"      "brew install ninja"
opt "pkg-config"     "command -v pkg-config" "pkg-config --version"             "brew install pkgconf"
opt "SDL3"           "pkg-config --exists sdl3" "echo SDL3 \$(pkg-config --modversion sdl3)" "brew install sdl3"

echo "== P7/P8: other targets (optional)"
opt "docker"         "command -v docker"  "docker --version"                    "OrbStack or Docker Desktop, for the Open Watcom DOS build"
opt "lwasm (lwtools)" "command -v lwasm"  "lwasm --version 2>&1"                "brew install lwtools (CoCo 3, phase 7)"
opt "cmoc"           "command -v cmoc"    "cmoc --version 2>&1"                 "build from source (CoCo 3, phase 7)"
opt "xroar"          "command -v xroar"   "xroar -V 2>&1"                       "brew install xroar (CoCo 3, phase 7)"

echo "== agent tooling (optional)"
opt "claude"         "command -v claude"  "claude --version"                    "Claude Code CLI"
opt "opencode"       "command -v opencode" "opencode --version"                 "OpenCode CLI"
opt "cursor-agent"   "command -v cursor-agent" "cursor-agent --version"          "Cursor CLI"

echo "== inputs"
if $PY tools/setup/inputs.py --check >/tmp/poolrad-inputs.$$ 2>&1; then line ok "pinned inputs" "$(tail -1 /tmp/poolrad-inputs.$$)"; else line missing "pinned inputs" "$(tail -1 /tmp/poolrad-inputs.$$)"; REQ_MISSING=1; fi
rm -f /tmp/poolrad-inputs.$$

echo
if [ $REQ_MISSING -eq 0 ]; then echo "doctor: required checks pass"; else echo "doctor: required checks missing (see 'missing' lines)"; fi
exit $REQ_MISSING

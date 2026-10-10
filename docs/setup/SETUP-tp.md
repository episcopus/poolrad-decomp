# Turbo Pascal toolchain (version pin and RTL byte comparison)

The game was built with **Turbo Pascal 6.0, June 1991 release** (`TURBO.TPL` dated 1991-06-11). This page says how to get the candidate compilers, install them under `build/` and rerun the comparison that pins the version. Results and evidence: `docs/design/WHITEPAPER.md` section 2.2. Checked on 2026-10-09.

## 1. What is pinned

| Version id | Product | TPC.EXE (bytes, sha256) | TURBO.TPL (bytes, sha256) | Runtime copyright | Our System unit |
|---|---|---|---|---|---|
| `tp60-1991` | Turbo Pascal 6.0, files dated 1991-06-11 | 69,278 `03836c60d1a8e5ad4394462813bfd497d1d091913e533065c75fdf5cda97c563` | 45,344 `19040e3914d1b32209f88754ece12d6bc1eafc0c9e7873b73bdeee95483931ff` | `1983,91` | **match** |
| `tp60-1990` | Turbo Pascal 6.0, files dated 1990-10-23 (first release) | 69,214 `2feaeb1bb125eccc44470755440098500fae8239fc74291da71b233f9445473d` | 45,344 `65079b04179d219cc7ef02ba6c4c344f43c8ab3e741b61eb1e992f4dc3156b33` | `1983,90` | differs |
| `tp70` | Turbo Pascal 7.0, files dated 1992-10-30 | 75,400 `970fa7aca0b85e773a9cabaca521b3790170297e797117d1312c00a30f2dd3e8` | 48,432 `656ba42e0220e911277089e1f239d89f84abb8a06bdcf94a8a2c55340b53678d` | `1983,92` | differs |

Both 6.0 releases print the same banner (`Turbo Pascal Version 6.0 Copyright (c) 1983,90 Borland International`); only the file dates, sizes and the runtime copyright tell them apart. When someone says "TP 6.0" ask which one.

## 2. Getting the archives

Licence: Turbo Pascal 6.0 and 7.0 are proprietary (Borland, now Embarcadero). Unlike TP 1.0, 3.02 and 5.5 they were never released as freeware, and archive.org hosting is not a licence. The cleanest source is original Borland media you own; otherwise the archive.org items below are the ones whose hashes are pinned. Use them locally for comparison only. **Never commit them**: everything lives under `build/` (gitignored).

| Put this file | From | sha1 |
|---|---|---|
| `build/toolchain/dist/tp60/disk1_install_compiler.img` | archive.org item `turbo-pascal-60`, file `turbo pascal 6.0 install & compiler.img` (360 KB FAT12) | `6321a93c3442f05a4160aadcd417720016d098f8` |
| `build/toolchain/dist/tp60src/TP6SrcInst.zip` | archive.org item `TP6SrcInst` (the only file in it, 1,641,257 bytes) | `4432ede41be7be0f36aa5cf340406fa967d4779e` |
| `build/toolchain/dist/tp70/TP70.zip` | archive.org item `turbopascal7.0`, file `TP70.zip` | `0025e6bfa804fa4f3cfa88d83997d0050f5edc4a` |

`tools/re/tp_toolchain.toml` holds the full list (the other three TP 6.0 floppies are optional), direct URLs, md5s and the hash of every intermediate file. The sha1/md5 values equal archive.org's published metadata. Only disk 1 is needed for the pinned compiler. `TP6SrcInst.zip` is only used for its Borland `TURBO.ZIP`; its `Source/` tree is third-party material of unclear provenance and the extractor never reads it. If you own the media, image the install disk and drop it in the same place; the hashes tell you whether it is the same release.

The project sandbox cannot reach archive.org, so download in a browser and copy the files into `build/toolchain/dist/`.

## 3. Install and compare (one command)

```sh
make emu2        # once: builds tools/vendor/emu2 (headless DOS emulator, pinned commit)
make tp-pin      # tp-install + tp-probe + tp-compare
```

- `tp-install` checks every archive hash, extracts `TPC.EXE` and `TURBO.TPL` (FAT12 reader in Python, PKZIP implode via the system `unzip`) and checks their hashes. Output: `build/toolchain/<version>/BIN/`.
- `tp-probe` compiles `tools/re/tp_probe/SINK.PAS` (plus the overlaid unit `OVU.PAS`) with `TPC /B /GS /GP` for every installed version. Output: `build/toolchain/probe/<version>/SINK.EXE`, `.MAP`, `.OVR`. The probe pulls in a superset of the runtime routines POOL uses; if the comparison ever reports `ours-only` bytes, extend the probe.
- `tp-compare` aligns our System, Crt, Dos and Overlay code with each probe build and classifies every byte (see the docstring of `tools/re/tp_toolchain.py`). It writes `build/toolchain/compare.md` and `compare.json` and exits 0 when exactly one candidate matches the System unit. Tests: `tests/unit/test_tp_toolchain.py` (the pinned build matches; a single flipped byte in System is rejected).

Expected result:

```
tp60-1991  SYSTEM MATCH (unexpl 0, ours-only 0); CRT MATCH (...); DOS MATCH (...); OVERLAY MATCH (...)
tp60-1990  SYSTEM differs (unexpl 6, ours-only 6); CRT differs (unexpl 11, ours-only 4); DOS MATCH; OVERLAY MATCH
tp70       SYSTEM differs (unexpl 900, ours-only 1227); CRT differs (unexpl 69, ours-only 20); DOS differs; OVERLAY MATCH
System unit matches: tp60-1991
```

Addresses in the report are load-image paragraphs (System is `0AF8`); add `1000h` for Ghidra and `make smoke`.

## 4. Emulator options on Apple Silicon (ranked)

1. **emu2** (default for `tp-probe`). Headless, runs `TPC.EXE` directly from the shell, deterministic output, builds in seconds with clang. Verified on Linux arm64 with all three compilers; its source has macOS support but the macOS build was not exercised in this session **[?]**. Run `make emu2` and then `make tp-probe`.
2. **DOSBox-X** (already in the project for P2). `python3 tools/re/tp_toolchain.py probe --emu dosbox-x` runs the same command in a headless batch (`-silent -nogui -exit -c ...`) **[?] not exercised in this session**. By hand:
   ```sh
   dosbox-x -c "mount c $(pwd)/build/toolchain/probe/tp60-1991" -c "c:" -c "TPC.EXE /B /GS /GP SINK.PAS"
   ```
   (copy `TPC.EXE`, `TURBO.TPL`, `SINK.PAS`, `OVU.PAS` into that folder first; `tp-probe` does this.)
3. **FreeDOS VM** (UTM/QEMU). Works but is heavy and needs disk-image shuffling; only if both of the above fail.
4. **Wine**: not applicable. TP 6.0 and 7.0 are DOS programs; Wine does not run DOS executables. (Turbo Pascal for Windows is a different product.)

`TPC.EXE` looks for `TURBO.TPL` next to itself only when DOS gives it a full program path; under emu2 keep both files in the working directory (the tool does).

## 5. Compiling your own Pascal (`make tpc`)

```sh
make tpc SRC=tools/re/tp_idioms/STRIDIOM.PAS DISASM=1      # pinned TP 6.0
make tpc SRC=/tmp/x/GUESS.PAS VER=tp70                      # another installed version
make tpc SRC=GUESS.PAS OPTS='/$$R+'                         # extra TPC switches (or put {$R+} in the source)
```

The source must be an 8.3 `.PAS` name; `.PAS`, `.INC` and `.OBJ` files next to it are copied too, so units and includes resolve. Output goes to `build/tpc/<version>/<NAME>/` (`.EXE` plus a detailed `.MAP` with line numbers). With `DISASM=1` the program's own code is listed by source line, and every far call into the runtime is labelled with the POOL routine it corresponds to, for example:

```
0000:003B  9a4d050b00     lcall 0xb, 0x54d  ; System_StrConcat (POOL 0AF8:0B98)
```

Uses: naming runtime routines (call one RTL function per line and read the labels), seeing how TP 6.0 compiles an idiom before lifting or reviewing a routine (playbooks 30 and 70), and track M (SPEC 4.3). Compile with POOL's switches, `{$F+,S-,R-,G-}`, and remember TP 6.0 has no `const` parameters.

## 6. Directive probe (how the game's compiler switches were read)

Compile a small program twice with one switch flipped and look at what changes, then count that pattern in POOL. TP 6.0 (1991) patterns, measured with `TPC /GS` on `{$S+}`/`{$S-}` etc.:

| Switch | Code it generates (TP 6.0) | Our routine | How to count in POOL |
|---|---|---|---|
| `$S+` stack check | `push bp; mov bp,sp; mov ax,<locals>; call far System:StackCheck` | `0AF8:04DF` | prologues followed by that call |
| `$R+` range check | `mov di,<bounds in CS>; call far System:RangeCheck` before indexed stores | `0AF8:04B7` | far calls to it |
| `$I+` I/O check | `call far System:IOCheck` after each I/O call | `0AF8:04A9` | far calls to it |
| `$G+` 286 code | `push imm`, `leave` in procedures | none | instruction scan from each prologue |
| `$F+` far calls | `retf`/`retf n` epilogues instead of `ret`/`ret n` | none | epilogue scan |
| `$Q+` overflow | does not exist in TP 6.0 (`Error 17: Invalid compiler directive`) | none | not applicable |

Results are in WHITEPAPER section 2.2.

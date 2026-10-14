# How Pool of Radiance Works

*A living design document for SSI's Pool of Radiance (DOS), written from the decompilation.*

| | |
|---|---|
| Status | Seeded 2026-10-07 (Phase 0). Since 2026-10-11 the decompilation is Turbo Pascal matched by the original compiler (SPEC ADR-002); a matched routine is [V] evidence of what the code does. Most game systems are still open questions. |
| Covers | The build pinned in `re/inputs.toml` (see section 2) |
| Process | Updated by playbook 60 as each unit, format or tool lands; every change logged in `CHANGELOG.md` |

## How to read this document

Every claim carries a tag:

| Tag | Meaning |
|---|---|
| **[V]** | Verified on our build, with the evidence named (address, tool, test) |
| **[I]** | Strong inference, with the reasoning |
| **[H]** | Hypothesis or lead from prior art (cited), not yet proven on our bytes |
| **[?]** | Open question |

Addresses: `SSSS:OOOO` is a segment and offset in the *load image* before relocation (segment 0 is the first paragraph after the EXE header); `ovlNN:OOOO` is an offset inside overlay unit NN's code.

---

## 1. The game in one page

Pool of Radiance (SSI, 1988) is the first of the "Gold Box" AD&D games. The player creates a party of up to six characters, explores the ruined city of Phlan and its surroundings in a first-person 3D view, fights in a separate top-down tactical combat screen, and advances through scripted encounters, shops, temples, training halls and the main quest. Much of the content (encounters, dialogue, events) is data: scripts in the ECL files interpreted by the engine **[H]** (OpenGoldBox `docs/SCRIPTS.md`, coab `engine/ovr003.cs`).

This document grows a chapter per subsystem as the decompilation proves how each one works.

---

## 2. The build we study

### 2.1 Files **[V]** (`re/inputs.toml`, `make inputs`)

| File | Bytes | Role |
|---|---:|---|
| `START.EXE` | 65,231 | Main program, EXEPACK compressed **[V]** ("Packed file is corrupt" stub) |
| `start-unpack.exe` | 71,152 | The same program unpacked **[V]** (`make unexepack` reproduces it byte for byte from `START.EXE`) |
| `GAME.OVR` | 206,105 | Overlay code for 35 units **[V]** |
| `*.DAX` (113 files) | | Game data archives **[V]** (section 4.1) |
| `ITEMS` | 2,050 | Item type table (section 4.3) **[V]** |
| `SAVE/` | | A saved game: `SAVGAMA.DAT` plus per-character `CHRDAT<slot><n>.SAV/.ITM/.SPC` (section 4.4) |
| `POOL.BAT`, `CFG.EXE`, `CFG.C` | | Third-party launcher ("Gold Box Starter by Japo @ Abandonia.com", per `CFG.C`), not part of the original game |

### 2.2 Toolchain and version

- **Turbo Pascal** **[V]**: the unpacked image contains the runtime's error text ("Runtime error ", " at ", "." CR LF) immediately followed by "Portions Copyright (c) 1983,91 Borland"; the entry point is a chain of unit initialisation calls (section 3.2).
- **Pinned: Turbo Pascal 6.0, June 1991 release** **[V]** (`make tp-pin`, report `build/toolchain/compare.md`, setup and hashes in `docs/setup/SETUP-tp.md`). `TPC.EXE` 69,278 bytes (sha256 `03836c60d1a8e5ad4394462813bfd497d1d091913e533065c75fdf5cda97c563`), `TURBO.TPL` 45,344 bytes (sha256 `19040e3914d1b32209f88754ece12d6bc1eafc0c9e7873b73bdeee95483931ff`), files dated 1991-06-11. Its banner still reads "Version 6.0 ... 1983,90"; there is no separate version number for this release.
  - A probe program compiled with this compiler links System, Crt, Dos and Overlay code that is identical to ours except for link-time fields. `tools/re/tp_toolchain.py compare` classifies every byte of our units:

    | Unit (our range) | Bytes | Identical | Link-time fields (fixups, re-linked branches/offsets, moved DGROUP operands, padding) | Unexplained | Missing from reference |
    |---|---:|---:|---:|---:|---:|
    | System `0AF8:0000..0C7C:0000` | 6,208 | 5,935 | 273 | 0 | 0 |
    | Crt `0A40:0000..0AA2:0000` | 1,568 | 1,402 | 166 | 0 | 0 |
    | Dos `0A32:0000..0A40:0000` | 224 | 221 | 3 | 0 | 0 |
    | Overlay `0AA2:0000..0AF8:0000` | 1,376 | 1,239 | 137 | 0 | 0 |

    Every moved DGROUP operand differs by one of two constants per unit (typed-constant area, variable area), as expected when the game's own data shifts the runtime's. A one-byte change anywhere in System is rejected (`tests/unit/test_tp_toolchain.py`).
  - The string "Portions Copyright (c) 1983,91 Borland" is in this `TURBO.TPL` and in neither other candidate **[V]**.
- **Eliminated** **[V]** (same tool, same probe):
  - Turbo Pascal 6.0, first release (files dated 1990-10-23, runtime "1983,90"): System has 6 unexplained bytes (0AF8:0236 copyright year; 0AF8:030B, 0327, 03CA, 03CC in heap-manager code; 0AF8:0BDC) and 6 bytes it lacks (0AF8:0383, 4 bytes; 0AF8:04E2, 2 bytes); Crt has 11 unexplained and 4 missing. Dos and Overlay match.
  - Turbo Pascal 7.0 (files dated 1992-10-30, runtime "1983,92"): System 900 unexplained and 1,227 missing bytes, Crt 69 and 20, Dos 5 and 103. Two visible causes: 7.0's System init runs a CPU probe (`pushf`/`popf` flag test for `Test8086`) that ours lacks, and 7.0 inserts `SelectorInc..Test8086` before `FileMode` in its typed constants, while ours has `FileMode` at DS:442C, the 6.0 position. Overlay matches (the routines POOL uses did not change in 7.0), so the Overlay unit alone cannot tell 6.0 from 7.0.
- **Overlay file** `FBOV` **[V]**. Both TP 6.0 and TP 7.0 write `FBOV` (probe `SINK.OVR`), so the signature does not separate them. The earlier 1988 build analysed by wicanr2 uses `TPOV` and TP 5.x **[H]** (their `docs/re/dos-toolchain-baseline.md`; no TP 5.x was compiled here).
- **Runtime unit placement** **[V]** (k-mer location plus byte match above; supersedes the runtime rows of section 3.2 where they differ): Dos `0A32..0A40`, Crt `0A40..0AA2`, Borland Overlay unit `0AA2..0AF8`, System `0AF8..0C7C`. `0A31:0000` is a separate 16-byte unit whose only code is an empty initialisation (`push bp; mov bp,sp; pop bp; retf`). `042B` (res08) is a game unit, not the overlay manager: it holds the `GAME.OVR` string and makes 4 far calls into the Overlay unit at `0AA2`. Borland's Dos and Overlay units have no initialisation part, so they never appear in the init chain **[I]**. `re/units.toml` carries them as `res13` (Dos) and `res14` (Overlay) with `init = ""`; `make map` (`tools/re/rtl_ident.py`) applies these names and returned the two routines misnamed under the old ranges (`042B:00A4`, now `res08_init`; `0A31:0000`, now `res02_init`) to provisional names.
- **System variables in DGROUP** **[V]** (operand pairs at aligned sites): OvrHeapSize `DS:43EE`, OvrHeapOrg `43F4`, OvrHeapPtr `43F6`, OvrHeapEnd `43F8`, OvrLoadList `43FA`, HeapOrg `4400`, HeapPtr `4404`, HeapEnd `4408`, FreeList `440C`, HeapError `4414`, ExitProc `4418`, ExitCode `441C`, ErrorAddr `441E`, PrefixSeg `4422`, StackLimit `4424`, InOutRes `4426`, RandSeed `4428`, FileMode `442C`, Input `8508`, Output `8608`, SaveInt00 `8708` (19 saved vectors follow).
- **Compiler directives** (TP 6.0 code patterns measured by compiling each switch both ways; method in `docs/setup/SETUP-tp.md` section 5; counts over all resident code below `0A32` and all 35 overlays):
  - `$S-` **[I]**: none of the 805 `push bp; mov bp,sp` prologues calls StackCheck (`0AF8:04DF`); no far call to it anywhere.
  - `$R-` **[I]**: no far call to RangeCheck (`0AF8:04B7`).
  - `$I+` in one resident unit only **[I]**: 12 far calls to the I/O check (`0AF8:04A9`), all inside `0802..0899` (res05, the unit with "Please insert overlay disk."); none in other resident units or in any overlay. **[V]** (`make match UNIT=res05`): the unit compiles with `$I+`, and `WaitForOverlayDisk`, `OpenGameFile` and `FileExists` sit in a `{$I-}` region (no check after their `WriteLn`, `Reset` and `Close`).
  - `$G-` **[I]**: no 80286-only instruction (`push imm`, `enter`, `leave`, `pusha`, `imul imm`, shift by immediate) in the 805 routines.
  - `$F+` **[I]**: all 622 `mov sp,bp; pop bp; ret` epilogues return far (`retf`/`retf n`: 528 in overlays, 94 resident); not one near return.
  - `$Q`: does not exist in TP 6.0 **[V]** (`Error 17: Invalid compiler directive`).
  - Language limits of TP 6.0 that matter when reading the code **[V]** (`make tpc`): no `const` parameters (`Error 2: Identifier expected`), so structured value parameters are copied into the callee's frame; functions cannot return records.
  - `$N-`/`$E` **[I]**: no 8087 emulator interrupts (INT 34h..3Dh) or `fwait`+ESC sequences beyond 4 stray byte matches; the game does no floating point.
  - `$A-` **[V]** (`make match UNIT=res06`): `ShowMessageLine` copies its `string[40]` value parameter to `[bp-29h]` and keeps a `Char` at `[bp-2Ah]`, a 2Ah-byte frame; with `$A+` the compiler rounds the 41-byte copy to 42 and the frame to 2Ch. Every matched unit compiles with `$A-` (res04, res06, ovl00), and the setting also governs the DGROUP layout the rebuild must reproduce (SPEC 7.3).
  - `$O+` in overlay units **[V]** (`make match UNIT=ovl00`): a string constant passed to a routine is first copied into a stack temporary (`0AF8:0B0B`) and the temporary is passed, since the overlay holding the constant may be moved; resident units pass the constant's code-segment address directly (res04). Exception **[V]** (`make match UNIT=res05`): res05 is resident but compiled with `$O+`: `WaitForOverlayDisk` copies `'game.ovr'` into a stack temporary before calling `FileExists` (`0802:0218`, a 12-byte frame; without `$O+` the frame is 2 bytes and the literal is passed directly).
  - `$B`, `$V`, `$X` **[?]**: no evidence yet. `$B` will show in the jump shape of `and`/`or` Boolean expressions of the first unit that has one.

### 2.3 Configuration (`POOL.CFG`)

Five text lines **[V]** (writer: `CFG.C`; the game opens "POOL.CFG" and prints "Unable to find POOL.CFG" when missing, strings in the unpacked image):

1. video mode: `E` EGA, `C` CGA, `T` Tandy
2. sound: `P` PC speaker, `T` Tandy, `S` silent
3. game directory with trailing backslash
4. save directory with trailing backslash
5. `F` or `N` **[?]** (meaning unknown)

How the game starts **[V]** (the initialisation part of res08, `042B:00A4`, `src/RES08.PAS`):
it initialises res05, then the overlay manager on `GAME.OVR`; probes `pool.cfg` (untyped,
128-byte records) retrying with `Please insert startup disk.` plus a keypress until it opens,
then closes it and sets `DS:84F0` to 0; opens `POOL.CFG` as text (halting with `Unable to find
POOL.CFG` when missing) and reads the five lines: line 1 selects the video hardware
(`E`: `VideoAdapter` 1 and EGA mode `$0D`; `T`: 2 with the heap cut by `$400` paragraphs;
anything else: 0), line 2 the sound (`T`: `SoundMode` 0, `P`: 1, anything else: 2), lines 3
and 4 the game and save directories (each followed by a self-assigning `S := S` QUIRK),
line 5 the `F` flag (`DS:49D1` 1 for `F`, else 0). It saves the video mode (`INT 10h AH=$0F`
into `SavedVideoMode` and `DS:4A1D`), gives the overlay buffer `$18800` bytes (halting with
how many more bytes are needed when short), halts on a nonzero overlay status (`DS:43DC`,
`Overlay error, program abort!`) and starts the sound unit (`SilenceSound`).

---

## 3. Program architecture

### 3.1 The executable **[V]** (unpacked MZ header; `tools/re/tpovl.py`, `tools/re/unexepack.py`)

| Field | Value |
|---|---|
| Relocations | 561 |
| Load image | 68,592 bytes (paragraphs 0000 to 10BE) |
| Entry CS:IP | 0000:0006 |
| Initial SS:SP | 14F2:4000 (16 KB stack) |
| Data segment (DGROUP) | paragraph 0C7C **[I]** (the System unit's init executes `mov dx,0C7Ch; mov ds,dx` before relocation) |
| Initialised data | 0C7C to 10BE (about 17 KB); uninitialised data follows up to the stack segment |

#### 3.1.1 EXEPACK packing **[V]** (`tools/re/unexepack.py`, `make unexepack`)

`START.EXE` is Microsoft EXEPACK with an 18-byte header (`skip_len` present, signature `RB` at CS:0, stub at CS:IP = 0F72:0012). Fields that become the unpacked MZ values:

| EXEPACK field | Value |
|---|---|
| `real_ip` / `real_cs` | 0006 / 0000 |
| `real_sp` / `real_ss` | 4000 / 14F2 |
| `dest_len` | 10BF paragraphs (68,592 bytes) |
| `skip_len` | 1 |
| `exepack_size` | 05AF (header + stub + packed relocs) |

Compressed load image is 63,264 bytes; RLE commands are `0xB0` (fill) and `0xB2` (copy), decoded backwards after skipping trailing `0xFF` padding. The packed relocation table uses 16 segment buckets (`segment = i * 0x1000`). Reconstructing the MZ EXE pads the header to a multiple of 512 bytes (here 160 paragraphs) and sets `min_alloc` so load-image paragraphs plus `min_alloc` stay constant; the result matches `poolrad/start-unpack.exe` (SHA-256 `8e60e2b00c0caec91cd47d06abb30f5269ffeec857a06cb67975f619b47c549e`).

### 3.2 Units and start-up **[V]** (`tools/re/tpovl.py`, manifest field `init_chain`)

The entry point is 48 consecutive far calls, one per unit initialisation, in Turbo Pascal's unit order. 35 of them call offset `0020` of an overlay stub segment (entry 0 of an overlay unit) and 13 call resident units. Two more resident units have no initialisation part and so no init call; they were found by byte comparison with Turbo Pascal 6.0 (section 2.2) and are listed last:

| Unit | Init call | Role |
|---|---|---|
| res00 | 0AF8:0000 | System (Turbo Pascal 6.0 runtime, byte-matched) **[V]** |
| res01 | 0A40:0000 | Crt **[V]** (INT 10h probe in smoke); code `0A40..0AA2`, then the Borland Overlay unit `0AA2..0AF8` (2.2) |
| res02 | 0A31:0000 | 16-byte unit with an empty init **[V]**; Dos code follows at `0A32..0A40` (2.2) |
| res03 | 08AE:01D2 | [?] |
| res04 | 0899:013C | keyboard layer and QuitGame (5.8) **[V]** |
| res05 | 0802:0968 | hosts "Please insert overlay disk." string **[V]**; role otherwise [?] |
| res06 | 0709:0F82 | [?] (many far-call sites) |
| res07 | 0464:2A4A | [?] (large resident) |
| res08 | 042B:00A4 | game unit that sets up overlays **[V]**: strings `GAME.OVR`, `Overlay error...`, 4 far calls into the Borland Overlay unit at `0AA2` (2.2) |
| res09 | 03F1:0367 | [?] |
| res10 | 03ED:0000 | [?] |
| res11 | 03DA:0000 | [?] |
| res12 | 00BA:309E | [?] (largest resident code range before DGROUP) |
| res13 | none | Borland Dos unit, `0A32..0A40` **[V]** (2.2) |
| res14 | none | Borland Overlay unit, `0AA2..0AF8` **[V]** (2.2) |

Named overlay units from in-code strings (`make map` / `tools/re/name_units.py`) **[V]**; coab analogies tagged **[H]** in `re/units.toml` evidence only:

| Overlay | Name | Sample evidence |
|---|---|---|
| ovl03 | Encounter | `~COMBAT ~WAIT ~FLEE`, item file error |
| ovl04 | Temple | Heal / Pool / Appraise menus |
| ovl06 | Shop | Shopkeeper dialogue |
| ovl08/09 | CombatAI | Move/Attack strings |
| ovl13 | CombatSpells | Begins Casting |
| ovl15 | Camp | memorize / Cleric Spells (the camp menus, 5.22) |
| ovl16 | CharCreate | Character name / Training costs |
| ovl17 | SaveLoad | Put save disk in |
| ovl19 | Inventory | Ready Item / Trade with Whom |
| ovl22 | CastSpell | Choose Spell |
| ovl29 | GeoLoad | LoadWallSet / Load3DMap |
| ovl34 | TileLoad | Unable to load 8x8D |
| (others) | see `re/units.toml` | |

#### 3.2.1 System RTL entries used by game code **[V]** (`tools/re/rtl_ident.py`)

Hand-verified (Capstone) names applied to far-call targets; full list in `re/symbols.toml`:

| Address | Name | Evidence |
|---|---|---|
| 0AF8:0B0B | `System_StrCopy` | Pascal string copy; `retf` |
| 0AF8:0B25 | `System_StrLCopy` | copy with max length |
| 0AF8:0B98 | `System_StrConcat` | concatenate into dest |
| 0AF8:1685 | `System_Move` | overlapping-safe block move |
| 0AF8:16A8 | `System_FillChar` | `rep stosb` fill |
| 0AF8:13E2 | `System_Assign` | FileRec magic `D7B0` + path |
| 0AF8:1410 | `System_Reset` | INT 21h AH=3Dh |
| 0AF8:1491 | `System_Close` | INT 21h AH=3Eh |
| 0AF8:14FB | `System_BlockRead` | INT 21h AH=3Fh |
| 0AF8:04A2 | `System_IOResult` | swap `InOutRes` at DS:4426 |
| 0AF8:00E9 | `System_Halt` | exit / ExitProc teardown |
| 0AF8:16BC | `System_ParamStr` | `ParamStr(1)` compiles to a call here (`make match UNIT=res04`); it asks DOS for its version (INT 21h AH=30h) to find the program name, which is why it was first named `System_DosVersion` |
| 0AF8:0C10 | `System_StrCompare` | string `=` compiles to a call here, result in the flags (`make match UNIT=res04`) |
| 0AF8:0DC0 | `System_SetIn` | `x in [0, 1]` compiles to a call here with the set constant's address (`make match UNIT=res04`) |
| 0A40:02FD, 0A40:030F | `Crt_KeyPressed`, `Crt_ReadKey` | `KeyPressed`, `ReadKey` compile to calls here (`make match UNIT=res04`) |
| 0A32:000B | Dos `Intr` | `Intr($10, Regs)` compiles to a call here (`make match UNIT=res04`) |

Other externally called System/Crt/Overlay/Dos entries are named `*_rtl_XXXX` or INT-based until classified. Matching names them as a side effect: our compiled call reaches the POOL routine through `tp_toolchain.runtime_names`.

Start-up as observed by running the original code in the oracle (`make oracle-run`, appendix C) **[V]**:

1. The System unit saves 19 interrupt vectors (INT 21h AH=35h), installs INT 00h (`0AF8:00DF`), INT 23h (`0AF8:00E6`), INT 24h (`0AF8:00AE`) and a default INT 3Fh handler (`0AF8:00D7`), and queries the output handle with IOCTL (AH=44h).
2. The Crt unit probes the video BIOS (INT 10h AH=0Fh, 11h AL=30h, 08h) and installs INT 1Bh (`0A40:012D`).
3. The Borland Overlay unit replaces INT 3Fh with its manager (`0AA2:02E6`), opens `GAME.OVR` and reads its 8-byte header. The 35 overlay initialisations then run through that handler; each first call reads the unit's code (file offset from the stub, dword at +04h) and its fixup table with two INT 21h reads, so every unit is loaded from `GAME.OVR` by the program's own manager (the oracle implements no overlay logic).
4. `POOL.CFG` is opened and read. The sound unit (res03, init `08AE:01D2`) briefly hooks INT 08h and programs the timer to divisor `13B1h` (5041: 13 times the BIOS rate, 236.7 Hz, see 5.14) with `OUT 43h,B6h` followed by two `OUT 40h` bytes, restores INT 08h and divisor `FFFFh`, turns the speaker off (port 61h) and silences a Tandy SN76489 (`OUT C0h` with 9Fh, BFh, DFh, FFh).
5. `8X8D1.DAX`, `SQRPACI.DAX`, `COMSPR.DAX`, `ITEMS` and `TITLE.DAX` are loaded, the game switches to EGA mode 0Dh (320x200, 16 colours), shows "Loading... please wait", then the SSI logo, the Pool of Radiance title and the credits, polling the keyboard throughout. The code wheel prompt (5.12) follows.
6. The game installs no INT 08h/09h/1Ch handler for the rest of the session; keyboard input is INT 16h only (5.8).

#### 3.2.2 The start-up loader `StartGame` **[V]** (`make match UNIT=ovl11`, `src/OVL11.PAS`: unit complete)

The loader is overlay 11 (`ovl11:002D`, 1512 bytes) and is the first thing the main program runs. It owns the whole unit: `ovl11:0615` is its empty initialisation part, and no other routine exists (the map's `ovl11:0435` was a phantom: the far-call heuristic read the `lcall 0041:0025` at `ovl11:060C`, a call through ovl12's stub, as the linear address `0041*16+0025 = 0435` inside ovl11). `StartGame`:

- Allocates seven heap blocks with `New` (`ovl11:0034..00A3`): the game variables at `DS:49D2` (`^TGameVars`, `$800` bytes), a second `$800`-byte word block at `DS:49D6`, then `$400` (`DS:49DA`), `$1E00` (`DS:49DE`), `$588` (`DS:5E20`), `$924` (`DS:6A58`) and `$400` (`DS:6A5C`) byte blocks.
- Allocates three screen buffers through `AllocatePicture(Cols, Rows: Word; Planes, Flag: Byte; var Buf)` (`ovl11:00A4`, `00BC`, `00D4`): `(8, 1, 1, 0)` into `TileBuf`, `($A8, $15, 1, 0)` into `DrawBuf` and `($18, 3, 1, 0)` into `DS:4A24`. The callee allocates `Rows*Cols*2` (doubled when `VideoAdapter` is not 0) times `Planes`, plus `$17` bytes, and stores the pointer at `Buf` (`0464:248E`).
- Fills three 200-cell tables (`ovl11:0130..024D`): `DS:4EC0[I]` is the cell's scanline address (`$B800` for an even cell, `$BA00` for an odd one, plus `5*(I div 2)`), `DS:5050[I]` is `I*40` and `DS:51E0[I]` is the cell's graphics plane address (`10*(I div 4)` plus `$B800`, `$BA00`, `$BC00` or `$BE00`), so the tables drive the text and graphics planes of video adapter 2 (5.11). `DS:465C` is the loop counter of all three loops (a global).
- Sets the screen and game globals (`ovl11:0392..0456`), including `AreaViewKind := 1`, `MarkerFrame := 0`, the special view codes `DS:6F69 := $E8` and `DS:6F68 := $DB` (5.2.1) and `DebugMode := False`.
- Loads the data files (`ovl11:0469..0614`): it saves the current path `DS:547C` in `DS:4661`, draws "Loading...Please Wait" on row 24 (`DrawTextAt(0, 24, 10, ...)`), draws through `Load8x8Bank($CA, 4)` and `Load8x8Bank($CB, 0)`, loads pictures 1 and 2 of `SQRPACI` (`LoadPicture('sqrpaci', N, 0, 0, <bank pointer>)`, `ovl11:04BE`, into `DS:5E52` and `DS:5E56`) and pictures 13 to 24 of `COMSPR` (`LoadPictureSlot('COMSPR', I, I+13)`, `ovl11:0502`, then `LoadPictureSlot('COMSPR', $19, $19)`). It then builds the file path from the 30-byte name table `DS:2614[TileSet]` plus the character `DS:547D` plus `':'` and calls `OpenGameFile('ITEMS', Path, 0, F)` (a `Byte` function), which opens the untyped file `DS:468C`; `StartGame` seeks to record 2 (`Seek(F, 2)`) and reads one `$810`-byte block into `DS:5582` (`BlockRead`, count in `DS:5E1E`), closes it, restores the path, calls `Randomize` (`0AF8:1247`) and hands over to `ovl22_e10` and `ovl12_e1`.
- TP 6.0 idioms proven here (`make match UNIT=ovl11`, probe `tools/re/tp_idioms/PRB11..PRB16.PAS`): `New(P)` for an array type of `N` bytes emits `push N; lcall GetMem` and stores `DX:AX` in `P`; a `string` assignment always compiles to `System_StrLCopy` with the destination limit as the third argument; a `LongInt` (or pointer) `:= 0` (or `nil`) zeroes both words after one `xor ax,ax`, so `DS:6810`, `DS:5D92` and `DS:5D96` are 4-byte values; TP 6.0 rejects an anonymous `string[40]` in a parameter list (the type must be named, `String40`).

The main program **[V]** (`src/POOL.PAS`, `make match UNIT=main`: matched completely, 58 address fields) is segment `0000` (337 bytes plus padding): the string `'STING'`, then one far call per unit initialisation in the order of its `uses` clause (System, Crt, res02 to res08, then overlays and resident units interleaved: ovl34, res09, ovl33, res10, ovl32 to ovl30, res11, ovl29 to ovl25, res12, ovl24 to ovl00), then the main block:

```pascal
StartGame;
if ParamStr(1) <> 'STING' then begin ShowTitleScreen; CheckCodeWheel; end;   { title screens, code wheel (5.12) }
ovl16_e1;
SetWallDescriptors(11, 0, 7, 6);
ovl03_e1;
QuitGame;                                                    { quit (5.8) }
```

So the `STING` parameter also skips the title screens and the copy protection **[V]**. Of the 46 game units, 44 have an empty initialisation part (`begin end.`); only res08 (the overlay set-up) and ovl00 (the heap error handler) run code at start-up **[V]** (`tools/match/skeleton.py`, from the bytes at each init entry). res02, res10 and res11 contain nothing else: 16-byte units whose only code is that empty initialisation (`make match`, complete).

Turbo Pascal background **[H]** (Turbo Pascal reference manuals): units are compiled separately; each has an interface, an implementation and an optional initialisation part; overlaid units are called through stubs and loaded on demand by the Overlay unit's manager.

### 3.3 Overlays **[V]** (`tools/re/tpovl.py`, all checks pass)

`GAME.OVR` starts with `FBOV` and a 32-bit length equal to the file size minus 8. For each overlaid unit the load image holds a **stub segment** with this header:

| Offset | Size | Meaning |
|---|---|---|
| +00 | 2 | `CD 3F`: INT 3Fh, the overlay manager trap |
| +02 | 2 | return save area (0 on disk) |
| +04 | 4 | offset of the unit's code in `GAME.OVR` |
| +08 | 2 | code size |
| +0A | 2 | fixup table size (a list of 16-bit code offsets, stored right after the code) |
| +0C | 2 | number of entry points |
| +0E | 2 | link **[?]** (meaning not confirmed) |
| +10 to +1F | | runtime fields (zero on disk) |
| +20 | 5 each | entry stubs: `CD 3F`, 16-bit offset of the entry in the unit's code, `00` |

The 35 units tile `GAME.OVR` exactly (no gaps, no overlaps), with 406 entry points and 197,641 bytes of code in total. Entry 0 of each unit is its initialisation **[I]** (the init chain calls offset `0020` of every stub). Full table in appendix A.

Overlay error messages in the image **[V]**: "Overlay error, program abort!", "Please insert overlay disk.", "Not enough memory to run game.  You need ... more bytes."

### 3.4 Calling conventions **[V]** (samples below; matches Turbo Pascal far model)

Observed on this build (Capstone on `start-unpack.exe` / `ovl00.bin`):

| Site | Evidence |
|---|---|
| `ovl00` entry 0 @ code `00AC` | `push bp; mov bp,sp; ...; pop bp; retf` (0 params) |
| `Crt_init` `0A40:0000` | frame; far calls via `push cs`/`lcall`; ends `pop bp; retf` |
| `System` `0AF8:0254` | reads `[bp+6]` then `les cx,[bp+8]`; ends `retf 6` (callee pops 6 bytes) |
| `Overlay_init` `042B:00A4` | `sub sp,0Ah` locals; pushes `ds:di` / `cs:di` before `lcall` into System |
| `System_init` `0AF8:0000` | no BP frame; sets `ds=0C7Ch`, installs INT vectors (smoke) |

Rules for lifting:

- Interface routines are **far** (`retf` / `retf n`). Near `call`/`ret` appear for unit-private helpers.
- Frame: `push bp; mov bp,sp` then optional `sub sp,locals`.
- After the far return address, the first parameter is at `[bp+6]`; a far pointer follows as `[bp+8]:[bp+0A]` when pushed as `seg` then `off` (order as pushed).
- Callee removes parameters (`retf n` where `n` is total parameter bytes).
- String / VAR arguments are passed as far pointers (`push ds; push di` or `push ss; push di` patterns above).
- Nested-procedure static links and exact left-to-right push order for multi-arg calls: further samples **[I]** (still consistent with TP manuals).

### 3.5 Memory **[?]**

Heap usage, far pointer structures (characters, items) and how overlays share the overlay buffer are open questions for Phase 1.

C track (ADR-001, 2026-10-10, kept on branch `track-c-hybrid`) **[V]** on that branch: a C memory model (the 64 KB DGROUP image inside a 1 MB arena, `farptr` + `FP()`) held for `System_Move`, `System_FillChar` and `System_Random`, run inside the oracle and fuzzed against the original bytes. Facts it proved about the runtime, still true: `Move` chooses its direction by offsets only (`cmp si,di; jae` at `0AF8:1696`), `rep movsb` wraps each offset at 64 KB and keeps the segment (it smears when the offset order and the linear order disagree), the backward path leaves DF set on return (including a count of 0); `Random(0)` still steps the seed and returns 0 (5.13). Under ADR-002 these routines are the compiler's own and need no decompiling.

### 3.6 How Turbo Pascal 6.0 lays out a unit **[V]** (`make match`, tests/unit/test_match.py)

What the matching harness relies on, each proven by a complete match of res04 (resident) and ovl00 (overlay):

- A unit's routines are laid out in source order, each starting `push bp; mov bp,sp` (encoded `55 89 E5`; the map tool used to look for `55 8B EC` only and missed routines such as `res04:0122`, fixed 2026-10-11: `make map` found 38 more).
- The string and set constants a routine uses are placed in the code segment immediately before it (a set constant is 32 bytes); `re/symbols.toml` therefore counts them in the size of the routine before (for example `QuitGame`, 89 bytes, of which 51 are code and 38 the constants of `ReadGameKey`).
- Every routine is far (`$F+`); a call within the unit is `push cs; call near`.
- The initialisation part comes last; an empty one (`begin end.`) is `push bp; mov bp,sp; pop bp; retf`. A resident unit is padded with zeros to a paragraph.
- Globals are DS offsets fixed at link time; a routine of an overlay unit is addressed through its stub entry (`@HeapErrorHandler` is `0016:0025`, the stub segment and entry offset).
- Linking the whole program from source (`make rebuild`: `src/POOL.PAS` with `{$O OVLnn}` for the overlay units) reproduces the original's arrangement **[V]**: the main program at `0000`, the overlay stub segments from paragraph `16h` on (where the original's ovl00 stub is), the resident units after them in reverse initialisation order and System last, and an `FBOV` overlay file whose first unit's code starts with ovl00's string pool, like `GAME.OVR`. `tools/re/tpovl.py` reads the rebuilt pair and finds the original's 35 overlays and 48 initialisations (13 resident).
- A string value parameter is copied to a hidden stack temporary on entry (`System_StrLCopy`,
  `0AF8:0B25`, limit = the parameter's maximum), and the routine uses the temporary throughout
  (a `string[40]` value parameter costs a 42-byte frame: 41 bytes of string plus one of
  padding **[I]**) **[V]** (`DrawWindow`, `03F1:02E8`: the copy is the entry code, and `Length`
  and the `DrawTextAt` call read `[bp-$29]`; `make tpc` probes of every value form).
- A `case` on consecutive values compiles to one compare per label, `cmp; je body; jmp next`
  when the next dispatch is beyond a short jump and `cmp; jne next` when it is not (the jump
  form follows body size) **[V]** (`ClearWindow`, `03F1:0137`: `je` for labels 0 and 2, `jne`
  for 1; the same `je`-form opens the `case` of `ShowAreaView`, ovl26:018C).
- Indexing a two-dimensional absolute array generates the row-stride multiply inline
  (`mov ax,$50; mul Row; mov di,ax; add di,cx`) **[V]** (`ClearWindow` addresses its video
  planes, declared as `array[0..99, 0..79] of Byte absolute $B800:$0000`, as `Plane[Row, Col]`).
- Signed and unsigned multiply differently: `80 * IntegerRow + ShortIntExpr` adds in 16 bits,
  while the same expression with a `Word` row promotes the addition to 32 bits (`cdq`/`adc`),
  so a `Word` loop variable needs `Integer(...)` casts in products; and a `ShortInt` `for`
  loop exits with `jg` where a `Word` loop uses `ja` **[V]** (the offset arithmetic and both
  `for` loops of the res09 routines; `make tpc` probes).
- res08 is a resident unit compiled with `$O+` **[V]** (its `OvrInit('GAME.OVR')` copies the
  literal to a stack temporary with `System_StrCopy` before the call, at `042B:00AF`; without
  `$O+` the compiler pushes the literal directly, as the unit's `Assign`/`WriteLn` literals
  show). So `$O+` is not overlay-units-only; SPEC 3 item 6 and AGENTS.md rule it per unit.
- `System_StrCopy` (`0AF8:0B0B`) pops only its source argument (`retf 4`), leaving the
  destination pushed: that is how a `$O+` caller passes a literal (push dest temp, push
  literal, copy, call) with no extra push **[V]** (res08_init `042B:00AF`, `DrawAdventureScreen`
  ovl27:020F; read from the image).
- A multi-argument `WriteLn` compiles to one string/number part after another plus a single
  newline (`WriteLn(Output, A, B, C)` is `0919, 09AF, 0919, 084A`); the `086E` helper call
  trails only a complete `Read`/`Write` without `Ln` **[V]** (res08_init `042B:023B`, `make tpc`
  probes of every form).
- `GameDir := GameDir` (and the same for `SaveDir`) is really in the code: a self-assigning
  `StrLCopy` with limit 255, kept for the match (QUIRK `042B:032D`, `042B:0358`) **[V]**.


---

## 4. Data files

### 4.1 DAX archives **[V]** (`make dax`: all 113 `.DAX` files, all 1,245 blocks)

```
u16  header_bytes                 ; 9 * number of blocks
repeat header_bytes / 9:
  u8   block_id
  u32  data_offset                ; from the end of the header
  u16  raw_size                   ; size after decompression
  u16  packed_size                ; size stored in the file (can exceed raw_size)
block data, back to back, exactly to the end of the file
```

Block compression is a byte-oriented run-length code **[V]** (every block decompresses to exactly `raw_size`):

```
while input remains:
  c = next byte
  if c < 0x80: copy the next c + 1 bytes literally
  else:        repeat the next byte (256 - c) times
```

Byte-for-byte correctness of the decompressed content is **[I]** (sizes all match; content checks come with each format's decoder).

**How the game reads a block** **[V]** (`make match UNIT=res05`, `src/RES05.PAS`: unit complete). `LoadDaxBlock(Name, Ext, BlockId, var Size, var Block)` (`0802:0716`) prefixes the name with the path `DS:547C` and opens the file twice through `OpenDaxFile` (`0802:05CD`): once as the data file through `OpenGameFile`, which asks for the disk while the file is missing, and once as the index file, from which it reads `header_bytes`; the data file is then positioned past the header. It reads index entries (id, offset, raw size into `Size`, packed size) until the id matches or the index file position reaches the header end; a packed size above `$8CA0` shows `tempsize <n>` and quits. A missing file or block gives `Size = 0` and `Block = nil`. Otherwise it allocates the packed buffer `PackedBuf` (`DS:557E`, rounded up to 8 bytes), `GetMem`s `Block` with the raw size, seeks to `header_bytes + 2 + offset`, reads the packed bytes, closes both files and unpacks with `UnpackRle` (`0802:050F`).
- `UnpackRle` reads the code byte as a `ShortInt`: 0..$7E copy code + 1 literal bytes, -127..-1 repeat the next byte -code times. QUIRK `0802:0574`: the codes $7F and $80 fall through both arms without moving the input, so the loop would never end. None of the 1,245 shipped blocks contains either code **[V]** (scan of the code bytes with `tools/re/dax.py`), so the decoder above is exact for the shipped data.
- The disk prompt **[V]**: `OpenGameFile` (`0802:025D`) shows `InsertDiskPrompts[TileSet]` (`DS:2614`, 30-byte `string[29]` entries; entries 1..8 hold `Insert disk N in drive ` in the image) plus the drive letter `DS:547D` and `:` on text row 24 (`ShowBottomMessage`, colour 14) and waits for a key, unless its `NoPrompt` byte (`DS:557C` from `OpenDaxFile`) is set. `FileExists` (`0802:02EB`) is `Reset` and `Close` with I/O checks off; the result of `IOResult` stays in `DS:49CE`. At start-up `WaitForOverlayDisk` (`0802:0212`, called by res08's initialisation) loops on `FileExists('game.ovr')`, writing `Please insert overlay disk.` with `WriteLn`.
- Text through the BIOS **[V]**: `WriteCharsAt` (`0802:0040`) sets the cursor with INT 10h function 2 and writes with function 9 on the page in `DS:4A1B`; with `VideoAdapter` 0 the colour goes through the 16-entry table `DS:25D5` (0,0,0,1,2,2,2,3,3,1,1,1,2,2,3,3 in the image: four colours), and with `VideoAdapter` 1 both calls are repeated on the page in `DS:4A1A`. `MakeDosFileName` (`0802:0425`) deletes the ten characters at `DS:0D1A` (space . * , ? / backslash : ; |), keeps 8 characters and upper-cases them; ovl17 calls it.

### 4.2 DAX families **[V]** counts, **[H]** roles (from file names and prior art)

| Family | Files | Blocks per file | Likely content |
|---|---:|---|---|
| `ECL1-8` | 8 | 2 to 5 | Event scripts per area (section 4.2.2) |
| `GEO1-8` | 8 | 2 to 6 | Area maps (walls, doors, events) (section 4.2.1) |
| `WALLDEF1-8` | 8 | 2 to 7 | Wall definitions for the 3D view (section 4.2.4) |
| `8X8D1-8` | 8 | 3 to 7 | 8x8 tile graphics (3D view, frames, fonts) |
| `PIC1-8`, `CPIC1-8` | 16 | 3 to 44 | Pictures (encounter art, combat pictures) |
| `SPRIT1-8` | 8 | 5 to 15 | Monster sprites |
| `HEAD1-8`, `BODY1-8`, `CHEAD`, `CBODY` | 18 | 1 to 128 | Character and monster portraits (heads, bodies) |
| `MON1-8CHA`, `MON1-8ITM`, `MON2-8SPC` | 22 | | Monster characters, items, affects (section 4.2.5) |
| `ITEM1-8` | 8 | 1 to 10 | Area loot; 63-byte item records (section 4.2.5) |
| `TITLE` | 1 | 2 | Title screens (both blocks unpack to 32,017 bytes: a 320x200x16-colour picture is 32,000 bytes) |
| `COMSPR`, `ICON` | 2 | 26, 6 | Combat sprites, icons |
| `DUNGCOM`, `WILDCOM`, `RANDCOM`, `SQRPACI`, `BACPAC`, `FINAL5` | 6 | 1 to 8 | Combat maps, random encounters, end sequence **[?]** |

#### 4.2.1 GEO maps **[V]** (`make test` / `tools/re/geo.py verify`: 8 files, 29 blocks)

Every decompressed GEO block is exactly `0x402` (1026) bytes **[V]** (`ovl29:10C7` Load3DMap compares the loaded size to `0x402` and fatals otherwise). Layout:

```
u16  payload_bytes                ; always 1024
u8   wall_ne[256]                 ; 16x16: low nibble = east wall id, high = north
u8   wall_sw[256]                 ; low nibble = west, high = south
u8   event[256]                   ; bit7 = interior, bits0-6 = event id
u8   door[256]                    ; 2 bits per direction: N, E, S, W (low bits first)
```

Load3DMap skips the `u16`, then `Move`s four 256-byte planes through the far pointer at DGROUP `0x6A5C` **[V]** (`ovl29:1160`..`ovl29:11DF`). It then records the block id in game variable 197 (`VarGeoBlock`) **[V]** (`make match UNIT=ovl29`). The planes are read through `WallIdAt(Col, Row, Dir)` (Dir 0/2/4/6: high/low nibble of the first plane, high/low nibble of the second), `DoorKindAt` (1 when that side has no wall, else the door bit pair of the fourth plane: bits 0-1 for Dir 0 up to bits 6-7 for Dir 6) and `EventByteAt`; for a cell outside 0..15 all three answer 0 while DS:84DC is 0 or 10 and otherwise wrap the coordinate to the opposite edge (16 becomes 0, -1 becomes 15) **[V]**. The movement code takes door kind 0 as a solid wall, 1 as open, 2 and 3 as two kinds of locked door (5.3) **[V]**. Wall-id nibble packing matches the pre-UA Gold Box `CELL_A` layout (ImHex `GB_GEO.hexpat`, coab) **[H]** for field meaning; plane order and size are from our bytes. Door values are a 2-bit enum per side (none / open / locked variants) **[H]**. Event id 0 means no script trigger on that cell **[H]**.

GEO and ECL share block ids for the same area in most cases; three GEO-only ids (30, 31, 32) and three ECL-only ids (8, 11, 19) are the known exceptions **[V]** (file inventory).

#### 4.2.2 ECL scripts **[V]** (`make test` / `tools/re/ecl.py verify`: 8 files, 29 blocks)

LoadEcl (`ovl07:0341`) allocates a `0x1E00`-byte buffer (same size as coab `EclBlock.ecl_struct_size`), opens `ECL#.DAX` for the current area, loads one block by id, requires `raw_size >= 2`, skips the leading `u16`, and copies `raw_size - 2` bytes into the buffer **[V]**. In every pinned file that leading word is `5000` **[V]**; every payload fits in `0x1E00` **[V]**.

After load, `InitScript` (`ovl07:01B6`) reads five word operands from the start of the block, script address `$9900` (section 5.1), into DS:49E3..49EB **[V]** (`make match UNIT=ovl07`); the slot names come from coab (`vm_init_ecl` / `vm_LoadCmdSets`) **[H]**, and the wilderness L key starts the script at slot 1 (`ovl14`) **[V]**:

| Slot | Role (coab name) **[H]** |
|---|---|
| 0 | `vm_run_1` |
| 1 | `SearchLocation` |
| 2 | `PreCampCheck` |
| 3 | `CampInterrupted` |
| 4 | `ecl_initial_entryPoint` |

Operand encoding (type byte, then low, then high when type is 1/2/3) matches coab `ovr008.vm_LoadCmdSets` **[H]**; our headers all use type 1 **[V]**. Full opcode coverage is not claimed here; that lands with the interpreter unit (section 5.1).

#### 4.2.3 EGA pictures **[V]** (`tools/re/pic.py verify`: 54 files, 778 blocks)

Picture-bearing archives: `TITLE`, `PIC1-8`, `CPIC1-8`, `SPRIT1-8`, `HEAD1-8`, `BODY1-8`, `CHEAD`, `CBODY`, `COMSPR`, `ICON`, `8X8D1-8`, `FINAL5`. Pixel records match coab `DaxBlock` **[H]**. `Load24x24Set` reads the item count at +8 and the word at +$11 (`ovl32:008C`) **[V]**; `DrawIcon` reads the height at +0 and the width at +2 when it allocates a copy **[V]**:

```
u16  height
u16  width_cols                 ; pixel width = width_cols * 8
u16  x_pos
u16  y_pos
u8   item_count                 ; tiles or frames inside this record
u8   palette[8]                 ; 16 EGA indices as packed nibbles
u8   pixels[item_count * height * width_cols * 4]
     ; each byte = two 4-bit colour indices (high nibble first)
```

Record size is always `17 + item_count * height * width_cols * 4` **[V]** (all non-font blocks above). `TITLE` blocks are 320x200 (`height=200`, `width_cols=40`); `CPIC`/`COMSPR`/`ICON` combat icons are 24x24; `HEAD`/`BODY` are 40x88 and 48x88 **[V]**.

**Loading a set** **[V]** (`Load24x24Set`, `ovl32:0022`): the set name is a string parameter. An index above 127 prints `Start range error in Load24x24Set` and calls `QuitGame`. Otherwise `LoadPicture` loads the set, and when the pointer at DS:5E52 is not nil the routine copies `item_count` times the word at +$11 bytes from the loaded picture's tail into that pointer, starting at index times the same word. The loaded picture is then freed. Callers in ovl03 and ovl10 also push 40, 24 or 5; the routine does not read that byte.

**Drawing one cell** **[V]** (`DrawCellPicture`, `ovl32:00F1`): a picture code above 127 is drawn from the pointer at DS:5E56 with bit 7 cleared; a code of 127 or less is drawn from DS:5E52. Both calls pass flags 0 and the destination pointer at DS:4A20 to `DrawPictureItem`. The fourth argument is never read.

**The picture table** **[V]** (`FreePictureSlot`, `ovl32:014E`; `DrawIcon`, `ovl32:04FC`): DS:5E5A is an array of two pointers per slot, stride 8. `FreePictureSlot` frees each pointer that is not nil through `ReleasePicture` (`FreeMem`, then the pointer is stored nil). `DrawIcon` indexes the same table by picture number times 8 plus mirror half times 4. `DrawPartyMarker` passes picture numbers 9 to 11, so the table runs past four slots; the declared bound is the byte index. When the chosen pointer is not nil, `DrawIcon` allocates a picture of the same height and width (`AllocatePicture`), copies into it (`MirrorPicture` when the icon set is above 3, otherwise `Move` of the tail at +$17 and the pixel buffer at +$13; adapter 1 copies a quarter of the bytes), draws it at the cell times 3 through `res07_fn_0D71`, and frees the copy.

**Loading a slot** **[V]** (`LoadPictureSlot`, `ovl32:01C8`, `make match UNIT=ovl32`: unit complete): loads picture `Block` of a set into the first pointer of slot `Slot` and picture `Block + $80` (the mirrored half) into the second, through `LoadPicture`. For `CHEAD` and `CBODY` a name ending in `T` adds $40 to `Block` and the `T` is dropped; `COMSPR` and `ICON` are used as named; any other set gets the file number `TileSet` appended. `ICON` pictures and the `TileSet` sets are then recoloured by `res07_fn_1E5C` with 16-entry colour maps: from the identity map DS:0CD2 to DS:0CF2 (colour 13 becomes 0) for `ICON`, to DS:0CE2 (13 becomes 8) for the others. `StartGame` fills slots 13 to 24 with `COMSPR` pictures 0 to 11 and slot 25 with picture 25.

`PIC*.DAX` and `SPRIT*.DAX` (and some `FINAL5` blocks) wrap several records as an animation **[V]**:

```
u8   num_frames
repeat num_frames:
  u32  delay                    ; tenths of a second **[H]** (coab)
  <picture record>
```

For `PIC`/`FINAL`, pixel bytes of frame N are XOR'd with frame 0 before draw **[H]** (coab `ovr030.load_pic_final`); applying that delta yields coherent PNGs from our files **[V]** (`pic.py dump`).

`8X8D1.DAX` block 201 is not a picture record: it is a 1-bit font, 177 glyphs of 8 bytes each (1416 bytes) **[V]** (size; coab `seg041.Load8x8Tiles` reads it the same way **[H]**). Other `8X8D` blocks are ordinary picture records of 8x8 tiles (`item_count` 31 to 70).

`Load8x8Bank(BlockId, Bank)` (`ovl34:003B`) loads DAX block `BlockId` as one of five 8x8 tile banks (bank 0..4 into `TileBanks`) from the file `8X8D<TileSet>` through res07 **[V]** (`make match UNIT=ovl34`; called by `LoadWallSet` and `StartGame`, ovl11). A bank that stays nil after the load ends the game: `Unable to load 8x8D<set>-<block>` on Output, a key, `QuitGame` **[V]** (`ovl34:00D8`). `Put8x8Symbol` (`ovl34:015D`) draws symbols 1..$11E from banks 0..4 (ranges 1..$2D, $2E..$73, $74..$B9, $BA..$FF, $100..$11E, made bank relative through `SymbolBase`) **[V]** (`make match UNIT=ovl34`: the fourth parameter is a `Byte` used as `Direct <> 0`, which compiles to the same `cmp byte [bp+8],0` a `Boolean` did; `DrawWindowFrame` passes 0, the three ovl29 calls pass 1, the DrawPictureItem path). Symbols 0 and $11F..$7FFF print `Bad symbol number in Put8x8Symbol.` and quit the same way **[V]** (`ovl34:01C5`); symbols above $7FFF skip the check and run on with an unset bank (QUIRK `ovl34:01C0`). A nil bank draws nothing; otherwise the tile goes through DrawPictureItem or is copied into the `TileBuf` staging buffer and shown with ShowPicture **[V]** (`ovl34:01EE`). Each bank is a picture record with the per-tile byte count at +$11 and the tiles at +$17 **[V]** (`ovl34:026B`, `ovl34:0274`).

`SelectTileSet` (`0802:094A`) saves `TileSet` in `ds5377` and stores the new 8X8D file number; `RestoreTileSet` (`0802:095D`) copies `ds5377` back **[V]** (`make match UNIT=res05`). ovl07 and ovl17 call the first; ovl17 calls the second.

CLI: `tools/re/pic.py dump <file.DAX> <id> out.png` (or a directory for multi-frame).

#### 4.2.4 WALLDEF wallsets **[V]** (`tools/re/walldef.py verify`: 8 files, 38 blocks)

`LoadWallSet(BlockId, First)` (`ovl29:0E08`, matched) loads block `BlockId` of `WALLDEF<TileSet>.DAX` into wallset slots `First..3` of the wall tiles (DS:6A58, `TWallSets`), rejecting (fatal message, key, `QuitGame`) only an empty block or one with more wallsets (`Size div 0x30C`) than slots left; it does not check for a multiple of `0x30C` (780) and `Move`s 780 bytes per wallset **[V]**. For each slot it adds `SymbolBase[First] - SymbolBase[1]` to every tile number at or above DS:272C (the wallset's 8x8 tiles live in the slot's bank) and loads the bank with `Load8x8Bank` (block `BlockId`, or `BlockId * 10 + n` for the n-th of several wallsets, block 0 counting as 10) **[V]**. The 15 walls of the three slots are wall ids 1..15 for the view (`TWallTiles`, `DrawWallPiece`) **[V]**. Within a wallset it addresses walls with stride `0x9C` (156), so each wallset is five walls of 156 bytes **[V]** (`ovl29:0FAA`). Observed sizes: 780, 1560, 2340 (1 to 3 wallsets) **[V]**. Each byte is an 8x8 tile number (`DrawWallPiece` passes it to `Put8x8Symbol`, 0 = no tile) **[V]**; PNG expansion is not done yet.

#### 4.2.5 Monster character / item / affect blocks **[V]** (`tools/re/records.py`)

| Archive | Blocks | Record | Size |
|---|---:|---|---:|
| `MON1-8CHA` | 172 | character | 285 (`0x11D`) |
| `MON1-8ITM` | 105 | item × N | N × 63 (`0x3F`) |
| `MON2-8SPC` | 42 | affect × N | N × 9 |

Character and item layouts match coab `PoolRadPlayer` / `Item` **[H]** and round-trip byte-for-byte on every pinned block and every `SAVE/CHRDAT*` file **[V]** (`tests/unit/test_records.py`). A character begins with a length-prefixed name (max 15) then ability scores at `0x10`..`0x16`, THAC0 at `0x2D`, race/class at `0x2E`/`0x2F`, age at `0x30`, `hp_max` at `0x32`, sex at `0x9E` **[V]** on our bytes. An item is a 63-byte record: Pascal name (max `0x2A`), then type at `0x2E`, namenum1–3, plus, readied, weight, count, value, affect_1..3 **[V]**; bytes past the Pascal length in the name slot are preserved on encode (they are often non-zero on disk). Affect (`.SPC`) records are opaque 9-byte rows that round-trip **[V]**; field meanings **[?]**.

Area loot `ITEM1-8.DAX` uses the same 63-byte item records **[V]**.

### 4.3 `ITEMS` type table **[V]** (`tools/re/items.py`)

File size 2,050 = 2 + 128 × 16 **[V]**. Loader skips the first `u16` then reads 128 `ItemData` rows of 16 bytes (coab `ItemDataTable` does the same seek/row size; Curse has 129 rows) **[H]/[V]** count on our file). Row fields (slot, hands, dice, bonus, attacks, range, classFlags, flags) match coab `ItemData` **[H]**; encode/decode round-trips the file **[V]**.

### 4.4 Saved games **[V]** (`tools/re/save.py verify poolrad/SAVE`)

- `CHRDAT<slot><n>.SAV`: 285 bytes; same character record as `MON*CHA` **[V]** (round-trip).
- `.ITM`: multiples of 63; same item records **[V]** (round-trip).
- `.SPC`: multiples of 9; same affect records **[V]** (round-trip).
- `SAVGAMA.DAT`: 13,137 bytes exact **[V]**; internal field map still **[?]**.

---

## 5. Game systems (to be written as units are decompiled)

Each section will cover: purpose, units and routines, data, algorithm, quirks, evidence.

| Section | Subsystem | Leads |
|---|---|---|
| 5.1 | ECL script interpreter: opcodes, variables, events | coab `engine/ovr003.cs`, `VmOpp.cs` **[H]**; wicanr2 places Pool's interpreter in overlay 3 of the 1988 build **[H]** |
| 5.2 | Areas, maps and movement (GEO, walls, 3D view) | OpenGoldBox `docs/MAPS.md` **[H]**; the area view, ovl26 (below) |
| 5.3 | Party and characters (creation, attributes, classes, levels) | wicanr2 `docs/spec/003`, `004` **[H]** |
| 5.4 | Items, money, shops | ovl06 Shop (below, **[V]**); ovl19 Inventory (partially matched); ovl21 Money (5.4.1, **[V]**) |
| 5.5 | Combat (tactical map, initiative, movement, attacks) | wicanr2 `ida-overlay08-*`, `ida-overlay13-*` **[H]** |
| 5.6 | Magic and effects (spells, memorisation, durations) | |
| 5.7 | Rest, time and healing | |
| 5.8 | Text, menus and the screen layout | |
| 5.9 | Graphics (EGA, CGA, Tandy), pictures and animation | OpenGoldBox `docs/graphics-format.md` **[H]** |
| 5.10 | Sound (PC speaker, Tandy) | OpenGoldBox `docs/sound-format.md` **[H]** |
| 5.11 | Saving and loading | |
| 5.12 | Copy protection (code wheel) | `poolrad/__ Code Wheel __.pdf` |
| 5.13 | Random numbers | TP 6 generator, `Randomize` from the clock (below) |
| 5.15 | Messages and running out of memory | res06, ovl00 (below) |

### 5.1 The script machine: memory, operands and helpers **[V]** (`src/OVL07.PAS`, `make match UNIT=ovl07`: unit complete, 33 routines)

ovl07 is the half of the ECL interpreter that ovl03 (the opcode loop, not decompiled yet) calls for everything below the opcodes.

- **The address space** **[V]** (`MemRegion`, `ovl07:06FB`; `ReadVmWord` `ovl07:0E0C`, `WriteVmWord` `ovl07:0C77`): a script address is a word. `$4900..$4CFF` are the words of `GameVars` (game variable *n* is address `$4900 + n`), `$6B00..$6EFF` the words of the second block (DS:49D6), `$9700..$98FF` the words of the third ($400 bytes, DS:49DA), `$9900..$B6FF` the bytes of the loaded script (`EclCode`, so the script can patch itself), and anything else is one of the engine's own variables, handled one by one. The source declares each block a second time with the script's index range (`TVmWords4900` and friends, `absolute` on the 0-based pointers), which is what makes the displacements `$6E00`, `$2A00`, `-$2E00` and `$6700` in the code.
- **The character window** **[V]** (`GetCharacterVar` `ovl07:07BC`, `SetCharacterVar` `ovl07:0A74`): in the second block, some addresses are fields of `SelectedCharacter` rather than words of the block (reads try the character first; writes store the word and then the field). The offsets are the script's own character layout, not `TCharacter`'s: for example `$6B18` is the constitution (+$14), `$6BBB..$6BC3` the first five money words (+$88..+$90), `$6C0C` the side and quick-combat state (0, $80 for a party member run by the computer, $81 for the other side), `$6DB1`/`$6DB4` the selected character's place in the party, `$6DCF` a value from the charisma (0 for 3, then 5 per point up to 20 at 7, 25 for 8..12, then 30, 35, 40, 50, 55 and 60 from 18), `$6E12` the 8X8 tile set (`SelectTileSet` on write), `$6E22`/`24`/`26` load a wall set into slot 1..3 when written with bit 7 set. Writing $6B00..$6B70 also reaches the memorized spells and the bytes after them (QUIRK `ovl07:0AA3`). The address `$6B00` read or written as a string is the character's name.
- **Engine variables** **[V]**: below `$BF68`/`$C04B`, `$B1`, `$FB`, `$FC` read DS:6F6E, 6F6A, 6F6C and `$33D` the facing; above, `$C04B..$C04F` read the party's column, row (signed), facing div 2, and the wall and event bytes of its cell (DS:6AAD..6AB1). Writes to `$C04B`/`$C04C` move the party and `$C04D` sets the facing (0..3 times 2, larger values taken modulo 4), each setting DS:84E6; `$C059`/`$C05F` set the special view codes with DS:84E5 (section 5.2.1).
- **Operands** **[V]** (`DecodeOperands` `ovl07:0000`, `OperandValue` `ovl07:0136`): a command is an opcode byte at `EclPC` followed by operands of a type byte and a low byte, plus a high byte for types 1, 2, 3 and $81. Type 0 is an immediate byte, 2 an immediate word, 1 and 3 (and $80 when read as a value) the word at that address; $80 is a packed string whose low byte is its length in bytes, $81 the address of a stored string. Strings go to `EclStrings[1..]` in operand order. `SkipCommand` (`ovl07:1EA6`) knows the operand count of every opcode (1 to 14; `$29` takes 14), so a script can jump over a command it does not run.
- **Packed strings** **[V]** (`DecodeString` `ovl07:1153`, `SixBitChar` `ovl07:06D3`): four 6-bit codes per three bytes; codes $20..$3F are themselves (space, digits, punctuation), 1..$1F become `A`..`_`, 0 is skipped. Phases 2 and 3 build a byte from the previous byte shifted left (6 or 4) plus the current one shifted right (2 or 4), then shift it right by 2 (`ovl07:11C5`, `11F3`): the arithmetic gives the plain 6-bit split of the three bytes.
- **Control and comparisons** **[V]**: `ScriptGosub` (`ovl07:1951`) pushes `EclPC` on a linked return stack of 6-byte entries (`ReturnStack`) and jumps to the operand's address; `CompareStrings` and `CompareWords` set the six flags `CompareFlags` (=, <>, <, >, <=, >=) that the conditional opcodes test [I]. `InitScript` (`ovl07:01B6`) resets the machine for a new script (the flags, the return stack, `EclPC := $9900`, the five entry addresses, `VarNoCasting`, `VarForceWallView := 1`) and clears game variables `$4A00..$4A1F` and words `$6E79..$6E82` unless DS:49F8 asks to keep them once.
- **Helpers for opcodes** **[V]**: `LoadEcl` (section 4.2.2); `AskMenu` (`ovl07:1684`, the prompt-line menu the shops and the Temple use: `~` marks the hotkeys, letters and digits are lowered by $20 first (QUIRK `ovl07:15BF`: digits become `P`..`Y`), the result is the hotkey's 0-based position, 0 for Return when allowed, $FF otherwise); `AskListMenu` (`ChooseFromList` with a prepared title); `ShowEncounterPicture` (`ovl07:054E`: the SPRIT sprite by distance in the 3D view, then the PIC picture or HEAD and BODY close-up); `OpenStepsAhead` (cells without a wall ahead, up to 2); `StepPartyForward`; `SetupDuel` (`ovl07:1A6F`: `DuelMode`, and a computer-run copy of the selected character named `ROLF` with copies of its items on the other side); `ScaleMoney` (all seven money words times a `Real`, truncated); `LoseItems` (`ovl07:1DF0`: each item is lost on a d100 roll at most the chance, which drops for good by 90 for an item weighing more than 255 and by 50 for one more than 24); `MovementRange` (the party's fastest and slowest `Movement`, +$11C, doubled by affect $27 and halved by affect $2A); `DamageWithMessage` (`ovl07:20CC`: `dies.` when the damage exceeds the hit points plus 10, else `is hit FOR n points of Damage.`, then `ApplyDamage`).
- **Map corrections and frames** **[V]**: the map listed 39 entries; six (`07FE`, `08A2`, `0B48`, `0E38`, `1307`, `20A9`) are inside routines or a literal pool. Nine routines have frame bytes no statement uses, declared as unused locals (QUIRKs `ovl07:0139`, `01B9`, `0344`, `0414`, `0551`, `0E0F`, `1156`, `1A72`, `20CF`). Idioms proven here: `Hi * 256 + Lo` (not `shl 8`) gives `mov cl,8; shl ax,cl` with the right operand loaded first; `S := Concat(S, Ch)` allocates its string temporaries in the opposite order from `S := S + Ch`; a `case` with one arm and `else` compiles to `mov al,x; cmp al,k` where `if x = k` gives `cmp byte ptr [x],k`.

### 5.2 The area view: wilderness blocks and the adventure screen **[V]** (`make match UNIT=ovl27`, `src/OVL27.PAS`)

The wilderness around Phlan is drawn as a 5x5 grid of area blocks. Every block covers 3x3 map
tiles and is one picture, drawn by `DrawCellPicture` (`ovl32:00F1`) at a cell position of the 3D view
window; the block at map position (column, row) comes from the area map, and entries 3 to 9 of
a fixed table can replace it while the game variables allow it (`DrawAreaView`, `ovl27:0000`).

- **The area map** at DGROUP `0x3648` (`AreaMap` in `src/POOLVARS.PAS`) is 36 rows by 44 columns
  of one-byte block codes **[V]** (row stride 44 at `ovl27:0040`; `ShowAreaView` clamps the view
  window to columns 0..39 and rows 0..31, `ovl26:0253..0287`, which is 44-5 and 36-5). The picture code
  drawn is the map byte minus one **[V]** (`ovl27:0049`). The shipped image fills the map with
  terrain codes; rows 34 and 35 are all `0x4E` (the letter N), and `ovl14:08BB` compares map bytes
  with `0x4E` specially **[I]**: N marks ground that draws no block. **[?]** Nothing in the code
  writes the map, so it is compiled-in data; whether the game rewrites parts of it at run time is
  open.
- **Nine fixed positions** are tested, and only entries 3 to 9 can replace a block: the table at
  DGROUP `0x0C30` (`SpecialBlocks`, ten records of Col, Row, Pic: Word; entry 0 is never read, its
  bytes are the tail of the previous table in the image). Entries 1 and 2 are compared with the
  block's column and row (`ovl27:006A`, index times 6 from DS:0C30) and then the `case` has no arm,
  so a match leaves the map code **[V]**. Entries 3 to 9 replace it with Pic minus one **[V]**
  (`ovl27:00B2`): entry 3 while word 396 is not 255; entry 4 while word 466 is
  nonzero, or bit 3 of word 380 is set, or word 415 is zero; entry 5 while bit 1 of word 416 is
  clear; entry 6 always; entry 7 while bit 0 of word 416 is clear; entries 8 and 9 while word 435
  is above 253. Entries 6 and 7 hold columns 165 and 157, beyond the 44-column map, so they can
  never match the window **[I]**: dead entries, or coordinates in a system not seen yet.
- **The party position on the area map** lives in the game variables, the word array the far
  pointer at DGROUP `0x49D2` (`GameVars`) leads to: word 195 is the column and word 196 the row
  **[I]** (`ovl26:0249` passes both minus 2, so the party block sits at the centre of the 5x5
  grid; `ovl26:023F` adds a per-zone column base from the byte table at `0x3C78`, whose entries
  for zones 2..4 are 0, 13, 26: three side-by-side strips of 13 columns **[V]** for the table,
  **[I]** for them being the wilderness zones). `ovl07:02E1` and `ovl17:1C20` index the same array
  dynamically **[V]**, consistent with the ECL scripts' variables **[H]** (coab `VmOpp.cs`).
- **`DrawAdventureScreen`** (`ovl27:0207`) frames the three windows of the adventure screen
  **[V]**: the 3D view rows 1..15 x columns 1..15, the side window rows 1..15 x columns 17..38
  and the text area rows 17..22 x columns 1..38, through `DrawWindow` (`03F1:02E8`), the
  window routine of res09 **[V]**: it clears the interior (`ClearWindow`), draws a frame from
  picture set `FrameSet` around it (`DrawWindowFrame`: the corner and edge pictures come from index
  `FrameSet*3+276` and are blitted by `Put8x8Symbol`) and centres the text on the top row
  (`DrawTextAt`). Its grid: a column is 16 pixels and a row 4 scanlines, 40x50 cells on a
  640x200 screen **[V]** (the multiplies in `ClearWindow`).
- QUIRK `ovl27:01CC`: `DrawAreaView` passes both cell coordinates as `BaseCol + 1 - 1` (and the
  same for the row): the additions cancel; the compiler must emit them to match the bytes. The
  fourth argument of `DrawCellPicture` is always 1 here (0 from `ovl31`) and the callee never reads it
  **[V]**.

#### 5.2.1 The area view dispatcher and the party marker **[V]** (`make match UNIT=ovl26`, `src/OVL26.PAS`)

- **The area view unit** **[V]** (`src/OVL26.PAS`, `make match UNIT=ovl26`: unit complete): the resident unit's view dispatcher calls `ShowAreaView` (`ovl26:016D`) for its view types 3 and 4 (`RedrawView`), and the wilderness map screen calls it after the text windows of `DrawAdventureScreen` (`DrawWildernessScreen`).
- **Two kinds of view** **[V]** (the `case` at `ovl26:018C`): `AreaViewKind` (DS:49FA) selects what to draw. Kind 1 is the 3D wall view: GeoLoad returns the event byte of the party cell (`EventByteAt`, wrapping the coordinates into 0..15; bit 7 marks an interior cell, 4.2.1), the wall id table `ds0C26` (16 entries: two equal groups of eight ids 0,15,12,11,13,10,9,14) is indexed by the game state words at +$1FA (outside cell) or +$1FC (interior cell), the four wall view descriptors DS:6A60..6A63 go to `SetWallDescriptors` (a pure setter for the same globals), and `DrawWallView` draws the rest (5.2.2; the overhead wall map instead of the 3D walls while `WallMapMode`, DS:6AAC, is set; ShowAreaView clears it when the state word at +$1F6 is set). Kinds 2 to 4 are the map window: `DrawAreaView(LeftCol, TopRow)` draws 25 blocks of the 44-column map grid (DS:3648, stride 44 [V] from `ovl27:0040`), stepping 3 view cells per block (the source's `BlockCells`, the same 3x3 cells as above), and `DrawPartyMarker` follows.
- **Where the kinds come from** **[V]**: the area loader sets `AreaViewKind := 1` (`StartGame`), the encounter unit sets 2, 3 or 4 together with view type 3 (`ovl03_fn_31B4`, keyed on DS:84DC); the game state word at +$1CC forces kind 1. `MapBaseX` (DS:3C76) holds the base column of each kind: entries 2..4 are 0, 13 and 26 **[V]** (the map image), so the kinds are three pages of the 44-column grid; the window is the party position minus 2, clamped to columns 0..39 and rows 0..31, and the page base is added to the column.
- **The party marker** **[V]** (`DrawPartyMarker`, `ovl26:0000`): the marker cell is the party position within the window `ShowAreaView` clamped (0 and 1 stay at the edges, columns 2 to 41 / rows 2 to 33 become the centre cell 2, column 42 / row 34 become cell 3, column 43 / row 35 or more cell 4, ovl26:001F and ovl26:0043). PicLoad draws it (`DrawIcon`) with the icon set DS:6AAF and the six-frame walk animation `MarkerFrame` (DS:6DDC): frame mod 2 picks the mirrored half, frame div 2 + 9 the picture 9 to 11, and the frame steps modulo 6 after each draw. The wilderness keys H, M, P and K set the icon set to 0, 2, 4 and 6 **[V]** (`HandleWildernessKeys`, `ovl14:0989`, which also cycles it by +2/+4/+6 mod 8), and `WriteVmWord` maps a script value 0..3 to the same four (script address `$C04D`) **[V]**. The same byte is the party's facing: `StepPartyForward` (`ovl07:19DB`) moves the party north, east, south or west for 0, 2, 4, 6 and `WallIdAt` takes it as the direction **[V]**, so the marker icon shows the facing **[I]**.
- **Special view codes** **[V]**: while DS:84E5 is set, `ShowAreaView` refreshes descriptors 2 to 4 from DS:6F69 and DS:6F68 through three nested Byte functions (`WallDesc2FromCode`..`WallDesc4FromCode`, `ovl26:00C7..016C`): codes 8 and $41 give descriptor 0, code $0B gives 8, code 6 gives 1, everything else $0F, 7 and 6. The loaders and the script set the codes: `InitScript` sets $41 and 9 and sets DS:84E5, `StartGame` sets $DB and $E8 (ovl11:0435 lies inside StartGame, StartGame; whitepaper 3.2.2), and script writes to addresses `$C059` and `$C05F` through `WriteVmWord` set the code and DS:84E5 (section 5.1). What the descriptors select is **[?]** (they reach the screen through `DrawWallDescriptors` (`ovl29:0174`, matched: it draws all four of them through `FillPictureRect`, passing `@ds260A` and `DrawBuf`), still not decompiled; the label strings near DS:0A26 include "1st Level" to "9th Level").

- **Special view codes** **[V]**: while DS:84E5 is set, `ShowAreaView` refreshes descriptors 2 to 4 from DS:6F69 and DS:6F68 through three nested Byte functions (`WallDesc2FromCode`..`WallDesc4FromCode`, `ovl26:00C7..016C`): codes 8 and $41 give descriptor 0, code $0B gives 8, code 6 gives 1, everything else $0F, 7 and 6. The loaders and the script set the codes: `InitScript` sets $41 and 9 and sets DS:84E5, `StartGame` sets $DB and $E8 (ovl11:0435 lies inside StartGame; whitepaper 3.2.2), and script writes to addresses `$C059` and `$C05F` through `WriteVmWord` set the code and DS:84E5 (section 5.1). What the descriptors select is **[?]** (they reach the screen through `DrawWallDescriptors` (`ovl29:0174`, matched: it draws all four of them through `FillPictureRect`, passing `@ds260A` and `DrawBuf`), still not decompiled; the label strings near DS:0A26 include "1st Level" to "9th Level").
- **More game variables** **[V]**: besides the party position (words 195 and 196, above), `ShowAreaView` reads word 230 (+$1CC, forces the wall view), word 251 (+$1F6, asks for the overlay labels) and words 253 and 254 (+$1FA and +$1FC, the wall id table index for an outside and an interior cell) of `GameVars^`; their names are the `Var...` constants of `src/POOLVARS.PAS`. The words are read as constant indices of the same `TGameVars` array that `DrawAreaView` uses, and `GameVars^[VarMapX]` compiles to the same `les di; mov ax,es:[di+186h]` a record field did (both units match against the one declaration).
- **TP 6.0 idioms proven here** **[V]** (probes `build/probes/`, `make tpc`): a nested routine receives its parent frame as a hidden last parameter (the caller pushes `bp` right before `push cs; call near`) and its code is emitted just before the parent's body, so the matcher proves it inside the parent's pre-entry region and compares that range instruction by instruction; a `case` with an arm body longer than the short-jump range places the arm body at a distance with `je` plus a `jmp` to the next test (`ovl26:018C`); `x - 2` compiles to two `dec`s; `x mod 2` on a Byte uses signed `idiv` while `x div 2` uses `shr`; an empty `then` branch compiles to the branch and a `jmp` and is what `ovl26:001F` shows.

#### 5.2.2 The 3D view and the overhead wall map **[V]** (`make match UNIT=ovl29`, `src/OVL29.PAS`: unit complete)

- **Ten wall pieces** **[V]**: the 3D view is an 11x11 grid of 8x8 tiles at screen column and row 2..12. Every wall of a wallset is a list of 156 tile numbers cut into ten pieces (`WallPieceFirstTile`, `WallPieceWidth`, `WallPieceHeight` at DS:0C8C, 0C96, 0CA0): the front walls of the far, middle and near rows (pieces 0, 3, 6: 1x2, 3x4, 7x8 tiles), their left and right side walls (1/2: 1x4, 4/5: 2x8, 7/8: 2x11) and the edge of a far front wall (9: 1x2). The widths times heights add up to 156 exactly. `DrawWallPiece` draws one piece at its position (`WallPieceCol`/`WallPieceRow`, DS:0CAA and 0CBE, Integer) plus a sideways shift, skipping tiles outside the grid and tile number 0.
- **Painter's order** **[V]** (`DrawWallView`, `ovl29:05FD`): after the frame (`DrawWallDescriptors`) it starts two cells ahead of the party and steps back one cell per row: the far row looks at four cells each side (front walls 2 tiles apart, the edge piece where a front wall ends, then the side walls of three cells each side), the middle row at three cells (3 tiles apart), the party's own row at two (7 tiles apart). Front walls use the facing direction, side walls the left (Dir + 6) or right (Dir + 2) direction mod 8; the step tables DS:2736/273F give one cell. Off-map cells follow the wrap of 4.2.1.
- **The overhead wall map** **[V]** (`DrawWallMap`, `ovl29:0000`): while `WallMapMode` is set the view shows an 11x11 window of the 16x16 map around the party (window corner clamped to 0..5), one 8x8 symbol per cell, `0x104` plus 1, 2, 4, 8 for a north, east, south, west wall, and the party arrow `0x100 + Dir div 2`. The movement loop's A key toggles the mode unless game variable 251 is set (5.3). The map listed a second routine at `ovl29:0143`; it is the tail of `DrawWallMap` (341 bytes).
- **Idioms** **[V]**: a two-dimensional array index `A[Row, Col]` through a far pointer compiles to `Col` into `dx`, `Row * 16` into `ax`, `les di`, `add di,ax`, `add di,dx`, with the field offset in the displacement (`es:[di+0x300]`); a lower bound of 1 shows as a negative displacement (`es:[di-0x9C]`, `es:[di-0x3A8]` for `[1..3, 1..5, 0..155]`). In a sum of an array element and a `ShortInt`, `X[i] + S` loads `S` first (`cwde; mov dx,ax`) while `S + X[i]` does not; `if (F < 1) or (F > 3) then Exit;` is the `jb; cmp; jbe; jmp` guard at `ovl29:0E0F`.

### 5.3 The wilderness keys and commands unit ovl14 **[V]** (`src/OVL14.PAS`, `make match UNIT=ovl14`: unit complete)

Overlay 14 drives wilderness interaction for `ovl03_fn_3379`: movement and view keys plus the Bash/Pick/Knock/Exit command menu on the area map.

- **Map corrections** **[V]**: the map split three routines into fragments (`ovl14_fn_077A` inside `073B`, `ovl14_fn_0889`/`08A2`/`08E5` inside `0818`, `ovl14_fn_0B48` inside `e2`); none has a `55 89 E5` prologue and aligned disassembly shows continuous code. The entries were deleted and the sizes corrected (`073B` 185, `0818` 354, `e2` 963) in `re/symbols.toml`.
- **No PIT read** **[V]**: the `E4 40` bytes at `ovl14:0B48` are the tail of `xor ah,ah` plus `inc ax` in the `(DS:6AAF + 2) mod 8` icon cycle, not `IN AL,40h`; per-routine disassembly from the true prologues shows no port I/O anywhere in the unit (the Entropy bullet is corrected above).
- **Signed bytes everywhere** **[V]**: the party cell `DS:6AAD`/`DS:6AAE`, the direction tables `DS:2736`/`DS:273F`, the record flag tables and the `Icon`/`Col`/`Row` parameters are all `ShortInt`, proven by `cbw` (not `xor`) widenings and signed `jb`/`ja`/`jle` comparisons (`ovl14:0696`, `069D`, `06A4`, `06D0`, `026A`); a `Byte` source compiles to the zero-extending forms instead (`make tpc` probes). Passing `ShortInt` to a `Byte` parameter is a type mismatch (Error 26), but `Byte` to `ShortInt` and `Integer` to either both compile.
- **The code-table records** **[I]** (`TCodeRec` in `src/OVL14.PAS`, head at `DS:5D96`): heap records chained through a pointer at +$104, each with a 21-byte code table at +$17 (the Knock code `$1F`), flag bytes at +$96 (5 gates Knock, 6 gates Pick), a Pick threshold at +$78, a Pick flag at +$10C, and lock fields at +$10 (type) and +$16 (strength 0..100) used by Bash; nothing in this unit allocates them (no `New`/`GetMem`), so their owner is **[?]**.
- **The routines** **[V]**: `HandleWildernessKeys` (`ovl14:0989`, the entry) reads menu keys (A/C/V/E/S/L) and movement keys (H steps via `ClampPartyPosition`, P/K/M cycle the icon set by +4/+6/+2 mod 8) through `ReadPromptChoice`, and runs a smaller loop on map pages 2..4 (icons set directly to 0/2/4/6); `DoWildernessMenu` (`ovl14:0D6D`) builds the Bash/Pick/Knock/Exit menu from the `DS:6DDE`/`DS:6DDF`/`DS:6DE0` flags and the record checks, prompts through `ReadPromptChoice` and dispatches the key: in the `DoorKindAt` = 2 arm 'B' calls `DoBash`, 'P' calls `DoPick` (`ovl14:0ED6`) and 'K' calls `DoKnock`, with Knock offered when `FindCodeRecord($1F)` finds a record (`ovl14:0E14`), while in the = 3 arm 'B' calls `DoBash` and 'K' calls `DoKnock`, with Knock offered when `HasRecFlag(5)` is set (`ovl14:0F53`), but 'P' only clears the Pick flag (`mov ds6DDF,0` at `ovl14:1015`, no `DoPick` call); on success it moves with `MoveParty`, steps the map with `CheckMapCell` on pages 2..4, and always frees the `DS:6A5C` sprite list; `CheckMapCell` (`ovl14:0818`) reads the area-map cell ahead through a `case` (N `$4E` and the impassable ranges pass silently, river codes `$66..$6C`/`$72` print the stench message unless `GameVars^[VarRiverGate]` (word 418) is set, anything else moves there); `MoveParty` (`ovl14:073B`) steps with wraparound; `ClampPartyPosition` (`ovl14:068D`) steps with edge clamping; `FindCodeSlot`/`FindCodeRecord`/`HasRecFlag` search the records; `ClearIconBits`/`SetIconBits` clear/set an icon set's bit pair in the map cell byte through a 2-D array view (`GeoCells^.Cells[Row, Col]`, `array[0..15, 0..15]`).
- **TP 6.0 idioms proven here** **[V]** (`make tpc` probes): `with Rec^ do` spills the record pointer with `les di; mov [temp],di; mov [temp+2],es` and reloads it per field access; commutative `+` evaluates its right operand first (so `GameVars^[VarMapX] + step` and `X + MapBaseX` match and the swapped forms do not); a 2-D array access keeps the `$300` field offset as the displacement while a folded `+ $300` index does not; `case` on a value reused across labels keeps it in `al` (an if-chain reloads or compares direct); `if C then A else B` with a far B compiles to jump-if-NOT-C (short) plus a `jmp` to B, so the source polarity is read off the jump, not the layout; parenthesised 4-term `and` chains nest while 2-term chains (and nested single-statement `if`s) stay flat.

### 5.4 Items, money and shops **[V]** (`src/OVL06.PAS`, `make match UNIT=ovl06`: unit complete)

The shop is overlay 6 (`ovl06`, "Shop"). `ShopMain` (`ovl06:053E`) is its entry, called from
ovl03 when the party enters a shop. It marks the shop open (`DS:49F3`, read by res12), clears
the 28-byte money block at `DS:67F4` and `DS:6DC0`, redraws the shop (`res12:27D9`,
`res12:0767`), and loops on a menu (`ReadPromptChoice`) whose text comes from `TreasureLeft`:

- The full menu is "Buy View Take Pool Share Appraise Exit"; when `TreasureLeft` says there is
  nothing to take or share, the shorter "Buy View Pool Appraise Exit" is shown. One `case`
  dispatches the key: B buys, V views an entry (`ovl19_e5`), T takes (`TakeMoney`), P pools
  when the flag is clear (`PoolMoney`), S shares (`ShareMoney`), A appraises (`AppraiseGems`), E
  leaves, and G/O update the selected party member through `UpdateSelectedCharacter`. G selects the
  preceding member (wrapping from the head to the tail); O selects the next member, wrapping to the
  head. Other keys select the head **[V]** (`ovl19:27DF`). Leaving while money lies in the pool asks through `AskMenu` ("Do you want to
  go back and get your Money?", '~Yes ~No'); `AskMenu` returns the 0-based hotkey position, so
  the party leaves on No (1) and stays on Yes **[V]** (`dec ax` at `ovl07:1775`, `ovl06:053E`).
- The shop stock is the linked list at `DS:6810` of 63-byte item records, the `TMenuLine` type
  of `src/POOLVARS.PAS` (`TItem` is the same record): the item record of 4.2.5 in memory, with
  `Text` (a `string[40]`, the item name) at +0, `Flag29` at +$29, `Next` at +$2A, `Weight` at +$37,
  `Count` at +$39 and `Value` (the price) at +$3A **[V]** (`make match UNIT=ovl06`, field offsets
  by `tools/re/records.py`). `ChooseShopItem` (`ovl06:0030`) draws the window titled "Shop"
  (`DrawWindow`) and, for each entry, rewrites `Text` into a 30-character field with the name on
  the left and `Value` right-justified (a zero value becomes 1, `ovl06:0068`); it then runs the item
  picker `ChooseFromList` ("Items: " with a "Buy" button).
- `BuyItems` (`ovl06:0361`) takes the chosen item's `Value` as the price. It pays first from the
  selected character's money (`CharacterMoneyValueInGold(SelectedCharacter)`, a LongInt) and then from the money
  pooled in the shop (`MoneyValueInGold` on `DS:67F4`); if the price fits, the item is added to the
  character's items and the amount is deducted (`SetCharacterGold` for the character, `SetPooledGold` for the
  pool), otherwise it shows "Not enough Money.". `CharacterMoneyValueInGold` and `MoneyValueInGold` both sum five coin
  amounts, each multiplied by its LongInt rate from the table at `DS:0D24`, add 100 and divide by
  the LongInt at `DS:0D30` (`ovl19:28BE`, `ovl21:00A8`); the character's coins are five words at
  +$88..+$90, the pool's five LongInts at the start of the 28-byte block `DS:67F4`. Both deduction
  routines divide the amount by 5 and write five coin amounts (`SetCharacterGold` into the character,
  `SetPooledGold` into `DS:67F4`), and the money blocks hold seven kinds, the five coins first (5.4.1). Two 16-bit truncations are kept (QUIRKs): `BuyItems` keeps only the low word of
  `CharacterMoneyValueInGold`'s LongInt (`ovl06:03C7`), so a character with 65536 or more is compared and charged
  modulo 65536, and it passes only the low word of the pool's LongInt remainder to
  `SetPooledGold(Amount: Word)` (`ovl06:0449`), so a pool above 65535 is rewritten truncated; ovl04's
  `ChargeForCure` does the same (5.19).
- `AddInventoryItem` (`ovl06:0239`) appends a clone of an item to `SelectedCharacter^.Items`
  (+$C8, the character's carried items) and sets its var `Overloaded` to 1 when the item was
  refused, 0 when it was added (`ovl06:026D`, `ovl06:0277`). The matched `WouldOverloadInventory`
  (`ovl19:275B`) first calls `RecalcCombatValues`, then returns true when the character's byte at +$C7
  exceeds 15 or when `CarriedWeight` (+$102) plus the item's added weight exceeds
  `StrengthWeightAllowance(Character) + 1500`. Added weight starts at `Item^.Weight`; the code multiplies it
  by `Item^.Count` only when the count is nonzero. `AddInventoryItem` refuses the item and shows
  "OverLoaded" when the function returns true **[V]** (`make match UNIT=ovl19 FN=WouldOverloadInventory`,
  `ovl06:026D..0277`). The strength-capacity interpretation of `StrengthWeightAllowance` remains **[I]**.

Map note: `re/symbols.toml` had split `ovl06:0239` at `ovl06:0311`; `0311` is one byte into a
`les di, [bp-8]` instruction, not a routine entry, and its stub was removed.

#### 5.4.1 Money: ovl21 **[V]** (`src/OVL21.PAS`, `make match UNIT=ovl21`: unit complete, 22 routines)

ovl21 ("Money") holds the coin arithmetic and the money commands the shop (5.4), the Temple (5.19)
and the treasure menu (5.20) share.

- **Seven kinds.** `TCharacter.Money` (+$88, seven words) and `PooledMoney` (`DS:67F4`, seven
  LongInts) are indexed alike: copper, silver, electrum, gold, platinum, gems, jewelry, the order of
  the name table `MoneyKindNames` (`DS:0FFA`, seven `string[10]`). `CoinCopperValues` (`DS:0D24`)
  values the five coins in copper: 1, 10, 100, 200, 1000. `MoneyValueInGold` (`ovl21:00A8`) sums the
  five coins in copper, adds 100 and divides by 200 (rounding to gold); gems and jewelry are not
  money until appraised. `SetCharacterGold` and `SetPooledGold` rewrite a gold amount as
  `Amount div 5` platinum plus `Amount mod 5` gold, clearing the other coins.
- **Weight.** Every coin weighs one unit of the carried weight `TCharacter.CarriedWeight` (+$102);
  `CarryLimit` is 1500 plus the strength allowance `StrengthWeightAllowance` (a table on the strength
  class: -350 for the weakest, up to several thousand), and `WouldOverload` tells whether Amount more fits and how much
  room is left. QUIRK `ovl21:04DB`: `TransferMoney` adds the coins' weight back to the giver instead
  of the taker.
- **Pool and Share.** `PoolMoney` (`ovl21:0508`) moves all the money of every member whose `B84` is
  0 or $B3 into `PooledMoney` and sets `MoneyInPool` (`DS:6DC0`). `ShareMoney` (`ovl21:063A`)
  divides each kind by the number of such members (`CountSharers`): each member below `B84` $80 takes
  his share, jewelry first, as far as his load allows, plus one coin of the remainder; the remainders
  then go to anybody who can carry them, and what is left stays pooled.
- **Take.** `TakeMoney` (`ovl21:0CEB`) lists the pooled kinds ("Select type of coin"), asks "How much
  <kind> will you take?" with `ReadAmount` (`ovl21:0294`: digits on row 24, Backspace, clamped to the
  maximum, Escape gives 0) and moves the amount with `TakeFromPool`. `DropMoney` puts dropped coins
  into the pool only in view mode 1 (shop, Temple) or 6 (treasure); elsewhere they are lost.
  `TreasureLeft` (`ovl21:0F7E`) reports pooled money and loot left for the menus.
- **Appraise.** `AppraiseGems` (`ovl21:19B2`) values one gem (d100: 10, 50, 100, 500, 1000 or 5000
  gp) or piece of jewelry (100 + Random(900) up to 2000 + Random(10000)) at a time; selling pays a
  fifth of the value in platinum (`GivePlatinum`, the overflow to the pool with "Overloaded.  Money
  will be put in Pool."), keeping makes an item of type $46 when the character can carry it and has
  fewer than 16 items. QUIRK `ovl21:1E74`: a character with no items loses the kept gem, and the
  kept item adds no weight.
- **Treasure items.** `BuildTreasureItem` (`ovl21:1010`, called from ovl03) fills a 63-byte
  `TMenuLine` for an item type: weapons and armour get a bonus of 1..3 (`RollItemBonus`, d20) with
  their name numbers, weight and value; types $3D and $3E get 1..3 random affects; other types take
  a fixed row of eight words of `TreasureItemRows` (`DS:0970`).

Map note: `07D1`, `0B48`, `0F21`, `1758`, `1F4B` and `2233` were inside routines (`ShareMoney`,
`TakeFromPool`, `TakeMoney`, `BuildTreasureItem`, `AppraiseGems`) and their entries were removed.

### 5.5 Combat: the round loop and the player's commands **[V]** (`src/OVL08.PAS`, `make match UNIT=ovl08`: 11 of 13 routines at L2)

- **Rounds and turns** **[V]**: `RunCombat` (`ovl08:007A`) runs rounds until one side is gone (DS:6814 or DS:6815 zero). In a round every character of the party list DS:5D96 (which holds every combatant, monsters included) gets `ovl13_e1`, then `PickNextCombatant` repeatedly picks the character with the highest positive initiative (`TCombatant.Initiative`, the combat state at character +$108, signed), ties broken by a 1d100 roll, and `CombatTurn` plays it; the round ends when nobody has an initiative above 0. Delay sets the initiative to 1 (act last).
- **Who plays** **[V]**: a character with `Quick` (+$10F) set is played by the computer (`QuickTurn`), the others by the player (`PlayerTurn`). Quick sets it (`SetQuickCombat`, which also forgets a remembered target on the character's own side, +$10E is the side), Space clears it for every character with byte +$84 below $80, and Alt-Q makes everybody quick. A pending spell (+$108^.+0) is finished through `ovl22_e5` instead of a turn.
- **Commands** **[V]**: the menu is Move (while half-moves are left, +$108^.+6, shown halved), View Aim, Use (item count +$C7), Cast (a memorized spell at +$17..+$2B, the combat flag +$108^.+1 and game variable 229 zero), Turn (cleric level, not turned yet), Quick Done. Done opens Guard, Delay, Quit, Bandage, Speed, Exit; Speed is the GameSpeed (0..9) menu of DS:49E2. The keys accepted besides the letters are the scan codes of Alt-Q, Alt-R, Alt-X and Alt-M (Magic On/Off, DS:6E30), with the key flag of `ReadPromptChoice` set.
- **Movement** **[V]** (`MoveCharacter`): the keypad scan codes H, I, M, Q, P, O, K, G are the directions 0 to 7 clockwise from north; a step towards a combatant attacks it (`MeleeAttack`: Not with that weapon, else `ovl13_e16`/`e7`/`e11`/`e12`), a step off the map asks Flee:, a step onto ground whose cost (`CombatTiles`, DS:2744, 4-byte entries; 5.5.1) is above the half-moves left says Blocked. Esc takes the move back.
- **Dying** **[V]**: a character with Status 5 bleeds one round per round end (`EndCombatRound`, +$108^.+$E) and gets Status 6 after more than 9; Your Teammate is Dying is shown while a party member (side 0) can be bandaged, and Bandage gives Status 4. When only the enemies are gone and DS:49F4 is 0 the game asks Continue Battle:.
- **Map corrections** **[V]**: the map listed 36 routines; 23 of them (`03A5`, `03D5`, `06A5`..`06FF`, `0718`, `0889`, `088E`, `08E5`, `0999`, `0B2F`, `0B34`, `0B48`) are inside the 13 real ones.

#### 5.5.3 The computer's turn ovl09 **[V]** (`src/OVL09.PAS`, `make match UNIT=ovl09`: unit complete, 14 routines and one proven nested)

- **The turn** **[V]** (`QuickTurn`, `ovl09:000F`, the entry, called by CombatTurn/PlayerTurn for a character with `Quick` set): reads a key (`HandleCombatKey`), clears the prompt line, ends the turn through `EndCombatTurn` when the character is not dying (`Flag10D` 0), rerolls the step pattern (+$15) when it is 0 or above 4 or a d4 comes up 1 (a d8 gives the new pattern, an 8 a d2 + 4, else a d4), and runs `CheckMorale` when no key was pressed; a panicking character (+$14 set) that is not stuck (+$10 0) shows 'flees in panic' (the unit's first bytes) through `ShowCharacterMessage`. While the turn lasts it then uses a magic item (`UseMagicItem`), finishes a pending spell (`Combat^.PendingSpell` through `ovl22_e5`), takes the level-0 turn (`ovl09_fn_0203`), casts a memorized spell (`CastMemorizedSpell`), uses the best item (`UseBestItem`) and reads keys again, looping on `ovl13_e21(Who, $FF, 1, 0)`: an initiative above 0 runs `AiTurn`, else the turn ends through `ovl09_fn_0F4F`.

- **Magic first** **[V]**: `UseMagicItem` (`ovl09:03E4`) walks the character's items for a castable one (`Affects[2]` the spell level, `Affects[3]` below $80 and `ovl22_e6` false) and uses it through `ovl19_e8`; `CastMemorizedSpell` (`ovl09:0545`) collects the memorized spells, keeps those `SpellAccepted` accepts and casts one through `ovl13_e15`. Both give up at once when the combat byte +$108^.+2 is zero, the side count `ds6814Sides[OpposingSide(Who)]` is zero or game variable 229 (`VarNoCasting`) is set, and both roll `RollDice(1, 7)` for the number of tries. `SpellAccepted` (`ovl09:02EB`) is the range test they share: it refuses when the spell row's byte +$D is below the requested range, accepts a spell other than 3 whose +$E byte is 0, asks `ovl13_e13(Who, Done)` for spell 3, and otherwise collects Who's enemies the area pattern of `ovl22_e3(Spell)` reaches (`CollectEnemiesInRange`, count `Tries`; the indexes land in DS:6DE4, from 1) and refuses when the nested `DifferentSideInArea` (`ovl09:0255`: `ScanTargets` around each collected enemy with the row's +$F byte as the line budget) finds a side unlike `OpposingSide(SelectedCharacter)`; a zero count or a zero +$F byte accepts.
- **Morale** **[V]** (`CheckMorale`, `ovl09:10D7`): clears the combat byte +$108^.+$14, then a nonzero +$108^.+$10 forces flight ("is forced to flee" through `ShowCharacterMessage`); a character with B84 above $7F compares `(B84 and $7F) * 2` (zeroed above $66, DS:6825) with the hit-point percentage lost and, a second time, DS:6E2F with `GameVars^[710]`: a failed check makes a monster of side 1 flee, and a character with Intelligence above 5 surrenders (`DropCombatant(Who, 4, 'Surrenders')`), the rest get the affects $4A and $4B removed.
- **Choosing a target** **[V]** (`ScoreTarget`, `ovl09:128D`): the score of a candidate is `Row[10] * Row[9]` of the candidate's `RaceRow` (DS:5582, 129 rows of 16 bytes over the loader's file buffer), plus eight times its HpMax and twice `Row[11]` when positive, plus `(Row[5] - 1) * 2` when bit 3 of `Row[14]` is set, plus 3 when `Row[1]` is at most 1; it is 0 when `Row[1]` plus the actor's byte +$100 is above 3, when the candidate's known-spell bytes $0C and $0B hold $84 and a low nibble unlike the actor's `ByteA0`, when byte $0B is $53 or byte 4 is set. `UseBestItem` keeps the highest score (`ovl09:1543`).
- **The AI's item step** **[V]** (`UseBestItem`, `ovl09:13CA`, called by `QuickTurn` every turn and by `AiTurn` before attacking): pays the two per-kind slot items (RaceRow[item type][1] off `Who^.ds100`), scores every carried item with `ScoreTarget(Who, item)` (the item's type indexes `RaceRow`) and keeps the best 'attack' item (`Row[14]` bit 3 or bit $10; score `Best`), the best other item (`Score2`) and the best type-1 item by `Plus + 1`. The item used is the attack pick when it beats half of `Score2` and `Row[14]` points at a slot item (bits 1 and $80 select the slots at +$F8 and +$FC), else the other pick. The slot-0 item (unless it is the pick or cursed), the slot-1 item (paying its `Row[1]` again) and the pick are used through `ovl19_e7` with `RecalcCombatValues` and `ovl13_e6`, and `ds100` above or below 2 chooses between the slot-1 item and the extra pick; a use ends the step through `DrawCharacterPanel`.
- **Stepping** **[V]** (`CanAffordStep`, `ovl09:0675`): attempt `Column` of the actor's step pattern turns the base direction by `StepTurnOffsets[+$108^.+$15, Column]` (DS:02AE, 7 rows of 5, rows 1 and 2 are drawn by `RollDice(1, 2)` at `ovl09:08CD`) modulo 8; `ProbeStep` looks at the cells, a tile of 0 reports off-map and returns, and the step is affordable when no combatant is in the way, the tile cost is below the moves left and the step's cost (tile cost times 2, times 3 on a diagonal; `Moves + 1` on `TileKept` without one of the affects $20, $1E, $6F, $7D) is at or below the moves left.
- **The AI's move step** **[V]** (`MoveStep`, `ovl09:07F2`): shows `Move/Attack, Move Left = Moves div 2` through `DrawTextAt(0, 24, 10, ...)` and lets `HandleCombatKey` interrupt (True ends the step). It gives up through `ovl09_fn_0F4F` when no half-move is left, the initiative is 0, or a magic-user (`ClassMask` 5) is not panicking (the byte past `TCombatant` at +$14). The direction comes from `ovl13_e18(Who, Combat^.Target)` while clear of panic, else from the party marker facing `PartyFacing` (+ 4 on the party side, mod 8) with a fresh `RollDice(1, 2)` step pattern (+$15). It tries pattern columns 1..5 through `CanAffordStep` (a panicking actor off the map ends through `ovl13_e5`), refuses a step back (`ds443C` = (Turn + 4) mod 8), advances the pattern when refused (`ds443D` counts) and may end the turn through `ovl13_e21` or `ovl09_fn_0F4F`. A step taken faces the actor (`SetCombatantIcon(Who, Turn, 0, 0)`), moves through `ovl13_e4` (or `ovl13_e3` once `Flag10D` is set past it) and `ApplyCloudTile`, an ended turn through `EndCombatTurn`.
- **Keys during the computer's turn** **[V]** (`HandleCombatKey`, `ovl09:0FC1`): Alt-M toggles Magic On/Off (DS:6E30), Space marks the character for quick combat, Alt-X asks `ovl13_e24`.
- **The AI's turn loop** **[V]** (`AiTurn`, `ovl09:0B3C`, returns 1 when the turn is over): clears the AI scratch (DS:443C/D/E), runs affect hook $0E, gives up at once when the initiative is 0, and loops: while the panic byte +$14 is set it keeps calling `MoveStep` until the moves run out or the initiative leaves 1..$13; then it attacks. The attack range is `RaceRow[Byte(SlotItems[0]^.ItemType)][12] - 1` (the item in slot 0 at +$CC, clamped to 1) and the remembered `Combat^.Target` is dropped when it is not dying (`Flag10D`) or is on the party side. A target within line of sight (`WalkLine`, step count halved) is attacked, else a random enemy of the `CollectEnemiesInRange(Who, Range)` scan (DS:6DE4), or `UseBestItem` chooses one when `IsRangedWeapon`/`2E46` and a 1-step scan agree. The attack runs `ovl13_e7` (ends the turn through `EndCombatTurn`), `ovl13_e11` and `ovl13_e12` with a second pointer filled by `ChooseAttackItem`; after 20 turns it gives up through `ovl09_fn_0F4F`.
- **Map corrections** **[V]**: the entries `06AA`..`0718` were inside `CanAffordStep`, `0893`..`0B34` inside `MoveStep`, `0B48`..`0B96` inside `AiTurn` and `1583`..`1758` inside `UseBestItem`; the compiler's boundaries removed all four sets (their `{@stub}` lines are gone too). `ovl09:0255` is not a unit-level routine but a nested routine of `SpellAccepted`, proven through the parent's match.

#### 5.5.1 The combat map view ovl31 **[V]** (`src/OVL31.PAS`, `make match UNIT=ovl31`: unit complete, 23 routines)

- **The map** is a block behind the far pointer `CombatMap` (`DS:6716`): a 7-byte header, then 25 rows of 50 tile ids (`+7 + 50 row + column`). Header `+2`/`+3` are the map cell shown at the top left of the 7x7 cell view, `+4` makes the cursor icon visible, `+5` is the cursor's footprint kind, `+6` is the tile gate ovl30's `WalkLine` reads (5.18). A view cell is drawn with `DrawCellPicture` at 3 times its column and row; the picture is byte `+3` of the 4-byte combat tile entry at `DS:2744` (`CombatTiles`, the same table ovl30 reads from `DS:2745`). Byte `+0` of the entry is a cost: `$FF` refuses a combatant, and when a footprint covers several tiles the one with the largest cost decides a step (`ProbeStep`); tile 0 (off the map) and tile `$1E` always win **[V]** (code; the table bytes give `$FF` or 1 for the costs and picture = tile id - 1).
- **Combatants** are numbered 1..n: `CombatantTable` (`DS:5F27`, 4 bytes each: X, Y, an unread byte, the footprint kind; entry 0's kind byte is n), `CombatantRecord` (`DS:65BD`, far pointers to their character records), their place in the view `CombatantViewCol/Row` (`DS:604B`, `DS:6093`) and the occupant map `CellOccupant` (`DS:60DB`, 50x25 bytes, rebuilt by `RebuildOccupancy`). The layout leaves room for 72 combatants **[I]** (the tables are packed back to back). A **footprint kind** (`Footprints`, `DS:2844`, four cell offsets per kind) is 1 for one cell, 2 for two cells one above the other, 3 for two side by side and 4 for a 2x2 square **[V]** (table bytes); `PlaceCombatant` takes it from bits 0..6 of the character record's byte `+$6C`, and the icon `DrawIcon` draws is the record's `+$BF` with the icon set at `+9` of the combat record the character points to at `+$108` (`TCombatant.IconSet`, the byte ovl08's MoveCharacter saves and restores around a move taken back) **[V]**. ovl08 and ovl31 share one combat record type, `TCombatant`.
- **The view and the cursor**: `ScrollViewTo` moves the window's centre one cell at a time until a cell is within a margin of it (columns 3..46, rows 3..21) and redraws all 49 cells; `MoveCombatCursor(X, Y, Margin, Dir)` steps by the direction tables `DirStepX`/`DirStepY` (direction 8 does not move), scrolls, redraws the combatants, repaints the old cell and draws the cursor (icon `$19`) on every cell of the cursor footprint. `ShowCursorOn` shows it on a combatant with that combatant's footprint **[V]**.
- **Death and bodies** (only in view mode 5, `ds49F3`): `RemoveCombatant` draws the picture `DS:5F1A` over the dying combatant's cells, calls the sound unit (`PlaySound(ds261E)`) and waits, and unless `NoBody` (`+$13` of its combat record, which also keeps ovl08's Bandage away) is set records a body (`BodyTable`, `DS:66DD`, 8 records of who, X, Y and the tile it covered; count `DS:6715`) and puts tile `$1F` on its cell (a `$1E` tile stays). `PlaceCombatant` with its Restore flag takes the body back and restores the tile. QUIRK `ovl31:0E41`: the check for an existing body record reads `BodyTable[ds70C7]`, a stray global (FreeSpriteList's loop counter), on every pass instead of the loop index **[V]** (code).
- `ovl31_e2` and `ovl31_e3` call `SetPaletteRegister` with (0, 8), (8, 0) and (0, 0), (8, 8) when `VideoAdapter` is 1; their purpose is **[?]**.

#### 5.5.2 The start of a battle ovl10 **[V]** (`src/OVL10.PAS`, `make match UNIT=ovl10`: unit complete, 16 routines at L2 and 7 proven nested)

- **Sequence** **[V]**: `StartBattle` (`ovl10:1E31`, entry 1, called by `RunCombat`) frees the picture animation and the HEAD/BODY sprites, then resets `HeadBankIndex` and `BodyBankIndex` to $FF. It prints `A battle begins...` on row 24, clears the round state (DS:6E30, DS:6DE3, `AttackRoll`, `BodyTable`, the lists DS:6DBB and DS:5D9A, word 819 of the second game word block), caps word 710 of that block at 100, then runs `CreateCombatMap`, discards waiting keys, prepares combatants, discards waiting keys, places them, and discards waiting keys again. It allocates the picture DS:6E36, puts the view origin 3 cells up and left of the first character of the party list, calls `DrawCombatScreen`, runs affect hook 8 for every character, calls `ovl13_e19` and sets view mode 5.
- **The map** **[V]**: `CreateCombatMap` loads the 24x24 sets `DungCom` (AreaViewKind 1, the 3D view) or `WildCom`, then `RandCom`, allocates the $4E9-byte `CombatMap` block, clears its cursor flag, sets its cursor kind to 1, clears the Head6 tile gate and builds it. The last `Load24x24Set` argument is not read (`ovl10:1244`). A **wilderness** map (`BuildWildernessMap`) starts all tile $17 (picture $16, the plain ground the scatterers look for), takes the area map block under the party (`AreaMap[VarMapY, VarMapX]`, the column moved by 13 or 26 for AreaViewKind 3 and 4) into `CombatBlock` (DS:465A), and `BlockTerrainFlags` maps that block code through a fixed range table to eight flag bits. A river (`PlaceRiver`, tiles $32/$33 one column right per row from a top column 34 - 5d4 moved left to the next column with (column + 2) mod 7 = 0; bridge tiles $34/$35 from the nested `PlaceBridge` on a d20 of 1 and always on the row after a bridge, or on one row of 7..15 when no bridge fell) appears on 35 or 75 in 100 (bits $20, $10), two-cell features (tile $24..$29, with $20..$23 above it for kinds 1..4) on up to 7 in 100 per ground cell (bits 2, 4, $40, 8; none for $80), single features from five cumulative chances out of 255 (tiles $2A..$2D, $2E..$31, $37..$39, $39..$3C, $3D..$41), and rare tiles $1A..$1D on d100 rolls of 98 and up (`ScatterRareTiles`). Bit $80 becomes bit 1 while game word 435 is $FF (the word ovl27 gates area blocks 8 and 9 with). A **dungeon** map (`BuildDungeonMap`, 0810) draws each area map cell within 6 columns and 2 rows of the party as a skewed block of the combat map, 6 columns right and 5 rows down per area column and row (cell (I, J) starts at column 6I + 5J + 21, row 5J + 10), from its west, north and east passages (`PassageKind`, 01AD: the OR of the nested `WallSideKind` of this side and of the neighbour's opposite side; a side is 1 a wall when `DoorKindAt` is 0, 0 open when `WallIdAt` is 0, else 3 a door; off the 16x16 map the east and west sides on the party's row (`PartyMapRow`) count as open, every other side as a wall).
- **Combatants** **[V]**: `PrepareCombatants` gives every character of the party list (DS:5D96, monsters included) a zeroed $16-byte `TCombatant` (`+$108`), sets `NoBody` for entries past the party size (word 830, `VarPartySize` of ovl05) and the starting icon set `FacingCombatDir[PartyFacing]` (DS:02F2: 7, 2, 3, 6; turned by 4 for side 1). A party-side `NoBody` member whose low-seven-bit B84 morale is 0 or greater than $66 becomes computer-run with B84 set to word 710 plus high-bit flag $80 [I]. `CheckMorale` (`ovl09:10D7`) reads `(B84 and $7F) * 2` as its morale threshold and zeroes values above $66. `PlaceAllCombatants` clears CombatantTable entries 1..255 even though the battle has at most 72 combatants (QUIRK `ovl10:0872`).
- **Placement** **[V]**: each side has an 11x6 grid in four groups (`PlacementCells`, DS:4440, 2 x 4 x 6 x 11 bytes), each group the column spans `PlacementShapes` (DS:0306) of the side's facing (group 1: shape 4). Side 0 stands at origin (0, 0) facing the party (`PartyFacing`), side 1 word 705 area map steps ahead facing back (`SideOriginCol/Row`, `SideFacing`, DS:4650..4657). Grid cell (C, R) of origin (X, Y) is combat map cell (C + 6X + 5Y + 22, R + 5Y + 10), the same skew as the dungeon blocks. `FindStartCell` walks rings of the grid from `RingStartCol/Row` (DS:02F6, DS:02FE), the first ring `FirstRingCells` long (half the side's count DS:6814/6815, rounded up), later ones 12, and falls back to groups 1..3 one area map step away in an open direction (`FacingWallDirs`, DS:02D2); `TryPlaceAt` takes a free grid cell whose map cell has no occupant and a passable tile (`ProbeStep`). QUIRK `ovl10:1434`: TryPlaceAt stores candidate X/Y before probing; a candidate rejected by ProbeStep leaves those attempted coordinates in CombatantTable[Index]. A character with `Flag10D` 0 is taken off again and leaves a body; one that finds no cell and has `NoBody` is cut out of the party list (`ovl16_e2`).
- **QUIRKs** **[V]**: `IsBeyondGrid` (`ovl10:1403`) answers True only when a cell is off the grid in both directions. `BlockTerrainFlags`' ordered case table (`ovl10:08AA..0B14`) has eight overlaps, with the first listed range winning: 3, 4 and 7 map to 3; $28, $29 and $2B map to 1; $7C maps to 8; and $F5 maps to $20. For a block code in no range, `Flags` is unassigned and the routine returns that unset byte (QUIRK `ovl10:0B68`).
- **Dungeon drawing** **[V]**: `BuildDungeonMap` (0810, matched with its five nested routines once the matcher proved a nested routine called only by a sibling, `push word ptr [bp+6]; push cs; call`, 82cbb26) reads `PassageKind` of the west, north and east sides of every cell and draws them through `SetDungeonCell` (0221: picture + 1 into `CombatMap^.Cells[5J + 10 + SubRow, 6I + 5J + 21 + SubCol]`, skipped off the 50x25 map). `DrawFloorAndWest` (02BA) fills sub-rows 2..4 of sub-columns 0..5 with picture $16 and draws a west wall as the diagonal 4, 3, $D down those rows or a west door as pictures 8 at (1, 2) and 0 at (5, 4); `DrawNorthSide` (0377) draws sub-columns 3..4 of sub-rows 0..1 as 5 over $A for a wall, else floor; `DrawNorthWestCorner` (040F, sub-columns 1..2) and `DrawNorthEastCorner` (0615, sub-columns 5..6) pick their four pictures in a `for K := 1 to 4` case from North, West or East and the far sides of the corner (`PassageKind` of the cell to the north and of the cell to the side; both open is an open corner), the compiler proof of every picture table. `PassageKind` and `PlaceRiver`, whose nested routines the parent calls itself, match since the nested comparison of `c7265b6`.
- **Map corrections** **[V]**: the map listed 32 routines; 10 of them (`06FF`, `07AA`, `0B2F`, `0B48`, `0BEE`, `1582`, `1758`, `1A1F`, `1A91`, `1B83`) are inside the 22 real ones.

### 5.6 Class statistics: ovl23 **[V]** (`src/OVL23.PAS`, `make match UNIT=ovl23`: unit complete)

Overlay 23 recomputes what a character draws from its eight class levels (`TCharacter.ClassLevels`, +$96..+$9D). Its four routines are called by ovl12, ovl16, ovl17 and ovl22.

- **`RecalcClassStats`** (`ovl23:0000`) **[V]**: over classes 0..7, `Thac0` (+$2D, cleared first) becomes the largest `ClassThac0Table[class, level]` (DS:3C7C, 11 bytes per class) and `HighestLevel` (+$73, signed) is raised to the highest level (never lowered there). Class 2 (fighter) sets `Attacks` (+$A1) to 3 above level 6, else 2. Class 0 (cleric) above level 1 copies `ClericSlotTable[level, 1..3]` (DS:40BD) into the cleric row of `SpellSlots` (+$B2..+$B4; `SpellSlots[class 0..1, level 1..3]`, +$B2..+$B7, ovl15 indexes both rows), adds the wisdom bonus (`AddWisdomBonusSpells`) and sets `KnownSpells[n]` (+$33..+$6A) to 1 for every row n of `SpellTable` (DS:320A, 16-byte rows, spells 1..$38) whose byte 0 is 0 and whose level (byte 1, signed) has a slot; entries are only ever set. Class 5 above level 1 copies `MageSlotTable[level, 1..3]` (DS:41D5) into the magic-user row of `SpellSlots` (+$B5..+$B7). Then `ComputeSavingThrows`, and `ComputeThiefSkills` when the class 6 level is above 0.
- **`AddWisdomBonusSpells`** (`ovl23:01AF`) **[V]**: one more level 1 slot at Wisdom 13 and at 14, level 2 at 15 and 16, level 3 at 17, each only for a level that already has a slot: the AD&D wisdom bonus spells, which is why +$B2..+$B4 are read as cleric slots **[I]**.
- **`ComputeSavingThrows`** (`ovl23:0255`) **[V]**: five bytes at +$6D start at 20 and take the minimum of `SavingThrowTable[class, level, n]` (DS:426E, 8 x 9 x 5 bytes) over the classes with a level: the five saving throws **[I]**.
- **`ComputeThiefSkills`** (`ovl23:0329`) **[V]**: eight bytes at +$77 are `ThiefSkillTable[thief level, n]` (DS:3CF4) plus the signed `ThiefRaceTable[Race, n]` (DS:3D3C), plus the signed `ThiefDexTable[Dexterity, n]` (DS:3D4F) for the first five; a negative race value larger than the base gives 0. Eight skills with a dexterity adjustment on five is the AD&D thief table **[I]**.
- **Class indices** **[I]**: 0 cleric and 2 fighter are confirmed elsewhere (5.5, 5.19); 5 magic-user and 6 thief follow from the tables they select here.
- **Idioms** **[V]**: a table indexed `T[row, column]` with several dimensions compiles to the last index into a register first, then each earlier index times its row size, accumulated in `di` (`mov di,ax; add di,cx; add di,bx`), with the table's base as the displacement; the same arithmetic written as one computed index of a flatter array accumulates in `ax` instead, which is what blocked the earlier drafts. A table whose columns count from 1 is addressed from the byte before it, so that byte is declared as its own global (`ds40BC`, `ds3CF3`, ...) to make the index base name the same thing in our layout. `with Table[i] do` on a global array element spills the element's far address (`add di,base; mov [t],di; mov [t+2],ds`) and reloads it with `les di` for every field. In `A + B` of two table elements the right operand is loaded first (`ovl23:03CD`).

### 5.8 Keyboard input and menus (observed in the oracle)

- Input is **INT 16h only** **[V]** (oracle: no INT 09h hook, ports 60h/64h never touched): Crt `KeyPressed` (`0A40:02FD`, AH=01h) and `ReadKey` (`0A40:030F`, AH=00h, an extended key returns 0 then the scan code on the next call).
- The resident unit res04 is the keyboard layer and the way out of the game **[V]** (`src/RES04.PAS`, `make match UNIT=res04`: unit complete):
  - `ReadGameKey` (`0899:0059`) is the `ReadKey` game code calls. Ctrl-S (`#19`), when `SoundMode` (`DS:5372`) is not 2, saves that byte in `SoundModeBeforePause` (`DS:5373`), calls `PlaySound` (`08AE:00DC`) with `ds2612` (`DS:2612`) and sets `SoundMode` to 2. A later Ctrl-S resumes only when `SoundMode` is already 2 and `SoundModeBeforePause` is in `[0, 1]` (`System_SetIn` at `0899:008B`): it copies the saved byte back and calls `SilenceSound` (`08AE:017B`). Any other second Ctrl-S does nothing. What 0 and 1 are is not shown here **[V]** (the bytes); reading the pair as a simple on/off switch was too strong. When `ParamStr(1) = 'STING'`, Ctrl-D (`#4`) toggles `DebugMode` (`DS:49F7`) and Ctrl-C (`#3`) quits through `QuitGame`: a developers' debug mode **[V]** (code), its effect **[?]**. Those tests use the first key. Then, unless that key is `#0` (the extended-key prefix), `while KeyPressed do Key := ReadKey` (`0899:00E4`) reads every key still waiting into `Key`, and the function returns that last key, not the first with the rest discarded **[V]**. The oracle's `key` script command therefore waits for the game to be idle.
  - The debug mode also shows traces: `ShowDebugTrace(Message: String40; Max, Current, Lost: Byte)` (overlay 33, matched as a whole) does nothing unless `DS:49F7` is set; then it clears the top text line (`ClearRect(0, 0, 39, 0)`: columns 0 to 39 of character row 0), shows the three numbers as `Max , Current , Lost` in colour 14, shows the message through `ShowMessageLine` (also colour 14, and it waits for a key, 5.15), and clears the line again **[V]**. Its only caller is `ovl12:2233` (the training and rewards unit), which passes the label `'max,cur,lost'` and a character's maximum, current and lost hit points (`hp_max` at +$32 of the character record, 4.2.5, and the bytes at +$11B and +$75), in that order.
  - `FlushKeyboard`, called before prompts (the code wheel, 5.12), is meant to flush the keyboard but returns at once: its first statement is `Exit` and the flush loop after it is dead code (QUIRK, `0899:010A`).
  - `DiscardWaitingKey` (`0899:0122`) calls `ReadGameKey` once when a key is waiting and throws the result away, so Ctrl-S and the STING keys still run. `ReadGameKey`'s drain can still consume keys past that one.
  - `QuitGame` (`0899:0000`) ends the program: it copies `SoundModeBeforePause` into `SoundMode` and calls `PlaySound(ds2612)`, the pause-path call, not `SilenceSound`. What that call does to the sound is not shown in this unit; the sound unit's proven stop is `08AE:13B1` (5.14) **[V]**. Then `Intr($10)` with AH=0 and AL = `SavedVideoMode` (`DS:4A1C`), through the `Registers` record at `DS:4A02`, and `Halt`. No writer of `SavedVideoMode` is in the decompiled units, so where that byte was saved is **[?]**.
- The menu unit is ovl25 (`src/OVL25.PAS`) **[V]** (`make match UNIT=ovl25`: `unit: complete`, 4682 bytes; GetMenuLine, CountMenuLines, ReadPromptChoice with its nested SplitPromptWords and DrawPromptWords, ClearPromptLine, ChooseFromList with its nine nested routines LastHeadingBefore, DrawListPage, FirstNonBlank, LastNonBlank, HighlightListLine, UnhighlightListLine, SkipHeadingLines, ScrollListPage and MoveListCursor, AskYesNo, NewMenuList, FreeMenuList and the empty initialisation part matched. Three of ChooseFromList's nested routines, FirstNonBlank, LastNonBlank and SkipHeadingLines, are called only by sibling nested routines, which pass their own static link, still the parent's frame (`push word ptr [bp+6]; push cs; call`, `ovl25:098D`, `09A2`, `0CB4`); the matcher proves such a callee from the proven sibling since commit 82cbb26). The pieces:
  - **The prompt line** `ReadPromptChoice` (`ovl25:03BD`) draws a title in column 0 of text row 24 and a row of words after it (`"Heal Exit"`, `"Yes No"`). Its nested `SplitPromptWords` (`ovl25:00CB`) cuts the words at every capital letter or digit (the set `['0'..'9','A'..'Z']` at `ovl25:00AB`), assuming one separator, up to 20 words; `DrawPromptWords` (`ovl25:01DA`) draws them a character at a time through `DrawGlyph`, capitals and the chosen word (`PromptWordChoice`, `DS:6B2B`, kept between calls) in the hot colour, the rest in the word colour. Keys: `,` and `.` step the chosen word with wrap-around; a capital or digit that begins a word chooses it and is returned (after `UpCase`); Space returns `' '`; Enter returns #13 only when one of the two colours is nonzero; Escape returns #0. An extended key (ReadGameKey's #0 prefix) is read and dropped unless the caller passes `ExtKeys`; then its scan letter is returned with the var `ExtKey` set to 1, and the keypad digits 1..9 are turned into the scan letters of the keys they carry (`'OPQK MGHI'`, `KeypadScanLetters`, `DS:288C`; `'\'` gives `'7'`). On return `ExtKey` is copied into `LastPromptExtKey` (`DS:6B2C`) and game variable 511 is cleared **[V]** (code).
  - While it waits, the prompt **animates the picture** of the sprite list at `DS:6ABE` (`PictureAnimation`: a count byte, the current frame, then 8-byte frames of a Longint delay and a sprite pointer, the same bytes `LoadSpriteList` fills): it draws the current frame at column 3, row 3 (`DrawSprite`) and steps to the next after `Delay * 10` GameClock hundredths, that is `Delay` tenths of a second, when the caller passes `Animate` or game variable 511 is nonzero (then it also steps every pass). A Longint `PromptTimeout` (`DS:6B2E`) above 0 makes the prompt return `PromptTimeoutKey` (`DS:6B32`) after that many hundredths, counted from the last animation frame (QUIRK `ovl25:0530`) **[V]** (code); who sets the timeout is **[?]**.
  - **The list menu** `ChooseFromList` (`ovl25:0D9A`) shows a list of 46-byte menu lines (`NewMenuList`/`FreeMenuList`, the Text, Flag29 and Next part of `TMenuLine`) in a window; a line with `Flag29` set is a heading, drawn in the first colour and skipped by the highlight. The first shown line is `ListMenuTop` (`DS:6B29`, kept between calls). The prompt is the caller's words plus `" Next"`/`" Prev"` when the list goes on below or above the page and `" Exit"` when asked; End and Home (scan letters `O`, `G`) move the highlight down and up inside the page, PgDn/PgUp and the words Next/Prev turn the page, Escape, `E` and #0 return #0, and any other key returns itself with the highlighted line in `Selected` and its 0-based number in `Choice` **[V]** (code; the End/Home behaviour matches the oracle's character creation lists). The arrow keys have no effect in these lists **[V]** (oracle: UP/DOWN/LEFT/RIGHT/TAB/SPACE leave the screen unchanged): `ChooseFromList` handles only the scan letters G, O, I, Q **[V]** (code, `ovl25:0FF4..102A`).
  - `AskYesNo` (`ovl25:10D1`) asks with `"Yes No"`, the highlight on No, until the key is Y or N; `ClearPromptLine` (`ovl25:06FB`) blanks row 24 **[V]**.
- Character creation flow **[V]** (one run of `tests/sessions/create-character.keys`): main menu (C) > race list > sex > class > alignment > rolled character sheet with "Keep this character? Yes No" > name prompt > "Head Body Keep" > icon editor ("Parts Color-1 Color-2 Size Exit") > "Is this icon OK? Yes No" > main menu. The game writes `SAVE\RAD.CHA` (285 bytes, the character record of 4.2.5) and `SAVE\CHARLIST.TXT` (`RAD`, CR LF) **[V]**; decoding `RAD.CHA` with `tools/re/records.py` gives the race, class, sex, age and six scores shown on the sheet (human 7, fighter 2, male 0, age 19, STR 15 INT 13 WIS 11 DEX 12 CON 16 CHA 12 in the pinned run).
- The title sequence is `ShowTitleScreen` (ShowTitleScreen, entry point called from the main program before the code wheel) **[V]** (decompiled and matched as a whole, `src/OVL01.PAS`): it backs up `GameDir` and clears it, loads the `title` picture (`LoadPicture`) and shows it (`ShowPicture`), waits (`WaitKeyOrTimeout(5)`), and, when the `F` flag (`DS:49D1`) is set, reloads, reshows, frees the title picture (`ReleasePicture`, `0464:2595`: it frees the pixel buffer at +$13 and the block, then stores nil in the pointer, no palette write), waits for a key or a tick deadline (`GameClock` + 500) and shows the credits (`ShowCredits`); with `F` clear it only restores `GameDir` and returns. `WaitKeyOrTimeout(Pause)` loops until the `GameClock` tick count passes its start plus 100 times `Pause`, or a key is waiting, then calls `FlushKeyboard`, which does nothing (QUIRK `0899:010A`) **[V]** (code).
- `ShowCredits` (ShowCredits) draws two empty windows and some thirty green/cyan/yellow name and role lines (`DrawWindow`, `DrawTextAt`) and waits the same way **[V]** (code).
- QUIRK ovl01:0729: the EGA-only palette animation inside the title wait is gated on a running sum: every pass of the wait loop adds `Random(4)` (0..3) to `Total` (ovl01:0721..0726, `add`/`adc` into a Longint), and when the sum passes 50000 the animation runs and the sum restarts from 0 (ovl01:073E..0743) **[V]** (code). How many passes the loop makes before its 500-tick deadline depends on the CPU speed, so whether the animation fires does too: about 33,000 passes are needed at the mean of 1.5. In the oracle run it did not fire (about 30,000 `Random(4)` calls, a sum near 45,000, see below) **[V]**; on period hardware **[?]**. A port must keep the animation, not drop it as dead code.
- The window unit is res09 **[V]** (decompiled and matched as a whole, `src/RES09.PAS`):
  `DrawWindow(LeftCol, TopRow, RightCol, BottomRow, FrameSet, TextColour, Text)` clears the
  rectangle (`ClearWindow`, `03F1:0137`), draws one frame set around it (`DrawWindowFrame`,
  `03F1:0000`) and centres `Text` on `TopRow` in colour `TextColour` (`DrawTextAt`,
  skipped when `Text` is empty). Coordinates are `ShortInt` (sign-extended; the frame reaches
  one cell past the window, so -1 is legal), colours and the frame set are `Byte`, and `Text`
  is a `string[40]` value parameter, which the compiler copies to a hidden stack temporary on
  entry (`System_StrLCopy`, `0AF8:0B25`, limit 40) **[V]** (code).
  - `DrawWindowFrame` draws four corner tiles, the top/bottom edges and the left/right edges
    through `Put8x8Symbol`, with tile base `FrameSet * 3 + $114` (`$114` = 276, the value 5.2 already
    reports for the adventure screen frame) **[V]** (code). The last two arguments of `Put8x8Symbol`
    are 0 here; what they select is still open **[?]**.
  - `ClearWindow` fills the rectangle with 0 by video hardware, selected by the `VideoAdapter`
    global (`DS:4A1E`) **[V]** (code): 0 fills two text-scanline planes (absolute byte planes
    over `$B800`/`$BA00`, 80 bytes per scanline row, 4 scanlines per text row), 1 draws through
    `FillPlaneRect` twice, 2 fills four graphics planes (`$B800`/`$BA00`/`$BC00`/`$BE00`, 160
    bytes per row, 2 rows per text row). The values are proven: res08_init sets 1 for `E`,
    2 for `T` and 0 otherwise (`042B:019B..01F9`) **[V]**; what `FillPlaneRect` draws is still
    open **[?]**.
  - Callers **[V]** (`make packet UNIT=res09`): `DrawWindow` is called for dialogs and screens
    from ovl01, ovl02 (the code wheel), ovl03, ovl04, ovl05 and ovl06; the frame and clear
    routines are also called directly from ovl08, ovl13, ovl14, ovl15, ovl16, ovl19 and res12.

### 5.11 Saving and loading (in progress: ovl17 SaveLoad)

Unit ovl17 reads and writes the saved-game files of section 4.4: the per-character
`CHRDAT<slot><n>.SAV/.ITM/.SPC` (character 285, item 63, affect 9 bytes) and the roster
`charlist.txt`. Most of its routines are still stubs; the one matched so far is how a loaded
character joins the party.

- **Adding a party member** **[V]** (`AddPartyMember`, `ovl17:1446`, `make match UNIT=ovl17`): given a
  `TCharacter`, it clears its `CombatIcon` (`+$BF`) to $FF, links it at the tail of the party list
  `ds5D96` (or makes it the head when the list is empty, setting `SelectedCharacter` too), then marks
  which of the eight combat map icon numbers 0..7 are already held by a member and gives the new
  member the lowest free one (`SelectedCharacter^.CombatIcon`). Finally it counts the member in the
  party size word (`ds49D6^[VarPartySize]`, word 830) and recalculates its class statistics
  (`RecalcClassStats`, ovl23). So every party member carries a distinct combat icon 0..7, and the
  party list `ds5D96` is the single list the combat and camp units walk **[V]** (5.5, 5.20).

**Boundary note** **[V]** (`make packet UNIT=ovl17`): the map splits several ovl17 routines into
mid-instruction entries (`ovl17_fn_0818/084A/0865` inside `ovl17_e4`, `ovl17_fn_0B48` inside
`ovl17_e5`, `ovl17_fn_0F99` inside `ovl17_e6`, `ovl17_fn_0AE5` a literal pool). Each real routine has
one `push bp; mov bp, sp` prologue and one `retf`; the phantom entries share the parent frame. Scan
for the real prologues before drafting, and let `make match WRITE=1` retire the phantom map entries.

### 5.12 Copy protection: the code wheel

- The check is `CheckCodeWheel` (`ovl02:00FD`, entry point of overlay 2, matched as a whole: `src/OVL02.PAS`, `make match UNIT=ovl02`: unit complete) **[V]**. At most three times it picks `r = Random(13)` (`System_Random`, `0AF8:11C0`), draws two rune glyphs and a path pattern from a table at the very start of DGROUP (`DS:0000`, 13 records of 21 bytes, the `TCodeWheelEntry` type in `src/POOLVARS.PAS`), calls the keyboard flush `res04:0104` (which does nothing, 5.8) and asks "INPUT THE CODE WORD:" **[V]**. The question window is drawn by `DrawWindow(1, 1, $26, $16, 0, 0, '')` and the instructions, the runes and the path by `DrawTextAt`, `DrawGlyph` (the runes as font characters at the four corners of a small grid) and one concatenation of five spaces with the record path **[V]** (code).
- Record layout **[V]** (`start-unpack.exe` image at `0C7C0h`, and the lcalls in `ovl02:01A2..02FD`): `+02` Pascal string[6] with the answer; `+09`, `+0A`, `+0B` glyph indices, each drawn as character `index + 40h` in the game's font (the two rune pictures the prompt asks to match, then a third); `+0C` a fourth index drawn only when it is not FFh; `+0D` Pascal string with the path pattern drawn under the runes (`- - - -`, `-..-..-`, `.......`).
- The 13 answers, in record order **[V]**: BEWARE, ZOMBIE, NOTNOW, COPPER, DRAGON, EFREET, FRIEND, JUNGLE, KNIGHT, SAVIOR, TEMPLE, VULCAN, WYVERN. The typed word is compared with `System_StrCompare` (`0AF8:0C10`, flags in ZF) after truncating the function result of `ReadInputLine` (the line reader of res06) to 40 characters; the failure message is "Sorry, that's incorrect." (`ovl02:00E4`) through `FlashMessageLine`; after the third failure `res04:0000` ends the program **[V]**.
- The line reader `ReadInputLine` is a string function: TP 6.0 passes the caller result pointer as the first (deepest) argument and the callee `retf 8` pops only the prompt and the two numbers, leaving the result pointer for the caller to consume (here: the truncating assignment `Answer := ReadInputLine('INPUT THE CODE WORD: ', 13, 6)`, `0AF8:0B25` with max 40) **[V]** (the frames: `retf 8` = 8 bytes of parameters, the observed 12 pushed).
- Which question appears depends on `RandSeed`, which comes from the clock, so it varies from run to run on real hardware. The oracle's virtual clock makes it repeat; its `wheel` script command reads the answer from the table by watching that `Random(13)` call (`tools/oracle/protection.py`) and types it, leaving the game's own check untouched.

### 5.13 Random numbers

- The generator is Turbo Pascal 6.0's, in System at `0AF8:120F` (step), `0AF8:11C0` (`Random(range)`) and `0AF8:11D6` (`Random` real) **[V]** (code read; every logged call of the oracle satisfies the formulas below, and the logged results equal `AX` at the return of `Random(range)` for the first 300 calls, `tests/unit/test_oracle.py`).
  - `RandSeed` (DS:4428, low word first) `:= RandSeed * 08088405h + 1` modulo 2^32.
  - `Random(range) = hi16(RandSeed) mod range`, except the step runs first: with `range` 0 the seed still advances and the result is 0 **[V]** (isolated differential fuzz of `0AF8:11C0`, P3 spike; the earlier wording did not say the step runs). This is TP 6's `div`, not the multiply-and-shift of TP 7, which matters for anyone lifting a routine that compares sequences.
- `Randomize` is `0AF8:1247`: `INT 21h AH=2Ch`, then `RandSeed := DX:CX` (seconds and hundredths in the high word, hours and minutes in the low word) **[V]**. The game calls it once, during the title screens, about 16.6 million instructions after start (`RandSeed` is written only there in the first 80 million instructions), so everything the game decides at random is a function of the clock at that moment and of the sequence of `Random` calls after it.
- The title sequence calls `Random(4)` from `ovl01:0721` over 30,000 times in its first 80 million instructions **[V]**, so the number of calls before the wheel question depends on how long the title screens ran. A run is reproducible only if both the seed and the timing of those screens are reproducible (`clock` script command and `--trace rng`, appendix C).

### 5.14 Time, input and sound hooks

What the game takes from the outside world, found by `make timing-scan` and by reading the routines (Capstone dumps of the addresses below). Basis of the platform layer of the C translation (`src/platform/platform.h` on branch `track-c-hybrid`).

- **Keyboard** **[V]**: Crt `KeyPressed` is `0A40:02FD` (`INT 16h AH=1`, ZF; a pending extended scan code is kept in `DS:8501`); `ReadKey` is `0A40:030F` (`INT 16h AH=0`, returns the scan code of an extended key on the second call, maps a zero scan code to Ctrl-C `3`) and then runs `0A40:0143` (when `CheckBreak` is on: drains the keyboard buffer in a loop that ends when it is empty, writes `^C` and raises `INT 23h`). `KeyPressed` was called 508,736 times in the two recorded sessions: menus and prompts poll it.
- **Time of day and date** **[V]**: Dos `GetTime` is `0A32:00A2` (`INT 21h AH=2Ch`, also what `Randomize` reads, 5.13) and `GetDate` is `0A32:006C` (`AH=2Ah`).
- **Delay** **[V]**: `Delay(ms)` is `0A40:029C`: a counted loop (`0A40:02BD`, `loope` against a byte that never changes) repeated `ms` times with a loop count calibrated at start up in `DS:84FC`. The calibration is Crt's initialisation, `0A40:002E` **[V]**: it waits for the BIOS tick count at `0040:006C` to change, then counts loop iterations until it changes again and divides by 55 (ms per tick). So `DS:84FC` depends on the emulated CPU speed and is not game state. `0A40:002E` is the only routine that reads the BIOS tick counter, and it does so through a register (`mov di,6Ch`; `es:[di]`).
- **Timer** **[V]**: the sound unit (res03) starts at `08AE:137C`: it saves INT 08h (`AH=35h`), installs its handler `08AE:13EA` (`AH=25h`) and writes `OUT 43h,B6h` and divisor `13B1h` = 5041 to port 40h, which is **13 times the BIOS rate, 236.7 Hz** (1,193,182 / 5041; the boot sequence note used to say about 297 Hz, which was wrong). The handler runs the voice stepper `08AE:1477` and a countdown at `DS:01DB` (a time-out that resets the video mode and terminates with exit code 255), and only every 13th call chains to the saved BIOS handler (`DS:01D7` counts 13 down), which keeps the BIOS clock at 18.2 Hz. Stop is `08AE:13B1`: restores the vector, divisor `FFFFh`, speaker off, Tandy chip silenced. The game's timer interrupt writes no DGROUP global outside its own stack frames (dynamic pass, `boot-title` and `create-character`).
- **Sound** **[V]**: the PC speaker is driven from PIT channel 2 (`OUT 42h` reload, `IN/OUT 61h` low two bits): `Crt.Sound(hz)` `0A40:02C9` (divisor = 1,193,181 / hz, gate 3), `Crt.NoSound` `0A40:02F6`, and the voice stepper `08AE:1477` over four voice records (stride 30h at `CS:022D`, see the next item). The Tandy 3-voice chip is written through port `C0h` (silencing: 9Fh, BFh, DFh, FFh).
- **The sound unit res03** **[V]** (`src/RES03.PAS`, `make match UNIT=res03`: the five Pascal routines at L2). Its Pascal part is a front end: `PlaySound(Sound)` (`08AE:00DC`; 0 sets both devices to tune 0 and the output flag off, 1 turns the output flag on, `FFh` sets both devices to tune 0, any other n starts tune n - 1 on the device `SoundMode` selects: 1 PC speaker through `SetSpeakerTune` `08AE:1742`, 0 Tandy through `SetTandyTune` `08AE:17AE`; nothing when `SoundMode` is 2, silent), `SilenceSound` (`08AE:017B`, runs the driver once to set both devices to tune 0) and `SetSoundDriverIdle(Idle)` (`08AE:01A5`: 0 starts the timer driver for good, so tunes play in the background; nonzero stops it, and `PlaySound` then starts it, waits 0.1 s with `WaitHundredths(10)` and stops it around each sound; the value is kept in `SoundDriverIdle`, `DS:5374`). `WaitHundredths` busy-waits on `TimeInHundredths` (`08AE:0000`, `GetTime` in hundredths since midnight; QUIRK `08AE:0033`: the minutes and seconds terms are Word products, so the minutes term wraps above 10 minutes). The rest of the segment, `08AE:01D7` to the end, is a hand-written assembly driver linked after the empty initialisation part (an external `.OBJ`: `8B EC` prologues, DS loaded with the unit's own segment `08AE`, so the voice records `022Dh` (speaker) and `03C7h` (Tandy), the tune tables `055Fh` and `0607h`, the output flag `020Dh` and the counters `01D7h` and `01DBh` above are offsets in the code segment, not DGROUP). That part cannot be written in Turbo Pascal without raw bytes and is held (escalated by dec-14, 2026-10-12); the map entries `08AE:09E3` to `08AE:1221` are data inside it, not routines.
- **Entropy**: `ovl22:0B89` reads `IN AL,40h` (low byte of the PIT channel 0 counter) and uses it as a random number **[V]**, outside `Random`. (An earlier revision also credited `ovl14:0B48` with a PIT read and mod 8 **[V]**; that was a misaligned disassembly of a bogus map entry: the `E4 40` bytes are the tail of `xor ah,ah` plus `inc ax` in the middle of `HandleWildernessKeys`, which cycles `(DS:6AAF + 2) mod 8`, and aligned disassembly shows no port I/O anywhere in ovl14. Corrected with `make match UNIT=ovl14`, 2026-10-12.) The oracle returns a deterministic function of the instruction count for port 40h.
- **No retrace polling** **[V]**: no routine reads port 3DAh. No routine reads the BIOS tick counter other than `0A40:002E`.
- **Not a wait** **[I]**: `0AF8:01A5` and `0AF8:01E7` write characters with `INT 21h AH=06h` (output, DL is the character); an early scan counted them as keyboard polls.

### 5.15 Messages and running out of memory **[V]** (`src/RES06.PAS`, `src/OVL00.PAS`, matched)

- `ShowMessageLine(Color, Text)` shows a one-line message on row 24: it clears 40 columns of that row (`ClearTextCells(0, 24, 0, 40)`), draws the text in the given colour (`DrawTextAt(0, 24, Color, Text)`) and waits for a key through `ReadGameKey`. The text is a `string[40]`. Twelve routines call it, in overlays 0, 3, 5, 7, 17 and 33 and in res06 itself (`make packet FN=ShowMessageLine`).
- `GameClock` (`GameClock`, `0709:0C3F`) is the game's time of day in hundredths of a second: it reads `GetTime` and returns `Hour * 360000 + Minute * 6000 + Second * 100 + Sec100`. `Hour * 360000` is a LongInt multiply (the `System` runtime), but `Minute * 6000` and `Second * 100` are Word multiplies whose high word is dropped (QUIRK `0709:0C75`, `0709:0C85`, so a minute above 10 loses its carry). `WaitKeyOrTimeout`, `ShowTitleScreen`, `AnimateFinalPicture` and `ReadPromptChoice` call it.
- Overlay 0 is the heap error handler: its initialisation sets `HeapError := @HeapErrorHandler`, so Turbo Pascal calls `HeapErrorHandler(Size)` when `New` or `GetMem` cannot get `Size` bytes. A zero size returns at once with an unassigned result (`jbe ovl00:004C` to `ovl00:00A3`). For a non-zero size it shows "WARNING: Insufficient Memory" in colour 14 (yellow); if the Boolean `DS:49D0` is set it calls `ovl17_e9` (the save and load unit) and repeats until `DS:557D` says to stop, otherwise it shows "Insufficient Memory. Exiting Program". Then it always ends the program (`QuitGame`), so that path never returns. The function result is never assigned on any path (QUIRK `ovl00:00A3`).
- `DrawGlyph(Col, Row, Color, Count, Glyph, Cook)` (`0709:01DF`) **[V]** draws Count copies of a font glyph from cell Col of text row Row (cells are 8 by 8 pixels, 40 by 25). The font is the `GameFont` block, 8 bytes per glyph indexed `[Glyph, PixelRow]`; Cook nonzero maps the character through `UpCase` into 0..63 (the text glyph set). Exits for a cell past column 39 or row 24, a nil font, or Count 0. By `VideoAdapter`: 0 builds 16-bit pixel rows from `GlyphPixelMasks` and `GlyphColorPatterns` (colour through the four-colour map `DS:25D5`) into the two text-scanline planes `$B800`/`$BA00`; 1 writes each font byte to the two EGA pages per plane through the Sequencer Map Mask (`EgaPlaneMasks`, port `3C5h`), 0 where the colour lacks the plane; 2 builds two colour nibbles per pixel pair into the four graphics planes `$B800..$BE00`.
- `ClearTextCells(Col, Row, Color, Count)` (`0709:05EB`) draws Count spaces; `DrawTextAt(Col, Row, Color, Text)` (`0709:0626`) draws a string cooked glyph by glyph (QUIRK `0709:0647`: the row is tested against 39, not 24, so DrawGlyph does the real row check). `FlashMessageLine(Text, Color)` (`0709:0D68`) is `ShowMessageLine` without the key wait: clear row 24, draw, `DelayByGameSpeed`, clear. `ReadInputLine(Prompt, Color, MaxLen)` (`0709:09E3`) is the line editor of the bottom row: characters `' '..'z'` up to MaxLen echoed in white, Backspace, Enter or Esc to end (Esc returns the text too), result upper-cased `string[40]`. `ReadNumber(Prompt, Color)` (`0709:0B66`) repeats it with 6 characters until `Val` accepts a number in 0..65536 and returns it as a Word (QUIRK `0709:0BBF`: 65536 passes and becomes 0). All **[V]** (`make match UNIT=res06`).
- `ShowPagedText(Left, Top, Right, Bottom, Color, ClearFirst, Text)` (`0709:0768`) **[V]** is the word-wrapping pager behind the shop, temple, treasure and battle-end text: it keeps a cursor in the globals `GlyphCol`/`GlyphRow` (`DS:5E24`/`DS:5E25`, reset to (Left, Top) when outside the rectangle or when ClearFirst clears it through `ClearRect`), scans Text word by word (leading `BreakChars` skipped, the run stops at a blank or a break character, trailing break characters absorbed from `Text[J + 1]`), draws a word through its nested `DrawTextRun` (`0709:06A7`: one `DrawGlyph` per character, `Delay(GameSpeed * 10)` after each while `DS:4A00` is set) when it still fits before Right, else starts a new line with its nested `SkipSpaces` (`0709:0714`); past Bottom with text left it shows "Press any key to continue" through `ShowMessageLine(13, ...)`, flushes the keyboard, clears the rectangle and continues from the top. QUIRK `0709:0919`: the equal-to-Right-and-blank branch is dead (the outer test already took greater than Right). Coordinates past column 39 or row 24 (Bottom is tested against 39 too) and empty text return at once; `Width` is computed and never read; the frame has an unused byte local. Matched with both nested routines (`make match UNIT=res06`: `NESTED` lines).
- TP 6.0 idioms proven while lifting `DrawGlyph` **[V]** (`make tpc` probes `scratch/Q*.PAS` in the res06 worktree, then `make match`): `0AF8:182A` is `System.UpCase`; an `or` chain with a far exit flattens so every operand but the last jumps on true to one shared exit jump (Q55); a `for` loop emits init, a jump over the first increment, increment-first body, and a short `jne` back for near bodies versus `je` plus a near `jmp` for far bodies (Q39); a byte test `(x and Mask) > 0` compiles to `or al,al; jbe`, where `<> 0` gives `je`; indexing a 2-D byte array through a pointer loads the column into DX first and adds it after the row (`les di; add di,ax; add di,dx`); `Inc(W, n)` on a word local is one `add [bp-k],n`; `Color shl 4` on a byte loads the count with `mov cx,4`; comparing a Byte parameter with `< 0` keeps the never-true `jb` (ClearTextCells), while `x in [0..n]` would put a set constant in the literal pool.

### 5.16 The 3D sprite unit ovl28 **[V]** (`src/OVL28.PAS`, `make match UNIT=ovl28`: all 10 routines at L2, complete)

Overlay 28 draws the 8x8 sprites of the 3D view and the HEAD/BODY strip of the character screen.
The parts proven so far:

- `DrawSprite(Col, Row: Integer; Direct: Byte; Sprite: Pointer)` (`ovl28:0000`): a nil sprite draws
  nothing; with `Direct` set it blits the sprite one column and one row up and left (`Col - 1`,
  `Row - 1`) onto the screen buffer
  `DS:4A20` through `res07_fn_0D71` (mode 0, flag 1) and steps the display (`FlushPictureChanges`);
  otherwise it copies the sprite into the staging buffer with `ShowPicture`.
- `DrawHeadSprite` and `DrawBodySprite` (`ovl28:0050`, `ovl28:0070`): draw a sprite at (column,
  row) and at (column, row + 5); `ShowHeadBodySprites` (`ovl28:0697`) uses them to draw the HEAD
  sprite `DS:6B01`, and with its `WithBody` argument also the BODY sprite `DS:6B06`, through the
  staging buffer (both helpers pass `Direct` 0; neither path draws straight to the screen buffer).
- `LoadHeadBodySprites` (`ovl28:05D9`) loads the HEAD and BODY banks of the picture number
  `TileSet` (`DS:5376`) from the files `HEAD<number>` and `BODY<number>` through `LoadPicture` into
  `DS:6B01` and `DS:6B06` (recording the loaded number in `DS:6B00` and `DS:6B05`, `$FF` = none).
- `FreeSpriteList` (`ovl28:048F`) frees every loaded sprite picture of a sprite list (through
  `ReleasePicture`) and zeroes the list, clears the picture name `DS:6B0A` and sets the current bank
  `DS:6B1C` to `$FF` (not 0).
- The sprite list is a `$42`-byte record: a count byte at +0, a flag at +1, and seven slots of 8
  bytes from +2, each holding 4 bytes copied from the picture data and the picture pointer at +4
  (the `TSpriteList` type of `src/OVL28.PAS`) **[V]** (`make match UNIT=ovl28`).
- Each picture is one record of `AllocatePicture` (the same one `ovl32`'s `DrawIcon` copies): height
  and width at +0 and +2 (the record fields `Height` and `WidthCols`, after `ovl32`; `AllocatePicture`
  declares the two parameters `Height` and `Width` and whitepaper 3.2.2 calls them `Cols` and
  `Rows`), item count at +8 (1 for a sprite), the pixel byte size at +$11 (height times width
  times 2, doubled on a non-zero `VideoAdapter`) and the pixel pointer at +$13; the sprite's base
  screen column and row sit at +4 and +6 (`TSpritePicture`) **[V]** (`make match UNIT=ovl28`;
  whitepaper 4.2.3, 5.13).

- `Show3DSprite` (`ovl28:0708`) shows slot 1..3 of a sprite list at the sprite's base column and row
  plus 2 through `res07_fn_0D71`; another slot restores the saved video mode (`RestoreVideoMode`,
  `SavedVideoMode`) and ends the game with the unit's range error string.
- `ShowHeadBodyWindow` (`ovl28:04F9`) draws the HEAD/BODY picture window (columns 28..38, rows 1..11)
  of the character record `DS:5D92` and shows the HEAD and BODY sprites of its two bank numbers
  (its two `Str` calls are computed and never read, QUIRK `ovl28:056C`).

- `LoadSpriteList(Name, Bank, Mode, List)` (`ovl28:00A2`) loads block `Bank` of `<Name><TileSet>.dax`
  into a sprite list, unless the same file and block are loaded already (`DS:6B0A`, `DS:6B1C`; the
  test ignores the `TileSet` digit). The
  block is a count byte (clamped to 4 for `PIC` block 1) followed per sprite by 4 bytes, the height
  and width words, the X and Y words, one skipped byte, 8 palette bytes and `Row + 1` bytes of pixel
  data (`Row` is the picture's byte size minus one, twice the byte size on `VideoAdapter` 0). A
  sprite is loaded only while `MaxAvail` is at least 3900, and the count becomes the number loaded.
  When it is below 3900 the jump to the loop end also skips the offset advance, so every later
  sprite is read from the middle of the skipped one and the loaded slots keep a nil gap under
  `Count` (QUIRK `ovl28:0269`); the final `FreeMem(Prev, Row + 1)` frees with the last picture's
  `Row` (QUIRK `ovl28:046C`). `PIC` and
  `FINAL` pictures after the first are stored xored with the first one's data, which the loader
  undoes before decoding (`UnpackPicturePixels`); bit 0 of `Mode` adds a pass through `res07_fn_1E5C` on
  non-zero video adapters **[V]** (matched). Callers: `ovl03`, `ShowEncounterPicture`, `ovl18` (FINAL) and
  `RedrawView`.

---

### 5.17 The ending narrative and door animation ovl18 **[V]** (`src/OVL18.PAS`, `make match UNIT=ovl18`: complete, every routine at L2)

Overlay 18 (PoolNarrative) plays the game's ending and animates the area view doors:

- `ShowEndingNarrative` (`ovl18:02A4`, called by `ovl03:2E10`) shows the dragon's death and the
  Tyranthraxus and Bane speech as lines of text at column 1, rows $11 onwards, colour 10
  (`DrawTextAt(1, Row, 10, Text)`) and loads and draws the `FINAL<number>` pictures (the number is
  `Str(TileSet)` in DS:4713) through `LoadPicture` and `res07_fn_0D71`, running the animation
  `AnimateFinalPicture(3, 5, 2, x)`, `(3, 1, 7, x)` and `(3, 1, 8, 1)` between the speech blocks. It saves
  the view mode DS:49F3 in DS:4712, sets 7 and restores it.
- `AnimateAreaDoors` (`ovl18:06B3`, called by `ovl03:31B4` and `ovl17:1602`) draws or clears the doors
  of the area view: it calls `res07_fn_1E5C(@ds091D, @ds092D, code, 1, bank)` for each entry of
  DS:0900 (0..10) and `(@ds091D, @ds093D, code, 1, bank)` for DS:090B (0..17), where bit 7 of a code
  selects the second SQRPACI bank DS:5E56 instead of DS:5E52 and the low 7 bits are the picture
  number, and it steps the view with `DrawAreaView(DS:094D[I], DS:095F[I])` over 9 steps.

- `AnimateFinalPicture` (`ovl18:0006`, called by `ShowEndingNarrative`) **[V]** (`make match
  UNIT=ovl18 FN=AnimateFinalPicture`) loads the `FINAL<TileSet>` frames of one bank through
  `LoadSpriteList('FINAL', Bank, 2, List)` and shows them `Cycles` times: each frame is drawn with
  `DrawSprite(Col, Row, 1, sprite)` and held for that slot's 4 data bytes, read as a LongInt
  delay scaled by (`GameSpeed` + 3) ticks of the `GameClock` timer, before stepping to the next
  frame. The frame cursor is the sprite list's `Flag` field (the loader sets it to 1, `ovl28:01D6`);
  `Count` is compared as a byte here (`ovl18:00E1` uses a byte `cmp`/`jbe`) although `TSpriteList`
  declares it `ShortInt`, so the source casts it with `Byte()`.

---

### 5.18 The line drawing unit ovl30 **[V]** (`src/OVL30.PAS`, `make match UNIT=ovl30`: unit complete)

Overlay 30 draws lines and sorts:

- `SignOf(N)` (`ovl30:0000`) returns -1, 1 or 0 for the sign of N. Also called from ovl22 and res12.
- `SortTable` (`ovl30:002E`) sorts the 3-byte record table DS:6718 in place (element 0 holds the
  count in its Val field): for every I < J it swaps the records when Key[J] < Key[I], or when the
  keys are equal and Val[J] < Val[I] and Val[J] mod 2 <= Val[I] mod 2.
- `SetupLine(Line)` (`ovl30:01A0`) fills the line drawing state (the `TLineState` type of
  `src/POOLVARS.PAS`: two endpoints, the three Bresenham steps, the current position and the x and y
  step directions) from the two endpoints.
- `StepLine(Line)` (`ovl30:02CC`) steps the line one pixel: when `DX > DY` it moves `X` towards `X2`
  and, while `D1 >= 0`, `Y` towards `Y2` by `SY`, else it moves `Y` towards `Y2` and, while
  `D1 >= 0`, `X` towards `X2` by `SX`; the smaller axis moves on the sign of `D1`, `First` advances
  by 2 or 3, and the direction taken picks the pattern byte from the 3x3 table `DS:25C0` at
  `[SY + 1, SX + 1]`. It returns whether it stepped. `DS:25C0` is a 2D array (the original scales
  the row by 3 with DI), and `TLineState.X,Y` are `Integer` like the coordinates (the original
  compares `X` to `X2` with a word `cmp`).

- `InDirArc(FromX, FromY, ToX, ToY, Dir)` (`ovl30:057B`) tests whether the point (ToX, ToY)
  lies in the 90-degree arc facing compass direction Dir from (FromX, FromY): 0 is north then
  clockwise to 7, 8 (and the $FF default) is omni and always true. Points outside X 0..49 or Y
  0..24 fail. The base point steps once towards Dir through the tables `DS:2736`/`DS:273F`
  (verified bytes: compass vectors (0,-1), (1,-1), (1,0), (1,1), (0,1), (-1,1), (-1,0), (-1,-1),
  (0,0)), and each direction's `case` body checks the two half-planes of its wedge, each shared
  with the neighbouring direction (direction 0 is `(ToX >= BaseX) and (ToY <= BaseX - ToX + BaseY)`
  or `(ToX <= BaseX) and (ToY <= ToX - BaseX + BaseY)`). `ovl22_e5` loops Dir upward to aim at a
  point. Compiler notes: the direction parameter is `Byte` (the table index zero-extends), the
  coordinates are `ShortInt`, and a `case` over 0..8 keeps the selector in AL with chained
  `cmp`/`jne` (proven by `make tpc` probes in `scratch/Q1.PAS`, `scratch/Q2.PAS`).

- `WalkLine(X1, Y1, Ex, Ey, StepCount, Map)` (`ovl30:0422`) walks a Bresenham line from
  (X1, Y1) towards (Ex, Ey) over the map rows and reports the steps in StepCount: it sets up
  Line from the endpoints and a horizontal Bound line from the start tile's table height (the
  `DS:2745` tile table, 4 bytes per tile id), then steps Bound and Line together, stopping with
  False at a blocking tile or past `2 * StepCount + 1` steps, else with True. The map is an
  array of 50-byte rows (7 header bytes, 43 tile cells); the tile gate needs row 0's header
  byte 6 clear and the current tile's block height above Bound.Y. Ex, Ey and StepCount carry
  the end point and the steps used. Called by ovl09_fn_0B96, ovl12_e70, ovl13_fn_2DFA and
  `ScanTargets`. Compiler notes: a far 2D subscript keeps a nonzero low bound as a memory
  displacement (`Map^[Y].Cells[X]` gives two `add di` plus `[di+7]`), and `Result := False;
  Exit` jumps to the epilogue including the result fetch (proven by `make tpc` probes in
  `scratch/Q8.PAS` to `scratch/Q11.PAS`). This unblocks the `BLOCKED` note dec-5 left in
  `re/symbols.toml`.
- `ScanTargets(FromX, FromY, MaxSteps, Dir, Base, Map)` (`ovl30:0909`) scans the DS:5F27
  map entity table (records with a map position, an unknown byte and a kind byte; entry 0's
  kind holds the count) for records reachable from the search point: for each active record it
  tries the four neighbours of the base point against the four neighbours of the record
  (`FootprintCell` fills the neighbour offsets from a base value, invalid neighbours get -1), keeps
  the pairs in direction Dir's arc (`InDirArc`) that the line walk (`WalkLine`) crosses in the
  fewest steps, appends one record per hit (table index, step count, working direction) to the
  `DS:6718` sort table and sorts it. The stored direction is the requested Dir, or the first
  working one when Dir is 8. Called from combat and item aiming (`ovl22_e48`) and from ovl09,
  ovl13, ovl24 and res12. Compiler notes: a `for` over a variable bound
  snapshots it into a hidden temp slot (the `sub sp` covers it), and near/far jump selection
  follows rel8 reachability (proven by `make tpc` probes in `scratch/Q4.PAS` to `scratch/Q6.PAS`).
All seven routines are decompiled and matched.

---

### 5.19 The Temple **[V]** (`src/OVL04.PAS`, `make match UNIT=ovl04`: unit complete)

- **The shop menu** **[V]** (`VisitTemple`, `ovl04:0D09`): `Heal View Take Pool Share Appraise Exit`, or `Heal View Pool Appraise Exit` while `TreasureLeft` reports no pooled money. On entry it sets the view mode `DS:49F3` to 1, redraws the view (`RedrawView`), reshows the character (`DrawPartyRoster`), clears `PooledMoney` (28 bytes at `DS:67F4`, which `MoneyValueInGold` sums into a `LongInt`) and sets `MoneyInPool` (`DS:6DC0`) to 0. Exit with money left in the pool shows the priest's `As you leave a priest says, "Excuse me but you have left some money here"` and `Do you want to go back and retrieve your money?` (`AskMenu`) and leaves when that returns 1 (No: `AskMenu` returns the 0-based hotkey position of `'~Yes ~No'`), so Yes keeps the money in the Temple.
- **The services** **[V]** (`HealMenu`, `ovl04:09D7`, ten names from the `string[40]` table at `DS:011A`: the nine services plus `Exit` at entry 10, `DS:028B`): services act on `SelectedCharacter` (`DS:5D92`). CureBlindness, CureDisease, RaiseDead, NeutralizePoison, RemoveCurse and StoneToFlesh ask `cast cure anyway:` when their condition is absent; CureWounds is always offered and never asks (`ovl04:0401`). `ChargeForCure` shows `<service> will only cost <n> gold pieces.`, takes the price from the character's money (`CharacterMoneyValueInGold`, `SetCharacterGold`) or else from the pool (`MoneyValueInGold`, `SetPooledGold`), and says `Not enough money.` when neither covers it. QUIRK `ovl04:0177`, `ovl04:01C8`: `CharacterMoneyValueInGold` returns a `LongInt` but `Money` is a `Word` and `SetPooledGold(Amount: Word)` takes only the low word of the pooled `LongInt`, so money or a pool of 65536 or more is compared and rewritten modulo 65536 (the same truncations as ovl06's `BuyItems`).

  | Service | Price | Needed when | Effect |
  |---|---:|---|---|
  | Cure Blindness | 1000 | affect $21 | removes affect $21 |
  | Cure Disease | 1000 | one of the affects $1F $22 $2B $2C $32 $39 (`DS:0114`) | removes all six |
  | Cure Light / Serious / Critical Wounds | 100 / 350 / 600 | always offered | heals 1d8, 2d8+1, 3d8+3 (`RollDice`, `HealCharacter`) |
  | Neutralize Poison | 1000 | affect $37 | removes $37, $16, $0F |
  | Raise Dead | 5500 | status (+$10C) 1 or 6 | removes $20 and $37, status 0, constitution - 1, hit point loss (below) |
  | Remove Curse | 3500 | a cursed item (+$36 of an item in the list at +$C8) or affect $24 | hands the character to `ovl22_e9` (`DS:6C95`) |
  | Stone to Flesh | 2000 | status 7 | status 0 |

- **Raise Dead and constitution** **[V]** (`ovl04:05E1..072A`): after lowering constitution (+$14) by one, a character with constitution 14 or more loses `(hp_max - byte +$B1) div bonus` hit points, where bonus sums over the eight class levels at +$96 (signed bytes): constitution - 14 per fighter level (class index 2), 2 per other level above constitution 15, else 1. The thresholds apply to the reduced constitution; when bonus is 0 the hit-point loss is not divided. The loss is skipped when the constitution is 17 or more and the character has no fighter level. `Flag10D` (+$10D) is the combat-participation flag checked by `AwardExperience` (`ovl05:0355`); `Flag11B` (+$11B) is the current hit points [I] (HealCharacter adds up to HpMax, `ovl24:17B9`). Raise Dead and Stone to Flesh set both to 1, restoring one hit point [I].
- QUIRK `ovl04:0250`: every service routine clears a 256-byte string local it never reads. The map had listed 16 phantom routines inside this overlay (case arms, literal pools and the middle of instructions, e.g. `ovl04:0311`); the compiler shows eleven routines plus the initialisation, and `re/symbols.toml` no longer lists the phantoms.

### 5.20 The end of a battle: experience, hirelings and loot **[V]** (`src/OVL05.PAS`, `make match UNIT=ovl05`: unit complete)

Overlay 5 (`ovl05`, "TreasureShare") runs once a combat is over; its only entry `EndBattle` (`ovl05:1527`, e1) clears the outcome word (`ds49D6^[711]`) and `MonstersLooted`, sets the view mode `DS:49F3` to 6 and then:

- **The outcome** **[V]** (`SettleBattleOutcome`, `ovl05:04C9`): the party list `DS:5D96` still holds every combatant. Walks stop at the first combatant whose combat state has `NoBody` = 1 (an extra combatant that is not a party member). Status values: 0 okay, 1 dead, 3 fled, 4 unconscious, 5 dying. `PartyFled` (`DS:443B`) is set when a member fled; `PartyDestroyed` (`DS:49FF`) stays 1 unless a player-run member (Side 0, `B84` below $80) is okay, dead or fled (or word 742 is 1); `BattleWon` (`DS:84DA`) is set and `PartyFled` cleared as soon as a combatant is okay or dead (monsters included, so a battle with a dead monster is never "fled"). A won battle awards the experience. Afterwards fled members come back okay, dying ones become unconscious, unconscious ones with `Flag11B` become okay; a fled party sets the outcome word to $81 and drops every member that did not flee (`ovl16_e2`); a destroyed party drops everybody and the party size word 830 becomes 0. In a duel (`DuelMode`, `DS:84D4`) only the duelist (okay, `Flag10D` 1, not a monster) gets the experience.
- **Experience** **[V]** (`ComputeBattleExperience`, `ovl05:0000`; `AwardExperience`, `ovl05:0355`): every monster (Side 1) that did not flee gives `XpValue` (+$B8) plus `HpB1` times `XpPerHp` (+$BA), its seven money words (+$88..+$94) go into `PooledMoney` (`DS:67F4`, seven LongInts: the money block holds seven kinds, not five as 5.4 inferred) and its items into the loot list `DS:6810` (every valuable item; worthless ones only while fewer than 8 items were taken and on 1d10 at most 3; none when word 739 is 1). The pooled money then adds its value: kind 0 / 200, kind 1 / 20, kind 2 / 2, kind 3, kind 4 * 5, kind 5 * 250, kind 6 * 2200 (the AD&D copper, silver, electrum, gold and platinum rates, then gems and jewelry **[I]**), and every looted item before `DS:5D9A` adds 400 per point of `Plus`. The total is divided by the party size (word 830) less the members without `Flag10D` or dead (`NoExperienceCount`, `DS:84D5`): `BattleExperience` (`DS:84D6`). In a duel with word 742 set it is 100 times the selected character's highest level instead. Each member with `Flag10D` that is not dead adds it to `Experience` (+$AC): 10% more for a cleric (class 0), fighter (2), magic-user (5) or thief (6) whose prime requisite (Wisdom, Strength, Intelligence, Dexterity) is above 15, half for classes 8, 10..14 and 16 and a third for 9 and 15, the multi-class combinations **[I]**. The class byte (+$2F) is compared signed (`jl` at `ovl05:045A`), so it is a `ShortInt`.
- **Monsters out** **[V]** (`RemoveBattleCombatants`, `ovl05:11AC`): monsters and extra combatants leave the party list through `ovl16_e2(Uncounted, FreePicture)` (`ovl16:3291`: unlinks `SelectedCharacter`, frees its picture slot when `FreePicture`, and decrements the party size word 830 unless `Uncounted`); word 712 counts the removed ones whose `Flag10D` is not 1. The members' combat states ($16 bytes) are freed.
- **Hirelings** **[V]** (`TakeHirelingShares`, `ovl05:12E8`): an okay member with `B84` $80 or more (run by the computer) holds `HirelingShare` (+$85) and 7 shares, everybody else one; each kind of pooled money loses the hirelings' part (QUIRK `ovl05:13A5`: the share of one kind is truncated to a byte before it is multiplied), and "<name> takes and hides his share." is shown for each hireling.
- **Result and loot** **[V]** (`ShowBattleResult`, `ovl05:0916`; `TreasureMenu`, `ovl05:0ECD`): "The party has won." (or the duel texts), "The party has fled." (no experience) or "The party has found Treasure!", then "Each character receives <n> experience points.". The menu is "View Take Pool Share" with " Detect Exit" when `SelectedCharacter` has spell 5 or $B memorized (Detect Magic of the cleric and the magic-user **[I]**, cast through `ovl22_e5`) and there are items; Take (`TakeTreasure`) asks "Take: Money Items Exit" when both are left, and the items are taken one by one from the "Loot" window (`TakeLootItems`, `ChooseLootItem`, `AddInventoryItem`). `TreasureLeft(var MoneyLeft, ItemsLeft)` reports what is left. Exit with treasure left asks "There is still treasure left.  Do you want to go back and claim your treasure?". Whatever loot is left is freed when the menu ends.
- **The end** **[V]**: a destroyed party (not in a duel) sets the outcome word to $80 and shows "The END!" and "The monsters rejoice for the party has been destroyed". Every battle ends by setting `DS:4A00` and clearing words 880..882, 739 and 742.
- **Map corrections and frames** **[V]**: the map listed 26 entries; 15 (`02AA`, `0311`, `0507`, `06EB`, `07AA`, `0889`, `08A2`, `091A`, `091F`, `0924`, `093D`, `0999`, `0B48`, `0FE2`, `1307`) are inside the 11 routines and the initialisation part (`ovl05:1671`). Four routines have frame bytes no statement uses (QUIRKs `ovl05:04CC`, `0B17`, `0ED0`, `12EB`), declared as unused locals to keep the frame. A record assignment of a 63-byte item (`Dest^ := Src^`) compiles to the copy helper `0AF8:0A3F`, not to `Move`.

### 5.21 Affects, rolls and damage: ovl24 **[V]** (`src/OVL24.PAS`, `make match UNIT=ovl24`: unit complete)

Overlay 24 holds the rules affects and rolls go through; its 22 entries (e1..e22) are called from other units (ovl04 uses the dice, the affect removal and the healing, ovl05 the dice).

- **Affects** **[V]**: a character's affects (`TCharacter.Affects`, +$7F) are a list of 9-byte records `TAffect`: `Id` (+0), `Duration` (+1, a word; 0 is permanent), `Data` (+3), `Flag` (+4) and `Next` (+5). `AddAffect` (`ovl24:0E52`) appends one; `RemoveAffect` (`ovl24:0026`) unlinks one (found by id when none is given) and, when its `Flag` is set, first calls its handler with mode 1; `ApplyAffect` (`ovl24:1656`) refuses an affect when the hooks of kind 9 clear `HookAffectId` (`DS:6817`) or a save negates it ("is Unaffected"), replaces an affect of the same id whose limited duration is shorter (any, when the new one is permanent) and shows the spell's message; `CureAffect` (`ovl24:1081`) removes one with "is Cured".
- **Handlers and hooks** **[V]**: every affect id has a far procedure in the table `AffectHandlers` (`DS:6828`, 4 bytes per id; `CallAffectHandler`, `ovl24:0000`, calls `AffectHandlers[Id](Who, Affect, Mode)`, mode 0 apply, 1 remove). Rolls do not test affects themselves: `RunAffectHooks(Kind, Who)` (`ovl24:02FA`) runs, for each of 20 event kinds, a fixed list of affect ids through `RunAffectHook` (`ovl24:0160`), which calls the handler when the character has the affect. Four affects ($15, $2D, $2E, $31) also act when another party member has them and, in combat, reaches the character (`ScanTargets` from the bearer, 6 squares for $31, else 1). The handlers change the roll in progress through globals: `AttackRoll` (`DS:6822`, signed), `SaveRoll` (`DS:6816`) with `SaveKind` (`DS:682A`), `DamageAmount` (`DS:6818`) and `HookAffectId`. Kinds used here: 6 damage, 9 a new affect, $A the attacker and $10 the target of a roll, $C a saving throw, $D a combatant going down.
- **Rolls** **[V]**: `RollDice(Count, Sides)` (`ovl24:0DE3`) sums `Random(Sides) + 1` in a byte. `SavingThrow(Who, Kind, Bonus)` (`ovl24:0D63`): a d20, 1 fails and 20 succeeds, otherwise roll + `SaveBonus` (+$101, signed) + Bonus after the save hooks must reach `SavingThrows[Kind]` (+$6D, the five saves of 5.6). `RollToHit(Attacker, Target, Needed)` (`ovl24:0CB7`): the attacker first loses affect $19 (`ClearAttackerAffect`: attacking ends it, an invisibility by that rule **[I]**), a d20 where 1 misses and 20 counts 100, the attacker and target hooks, then roll + `HitAdjust` (+$110) + the low byte of game word 881 (party) or 880 (others) must reach Needed. `RollBeatsResistance(Who, Level)` (`ovl24:0C4F`): the same d20 with the target hooks, plus Level, must exceed `ResistValue` (+$111), likely the magic resistance **[I]**.
- **Damage and healing** **[V]**: `DealDamage(Who, Damage, SaveEffect, Saved)` (`ovl24:1344`) lets the damage hooks change the amount, gives none (SaveEffect 1) or half (2) on a save, shows "takes <n> points of damage from Fire/Cold/Electricity/Acid/Magic" by `DamageKind` (`DS:6819`: and $F7 = 1, 2, 4, $10; bit 3 alone is magic), deals it (`ApplyDamage`), and in combat the victim cannot cast this round and loses a pending spell ("lost a spell"). One that goes down shows "Goes Down", ", and is Dying" (status 5) or "is killed" (status 6, 7, 8); in combat it loses the sixteen `DeathAffects` (`DS:0C14`), the hooks $D run and it leaves the map unless they revived it. `DropCombatant` (`ovl24:0F06`) takes a combatant out with a given status and message. `HealCharacter(Who, Amount, Flag)` (`ovl24:175D`) adds to the byte +$11B, capped at `HpMax`: +$11B is the current hit points **[I]** (also set by `ReviveCombatant` and cleared by `DropCombatant`); a dying character becomes unconscious. `ReviveCombatant` (`ovl24:1869`) stands a fallen combatant up: "stands up and grins" for a monster, "gets back up" otherwise.
- **Strength affects** **[V]**: `EncodeStrength` stores strength and exceptional strength in one byte (18/xx as 1..101, other values + 100) and `DecodeStrength` reverses it; `RaiseStrength` (`ovl24:115C`) refuses a lower strength, keeps the earlier one in the first strength affect ($C or $26) with bit 7 set, and sets the new one.
- **The cloud tile** **[V]** (`ApplyCloudTile`, `ovl24:0AE7`): a combatant standing on tile $1E without affects $1E, $1F, $20, $6F, $7D saves (kind 0): "starts to cough" (affect $1E, one round) or "chokes and gags from nausea" (affect $1F, 1d4 + 1 rounds), a stinking cloud by its texts **[I]**.
- **Map corrections** **[V]**: `ovl24:0475` (the middle of `RunAffectHooks`) and `ovl24:1758` (inside a set constant) were not routines; the unit has 23 routines and the empty initialisation part (`ovl24:1932`).

### 5.22 The camp: studying spells, resting and the Alter menu **[V]** (`src/OVL15.PAS`, `make match UNIT=ovl15`: unit complete)

- **The camp** **[V]**: `MakeCamp` (`ovl15:1E6F`, entry 1, called by ovl03) sets the view mode `ds49F3` to 2 (restored on leaving), shows "The party makes camp..." and runs the menu "Save View Magic Rest Alter Exit" (`CampMenuText`, `DS:0508`, a string[40] in the data segment like the other menu texts `CampMagicMenuText` `DS:0531`, `AlterMenuText` `DS:055A` and `PartyOrderMenuTexts` `DS:0584`). Save is `ovl17_e9` followed by "Quit TO DOS "; View is `ovl19_e5`. Extended keys (G and O) go to `UpdateSelectedCharacter`, which picks another character, in every camp menu.
- **Spell-list selection** **[V]** (`ChooseSpellFromList`, `ovl19:299C`): the first argument chooses both the list label ("in Memory", "in Spell Book", "on Scroll", "on Scrolls", "to choose from", "to be memorized", "to be scribed") and the list passed to `ovl22_e2`; the second argument and `Choice` go to `ovl22_e1`. A zero `Listed` result returns zero. When `Choice` is negative, it opens a one-row window with an empty frame title, redraws the selected character, and draws "Spells " plus the list label at row 1. The function returns the spell byte from `ovl22_e1` **[V]** (`make match UNIT=ovl19 FN=ChooseSpellFromList`).
- **Studying is pending until the rest** **[V]**: memorizing puts the spell number with bit 7 set into the first empty slot of `TCharacter.Spells` (+$17..+$2B, then sorted by `SortMemorizedSpells`); scribing sets bit 7 on a spell byte of a scroll (`TMenuLine.Affects[1..3]` of an item `ovl22_e6` accepts). `CancelPartyStudy` clears every pending spell and mark when the camp opens and again when it closes, and No to "Memorize/Scribe These Spells?" cancels them. During `RunRestPeriod`, `ProcessPendingScribedSpell` and `ProcessMemorizedSpell` clear the pending bit when their rest conditions are met and pass the spell and its message text to ovl22_e7/e8.
- **Rest time** **[V]**: `StudyRestMinutes` (`ovl15:0000`) is 15 minutes per spell level of every pending spell and scroll spell, plus 4 hours when there is one (6 hours when one is above level 2); the hours go to `TCharacter.RestHours` (+$2C). `RestParty` puts the party's largest value into `RestTime` (`DS:6DC2`, seven words: [1] minutes, [2] tens of minutes, [3] hours) for `RunRestPeriod`, whose byte result ends the camp when nonzero, and clears it afterwards.
- **Spell slots** **[V]**: `TCharacter.SpellSlots[class, level]` (+$B2..+$B7, class 0 cleric and 1 magic-user, the `SpellClass` byte of `SpellTable`, signed) less the spells of that class and level in `Spells` are the slots left (`SpellSlotsLeft`); `ShowSpellSlotsLeft` prints them under "Cleric Spells:" and "Magic-User Spells:". `MayUseMagic` refuses casting where game variable 229 is nonzero ("cannot cast spells in this area") and any study when `Status` is 1 or `Flag10D` is 0 ("is in no condition to ...").
- **Scribing** **[V]**: refused for a spell in `KnownSpells` ("You already know that spell"), one already being scribed ("You are already scibing that spell", sic) and one of a class and level without a slot ("You can not scribe that spell.").
- **Display** **[V]** (`DisplaySpellEffects`, `ovl15:0FBC`, matched with its nested `AddDisplayLine`, `ovl15:0E37`, which appends a 46-byte line to the list through the parent's `Last` pointer): a blank line 0, then for every member a heading line (`Flag29` 1) with the name and one line per affect the game can name (" <No Spell Effects>" when none), shown with `ChooseFromList` in the full text window (1,1)..($26,$16) titled "Display", with Exit. The affects by name: a spell affect takes the name of the first spell whose `SpellTable` byte +$A (`AffectId`) is that affect (`SpellNames`, `DS:28E9`, string[40] per spell 1..$38, "Bless" .. "Restoration"), others have fixed names ("Studying Manual of Bodily Health", "Prayer", "Poisoned", "Displaced" ...), unknown spell affects show as "Funky--n".
- **Alter** **[V]**: Order moves the picked member up or down the party list with wraparound (`MoveMemberUp`, `MoveMemberDown`; the list is `ds5D96` linked by `Next`, +$104); Drop removes a member through `ovl16_e2` ("bids you farewell" when `Flag10D` is set, else "is dumped in a ditch") or, for the last member, offers to quit to DOS; Speed moves `GameSpeed` in 0..9; Pics toggles `ShowMonsterPics` (`DS:49F6`) and `ShowPortraits` (`DS:49F5`).
- **Map corrections** **[V]**: 13 map entries of ovl15 were not routines (`0245`, `046C`, `07AA`, `07AF`, `080D`, `0889`, `08A2`, `08AC`, `0999`, `099E`, `1307`, `1BD7` inside routines, `08EA` the strings before `MemorizeSpells`); the unit has 22 routines, the nested `AddDisplayLine` (`ovl15:0E37`) and the empty initialisation part (`ovl15:1FD9`).

### 5.22.1 The rest clock and the rest: ovl20 **[V]** (`src/OVL20.PAS`, `make match UNIT=ovl20`: 13 of 14 routines at L2; the timed-affect updater remains a stub)

- **The clock** **[V]**: `RestTime` (`DS:6DC2`, `TRestClock`, seven words) is a mixed-radix clock. `ClockRadix` (`DS:363A`, seven words in the image: 10, 10, 6, 24, 30, 12, 256) says how many units of each digit make one unit of the next: `CarryRestClock` (`ovl20:02F2`) moves a digit at its radix into the next digit and loses the radix. The digit names are **[I]**: 1 minutes, 2 tens of minutes, 3 hours, 4 days, 5 months, 6 years (the radices 10, 6, 24, 30 and 12 and the camp's `RestParty`, 5.22).
- **Age** **[V]**: the top digit's carry (digit 6 at or above 256) adds one to the `Age` word (`+$30`) of every character on the party list (`ovl20:037B`, the `inc word es:[di+30h]`), and the radix stays set. The whitepaper's save layout has the age at `+$30` [V] (4.2.5).
- **Normalizing** **[V]**: `NormalizeRestTime` (`ovl20:03A3`) carries the clock, then turns the months (digit 5) into days at 30 a month and keeps the days at 99 or less. It runs after every change of the rest time: the Inc and Dec actions of the Rest menu (`RestTimeMenu`, `ovl20:0721`) and each countdown step (`SpendRestTime`, `ovl20:047A`).
- **Spending** **[V]**: `SpendRestTime(Amount, Index)` (`ovl20:047A`) takes `Amount` units off digit `Index`, lending from the next higher nonzero digit (each lent unit gives the radix to the digit below it). When no digit below the months has time left, it clears the clock. It does nothing while minutes, tens, hours and days are all zero. `RunRestPeriod` calls it with Index 1 and Amount 5, so the rest passes five minutes per step.
- **Game clock** **[V]**: `ovl20_e1` (`ovl20:03D5`, entry, called from OVL03, OVL08, OVL14, OVL15 and `RunRestPeriod`) adds `Amount` units to digit `Index` of the game clock: the seven game variables at 49C6h..49CCh (`VarsAt4900`, the words the ECL machine addresses; the copy and write-back address them as `GameVars` words 198..204). It carries on a local copy, writes the clock back and calls `ovl20_fn_0000(Amount, Index)`, which remains a stub.
- **Rest loop and interruption** **[V]**: `RunRestPeriod` (`ovl20:0C9A`) draws the rest time, calls `RestTimeMenu` (and rests only when it returns 1), and returns 1 only after a random interruption. Each five-minute step checks for a pending key and asks "Stop Resting? "; then it spends five minutes, advances the game clock, checks healing and study progress, and tests the encounter counter `ds49FB` against word 0x2D2 of `ds49D6`. When the threshold is reached it resets the counter and interrupts if a 1d100 roll is no greater than word 0x2D3. The interruption message is "The Party is rudely interrupted!"; the result ends camp through `RestParty` (`ovl15:077A`).
- **Healing** **[V]**: `CheckRestHealing` (`ovl20:0871`) increments `ds6DD8` once per rest step. At 0x120 (288 five-minute steps, 24 hours), it calls `HealCharacter` for each party member, shows "The Whole Party Is Healed", redraws the selected character if anyone changed, delays and clears `ds6DD8`.
- **Study timing** **[V]**: `AdvanceRestStudies` (`ovl20:0B0A`) decrements each member's `RestStudyCountdowns` byte at `DS:6DCF` on every step. At zero, when that member's `RestHours` is zero, it completes a pending scribed spell first, then a memorized spell, and sets the counter to three times the next pending spell's level. `AdvanceRestHour` (`ovl20:0BB2`) increments a shared counter on each call; every twelve calls (one hour) it decrements positive `RestHours`, and when a member reaches zero sets the same counter from the next pending spell level.
- **Completing study** **[V]**: `ProcessPendingScribedSpell` (`ovl20:09E7`) scans a member's carried items for a scroll (`ovl22_e6`) and spell bytes with bit 7 set. It marks the spell known, calls `ovl22_e7` with the character, item and spell, then passes `"has scribed"` and the spell to `ovl22_e8`. `ProcessMemorizedSpell` (`ovl20:0925`) clears bit 7 from a pending `Spells` slot and passes `"has memorized"` and the spell to `ovl22_e8`. Both return the level of a subsequent pending spell when the caller's `Handled` byte is already set. The `Dec` used to clear the byte flag is proven by `tools/re/tp_idioms/ovl20/PRB20_DEC.PAS`.
- **Strings and menu** **[V]**: `TwoDigitText` (`ovl20:0565`) gives a number as two characters: the text of `ByteToText`, with a `0` in front below 10 and only the first two kept. `ShowRestTime` (`ovl20:05F0`) draws `Rest Time:` at column 1 of row 17, then days and hours as `dd:hh` from column 12 (each in its colour, the selected field in 15, the others in 10) and the minutes (`10 * RestTime[2] + RestTime[1]`) at column 18. `RestTimeMenu` (`ovl20:0721`) loops on `ReadPromptChoice` with the text `Rest   daYs Hours Mins   Inc Dec   Exit` (colours 13, 10, 15, extended keys on) until Rest (result 1), Exit or Escape (result 0); Enter counts as Rest. `Y`, `H` and `M` select the days, hours or minutes field (`RestTime` digits 4, 3 and 2); the left and right arrows step between them with wrap-around; Inc or the up arrow adds 1 to the field (5 to `RestTime[1]` on the minutes field) and Dec or the down arrow takes it off through `SpendRestTime`, each followed by `NormalizeRestTime`. The menu starts on the minutes field.
- **Open** **[?]**: `ovl20_fn_0000` is 752 bytes including its literal pool and walks the party's affect lists while time advances. Its five-attempt draft did not match; the source is a stub and the matcher has not recorded L2. Compiler-proven boundaries removed the false entries `099E`, `09A3`, `09A8`, `0B2A`, `0B48` and `0B89`; they lie inside `ProcessMemorizedSpell` and `AdvanceRestStudies`, not in separate routines.

### 5.23 The picture unit res07 **[V]** (`src/RES07.PAS`, `make match UNIT=res07`: 17 of 19 routines at L2)

- **The picture record** **[V]**: `TPicture` holds Height and WidthCols as words at +0/+2, XPos and YPos at +4/+6, ItemCount at +8, the 8-byte palette at +9, ByteSize (bytes per item) at +$11, the pixel-buffer pointer at +$13 and the packed pixel data from +$17 (data indexed with range checks off, like ovl32's TMemPic). `AllocatePicture` (`0464:248E`) allocates `Height*WidthCols*2` bytes per item (doubled when VideoAdapter is not 0) times ItemCount plus $17, zeroes it, stores the header, and with bit 0 of AllocFlags allocates the pixel buffer (a quarter of the size when VideoAdapter is 1); `ReleasePicture` (`0464:2595`) frees both, with a `with PPicture(Pointer(Pic))^` over the untyped var.
- **Loading** **[V]**: `LoadPicture` (`0464:0111`, 404 bytes) frees any picture already in the caller's pointer, calls `LoadDaxBlock(Text, '.dax', BlockId, Size, Block)`, copies Height/WidthCols/XPos/YPos/ItemCount/Palette into locals with `Move`, allocates, stores XPos/YPos/Palette into the new picture and calls `UnpackPicturePixels` (`0464:02A5`, matched, below) with (Block, $11, AllocFlags, Color, Target^); then frees the DAX block and calls FlushKeyboard. It leaves one byte of its frame unused (QUIRK `0464:0114`).
- **The unit is compiled with O+** **[V]**: like res08, res07 is resident but was built with `{$O+}`: a string constant passed to a routine is copied to a stack temporary through `System_StrCopy` (`0AF8:0B0B`) at `0464:0152` (`LoadDaxBlock`'s '.dax' under the overlay-copy rule), and all 14 matched routines match with `{$A-,O+,F+,S-,R-,G-,I-}`. This is more evidence for the res08 escalation (O+ is per unit, not overlay-units-only).
- **The mirrors** **[V]**: `MirrorPicture` (`0464:15C7`, 906 bytes) copies a picture mirrored: the palette as is, then each pixel row reversed per VideoAdapter (each 16-bit unit through `MirrorWord` 0464:1509, which reverses the eight 2-bit groups using `GlyphPixelMasks`; each byte through `MirrorByte` 0464:1484 in 4-byte groups; or through `SwapNibbles` 0464:1596), and the pixel buffer at +$13 mirrored too (word by word, byte by byte within the row, or in place). ovl32 DrawIcon uses it for icon sets above 3.
- **The direct blit** **[V]**: `ShowPicture` (`0464:1951`, 513 bytes) copies a picture's pixel data straight to the video hardware: adapter 0 moves one WidthCols*2-byte row per screen row to the segment `ds4EC0[Row]` at column X*2; adapter 1 writes one byte per pixel through the four EGA planes (map mask `EgaPlaneBitMasks`, new global at DS:25F6, address `ds5050[Row]+Col` in segment $A000); adapter 2 is the adapter-0 move with four bytes per column and the `ds51E0` table.
- **The changed-region flush** **[V]**: the blitters mark changed screen rows in `ds4A28` (a byte flag per row) and the first and last changed offset in the word arrays `ds4AD0`/`ds4C20`/`ds4D70`; `FlushPictureChanges` (`0464:1B52`, 778 bytes) presents them per adapter (row moves to the `ds4EC0`/`ds51E0` segments, or the four planes through port 3C5 plus a Graphics-Controller write-mode-1 copy from $A200 to $A000) and then clears the trackers. The blitter `DrawPictureItem` (`0464:08D4`, matched, below) marks the same trackers; `0D71` is still a stub.
- **Video mode and palette** **[V]**: `SetVideoMode` (`0464:00CF`) saves the current mode (`ds4A1D`) in `SavedVideoMode` and sets INT 10h function 0 with the new mode; `RestoreVideoMode` (`0464:00FF`) sets the saved one back. `SetPaletteRegister` (`0464:2A0D`) writes one EGA palette register through INT 10h AH=10h AL=0 (BH = the colour, mapped from 0..7 as is and 8.. as +8, BL = the register). `ColorMatchMask` (`0464:0000`) returns the bit mask of the eight 4-bit pixels of a 4-byte cell that equal a colour; `PaletteColor` (`0464:007B`) returns a palette colour for a pixel value.
- **Map corrections** **[V]**: 19 of the 39 map entries of res07 were not routines (they have no `55 89 E5` prologue; aligned disassembly runs through them): 066F/0710 inside 02A5, 0A33/0C0C/0D6C inside 08D4, 0E01..140E (11) inside 0D71, 1514 inside 1509, 1708 inside 15C7, 1A19 inside 1951. Six routines were resized (02A5 1583, 08D4 1181, 0D71 1811, 1509 141, 15C7 906, 1951 513) and 00FF is 13 bytes plus a 5-byte literal pool, not 18. res07 has 19 routines plus the empty initialisation part.
- **Unpacking** **[V]** (`UnpackPicturePixels`, `0464:02A5`, 1583 bytes, `make match`): the DAX pixel data (4 bytes = one 8-pixel cell, read from offset $11) becomes the picture's data per VideoAdapter. Adapter 0 turns each pixel's nibble into its palette colour (`PaletteColor`, `0464:007B`) and that colour into 2-bit pairs through `ds25FA[colour, position]`, two bytes per cell; with a pixel buffer (`Pixels`, AllocFlags bit 0) it also stores the mask of the pixels equal to `Color` (`ColorMatchMask`, `0464:0000`) and clears those bits of the data. Adapter 1 keeps the raw nibble: each pixel's colour bits select the EGA planes through `EgaPlaneBitMasks`, one byte per plane per cell. Adapter 2 copies `ByteSize` bytes per item unchanged. The third argument (LoadPicture's AllocFlags) is never read; the frame keeps 17 bytes that are never touched (QUIRK `0464:02A5`).
- **Fill** **[V]** (`FillPictureRect`, `0464:2632`, 987 bytes): called four times by `DrawWallDescriptors` (`ovl29:0174`) with X = 2, the wall descriptor rows and the colours `ds6A60..ds6A63`; it fills Width x Height cells of the picture with the palette colour, clipped at all four edges, marks the trackers, and per adapter writes two bytes (0, colour through `ds0D02`), four bytes (2, `ds0D06`) or the four plane bytes (1, `EgaPlaneBitMasks`) per cell. QUIRK `0464:2707`: a rectangle that starts above row 0 is drawn one row too far (the bound is `Height - |Y|` with an inclusive loop).
- **Item copy** **[V]** (`DrawPictureItem`, `0464:08D4`, 1181 bytes): copies item `PicIndex` of the picture `Source` into `Dest` at column `Col` and pixel row `Row * 8`, one source row of bytes at a time (2 bytes per cell on adapter 0, 4 on 1 and 2). With `Flags` bit 0 and a pixel buffer in `Source`, a destination byte becomes `(dest and mask) or source`; adapter 1 reads one mask byte per four data bytes. It does no clipping of its own (`RightRoom` is a Word, added as it is). Callers: `DrawCellPicture` (`ovl32:00F1`) and `Put8x8Symbol` (`ovl34:015D`).
- **The fill tables** **[V]** (bytes of `start-unpack.exe` at DS:0D02, DS:0D06, DS:25FA, DS:25E5, DS:25F6): `ds0D02[C]` is four 2-bit pixels of colour C (`00 55 AA FF` for C 0..3), `ds0D06[C]` two 4-bit pixels of colour C (C * `$11`); the two overlap (`ds0D02[C + 4]` is `ds0D06[C]`). `ds25FA` is a 16 x 4 table (`colour, position`): for colours 0..3 the colour's 2-bit value in the bit pair of that pixel (colour 1 at position 0 is `$40`); colours 4..15 do not follow that pattern. `GlyphPixelMasks` (words `C000 3000 0C00 0300 00C0 0030 000C 0003`) and `EgaPlaneBitMasks` (`01 02 04 08`) are the plane and pixel masks. The meaning of the fill bytes for colours 4..15 is **[?]**.
- **Remaining** **[?]**: `0D71` (the clipped sprite blitter that `ovl18`, `ovl28`, `ovl31` and `res12` call) and `1E5C` (the 16-entry colour remap used by `LoadPictureSlot`, `AnimateAreaDoors` and `LoadSpriteList`).

### 5.24 The resident character and item helper unit res12 (in progress)

res12 is the resident helper the overlays call for character, item and view work. Forty
routines are matched so far **[V]** (`make match UNIT=res12`): `RecalcCombatValues` recomputes a character's
combat values and calls `SetArmourMovement` (`00BA:01FB`), `AddReadiedItemBonus` (`00BA:0282`),
`ApplyWeaponBonuses` (`00BA:0000`) and `CapMovementByLoad` (`00BA:03A0`); `IsHelpless`
(`00BA:0B73`) tests the four affects that leave a character helpless; the four panel routines
`DrawPartyRoster` (`00BA:0767`), `DrawArmourClass` (`00BA:08EF`), `DrawHitPoints` (`00BA:0973`) and
`DrawCharacterPanel` (`00BA:09E3`) draw the shop, Temple, combat and inventory character panels.
The unit is compiled with **`$O+`** even though it is resident: every string literal passed to a
`string` parameter is copied to a stack temporary first (proven by a `make tpc` probe: `$O-` passes
the literal's code-segment address, `$O+` copies it), and `DrawPartyRoster`/`DrawCharacterPanel`
matched only with the copy.

- **Movement** **[V]**: the character's base movement is the byte at +$72 (`BaseMovement`);
  `SetArmourMovement` copies it to Movement (+$11C) for an armour (item kind 2) below weight
  $97, uses 9 up to $18F and 6 above, and adds 3 for a magic armour while the movement is at
  most 9. `CapMovementByLoad` then caps Movement by the carried weight (+$102) above the
  strength allowance `StrengthWeightAllowance`: excess up to $200 keeps it, up to $300 caps at 9, up to
  $400 at 6, above at 3, and the cap never raises it.
- **Strength and its adjustments** **[V]**: `StrengthRowIndex` (`00BA:11EA`) turns a character's
  Strength (+$10) plus its exceptional StrengthPercent (+$16) into a 0..30 row of the strength
  table: strength 0..17 is itself, an 18 with percent 0, 1..50, 51..75, 76..90, 91..99 or 100
  becomes 18..23, and strength 19..25 becomes 24..30. `StrengthAttackAdjustment` (`00BA:1282`)
  and `StrengthDamageAdjustment` (`00BA:1325`) pick the to-hit and damage bonus from that row,
  and `StrengthWeightAllowance` (`00BA:13AB`) picks the weight a character can carry in coins
  from it (rows 1..3 give -350, 12..13 100, 16 350, 17..21 step by 250, 22..26 by 1000 and
  28..30 by 3000 from 9000). The byte `StrengthBonusFlag` at +$AA gates only the attack and
  damage adjustments (a 0 suppresses them); what it marks is not proven. `ForgetSpell`
  (`00BA:148B`) clears the first memorized spell (`SelectedCharacter^.Spells`, +$17) equal to a
  spell number; `DealDamage` calls it when a victim loses a pending spell.
- **Readied items** **[V]**: `AddReadiedItemBonus` reads the item kind's RaceRow byte 6: bit 7
  clear means the item contributes nothing; with it set the low seven bits are a bonus class.
  A kind-1 item assigns bonus class plus Plus to a kind bonus; other items with class 0 sum
  their Plus (a kind-9 item keeps the largest instead) and always add PlusSave (+$33, signed)
  to `SaveBonus` (+$101); a class above 0 keeps the largest class plus Plus and, for a positive
  plus on an armour, sets a flag. `ApplyWeaponBonuses` builds the readied weapon's attack values
  from its RaceRow row: HitAdjust (+$110) is reset to Thac0 (+$2D), the flag byte $E adds the
  dexterity roll adjustment (`DexterityAttackAdjustment`, bit 2) and the strength roll adjustment
  (`StrengthAttackAdjustment`, bit 4), WeaponAttacks (+$115) and WeaponDamage (+$117) come from bytes 9 and
  $A, and the signed WeaponDamageBonus (+$119) from byte $B plus the strength damage adjustment
  (`StrengthDamageAdjustment`) and the plus of the weapon and, by flag bits 0 and 7, of slot items 11
  (+$F8) and 12 (+$FC). The RaceRow kind column is 0 weapon, 1 plus item, 2 armour, 9 special.
- **Recalculating the combat values** **[V]**: `RecalcCombatValues` (`00BA:0BB8`) is the routine
  every equipment change calls (ovl03, ovl06, ovl08..ovl10, ovl12, ovl13, ovl16, ovl19, ovl21,
  ovl24). It clears the 13 per-kind slots (`SlotItems`, +$CC); walks the carried item list (`Items`,
  +$C8) to count the items (`ItemCountC7`, +$C7), add each item's `Weight` (+$37) times its `Count`
  (+$39) to the carried weight (+$102) and to `ReadiedItemWeight` (DS:4846), and file each readied
  item into its slot (item kinds 0..8 into `SlotItems[kind]`, kind 9 into the first free of slots 9
  and 10, item type $49 into slot 11 and $1C into slot 12), raising `ds100` (+$100) by
  RaceRow[item type][1]. It then adds the seven carried money words (+$88) to the weight (every coin
  counts one), copies the base attack triple (+$A3, +$A5, +$A7) into the readied weapon triple
  (+$115, +$117, +$119) and the base value +$A9 (ovl16:05E4 sets 50) into `ResistValue` (+$111),
  resets `SaveBonus` (+$101), `Movement` (+$11C) and `HitAdjust` (+$110), adds the unarmed strength
  bonuses (`StrengthAttackAdjustment`, `StrengthDamageAdjustment`) when no weapon is readied, and runs `ApplyWeaponBonuses`
  and, per readied item, `SetArmourMovement` and `AddReadiedItemBonus`. A readied item whose
  `NameNum[1]` is $BA (a weightless container) instead counts 5000 less and the weight is floored at
  `ReadiedItemWeight`. Finally `ResistValue` becomes the sum of the accumulator's five bytes, `ds112`
  (+$112) its best three minus two, and `Movement` is capped by `CapMovementByLoad`. The base and
  readied attack values are each a pair of bytes (entry 1 is the one the AI and the weapon code read),
  which is what forced the `TCharacter` fields at +$A3, +$A5, +$A7, +$115, +$117 and +$119 to be
  two-element arrays.
- **Helpless** **[V]**: `IsHelpless` (`00BA:0B73`) returns True when any of the four affects in
  `HelplessAffects` (DS:286B, entries 1..4 = $33, $34, $35, $1F) is on the character's affect list
  (`HasAffect`). ovl13:1FC3 compares the same entries with the 16-byte combat table at DS:3204;
  `DrawCharacterPanel` shows "(Helpless)" for a True answer.
- **The item name table** **[V]**: 256 strings of at most 20 characters at DS:10A7 (the image:
  entry 1 `Battle Axe` through entry 255 `Cursed`, entry 0 unused); the menu-line formatter
  `res12_fn_0442` indexes it with a line's NameNum. That formatter is blocked (its plural rule
  is two bytes short of a match, see `re/symbols.toml`); the rest of the unit (the shop, view
  and message routines) is still stubs. The item field at +$33 (`PlusSave`) is signed.
- **The character panels** **[V]**: `DrawPartyRoster` (`00BA:0767`) draws the
  "Name / AC  HP" header and one line per party member (the list `ds5D96`, linked by
  TCharacter.Next +$104), clearing each line and drawing the selected member in white and the
  others through `DrawCharacterName`; the left column is 1 in the shop (`ds49F3` = 0) and $11
  elsewhere. `DrawCharacterPanel` (`00BA:09E3`) draws the combat/inventory box ($17,1)-($26,$15):
  the name line (`ShowCharacterMessage`), the "Hitpoints" value (`DrawHitPoints`, current hit points
  +$11B coloured Yellow below HpMax +$32, Green at it, LightMagenta on a highlight flag), the
  "AC" value (`DrawArmourClass`, `Abs(+$111 - 60)` signed in Green), the readied weapon's text
  (`res12_fn_0442` then `ShowPagedText`), and the status name `StatusNames[Status]` (+$10C, the
  eight string[12] entries at DS:1047: Okay Animated tempgone Running Unconscious Dying Dead
  Stoned), or "(Helpless)" when `IsHelpless` says so. The value at +$111 is the one
  `ovl24`'s `RollBeatsResistance` compares a d20+level against.
- **Item-list helpers** **[V]**: the carried-item list is `TCharacter.Items` (+$C8), linked through
  `TMenuLine.Next` (+$2A). `RemoveInventoryItem` (`00BA:1509`) unlinks an item and frees the record
  (63 bytes): it re-points the head when the item is `Items`, else walks for the record whose Next is
  the item, reports through `ShowMessageLine` (Yellow) on a nil item ("Nil Item pointer...") or one not
  on the list ("Tried to Lose item & couldn't find it!"), then always clears `Item^.Next` and frees it;
  ovl07 `LoseItems` calls it for every lost item. `AddItemCopy` (`00BA:15F7`) GetMems a 63-byte
  record, `Move`s the item into it, clears the copy's Next and appends it at the end of `Items`; it is
  the "give a copy of an item" helper, ovl12 and ovl19 call it.
- **Message helpers** **[V]**: `ShowCharacterMessage` (`00BA:16EC`) is the per-character message box:
  in the combat view mode (`ds49F3` = 5) it clears the box ($17,Row)-($26,$15) and in every other view
  a fixed box, top row $11 or $12 (`ds6DDA` picks and the $11 case first draws the frame); it then
  draws the character's name through `DrawCharacterName` and the wrapped text through `ShowPagedText`
  (Green, cleared first) and, when the wait byte is set, delays `DelayByGameSpeed` and clears the box
  through `ClearCharacterMessage` (`00BA:17E3`, box ($17,$A)-($26,$15) in view mode 5, else
  (1,$12)-($26,$16)). `ShowFlashMessage` (`00BA:1693`) flashes a `String40` on the bottom row 24 in
  Green (clear, draw, `DelayByGameSpeed`, clear); `DrawCharacterName` (`00BA:1816`) draws a
  character's `Name` (+0) at (Col,Row) in the colour of its combat state (LightRed when `Flag10D` is 0,
  Yellow on the party side 1, LightCyan otherwise) and, when its Mode byte is set, appends the literal
  `'s` (the bytes `02 27 73`) after the name at Col plus its length.
- **The combat turn, the enemy scan and the spell level** **[V]**: `EndCombatTurn` (`00BA:2637`)
  ends a combatant's turn (clears `Combat^.PendingSpell` +$0, `Initiative` +$3, the guard byte `B7`
  +$7 and `Moves` +$6) and returns 1; `GuardTurn` (`00BA:2686`) calls it, sets `B7` to 1 and flashes
  'Guarding' (the Done menu's Guard command, ovl08:0E45, and the AI fallback `ovl09_fn_0F4F`).
  `CollectEnemiesInRange` (`00BA:2433`) runs `ScanTargets` from Who within Range steps, keeps only the
  records whose combatant is on `OpposingSide(Who)`'s side (three bytes each, compacted in place), and
  writes the kept combatant indexes into `ds6DE4` from entry 1, returning the count; `AiTurn` picks a
  random one and `SpellAccepted` loops them for the area spells. `DistanceToTarget` (`00BA:255B`)
  saves the scan table, opens the WalkLine tile gate (`CombatMap^.Head6`, +$6), scans omni from Who
  over $FF steps and returns half the shortest walk length to Target (the distance in map cells,
  which tests = 1 as melee range); the table is restored before the return. `SpellCasterLevel`
  (`00BA:26C2`) returns the selected character's level in a spell's class (`ClassLevels`: 0 cleric,
  5 magic-user), 12 for spell class 2, and a forced 6 while `ds6DBF` is set; ovl22_e3 multiplies the
  spell row's +3 byte by it. QUIRK `00BA:26FB`: a spell class other than 0, 1 or 2 leaves the result
  unassigned.
- **Map artifacts** **[V]**: `00BA:2571` was not a routine but the middle of `DistanceToTarget`
  (`00BA:255B`, whose real size is 220 bytes); `make match WRITE=1` removed it. `00BA:06D5` and
  `00BA:0712` are not routines but labels inside the
  blocked `res12_fn_0442` (06D5 even starts one byte late, under an `es:` prefix), and
  `00BA:0B4F` was the same inside `DrawCharacterPanel` (removed by `make match WRITE=1`).
  `00BA:1857` and `00BA:187D` were the same inside `DrawCharacterName` (`00BA:1816`, whose real size
  is 124 bytes, not the 65 the map guessed; `make match WRITE=1` removed both).
- **The view dispatcher and the screens** **[V]**: `RedrawView` (`00BA:27D9`) redraws the whole
  screen for the current view mode (`ds49F3`, the resident unit's view dispatcher): mode 0 draws the
  plain full window, mode 1 the character portrait screen (`DrawViewWindows`, then the HEAD and BODY
  sprites at (3,3) through `LoadHeadBodySprites`/`ShowHeadBodySprites`), mode 2 the camp (the
  portrait windows, the PIC block $1D sprite list and the roster), modes 3 and 4 the area view
  (`DrawViewWindows`, `ShowAreaView` and the roster; only mode 4 draws the inner window) and mode 6
  the loot screen (the portrait windows, the PIC block 1 sprite list and the roster); modes 2, 3 and
  4 draw the roster and the location line, mode 6 the roster only and modes 0 and 1 neither. `DrawViewWindows` (`00BA:272A`) draws
  the view's window frames through `DrawWindow`: the full screen (1,1)-(38,22), the bottom text
  window (1,17)-(38,22) and the upper-left window (1,1)-(15,15), plus the inner window
  (3,3)-(13,13) that frames the portrait or the 3D view. `DrawWildernessScreen` (`00BA:2B5E`) is the
  wilderness map screen `HandleWildernessKeys` shows: it sets view mode 3 and draws the adventure
  screen's three windows (`DrawAdventureScreen`), the area view, the party marker, the location line
  and the roster. `DrawCombatScreen` (`00BA:2B88`, called by `StartBattle` and `PlayerTurn`) prepares
  the EGA palette (`ovl31_e2`), draws the two combat windows (1,1)-(21,21) and (23,1)-(38,21), clears
  the bottom rows (0,23)-(39,24) and places the cursor on the combat map's view origin plus the centre
  cell (margin $FF, the no-step direction 8). `DrawLocationLine` (`00BA:290B`) draws the party
  position line on row 15 of the side window: the position (`PartyMapColumn`/`PartyMapRow`, or the
  game map words `VarMapX`/`VarMapY` shifted by the map page width for `AreaViewKind` 3 and 4), the
  facing (`FacingNames`, the string[2] table at DS:25A8: N, NE, E, SE, S, SW, W, NW, indexed by
  `PartyFacing`) and the game clock time as hours:minutes (the game clock digits, each padded to two
  digits), with "column,row " prepended outside the 3D view, " camping" in the camp and " search"
  while the wilderness search bit (bit 0 of `ds49D6^[714]`) is set. `SelectPartyMember` (`00BA:2C48`)
  is the member picker the inventory and other screens use: it loops showing the roster and a
  `ReadPromptChoice` "Select" prompt (with " Exit" when the caller asks), moves the caller's
  `Selected` pointer to the previous member with G or the next with O (wrapping the party list
  DS:5D96), clears it with E or the extended-key prefix, and ends on Enter, Escape or E.

## 6. Open questions

1. Remaining compiler directives (`$A`, `$B`, `$V`, `$X`) and which game unit is the 16-byte unit at `0A31` (2.2). The version is pinned: Turbo Pascal 6.0, June 1991 release.
2. Meaning of the stub field at +0E (3.3) and of the fifth `POOL.CFG` line (2.3).
3. Roles of the 11 unnamed resident units (3.2).
4. How much of the resident code is hand-written assembly (graphics, sound, timer) **[?]**.
5. Field map of `SAVGAMA.DAT` (size known, 4.4); WALLDEF tile-to-pixel expansion (4.2.4); affect (`.SPC`) field meanings (4.2.5).

---

## Appendix A. Overlay units **[V]** (`make overlays`)

| Overlay | Stub segment | GAME.OVR offset | Code bytes | Fixups | Entries |
|---|---|---|---:|---:|---:|
| ovl00 | 0016 | 0x00008 | 190 | 7 | 2 |
| ovl01 | 0019 | 0x000D4 | 2062 | 101 | 2 |
| ovl02 | 001C | 0x009AC | 862 | 30 | 2 |
| ovl03 | 001F | 0x00D46 | 13581 | 402 | 2 |
| ovl04 | 0022 | 0x04577 | 3895 | 104 | 2 |
| ovl05 | 0025 | 0x0557E | 5750 | 112 | 2 |
| ovl06 | 0028 | 0x06CD4 | 1949 | 49 | 3 |
| ovl07 | 002B | 0x074D3 | 8730 | 141 | 25 |
| ovl08 | 0035 | 0x09807 | 4735 | 157 | 2 |
| ovl09 | 0038 | 0x0ABC0 | 6439 | 117 | 2 |
| ovl10 | 003B | 0x0C5D1 | 8082 | 56 | 2 |
| ovl11 | 003E | 0x0E5D3 | 1562 | 55 | 2 |
| ovl12 | 0041 | 0x0EC5B | 14510 | 377 | 117 |
| ovl13 | 0068 | 0x127FB | 15474 | 303 | 25 |
| ovl14 | 0072 | 0x166CB | 4268 | 93 | 3 |
| ovl15 | 0075 | 0x17831 | 8158 | 184 | 3 |
| ovl16 | 0078 | 0x1997F | 17497 | 263 | 4 |
| ovl17 | 007C | 0x1DFE6 | 9189 | 361 | 12 |
| ovl18 | 0082 | 0x2069D | 2299 | 81 | 3 |
| ovl19 | 0085 | 0x2103A | 11026 | 320 | 13 |
| ovl20 | 008C | 0x23DCC | 3685 | 44 | 3 |
| ovl21 | 008F | 0x24C89 | 8795 | 154 | 15 |
| ovl22 | 0096 | 0x27018 | 14261 | 349 | 64 |
| ovl23 | 00AC | 0x2AA87 | 1123 | 0 | 5 |
| ovl24 | 00B0 | 0x2AEEA | 6455 | 87 | 23 |
| ovl25 | 03C5 | 0x2C8CF | 4682 | 55 | 8 |
| ovl26 | 03CA | 0x2DB87 | 677 | 6 | 3 |
| ovl27 | 03CD | 0x2DE38 | 648 | 7 | 3 |
| ovl28 | 03D0 | 0x2E0CE | 1989 | 50 | 8 |
| ovl29 | 03D5 | 0x2E8F7 | 4619 | 40 | 8 |
| ovl30 | 03DB | 0x2FB52 | 3038 | 5 | 7 |
| ovl31 | 03E0 | 0x3073A | 4864 | 25 | 20 |
| ovl32 | 03E9 | 0x31A6C | 1605 | 55 | 6 |
| ovl33 | 03EE | 0x3211F | 252 | 13 | 2 |
| ovl34 | 0428 | 0x32235 | 690 | 25 | 3 |

## Appendix B. Regenerating the facts in this document

| Facts | Command |
|---|---|
| File hashes | `make inputs` |
| Units, overlays, stubs, entry points | `make overlays` (writes `build/re/overlays.json`) |
| Start-up interrupt sequence | `make smoke` |
| DAX container and RLE | `make dax` / `make test` (`tools/re/dax.py verify poolrad/`) |
| GEO maps | `tools/re/geo.py verify poolrad/` (also via `make dax` / `make test`) |
| ECL script headers | `tools/re/ecl.py verify poolrad/` (also via `make dax` / `make test`) |
| EGA pictures / font | `tools/re/pic.py verify poolrad/` (also via `make dax` / `make test`) |
| WALLDEF wallsets | `tools/re/walldef.py verify poolrad/` |
| Character / item / affect | `tools/re/records.py verify poolrad/` |
| ITEMS type table | `tools/re/items.py verify poolrad/` |
| SAVE directory | `tools/re/save.py verify poolrad/SAVE` |
| Boot, key script sessions, traces | `make oracle-run SCRIPT=tests/sessions/create-character.keys` |
| Screens vs DOSBox-X | `make oracle-dosbox` |

## Appendix C. The oracle: what it models

`tools/oracle` runs the original `start-unpack.exe` and `GAME.OVR` in Unicorn as a deterministic, headless PC (SPEC 8.2, playbook 25). Everything below is **[V]** by `tests/unit/test_oracle.py` unless marked otherwise.

| Area | Modelled | Not modelled (raises or is ignored, never silently wrong) |
|---|---|---|
| CPU and memory | 16-bit real mode, 640 KB, MZ loader with relocations, PSP and environment at `0FF0`/`0F00`, load image at `1000:0000` (the addresses of this document plus `1000h`) | 8087, protected mode, EMS/XMS |
| Interrupts | Software INTs dispatch through the real IVT, so handlers the program installs run as original code (the Borland overlay manager on INT 3Fh, INT 08h of the sound unit); service vectors end in IRET stubs hooked in Python | hardware IRQs 1 to 7 other than IRQ0 |
| Time | Executed-instruction counter (1,000,000 per virtual second), PIT channel 0 reload honoured, IRQ0 delivered at chunk boundaries with IF set and EOI tracked; ports 40h/42h read as free-running counters; port 3DAh retrace derived from the clock; time of day is 12:00:00 plus the clock, optionally pinned by the session (`clock HH:MM:SS.hh`: the first read returns exactly that). A timer interrupt left pending for 2 million instructions (interrupts never re-enabled) stops the run as stalled. Hybrid runs do not use this clock: they replay the recorded reads (below) | wall clock, host date (reported date is fixed 1991-06-11) |
| DOS (INT 21h, 20h, 27h, 29h, 2Fh) | console, vectors, version 3.30, handle file I/O, find first/next, directories, memory blocks, IOCTL, time, exit | EXEC, FCBs, networking, EMS |
| BIOS | INT 10h (mode set, cursor, scroll, tty, palette registers, font info, EGA info), 11h, 12h, 13h reset, 15h (a few), 16h (read, peek, flags), 1Ah (ticks, RTC, date) | disk I/O, serial, printer, mouse (INT 33h is a bare IRET: no driver), VGA DAC, CGA/Tandy video modes |
| Files | `poolrad/` read-only as `C:\POOLRAD`; every write goes to an in-memory layer (`SAVE\RAD.CHA` etc.) and never reaches disk | |
| EGA | 4 planes, latches, map mask, bit mask, set/reset, rotate, logical ops, write modes 0 to 3, read modes 0 and 1, attribute palette to RGB, CRTC start address, modes 0Dh/0Eh/0Fh/10h, simple text modes; PNG screenshots | split screen, panning, odd/even and chain-4 addressing |
| Sound | PIT channel 2 and port 61h writes logged as a speaker event list (`m.speaker_log`) | audio output |
| Input | Script player (`tests/sessions/*.keys`): keys released when the game is idle, time-based waits, `shot`, `digest`, `wheel`, `quit` | joystick, mouse |
| Randomness | Every call of the generator step is logged `(index, time, kind, caller, range, seed, result)` in `m.random_log` (`tools/oracle/rng.py`), direct `RandSeed` writes in `m.seed_writes`; `summary.json` carries the count and a digest of the `(kind, caller, range, result)` sequence without times, so a run with other timing can be compared on decisions alone; `--trace rng` writes `random.txt` | |
| Tracing | Interrupts, file I/O, port I/O, call and return of every routine of `re/symbols.toml` (resident and overlay, overlay entry points resolved from the stub's load segment), memory watch points, coverage of routines entered | argument decoding by signature (the signatures in `re/symbols.toml` are still empty: four raw stack words are logged) |
| State | `Machine.state_digest()` (registers, conventional memory, video), `oracle.state.canonical_digest()` from `re/state.toml` (DGROUP, the allocated Turbo Pascal heap HeapOrg..HeapPtr at DS:4400/4404, and the video planes; `heap = "compared"`, decision 2026-10-11) | `heap_root` entries (need `re/types/`) |
| Hybrid hooks | `routines.replace(m, id, fn, ret_bytes=, far=)` replaces a routine by Python or C wherever it is loaded (overlay routines are rehooked after every read of GAME.OVR) and declines (`return False` runs the original); `Machine.hook_routine` / `hook_linear` at a fixed address. The C library (`make hybrid`, `tools/oracle/hybrid.py`) is bound to guest RAM. `routines.Profiler` counts each call's own-code instructions (the dynamic timing scan) | a general marshaller from `re/symbols.toml` signatures; the three spike routines have hand-written stack layouts. `orig_call` (C calling an unlifted routine) is not built yet |

Acceptance results (playbook 25):

- **Boots to the title screens**: `tests/sessions/boot-title.keys` reaches the SSI logo, the title and the credits in EGA mode 0Dh after 24, 35 and 44 million instructions. Each of the three screens is **pixel-identical** to a frame recorded by DOSBox-X 2026.10.01 running the same unpacked executable (`make oracle-dosbox`: DOSBox-X's `dx-capture` ZMBV recording decoded with ffmpeg, compared byte for byte). The wheel screen is not compared because its runes depend on the clock.
- **Deterministic**: the same script run twice gives identical stop points, instruction counts, per-key-read state digests, checkpoint digests, final state digest and call traces.
- **Character creation completes from a script**: `tests/sessions/create-character.keys` (about 64 million instructions, 13 s of wall time) ends at the main menu with `SAVE\RAD.CHA` decoded as the character shown on the sheet (5.8).
- **Hybrid timing, first method (2026-10-10, retired 2026-10-11)**: an exact-time mode counted instructions one by one in Python and charged each replaced call the instructions the original had spent in it, from a per-call cost table. It worked for `System_Move` and `System_FillChar`, but needed a cost merge for every callee a C routine absorbs, a one-call spinner allowance at checkpoints, ran 7 times slower than the plain oracle, and could never apply to the native build. It is replaced by record/replay (below). Kept from it: the finding that a hybrid run differs from the original only in the stack segment.
- **Hybrid with C routines** (C track, branch `track-c-hybrid`): `System_Move`, `System_FillChar` and `System_Random` in C reproduced both goldens' recordings at every read and checkpoint. The replacement hook (`oracle.routines.replace`) and the record/replay stay on `main` for the rebuild and the C translation.
- **Record/replay** (decision of the human 2026-10-11, `tools/oracle/replay.py`, `tests/unit/test_replay.py`, SPEC 8.4). Exhume's port method (UW2Decomp `PORT.md`, "The differential test") applied to hybrid runs: time matters to the game only where it reads the outside world, so those reads are recorded and replayed instead of instructions being counted. A survey of both sessions found the reads are only INT 16h (peeks and reads), INT 21h AH=2Ch (106,036 polls in `boot-title`, 181,103 in `create-character`) and the BIOS tick word 0040:006C read by Crt init and Crt.Delay (32,176); no timer or retrace port reads and no INT 1Ah. The recording run is the golden run, and the recording is saved with the golden (`replay.json.gz`, about 115 KB per session) and verified by `make golden CHECK=1`; each read is stored with the number of timer interrupts raised so far, run-length coded per kind. A replay answers each read from its stream and raises the timer interrupt as often as the recording had by that read, so the game's timer handler runs at reads instead of mid-computation (its only writes are stack frames and the BIOS tick, see Time above). Checkpoints sit on read boundaries (after each key read, after the first read that follows a script `shot`, and every 20,000 reads) and compare the no-stack canonical state, all memory outside the stack segment, the screen, the Random count and the interrupt count; the end also compares the Random sequence and the files written. **[V]** Replaying the original alone reproduces both recordings; with Move, FillChar and Random in C (49,966 + 15,138 + 33,431 calls in `boot-title`, 53,352 + 15,740 + 33,548 in `create-character`) both sessions match at every read with no time charged, no cost table and no spinner allowance, in about 10 to 22 s per session. A C Random that answers one wrong value is caught at the `sheet` checkpoint; a corrupted Move is caught when the replay stops reading the outside world (watchdog at four times the recording's longest quiet stretch). A read of another kind than the recording's next one is reported by its number.
- **Goldens recorded** (playbook 40, `make golden`): each session is run twice and written only when both runs agree on stop reason, instruction count, every checkpoint (virtual time, screen, canonical and full state digests, Random call count), every per-key-read state digest, the Random sequence and the final state. A golden is `tests/sessions/golden/<name>/{golden.json, reads.txt, reads_nostack.txt, replay.json.gz, <label>.png}`; `make golden CHECK=1` re-runs the original and compares digests (not PNG bytes). Recorded: `boot-title` (3 checkpoints, 44,049,050 instructions) and `create-character` (5 checkpoints, 26 key reads, 64,701,234 instructions, 33,548 Random calls). `boot-title` has no key reads: the title screens run without input, so its verdict is the three checkpoint digests. The scripts' screenshots were reviewed by eye; one capture point was wrong and was fixed before recording (`sheet` was taken while the character was still being rolled, all scores 0; the script now waits for the "Keep this character? Yes No" prompt).

Known limits **[V]** (test `test_hybrid_hook_python_move_matches_original`):

- On the instruction clock, virtual time is instructions and a replacement executes none, so after a few timer ticks a hooked run places ticks at slightly different program points and tick-derived bytes in DGROUP differ (`DS:C312`, `C404..C407` at the 400th call of `System_Move`; equal states hold up to the 120th call). Session replays remove this: the game's reads of the outside world are answered from the original's recording, so where the timer lands no longer changes what the game decides (acceptance results above).
- **Wait loops** **[V]** (`make timing-scan`, `tools/re/timing_scan.py`, tests `test_timing_scan.py`): the replacement runs instantly at the routine's entry, so a routine that *waits* (spins until a key, a tick, a retrace) cannot be a literal C transliteration: no time passes while C runs, and in a replay the reads it would spin on are recorded values. Static scan over all 1393 routines with the call graph (far calls through overlay stubs resolved): 100 loop around a time or input feature (2 in their own bytes: the keyboard drain `res01_fn_0143` and Crt init `0A40:002E`, which spins on the BIOS tick; 98 through a callee: `Crt` KeyPressed `0A40:02FD` and ReadKey `0A40:030F`, the sound routines `0A40:029C` and `08AE:006C`); 369 more read the clock or keyboard outside a loop; 924 do neither. Note that most of these loops are not waits in the sense that matters: draining a buffer or polling a key in a menu loop ends by itself in a replay, where each poll returns its recorded result; what cannot work in C inside the oracle is a loop whose exit depends on time passing (5.14). Dynamic pass over `boot-title` and `create-character`: 228 routines ran, KeyPressed alone 508,736 times; four calls spun a whole timer period or more in their own code (`ovl01:0000`, `ovl01:0627`, the menu loop `ovl25:03BD`, and `UnpackRle` with 342,000 instructions, which the static pass says touches nothing, so it is computation). The game's own timer interrupt writes no DGROUP global (its only writes are its stack frames). Exactly one routine reads the BIOS tick counter at 0040:006C, `0A40:002E` (an earlier version of this paragraph said none: the scan missed the register-indirect access). Decision of 2026-10-10 (human): waits go through the platform layer, `src/platform/platform.h` (5.14); the scan's list (`build/re/timing-scan.md`) says which routines need `platform_*_wait` instead of a spin.
- **Stack segment** **[V]**: a replaced routine does not push the frames the original pushed, so bytes of the stack segment (SS:0000 to 4000) differ between a hybrid run and the original, including slots of live frames that nobody has written yet (SS:3A4D at the first key reads of `create-character`). No byte of globals, heap or video differs. The goldens therefore carry two state digests: `canonical` (everything, as before) and `canonical_nostack`. Decision 2026-10-10 (human): `re/state.toml` sets `stack = "diagnostic"`, and a hybrid run is compared on `canonical_nostack`. The full digest stays in the golden. A read of an uninitialised Pascal local (stale stack content) is a quirk a C lift does not reproduce, and it is not part of the state the port has to match.
- Pinning the clock fixes the seed but not the number of `Random` calls that timing-driven code makes (5.13). In a hybrid run the logged sequence is the first thing to compare: the first differing entry names the call where it diverged.
- Time is exact at chunk boundaries only (chunks end at timer events); an interrupt that falls inside a service call is delivered after it.
- The BIOS font ROM is not in the pinned inputs: text-mode screenshots use a placeholder font (the game itself draws all text in graphics mode with its own font, so game screens are unaffected).

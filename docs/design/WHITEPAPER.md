# How Pool of Radiance Works

*A living design document for SSI's Pool of Radiance (DOS), written from the decompilation.*

| | |
|---|---|
| Status | Seeded 2026-10-07 (Phase 0). Most game systems are still open questions. |
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
  - `$I+` in one resident unit only **[I]**: 12 far calls to the I/O check (`0AF8:04A9`), all inside `0802..0899` (res05, the unit with "Please insert overlay disk."); none in other resident units or in any overlay.
  - `$G-` **[I]**: no 80286-only instruction (`push imm`, `enter`, `leave`, `pusha`, `imul imm`, shift by immediate) in the 805 routines.
  - `$F+` **[I]**: all 622 `mov sp,bp; pop bp; ret` epilogues return far (`retf`/`retf n`: 528 in overlays, 94 resident); not one near return.
  - `$Q`: does not exist in TP 6.0 **[V]** (`Error 17: Invalid compiler directive`).
  - Language limits of TP 6.0 that matter when reading the code **[V]** (`make tpc`): no `const` parameters (`Error 2: Identifier expected`), so structured value parameters are copied into the callee's frame; functions cannot return records.
  - `$N-`/`$E` **[I]**: no 8087 emulator interrupts (INT 34h..3Dh) or `fwait`+ESC sequences beyond 4 stray byte matches; the game does no floating point.
  - `$A`, `$B`, `$V`, `$X` **[?]**: not visible in these counts. Next step: `$A` from the alignment of word variables after odd-sized ones in DGROUP; `$B` from the jump shape of `and`/`or` boolean expressions, both measured against probe compiles.

### 2.3 Configuration (`POOL.CFG`)

Five text lines **[V]** (writer: `CFG.C`; the game opens "POOL.CFG" and prints "Unable to find POOL.CFG" when missing, strings in the unpacked image):

1. video mode: `E` EGA, `C` CGA, `T` Tandy
2. sound: `P` PC speaker, `T` Tandy, `S` silent
3. game directory with trailing backslash
4. save directory with trailing backslash
5. `F` or `N` **[?]** (meaning unknown)

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
| res04 | 0899:013C | [?] |
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
| ovl15 | SpellMemorize | memorize / Cleric Spells |
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

Other externally called System/Crt/Overlay/Dos entries are named `*_rtl_XXXX` or INT-based until classified.

Start-up as observed by running the original code in the oracle (`make oracle-run`, appendix C) **[V]**:

1. The System unit saves 19 interrupt vectors (INT 21h AH=35h), installs INT 00h (`0AF8:00DF`), INT 23h (`0AF8:00E6`), INT 24h (`0AF8:00AE`) and a default INT 3Fh handler (`0AF8:00D7`), and queries the output handle with IOCTL (AH=44h).
2. The Crt unit probes the video BIOS (INT 10h AH=0Fh, 11h AL=30h, 08h) and installs INT 1Bh (`0A40:012D`).
3. The Borland Overlay unit replaces INT 3Fh with its manager (`0AA2:02E6`), opens `GAME.OVR` and reads its 8-byte header. The 35 overlay initialisations then run through that handler; each first call reads the unit's code (file offset from the stub, dword at +04h) and its fixup table with two INT 21h reads, so every unit is loaded from `GAME.OVR` by the program's own manager (the oracle implements no overlay logic).
4. `POOL.CFG` is opened and read. The sound unit (res03, init `08AE:01D2`) briefly hooks INT 08h and programs the timer to divisor `13B1h` (about 297 Hz) with `OUT 43h,B6h` followed by two `OUT 40h` bytes, restores INT 08h and divisor `FFFFh`, turns the speaker off (port 61h) and silences a Tandy SN76489 (`OUT C0h` with 9Fh, BFh, DFh, FFh).
5. `8X8D1.DAX`, `SQRPACI.DAX`, `COMSPR.DAX`, `ITEMS` and `TITLE.DAX` are loaded, the game switches to EGA mode 0Dh (320x200, 16 colours), shows "Loading... please wait", then the SSI logo, the Pool of Radiance title and the credits, polling the keyboard throughout. The code wheel prompt (5.12) follows.
6. The game installs no INT 08h/09h/1Ch handler for the rest of the session; keyboard input is INT 16h only (5.8).

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

Load3DMap skips the `u16`, then `Move`s four 256-byte planes through the far pointer at DGROUP `0x6A5C` **[V]** (`ovl29:1160`..`ovl29:11DF`). Wall-id nibble packing matches the pre-UA Gold Box `CELL_A` layout (ImHex `GB_GEO.hexpat`, coab) **[H]** for field meaning; plane order and size are from our bytes. Door values are a 2-bit enum per side (none / open / locked variants) **[H]**. Event id 0 means no script trigger on that cell **[H]**.

GEO and ECL share block ids for the same area in most cases; three GEO-only ids (30, 31, 32) and three ECL-only ids (8, 11, 19) are the known exceptions **[V]** (file inventory).

#### 4.2.2 ECL scripts **[V]** (`make test` / `tools/re/ecl.py verify`: 8 files, 29 blocks)

LoadEcl (`ovl07:0341`) allocates a `0x1E00`-byte buffer (same size as coab `EclBlock.ecl_struct_size`), opens `ECL#.DAX` for the current area, loads one block by id, requires `raw_size >= 2`, skips the leading `u16`, and copies `raw_size - 2` bytes into the buffer **[V]**. In every pinned file that leading word is `5000` **[V]**; every payload fits in `0x1E00` **[V]**.

After load, the VM reads five word operands from offset `0x8000` (coab `vm_init_ecl` / `vm_LoadCmdSets`) **[H]** naming, **[V]** that our headers parse as five type-1 word operands:

| Slot | Role (coab name) **[H]** |
|---|---|
| 0 | `vm_run_1` |
| 1 | `SearchLocation` |
| 2 | `PreCampCheck` |
| 3 | `CampInterrupted` |
| 4 | `ecl_initial_entryPoint` |

Operand encoding (type byte, then low, then high when type is 1/2/3) matches coab `ovr008.vm_LoadCmdSets` **[H]**; our headers all use type 1 **[V]**. Full opcode coverage is not claimed here; that lands with the interpreter unit (section 5.1).

#### 4.2.3 EGA pictures **[V]** (`tools/re/pic.py verify`: 54 files, 778 blocks)

Picture-bearing archives: `TITLE`, `PIC1-8`, `CPIC1-8`, `SPRIT1-8`, `HEAD1-8`, `BODY1-8`, `CHEAD`, `CBODY`, `COMSPR`, `ICON`, `8X8D1-8`, `FINAL5`. Pixel records match coab `DaxBlock` **[H]** and the fields `Load24x24Set` reads at `ovl32:008C` (height at +0, `item_count` at +8, bytes-per-picture at +0x11) **[V]**:

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

`PIC*.DAX` and `SPRIT*.DAX` (and some `FINAL5` blocks) wrap several records as an animation **[V]**:

```
u8   num_frames
repeat num_frames:
  u32  delay                    ; tenths of a second **[H]** (coab)
  <picture record>
```

For `PIC`/`FINAL`, pixel bytes of frame N are XOR'd with frame 0 before draw **[H]** (coab `ovr030.load_pic_final`); applying that delta yields coherent PNGs from our files **[V]** (`pic.py dump`).

`8X8D1.DAX` block 201 is not a picture record: it is a 1-bit font, 177 glyphs of 8 bytes each (1416 bytes) **[V]** (size; coab `seg041.Load8x8Tiles` reads it the same way **[H]**). Other `8X8D` blocks are ordinary picture records of 8x8 tiles (`item_count` 31 to 70).

CLI: `tools/re/pic.py dump <file.DAX> <id> out.png` (or a directory for multi-frame).

#### 4.2.4 WALLDEF wallsets **[V]** (`tools/re/walldef.py verify`: 8 files, 38 blocks)

`LoadWallSet` (`ovl29:0E08`) loads `WALLDEF#.DAX`, rejects a size that is not a positive multiple of `0x30C` (780), and `Move`s each 780-byte wallset into the wall buffer **[V]**. Within a wallset it addresses walls with stride `0x9C` (156), so each wallset is five walls of 156 bytes **[V]** (`ovl29:0FAA`). Observed sizes: 780, 1560, 2340 (1–3 wallsets) **[V]**. Bytes are small integers used as 8x8 tile indices **[H]**; PNG expansion is not done yet.

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
| 5.2 | Areas, maps and movement (GEO, walls, 3D view) | OpenGoldBox `docs/MAPS.md` **[H]** |
| 5.3 | Party and characters (creation, attributes, classes, levels) | wicanr2 `docs/spec/003`, `004` **[H]** |
| 5.4 | Items, money, shops | |
| 5.5 | Combat (tactical map, initiative, movement, attacks) | wicanr2 `ida-overlay08-*`, `ida-overlay13-*` **[H]** |
| 5.6 | Magic and effects (spells, memorisation, durations) | |
| 5.7 | Rest, time and healing | |
| 5.8 | Text, menus and the screen layout | |
| 5.9 | Graphics (EGA, CGA, Tandy), pictures and animation | OpenGoldBox `docs/graphics-format.md` **[H]** |
| 5.10 | Sound (PC speaker, Tandy) | OpenGoldBox `docs/sound-format.md` **[H]** |
| 5.11 | Saving and loading | |
| 5.12 | Copy protection (code wheel) | `poolrad/__ Code Wheel __.pdf` |
| 5.13 | Random numbers | TP 6 generator, `Randomize` from the clock (below) |

### 5.8 Keyboard input and menus (observed in the oracle)

- Input is **INT 16h only** **[V]** (oracle: no INT 09h hook, ports 60h/64h never touched): Crt `KeyPressed` (`0A40:02FD`, AH=01h) and `ReadKey` (`0A40:030F`, AH=00h, an extended key returns 0 then the scan code on the next call).
- A resident wrapper `res04:0059` (a `ReadKey` with Ctrl-S pause and a debug toggle) is what game code calls. Before most prompts the game flushes the keyboard with `res04:0104` (`while KeyPressed do ReadKey`) **[V]**, so keys typed before the prompt appears are lost, as for a person. The oracle's `key` script command therefore waits for the game to be idle.
- The menu loop is `ovl25:03BD` (get key, parse the item string, redraw `ovl25:01DA`), called by the list handler at `ovl25:0FA0..10A7` **[V]**. It parses the item string with a 36-character set at `ovl25:00AB` (upper-case letters and digits mark the first letter of each item: the highlighted hotkey). In the lists of the character creation (race, sex, class, alignment) the highlight moves with **END (next) and HOME (previous)**, ENTER selects, and the one-item bar at the bottom ("Exit") answers to its first letter **[V]** (oracle session `create-character`). The arrow keys have no effect in these lists **[V]** (oracle: UP/DOWN/LEFT/RIGHT/TAB/SPACE leave the screen unchanged); `ovl25:03BD` drops an extended key unless its caller asked for it (`ovl25:0580..0599`) **[I]**, and `,` and `.` move the highlight of its own item bar (`ovl25:05C4`, `05E8`) **[I]**.
- Character creation flow **[V]** (one run of `tests/sessions/create-character.keys`): main menu (C) > race list > sex > class > alignment > rolled character sheet with "Keep this character? Yes No" > name prompt > "Head Body Keep" > icon editor ("Parts Color-1 Color-2 Size Exit") > "Is this icon OK? Yes No" > main menu. The game writes `SAVE\RAD.CHA` (285 bytes, the character record of 4.2.5) and `SAVE\CHARLIST.TXT` (`RAD`, CR LF) **[V]**; decoding `RAD.CHA` with `tools/re/records.py` gives the race, class, sex, age and six scores shown on the sheet (human 7, fighter 2, male 0, age 19, STR 15 INT 13 WIS 11 DEX 12 CON 16 CHA 12 in the pinned run).

### 5.12 Copy protection: the code wheel

- The check is `ovl02:00FD` (entry point of overlay 2, 862 bytes of code) **[V]**. At most three times it picks `r = Random(13)` (`System_Random`, `0AF8:11C0`), draws two rune glyphs and a path pattern from a table at the very start of DGROUP (`DS:0000`, 13 records of 21 bytes), flushes the keyboard (`res04:0104`) and asks "INPUT THE CODE WORD:" **[V]**.
- Record layout **[V]** (`start-unpack.exe` image at `0C7C0h`, and the lcalls in `ovl02:01A2..02FD`): `+02` Pascal string[6] with the answer; `+09`, `+0A`, `+0B` glyph indices, each drawn as character `index + 40h` in the game's font (the two rune pictures the prompt asks to match, then a third); `+0C` a fourth index drawn only when it is not FFh; `+0D` Pascal string with the path pattern drawn under the runes (`- - - -`, `-..-..-`, `.......`).
- The 13 answers, in record order **[V]**: BEWARE, ZOMBIE, NOTNOW, COPPER, DRAGON, EFREET, FRIEND, JUNGLE, KNIGHT, SAVIOR, TEMPLE, VULCAN, WYVERN. The typed word is compared with `System_StrCompare` (`0AF8:0C10`, flags in ZF) after `StrLCopy(local, input, 40)`; the failure message is "Sorry, that's incorrect." (`ovl02:00E4`); after the third failure `res04:0000` ends the program **[V]**.
- Which question appears depends on `RandSeed`, which comes from the clock, so it varies from run to run on real hardware. The oracle's virtual clock makes it repeat; its `wheel` script command reads the answer from the table by watching that `Random(13)` call (`tools/oracle/protection.py`) and types it, leaving the game's own check untouched.

### 5.13 Random numbers

- The generator is Turbo Pascal 6.0's, in System at `0AF8:120F` (step), `0AF8:11C0` (`Random(range)`) and `0AF8:11D6` (`Random` real) **[V]** (code read; every logged call of the oracle satisfies the formulas below, and the logged results equal `AX` at the return of `Random(range)` for the first 300 calls, `tests/unit/test_oracle.py`).
  - `RandSeed` (DS:4428, low word first) `:= RandSeed * 08088405h + 1` modulo 2^32.
  - `Random(range) = hi16(RandSeed) mod range` (0 when `range` is 0). This is TP 6's `div`, not the multiply-and-shift of TP 7, which matters for anyone lifting a routine that compares sequences.
- `Randomize` is `0AF8:1247`: `INT 21h AH=2Ch`, then `RandSeed := DX:CX` (seconds and hundredths in the high word, hours and minutes in the low word) **[V]**. The game calls it once, during the title screens, about 16.6 million instructions after start (`RandSeed` is written only there in the first 80 million instructions), so everything the game decides at random is a function of the clock at that moment and of the sequence of `Random` calls after it.
- The title sequence calls `Random(4)` from `ovl01:0721` over 30,000 times in its first 80 million instructions **[V]**, so the number of calls before the wheel question depends on how long the title screens ran. A run is reproducible only if both the seed and the timing of those screens are reproducible (`clock` script command and `--trace rng`, appendix C).

---

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
| Time | Executed-instruction counter (1,000,000 per virtual second), PIT channel 0 reload honoured, IRQ0 delivered at chunk boundaries with IF set and EOI tracked; ports 40h/42h read as free-running counters; port 3DAh retrace derived from the clock; time of day is 12:00:00 plus the clock, optionally pinned by the session (`clock HH:MM:SS.hh`: the first read returns exactly that). `Machine(exact=True)` counts instructions one by one (about 3 million per second) so hooks know the position inside a chunk; it reproduces the plain model digest for digest | wall clock, host date (reported date is fixed 1991-06-11) |
| DOS (INT 21h, 20h, 27h, 29h, 2Fh) | console, vectors, version 3.30, handle file I/O, find first/next, directories, memory blocks, IOCTL, time, exit | EXEC, FCBs, networking, EMS |
| BIOS | INT 10h (mode set, cursor, scroll, tty, palette registers, font info, EGA info), 11h, 12h, 13h reset, 15h (a few), 16h (read, peek, flags), 1Ah (ticks, RTC, date) | disk I/O, serial, printer, mouse (INT 33h is a bare IRET: no driver), VGA DAC, CGA/Tandy video modes |
| Files | `poolrad/` read-only as `C:\POOLRAD`; every write goes to an in-memory layer (`SAVE\RAD.CHA` etc.) and never reaches disk | |
| EGA | 4 planes, latches, map mask, bit mask, set/reset, rotate, logical ops, write modes 0 to 3, read modes 0 and 1, attribute palette to RGB, CRTC start address, modes 0Dh/0Eh/0Fh/10h, simple text modes; PNG screenshots | split screen, panning, odd/even and chain-4 addressing |
| Sound | PIT channel 2 and port 61h writes logged as a speaker event list (`m.speaker_log`) | audio output |
| Input | Script player (`tests/sessions/*.keys`): keys released when the game is idle, time-based waits, `shot`, `digest`, `wheel`, `quit` | joystick, mouse |
| Randomness | Every call of the generator step is logged `(index, time, kind, caller, range, seed, result)` in `m.random_log` (`tools/oracle/rng.py`), direct `RandSeed` writes in `m.seed_writes`; `summary.json` carries the count and a digest of the `(kind, caller, range, result)` sequence without times, so a run with other timing can be compared on decisions alone; `--trace rng` writes `random.txt` | |
| Tracing | Interrupts, file I/O, port I/O, call and return of every routine of `re/symbols.toml` (resident and overlay, overlay entry points resolved from the stub's load segment), memory watch points, coverage of routines entered | argument decoding by signature (the signatures in `re/symbols.toml` are still empty: four raw stack words are logged) |
| State | `Machine.state_digest()` (registers, conventional memory, video), `oracle.state.canonical_digest()` from `re/state.toml` (DGROUP and video planes while that file is empty) | `heap_root` entries (need `re/types/`) |
| Hybrid hooks | `Machine.hook_routine(seg, off, fn, ret_bytes, cost=)` replaces a routine by Python or declines (`return False` runs the original); `unhook`. With exact time: `timing.replace(m, id, fn, table=)` (resident and overlay routines, rebound after every GAME.OVR read) and `timing.record` / `make oracle-timing` for the per-call costs | the C hybrid library and marshalling from `re/symbols.toml` signatures (P3) |

Acceptance results (playbook 25):

- **Boots to the title screens**: `tests/sessions/boot-title.keys` reaches the SSI logo, the title and the credits in EGA mode 0Dh after 24, 35 and 44 million instructions. Each of the three screens is **pixel-identical** to a frame recorded by DOSBox-X 2026.10.01 running the same unpacked executable (`make oracle-dosbox`: DOSBox-X's `dx-capture` ZMBV recording decoded with ffmpeg, compared byte for byte). The wheel screen is not compared because its runes depend on the clock.
- **Deterministic**: the same script run twice gives identical stop points, instruction counts, per-key-read state digests, checkpoint digests, final state digest and call traces.
- **Character creation completes from a script**: `tests/sessions/create-character.keys` (about 64 million instructions, 13 s of wall time) ends at the main menu with `SAVE\RAD.CHA` decoded as the character shown on the sheet (5.8).
- **Hybrid timing** (exact time, `tools/oracle/timing.py`): the original is run once with a recorder that notes, for every call of the chosen routines, the exact time at entry and the instructions executed in the routine's own code (callees and interrupt handlers are not part of it: they run for real in the hybrid run). A hybrid run charges that cost at the call in the original's chunk structure; a timer tick that falls inside the routine is delivered at the routine's entry at its original time, and the routine resumes afterwards. Result with `System_Move` (0AF8:1685) replaced by Python for a whole session (49,966 calls in `boot-title`, 53,400 in `create-character`): every call enters at its recorded time, the run ends at the same instruction count, and every time, screen, Random count and no-stack state digest of the golden is reproduced; `exact=True` alone reproduces every digest of the golden. The first known limit below, the drift this replaces, no longer applies.
- **Goldens recorded** (playbook 40, `make golden`): each session is run twice and written only when both runs agree on stop reason, instruction count, every checkpoint (virtual time, screen, canonical and full state digests, Random call count), every per-key-read state digest, the Random sequence and the final state. A golden is `tests/sessions/golden/<name>/{golden.json, reads.txt, <label>.png}`; `make golden CHECK=1` re-runs the original and compares digests (not PNG bytes). Recorded: `boot-title` (3 checkpoints, 44,049,050 instructions) and `create-character` (5 checkpoints, 26 key reads, 64,701,234 instructions, 33,548 Random calls). `boot-title` has no key reads: the title screens run without input, so its verdict is the three checkpoint digests. The scripts' screenshots were reviewed by eye; one capture point was wrong and was fixed before recording (`sheet` was taken while the character was still being rolled, all scores 0; the script now waits for the "Keep this character? Yes No" prompt).

Known limits **[V]** (test `test_hybrid_hook_python_move_matches_original`):

- Without exact time, virtual time is instructions and a replacement executes none, so after a few timer ticks a hooked run places ticks at slightly different program points and tick-derived bytes in DGROUP differ (`DS:C312`, `C404..C407` at the 400th call of `System_Move`; equal states hold up to the 120th call). This is what `timing.py` removes (see acceptance results). What remains of it **[V]** (tests `test_exact_time.py`): the replacement's effect is applied at the routine's entry, so a timer handler that runs while the original was in the middle of the routine sees the finished routine (a routine whose state a timer handler reads or writes needs the C code to say so; not the case for `System_Move`); a script checkpoint (`shot`, `digest`) that falls inside a replaced routine sees its finished state; and the interrupt frame is pushed at the routine's entry depth.
- **Wait loops** **[V]** (`make timing-scan`, `tools/re/timing_scan.py`, tests `test_timing_scan.py`): the replacement runs instantly at the routine's entry and the clock is charged afterwards, so a routine that *waits* (spins until a key, a tick, a retrace) cannot be a literal C transliteration: no time passes while C runs. Static scan over all 1393 routines with the call graph (far calls through overlay stubs resolved): 100 loop around a time or input feature (1 in its own bytes, `res01_fn_0143`; 99 through a callee: `Crt` KeyPressed `0A40:02FD` and ReadKey `0A40:030F`, the sound routines `0A40:029C` and `08AE:006C`); 374 more read the clock or keyboard outside a loop; 919 do neither. Dynamic pass over `boot-title` and `create-character`: 228 routines ran, KeyPressed alone 508,736 times; four calls spun a whole timer period or more in their own code (`ovl01:0000`, `ovl01:0627`, the menu loop `ovl25:03BD`, and `res05_fn_050F` with 342,000 instructions, which the static pass says touches nothing, so it is computation). The game's own timer interrupt writes no DGROUP global (its only writes are its stack frames), and no routine reads the BIOS tick counter at 0040:006C. A lift of a wait routine needs a platform wait (a `platform.h` change: human) or stays in the original; `timing_scan.md` is the work list.
- **Stack segment** **[V]**: a replaced routine does not push the frames the original pushed, so bytes of the stack segment (SS:0000 to 4000) differ between a hybrid run and the original, including slots of live frames that nobody has written yet (SS:3A4D at the first key reads of `create-character`). No byte of globals, heap or video differs. The goldens therefore carry two state digests: `canonical` (everything, as before) and `canonical_nostack`; a hybrid run is compared on the second. Whether `re/state.toml` should define the stack as out of the canonical state is a decision for the human; a C local never lives on the guest stack, so a read of an uninitialised Pascal local (stale stack content) is a quirk a faithful C lift cannot reproduce.
- Pinning the clock fixes the seed but not the number of `Random` calls that timing-driven code makes (5.13). In a hybrid run the logged sequence is the first thing to compare: the first differing entry names the call where it diverged.
- Time is exact at chunk boundaries only (chunks end at timer events); an interrupt that falls inside a service call is delivered after it.
- The BIOS font ROM is not in the pinned inputs: text-mode screenshots use a placeholder font (the game itself draws all text in graphics mode with its own font, so game screens are unaffected).


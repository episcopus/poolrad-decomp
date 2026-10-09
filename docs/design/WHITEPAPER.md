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
| `start-unpack.exe` | 71,152 | The same program unpacked (made earlier by hand; reproduction is a Phase 0 task) |
| `GAME.OVR` | 206,105 | Overlay code for 35 units **[V]** |
| `*.DAX` (113 files) | | Game data archives **[V]** (section 4.1) |
| `ITEMS` | 2,050 | Item data **[?]** format |
| `SAVE/` | | A saved game: `SAVGAMA.DAT` plus per-character `CHRDAT<slot><n>.SAV/.ITM/.SPC` (section 4.4) |
| `POOL.BAT`, `CFG.EXE`, `CFG.C` | | Third-party launcher ("Gold Box Starter by Japo @ Abandonia.com", per `CFG.C`), not part of the original game |

### 2.2 Toolchain and version

- **Turbo Pascal** **[V]**: the unpacked image contains the runtime's error text ("Runtime error ", " at ", "." CR LF) immediately followed by "Portions Copyright (c) 1983,91 Borland"; the entry point is a chain of unit initialisation calls (section 3.2).
- Overlay file signature `FBOV` **[V]**. The earlier 1988 build analysed by wicanr2 uses `TPOV` and Turbo Pascal 5.x **[H]** (their `docs/re/dos-toolchain-baseline.md`). Together with the 1991 runtime date this makes ours a later rebuild with a newer Turbo Pascal (6.0 era) **[I]**. Exact version **[?]**, to be bounded by comparing runtime code with Turbo Pascal 6.0 and 7.0 (playbook 10, step 4).
- Which compiler directives were used (range, stack and overflow checks) **[?]**.

### 2.3 Configuration (`POOL.CFG`)

Five text lines **[V]** (writer: `CFG.C`; the game opens "POOL.CFG" and prints "Unable to find POOL.CFG" when missing, strings in the unpacked image):

1. video mode: `E` EGA, `C` CGA, `T` Tandy
2. sound: `P` PC speaker, `T` Tandy, `S` silent
3. game directory with trailing backslash
4. save directory with trailing backslash
5. `F` or `N` **[?]** (meaning unknown)

---

## 3. Program architecture

### 3.1 The executable **[V]** (unpacked MZ header; `tools/re/tpovl.py`)

| Field | Value |
|---|---|
| Relocations | 561 |
| Load image | 68,592 bytes (paragraphs 0000 to 10BE) |
| Entry CS:IP | 0000:0006 |
| Initial SS:SP | 14F2:4000 (16 KB stack) |
| Data segment (DGROUP) | paragraph 0C7C **[I]** (the System unit's init executes `mov dx,0C7Ch; mov ds,dx` before relocation) |
| Initialised data | 0C7C to 10BE (about 17 KB); uninitialised data follows up to the stack segment |

### 3.2 Units and start-up **[V]** (`tools/re/tpovl.py`, manifest field `init_chain`)

The entry point is 48 consecutive far calls, one per unit initialisation, in Turbo Pascal's unit order. 35 of them call offset `0020` of an overlay stub segment (entry 0 of an overlay unit) and 13 call resident units:

| Unit | Init call | Provisional role |
|---|---|---|
| res00 | 0AF8:0000 | System (Turbo Pascal runtime) [I] |
| res01 | 0A40:0000 | Crt [I] |
| res02 | 0A31:0000 | [?] |
| res03 | 08AE:01D2 | [?] |
| res04 | 0899:013C | [?] |
| res05 | 0802:0968 | [?] |
| res06 | 0709:0F82 | [?] |
| res07 | 0464:2A4A | [?] |
| res08 | 042B:00A4 | [?] |
| res09 | 03F1:0367 | [?] |
| res10 | 03ED:0000 | [?] |
| res11 | 03DA:0000 | [?] |
| res12 | 00BA:309E | [?] |

Start-up as observed by running the original code in Unicorn (`tools/oracle/smoke.py`) **[V]**: the System unit saves 19 interrupt vectors (INT 21h AH=35h) and installs 4 handlers (AH=25h), queries a device with IOCTL (AH=44h), then the Crt unit probes the video BIOS (INT 10h AH=0Fh, 11h, 08h).

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

### 3.4 Calling conventions **[H]** (Turbo Pascal documentation; to verify on samples, playbook 10 step 5)

- Parameters pushed left to right; the callee removes them (`RET n`).
- Function results: 8 and 16-bit in AL/AX, 32-bit and pointers in DX:AX; string results through a caller-provided buffer pushed first.
- VAR parameters and large value parameters passed by address.
- Nested procedures receive the enclosing procedure's frame pointer (static link) as an extra parameter.
- Routines in a unit's interface use far calls; implementation-only routines may be near.

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
| `ECL1-8` | 8 | 2 to 5 | Event scripts per area |
| `GEO1-8` | 8 | 2 to 6 | Area maps (walls, doors, events) |
| `WALLDEF1-8` | 8 | 2 to 7 | Wall definitions for the 3D view |
| `8X8D1-8` | 8 | 3 to 7 | 8x8 tile graphics (3D view, frames, fonts) |
| `PIC1-8`, `CPIC1-8` | 16 | 3 to 44 | Pictures (encounter art, combat pictures) |
| `SPRIT1-8` | 8 | 5 to 15 | Monster sprites |
| `HEAD1-8`, `BODY1-8`, `CHEAD`, `CBODY` | 18 | 1 to 128 | Character and monster portraits (heads, bodies) |
| `MON1-8CHA`, `MON1-8ITM`, `MON2-8SPC` | 22 | | Monster characters, their items, their special abilities |
| `ITEM1-8` | 8 | 1 to 10 | Item data per area |
| `TITLE` | 1 | 2 | Title screens (both blocks unpack to 32,017 bytes: a 320x200x16-colour picture is 32,000 bytes) |
| `COMSPR`, `ICON` | 2 | 26, 6 | Combat sprites, icons |
| `DUNGCOM`, `WILDCOM`, `RANDCOM`, `SQRPACI`, `BACPAC`, `FINAL5` | 6 | 1 to 8 | Combat maps, random encounters, end sequence **[?]** |

### 4.3 `ITEMS` **[?]**

2,050 bytes: 2 + 2,048, consistent with 128 records of 16 bytes **[H]**.

### 4.4 Saved games **[V]** sizes, **[I]** structure

- `CHRDAT<slot><n>.SAV`: 285 bytes each: one character record.
- `.ITM`: 63, 126 or 189 bytes: multiples of 63, so 63-byte item records **[I]**.
- `.SPC`: 9 to 45 bytes: multiples of 9, so 9-byte records (spells or effects) **[I]**.
- `SAVGAMA.DAT`: 13,137 bytes: the game state **[?]**.

coab reads Pool of Radiance characters for import (`Classes/PoolRadPlayer.cs`) **[H]**: a lead for the 285-byte layout.

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
| 5.13 | Random numbers | Turbo Pascal's `Random` **[H]** |

---

## 6. Open questions

1. Exact Turbo Pascal version and compiler directives (2.2).
2. Meaning of the stub field at +0E (3.3) and of the fifth `POOL.CFG` line (2.3).
3. Roles of the 11 unnamed resident units (3.2).
4. How much of the resident code is hand-written assembly (graphics, sound, timer) **[?]**.
5. Formats of `ITEMS` and `SAVGAMA.DAT` (4.3, 4.4).

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
| DAX container and RLE | `make dax` (`tools/re/dax.py verify poolrad/`) |

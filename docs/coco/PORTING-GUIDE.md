# Pool of Radiance on the CoCo 3: porting guide (Phase 8 baseline)

Version 0.5, 2026-10-17. Status: steps 8.0, 8.1, 8.1c and 8.2 are done (`ports/coco3/docs/PHASE-8.0.md`, `PHASE-8.1.md`, `PHASE-8.1c.md`, `PHASE-8.2.md`). **D12 is confirmed as the hybrid: engine-owned pictures, mapped hot data, banked cold data, driven by a placement table; it runs on the host and the seven sessions pass.** The engine, the 6809 build and the save format are not done. Every design choice below is a **proposal** until the human approves it at the Phase 8 kick-off (section 10 lists the decisions). Facts carry the project's tags: **[V]** verified on our bytes or by running a tool, **[S]** stated by a cited source (details and URLs in `research/`), **[E]** an estimate, **[?]** open.

This guide is the synthesis. The eight research files under `research/` hold the evidence, the register tables, cycle counts and sources. Read this file first, then the research file for the module you are working on (the table in section 11 says which).

---

## 1. The port in one page

- **Target machine:** Tandy Color Computer 3 with **512 KB**, stock **6809** at **1.79 MHz**, RGB monitor by default with a composite palette option, floppy (Disk BASIC DSKCON) as the baseline storage, CoCo SDC and DriveWire as later fast paths. The 6309 and the Games Master Cartridge (GMC) are optional extras, never requirements. [S] 512 KB is what every high-end modern CoCo 3 game requires (06; a few, such as Gloom2, run on 128 KB), and DOS Pool of Radiance itself needed 512 KB with EGA (06).
- **Why it is feasible:** the game is turn based and event driven (it redraws on input, it has no vsync dependency [V] whitepaper 5.14), its graphics are 320x200 at 16 colours, which the CoCo 3 GIME shows natively with the **same pixel packing as the game's data** (4 bits per pixel, high nibble = left pixel [V] whitepaper 4.2.3, [S] 02), and the EGA colour space maps **exactly** onto the GIME palette [S] 02. SSI fitted this game into a 64 KB Commodore 64 with overlays and fixed resource slots [S] 06; a 512 KB CoCo 3 with an MMU has more room than any 8-bit machine that ever ran it.
- **What makes it hard:** (1) code size: about 197 KB of x86 overlay code becomes an estimated 180 to 300 KB of 6809 code [E] 01, and with about 40 KB of resident game code the same ratio gives about 210 to 350 KB, all of it reached through 8 KB MMU banking that CMOC does not support natively [S] 04; (2) CMOC is a non-standard C compiler whose byte arithmetic silently differs from C and Turbo Pascal [V] section 6; (3) the current C translation's memory model (a flat 1 MB arena of segment:offset far pointers, a byte mirror of DGROUP, an emulated planar EGA) cannot run on a 64 KB address space and must be replaced; (4) the data is 2.6 MB unpacked (1.27 MB compressed) [V], so it streams from disk exactly as on the PC, with disk swaps on floppy.
- **The proven pattern to copy:** assembly engine plus CMOC game logic in banked 8 KB pages, as in Space Bandits on the DynoSprite engine (Jamie Cho, Richard Goedeken), built in the same `jamieleecho/coco-dev` image this project uses [S] 04, 05, 06. Every successful whole-game CoCo 3 port (Glen Hewlett's Pac-Man, Defender and Joust; Sock Master's Donkey Kong) kept the original game logic, translated to native code, and rewrote only the hardware layer as "work-alike" routines [S] 05. We already have the logic as matched, proven Pascal and C.
- **How it will be proven:** the same recorded sessions (`tests/sessions/*.keys`) replayed through an input layer built into the CoCo port, with the 32,000-byte screen and selected state dumped at checkpoints and compared at palette-index level against the host build, headless in MAME with Lua [S] 08.

---

## 2. Facts that shape everything

### 2.1 The machine (details: research 01, 02)

| Item | Value | Tag |
|---|---|---|
| CPU clock | 28.636363 MHz / 16 = 1.789773 MHz after a write to `$FFD9` (0.894886 MHz at power-up) | [S] 01 |
| Cycles per 59.92 Hz field | 29,868 (262 lines x 114 cycles; DynoSprite's benchmark quotes about 29,860) | [S] 01, 02 |
| Video DMA cost | none: the GIME fetches video in the other half of each E cycle | [S] 02 |
| Fill / copy speed, best 6809 code | fill about 2 cycles per byte (unrolled PSHU), copy 3.4 to 4.6 cycles per byte (stack blasting) | [S] 01 |
| Full 32,000-byte screen | clear 34 to 39 ms, copy 60 to 80 ms (about 2 and 4 fields) | [S] 01, 02 |
| Naive C byte loop | 15 to 20 cycles per byte | [S] 01 |
| Interrupt entry/exit | IRQ 19 + 15 cycles (whole state), FIRQ 10 + 6 (PC and CC) | [S] 01 |
| MMU | 64 physical 8 KB blocks (`$00` to `$3F`) on 512 KB; two task register sets `$FFA0` to `$FFA7` and `$FFA8` to `$FFAF`, task select `$FF91` bit 0; constant page `$FE00` to `$FEFF` | [S] 02 |
| Graphics mode for the port | 320x200x16: `$FF98=$80`, `$FF99=$3E`; 160 bytes per line, 32,000 bytes | [S] 02 |
| Screen start | `$FF9D`/`$FF9E`, latched at the top of the frame, so a write flips cleanly; keep screens on 8 KB boundaries (odd offsets can crash the 1986 GIME) | [S] 02 |
| Palette | 16 registers `$FFB0` to `$FFBF`, 6-bit RGB; EGA value e maps to `((e & 7) << 3) \| (e >> 3)` on RGB; write only in the vertical border (visible sparkle otherwise) | [S] 02, 05 |
| Text mode | not usable: the GIME 40x25 text font is fixed in the chip; the game's font is drawn in software (an 8-pixel glyph is 4 bytes, so all 40 columns are byte aligned) | [S] 02 |
| Timer | GIME 12-bit timer; from the 63.695 us line clock a count of 66 lines gives 237.9 Hz (0.5% fast against the game's 236.7 Hz); reload is N+1 on the 1987 GIME and N+2 on the 1986 GIME, so detect the revision at boot. MAME emulates only the 1986 reload (N+2), so test the 1987 path in XRoar; Sock Master notes the timer details are being re-investigated | [S] 02, 09 |
| Sound | 6-bit DAC at `$FF20` and 1-bit sound built in; optional GMC with an SN76489AN at `$FF41` (the Tandy 1000 PSG family), emulated by MAME and XRoar | [S] 02, 05 |
| Disk | RS-DOS 35 tracks, 68 granules x 2,304 bytes = 156,672 bytes of files per disk; DSKCON `JSR [$C004]`, parameter block at `$EA` to `$F0` | [S] 03, 07 |
| Byte order | big endian (PC data is little endian) | [S] 01 |

### 2.2 The game (details: `docs/design/WHITEPAPER.md`)

| Item | Value | Tag |
|---|---|---|
| Overlay code | 35 units, 197,641 bytes of x86; largest ovl16 17,497, ovl13 15,474, ovl12 14,510, ovl22 14,261, ovl03 13,581, ovl19 11,026 | [V] appendix A |
| Resident code | load image 68,592 bytes; code paragraphs 0000 to 0C7C (about 51 KB) include the Borland runtime units (System, Crt, Dos, Overlay), which the port replaces | [V] 3.1 |
| DGROUP | paragraph 0C7C up to the stack segment 14F2: 34,656 bytes (33.8 KB), of which about 17 KB initialised; 16 KB stack | [V] 3.1 |
| Heap in play, measured in 8.1 | peak 182,984 bytes at start-up and the title screen; 118,936 to 142,560 live in the game, of which 2 x 36,888 are the staging screens and 14,136 one picture; the rest 45 to 69 KB (17.6 KB loader blocks, small blocks 11 to 23 KB, loaded pictures). DGROUP: the 17,370-byte constants image never changed in seven sessions; 17,284 bytes of variables, 4,099 of them nonzero at the end | [V] `make heap-stats` |
| Start-up heap blocks | game variables `$800`, a second `$800`, `$400`, ECL buffer `$1E00`, `$588`, wall sets `$924`, GEO planes `$400` (about 17 KB) plus the screen staging buffers and pictures loaded on demand | [V] 3.2.2 |
| DAX data | 113 archives, 1,245 blocks, 1,273,124 bytes packed, 2,603,688 bytes unpacked; largest block 36,881 bytes; 831 blocks are 1 KB or less, 1,178 are 8 KB or less | [V] measured 2026-10-17 |
| Biggest data families (unpacked) | PIC 1.27 MB (92 blocks), SPRIT 308 KB, ECL 176 KB, HEAD 112 KB, 8X8D 99 KB, BODY 98 KB, CPIC 90 KB, FINAL 78 KB | [V] measured |
| Screen layout | 40x25 text cells of 8x8 pixels; adventure screen: 3D view window, side window, text area (`DrawAdventureScreen`) | [V] 5.2 |
| 3D view | 11x11 grid of 8x8 tiles at cell columns and rows 2 to 12 (88x88 pixels), walls built from WALLDEF tile lists, painter's order far to near | [V] 5.2.2 |
| Combat view | 7x7 cells of 24x24 icons (168x168 pixels) over a 50x25 tile map; up to 72 combatants | [V] 5.5.1 |
| Pictures | 4bpp packed records with a 16-colour palette; animations as frames XOR'd against frame 0 with per-frame delays; portraits 40x88 and 48x88; 1-bit 8x8 font, 177 glyphs | [V] 4.2.3 |
| The Tandy path already exists | `VideoAdapter` 2 keeps the DAX pixel bytes unchanged ("adapter 2 copies ByteSize bytes per item unchanged") and writes rows with `Move(..., Mem[TandyScanlineSegments[Row]:FirstCol], RowBytes)`: a per-row base address plus a byte column, which is exactly the GIME's linear 160-byte rows | [V] 5.23, `src/RES07.PAS:872` |
| Sound | PC speaker and Tandy SN76489-family chip, 236.7 Hz timer driver (`src/RES03.ASM`), 11 tunes and effects actually played, no music | [V] 5.14, `c/README.md` |
| Saved game | `SAVGAMx.DAT` 13,137 bytes plus per member `.SAV` 285, `.ITM` 63 x n, `.SPC` 9 x n: about 16 KB per slot | [V] `poolrad/SAVE` |
| Pascal Real | used only in ovl03 and ovl07 (`ScaleMoney` and one roll conversion) | [V] grep of `src/` |

**The single most useful fact:** the matched code already contains a Tandy 1000 graphics path whose data layout (4bpp packed, high nibble left, per-row base address) is the CoCo 3's. The port should select `VideoAdapter = 2` semantics and replace only the address arithmetic, not invent a new renderer. The EGA path the C build currently runs (`c/rtl/ega.c`, planes, latches, write modes) is dropped.

---

## 3. Architecture

### 3.1 Layers

```
+--------------------------------------------------------------+
| Game logic: the Pascal units as CMOC C (generated, see 6.2)   |  banked 8 KB pages
+--------------------------------------------------------------+
| Port RTL in C: strings, sets, heap, Crt/Dos work-alikes,      |  pinned or banked
| DAX container access, save files                              |
+--------------------------------------------------------------+
| Engine in LWASM 6809 assembly: takeover and boot, MMU and     |  pinned core
| far-call trampolines, IRQ/FIRQ, keyboard scan, timer clock,   |  + constant page
| DSKCON wrapper, RLE/ZX0 decode, blitters, glyphs, XOR deltas, |
| fills and copies, line inner loop, sound backends             |
+--------------------------------------------------------------+
| CoCo 3 hardware: GIME, PIAs, DAC, FDC (or SDC), optional GMC  |
+--------------------------------------------------------------+
```

This is the Space Bandits / DynoSprite split [S] 04, 05, 06 and Hewlett's "keep the logic, replace the hardware" rule [S] 05. The boundary between C and the engine is the existing `c/include/platform.h` plus the res07/res09 drawing entry points: everything the game reads from or writes to the machine already goes through a short list there [V] `c/README.md`.

### 3.2 Operating environment: bare metal over Disk BASIC (proposed, decision D3)

Take over the machine at boot (interrupts off, PIA interrupts off, all-RAM mode `$FFDF`, 1.79 MHz `$FFD9`, own vectors at `$FEF4` FIRQ and `$FEF7` IRQ, GIME programmed; **[V] 8.3:** the stubs are three bytes, so a `JMP` goes there, and the words at `$FFF6`/`$FFF8` are written too: MAME reads the vector of `$FFF8` as `$FEF7` in all-RAM mode), and call Disk BASIC's DSKCON only through a wrapper that maps BASIC's low RAM block and the ROM images back in for the duration of each call, exactly as DynoSprite's `System_CallDSKCON` does [S] 03. Do not use the Disk BASIC file manager (OPEN/GET/PUT) or write the FAT at run time: read the directory and FAT once, then read sectors, and save games into pre-allocated files rewritten in place [S] 03.

OS-9/NitrOS-9 Level 2 scored lowest in the comparison (24, against 31 for bare metal with DSKCON and 33 for the recommended hybrid: bare metal now, faster SDC and DriveWire backends later): every process is still a 64 KB map, CMOC's OS-9 library support is partial, and few players boot NitrOS-9 for games [S] 03. Sierra's King's Quest III did ship on OS-9 [S] 06, so this is a defensible alternative, not a mistake.

### 3.3 Memory: physical map (512 KB, candidate)

| Physical blocks | Size | Use |
|---|---:|---|
| `$00` to `$03` | 32 KB | Screen A (32,000 bytes + 768 spare); `$FF9D/$FF9E = $00/$00` |
| `$04` to `$07` | 32 KB | Screen B (back buffer); `$FF9D/$FF9E = $10/$00` |
| `$08` to `$0B` | 32 KB | Optional: composition or clean background (combat map backdrop, save-under, title picture decode target) |
| `$0C` to `$2F` | 288 KB | Code banks (all game code, loaded once at boot, ZX0 compressed on disk) and the resource cache |
| `$30` to `$37` | 64 KB | Pinned core: direct page, globals, heap, stack, engine, CMOC helpers |
| `$38` | 8 KB | Reserved: BASIC low RAM (DSKCON's direct page `$EA` to `$F0` and Disk BASIC's RAM from `$600`) |
| `$39` to `$3B` | 24 KB | Free (more cache or code) |
| `$3C` to `$3F` | 32 KB | Reserved: ROM images in RAM (Color, Extended, Disk BASIC) and the `$FE00` vector page |

Reconciliation note: research 02 proposed resident code in `$30` to `$3B`; research 03 requires `$38` and `$3C` to `$3F` untouched while DSKCON is used. This table honours 03. If a later backend replaces DSKCON entirely (own FDC or SDC driver), blocks `$38` and `$3C` to `$3F` become free as well (40 KB more; `$39` to `$3B` are free already).

Budget [E]: 288 + 24 KB = 312 KB for code and cache. At 250 KB of 6809 code that leaves about 60 KB of cache, enough for the current area's GEO, ECL, wall sets, 8x8 banks, combat icons and a few pictures, but not for PIC animations (the largest PIC block unpacks to 31 KB). Keeping all code resident in RAM after boot means the game never reads code from disk again; if code is closer to 300 KB, the cold units (character creation ovl12/ovl13, the ending ovl18) load on demand like the PC overlays did.

### 3.4 Memory: logical map (CPU 64 KB, candidate, to confirm in 8.1)

| Slot | Address | Normal use | During a DSKCON call |
|---|---|---|---|
| 0 | `$0000` to `$1FFF` | direct page for the engine (`$00xx`), hot globals | BASIC low RAM (block `$38`) |
| 1 | `$2000` to `$3FFF` | globals, heap | unchanged |
| 2 | `$4000` to `$5FFF` | globals, heap, stack (top) | unchanged |
| 3 | `$6000` to `$7FFF` | pinned code: engine, trampolines, DSKCON wrapper, CMOC runtime helpers | unchanged (the wrapper runs here) |
| 4 | `$8000` to `$9FFF` | code window, page 1 | unchanged |
| 5 | `$A000` to `$BFFF` | code window, page 2 (16 KB window with slot 4) | Color BASIC image |
| 6 | `$C000` to `$DFFF` | data window (a DAX block, the ECL buffer of 7,680 bytes, a picture) | Disk BASIC image |
| 7 | `$E000` to `$FDFF` | screen aperture or second data window; `$FE00` page is constant: ISR entry stubs, vectors, sound tick state | top ROM block |

Rules that follow from this map [S] 02, 03, 05:
- Interrupt handlers and their data live in the `$FE00` page or in slots that are never remapped (1 to 3). A handler never assumes what slots 0, 4 to 7 hold.
- The DSKCON wrapper, its caller's stack and the sector buffer live in slots 1 to 4.
- Globals that do not fit slots 0 to 2 (DGROUP is 34,656 bytes and the start-up heap another 17 KB [V]) go into a **data bank** reached through accessors; the big cold tables are the candidates (area map 1,584 bytes, combat occupancy 1,250, the image of typed constants). **Measured in 8.1 [V]: the constants image (17,370 bytes) is read-only in practice and goes to banked read-only data; but the data the C code dereferences at once is still 45 to 58 KB (15 to 17 KB of variables plus 29 to 41 KB of heap), so this map has no room for the code. The question is not which tables to bank but the addressing model: `ports/coco3/docs/PHASE-8.1.md` sections 6.4 and 7, decision D12.**
- Drawing: two options to measure in 8.1. (a) Aperture: map the one or two screen blocks that hold the target rows into slots 6 and 7 (16 KB, but the top 512 bytes of slot 7 are the constant page and I/O, so about 99 writable rows) for each blit. (b) Task 1: a second MMU task with the whole back buffer at `$8000` to `$FCFF` (32,000 bytes end below `$FE00`), the blitter code and the source in slots 0 to 3; a task switch is one store to `$FF91` [S] 02. Research 02 recommends (b); (a) keeps one task and is simpler to reason about.

### 3.5 Banking: how overlays become MMU pages

CMOC has no far calls, overlays or section pragmas [S] 04. The method proven by Space Bandits and DynoSprite [S] 04, 05:
1. Link the pinned core first; extract its symbols from the lwlink map into a generated assembly file of absolute symbols.
2. Compile each unit (or group of units) separately and link it at the code window address (`$8000`) against those symbols, with no CMOC library, so it calls the core's copy of the CMOC helpers instead of carrying its own. **Works [V], step 8.0:** `tools/symexport.py` turns the core's lwlink map into a `constant` section of absolute symbols (restricted to what the bank references, an unresolved one is an error); `lwlink` resolves the bank's calls to `MUL16` and to resident functions against it (Q6 answered).
3. Every call into another bank goes through an assembly trampoline in the core: save the current window mapping, map the callee's pages, call, restore. **Measured in step 8.0: 176 cycles per far call on top of the call itself (287 against 111 for a resident call of the same shape) [V]**, not the few dozen first estimated; calls to the core are plain `JSR`.
4. The unit boundaries are the original 35 overlays plus the resident units, because the original already partitioned the program so that calls across overlay units are rare and the overlay manager made them correct [V] 3.3. An overlay that compiles to more than the window splits along routine boundaries.

Window size (decision D4): 16 KB (two slots) fits most units; ovl16, ovl13, ovl12, ovl22 and ovl03 (13.6 to 17.5 KB of x86) will probably need splitting at 16 KB [E], or the window grows to 24 KB at the cost of data space. Measure the CMOC size of these five first (task 8.1).

---

## 4. Module-by-module plan

Each row says what the module does, how it maps to the CoCo 3, whether the work is assembly or C, and the main risk. Unit names as in `src/` and the whitepaper.

| Module (units) | What it does | CoCo 3 approach | Lang | Risk |
|---|---|---|---|---|
| Runtime System, Crt, Dos, Overlay (res00, res01, res13, res14) | Borland library | Replaced by the port RTL: strings, sets, heap, `KeyPressed`/`ReadKey` work-alikes over the keyboard scanner, `Delay` and `GetTime` from a VBORD frame counter, no overlay manager (banking replaces it) | C + asm | Low |
| Start-up (POOL.PAS, res08, ovl11) | Init chain, overlay set-up, `StartGame` heap blocks | Boot loader fills the code banks (ZX0 [S] 05), takeover, then `StartGame` with the blocks placed by the memory map | asm + C | Medium |
| DAX access (res05) | `LoadDaxBlock`, `UnpackRle`, disk prompts | Containers repacked on the host: id index, 256-byte aligned blocks, pictures preconverted; RLE (or ZX0) decode in asm straight into the data bank; "Insert disk N" becomes "volume N not mounted", 4 drives mounted at once [S] 03 | asm + C | Medium |
| Pictures and blits (res07, ovl32, ovl34, ovl28) | Picture records, `DrawPictureItem(Clipped)`, `ShowPicture`, `FlushPictureChanges`, mirrors, remap, 8x8 symbols, sprites | Use the Tandy (adapter 2) semantics: packed bytes kept as they are; row address table (`base + row * 160`) replaces `TandyScanlineSegments`; byte-aligned unrolled blits for 8x8 tiles (4 bytes x 8) and 24x24 icons (12 bytes x 24); transparency via a mask or compiled sprites for the hot icon set [S] 01, 05; mirror through a 256-byte nibble-swap table; the changed-row trackers flush to the visible screen or drive a page flip | asm | Medium: the clipped blit is the most complex routine (1,811 bytes x86) |
| Text and windows (res09, res06) | `DrawGlyph`, `DrawTextAt`, `ClearWindow`, frames, message line | 1bpp glyph to 4bpp via a colour-pair expansion table (4 lookups per glyph row); PSHU fills for window clears [S] 01, 02, 05 | asm | Low |
| Palette (res07 `SetPaletteRegister`, ovl31 swaps) | EGA palette writes | 64-entry EGA-to-GIME table (exact for RGB, tuned for composite); writes queued and applied in the vertical border [S] 02 | asm | Low |
| 3D view and area views (ovl26, ovl27, ovl29) | Wall view, wilderness 5x5 blocks, overhead map | Unchanged logic; draws through the 8x8 symbol and cell picture blits; the 88x88 view is 3,872 bytes of tiles, cheap [E] about 20,000 cycles, under one field | C | Low |
| Line drawing (ovl30) | Bresenham for missiles and line of sight, sorting | C logic, inner pixel loop in asm if profiling says so | C | Low |
| Combat (ovl08, ovl09, ovl10, ovl31, ovl05, ovl24) | Round loop, AI, map view, damage | C; the 49-cell redraw in `ScrollViewTo` is about 14 KB of icon bytes, 2 to 3 fields [E], acceptable; AI (ovl09) and pathing are the CPU-bound logic to profile first | C | Medium: speed of AI under CMOC |
| Script machine (ovl07) | ECL bytecode VM, game variables | C; ECL buffer (7,680 bytes) in the data window; the VM's hot loop is a profiling target | C | Medium |
| Menus, character creation, spells, shops, temple, camp (ovl01 to ovl06, ovl12, ovl13, ovl15, ovl16, ovl19 to ovl23) | Most of the code by size | C in banks; size, not speed, is the issue; split units above the window | C | High: code size (ovl12 alone is 136 KB of generated C source) |
| Animations and ending (ovl18, PIC/FINAL loaders) | Frame deltas, door animation | XOR delta apply in asm, frame delays from the frame counter; double buffer through `$FF9D/$FF9E` | asm + C | Medium: PIC blocks up to 31 KB unpacked need cache space |
| Save and load (ovl17) | Writes `SAVGAMx.DAT` and member files | Pre-allocated save files written in place; byte order handled (decision D7); slot count limited by disk space (about 16 KB per slot) | C | Medium |
| Sound (res03, `RES03.ASM`) | Speaker and Tandy PSG voice stepper on a 236.7 Hz timer | GIME timer on FIRQ near 237.9 Hz runs the existing driver logic; backend A: 1-bit or DAC square wave for the speaker voice (always present); backend B: GMC `$FF41` with tone periods scaled by 4.0 / 3.579545 = 1.11746 and writes 15 cycles apart [S] 02 | asm | Medium: the GMC shares the cartridge slot with the disk controller (a Multi-Pak is needed for both) [S] 02 |
| Copy protection (code wheel) | Asks for a code wheel answer | Keep, as the C build does; `--skip-intro` equivalent for tests | C | Low |
| Keyboard | PC keys: arrows, Home/End (diagonals), Enter, Esc, letters | PIA matrix scan in asm (polled by the menus, as now); mapping table PC to CoCo; Esc to BREAK; the PC diagonal keys need a mapping (decision D8) | asm | Low |

---

## 5. Performance budget

| Operation | Estimate at 1.79 MHz | Basis |
|---|---|---|
| Full screen clear | 34 to 39 ms | [S] 01 |
| Full screen copy or page compose | 60 to 80 ms | [S] 01, 02 |
| Title picture: read 33 KB packed from floppy | 5 to 10 s; SDC well under 1 s | [E] scaled from 03's 10 KB estimate |
| 10 KB block load | floppy 1.5 to 3 s, SDC 0.05 to 0.3 s, DriveWire 115,200 bps 1 to 1.5 s | [E] 03 |
| 3D view redraw (121 tiles) | about 1 field [E] | section 4 |
| Combat view redraw (49 icons) | 2 to 3 fields [E] | section 4 |
| Sound tick on FIRQ | under 1% of the CPU | [S] 01 |
| Game logic in CMOC | roughly equal to the original on a 4.77 MHz 8088, slower on 16-bit multiply, divide and 32-bit math | [S] 01, 04 |

Rules: anything over about 5 fields (150,000 cycles) per keypress feels slow [S] 01; loads happen where the PC loaded (area change, combat start, picture display), never per move. Measure from the first playable build with a border-colour CPU meter and MAME `totalcycles` traces joined with the lwlink map (log the current bank with each line, since banks share addresses) [S] 05, 08.

---

## 6. The C code: from the Phase 7 translation to CMOC

### 6.1 CMOC traps, verified here

Probe `probes/cmoc-byte-arith.c`, compiled with CMOC 0.1.86 built from source (GitHub mirror `stahta01/cmoc`) and LWTOOLS 4.21, run in CMOC's bundled USim simulator, 2026-10-17 [V]:

| Expression (operands `unsigned char`) | Standard C and Turbo Pascal | CMOC 0.1.86 | `-Wgives-byte` warns? |
|---|---:|---:|---|
| `row * 40` with `row = 10` | 400 | **144** | **no** |
| `a + b` with 200 and 100 | 300 | **44** | yes |
| `k - 10` with `k = 7`, stored in `int` | -3 | **253** | **no** |
| `(long)w1 + w2` (Words 60000, 10000) | 70000 | 70000 | n/a |

So CMOC computes a binary operation on two byte-sized operands (an 8-bit constant counts) in 8 bits, and its own warning misses the multiply and subtract cases with a constant. Research 04 also reports that CMOC takes the signedness of `+ - * /` from the left operand [S] 04. **Re-run on 0.1.100 in the container, step 8.0 [V]:** the same results, on the emulated CoCo 3 in MAME and XRoar (`ports/coco3/probes/byte-arith.c`, `make probe P=byte-arith`); also `a + 100` gives 44, `sa / ub` with `sa` = -8 gives 65532 (the left operand's signedness), and `-Wgives-byte` still warns only when neither operand is a constant (it misses `row * 40`, `k - 10`, `a + 100`). Details: `ports/coco3/docs/PHASE-8.0.md` section 3.

Other CMOC limits that the translated C will hit [S] 04: structs, enums and typedefs only at global scope; `volatile` accepted but ignored (ISR-shared flags go through an asm accessor until shown otherwise); no `inline` or `_Bool`, and designated initializers are probably unsupported (inferred, test it); bit-fields take full storage; `long` arithmetic through helper calls and pointers (about 4 to 6 times the cost of 16-bit for an add, much more for multiply and divide); float only through the BASIC ROM or `--mc6839`, neither bit-compatible with Turbo Pascal's 6-byte Real; no `stdint.h`, `string.h` or `stdio.h` (ship shim headers); globals addressed PC-relative.

### 6.2 Generate CoCo C from the Pascal (proposed, decision D5; the pointer part depends on D12)

8.1 measured how far the existing C is from CMOC: the list of constructs it cannot read (pointers to arrays, parenthesised declarators, compound literals, 32-bit enumerators, anonymous unions, two code generation bugs) is in `ports/coco3/docs/PHASE-8.1.md` section 2 and is the first requirement of the profile.

`tools/c/pas2c.py` already models Turbo Pascal's integer classes exactly (whitepaper appendix D): it knows, for every expression, whether the original computed in Byte, Integer, Word or Longint. The cheapest and safest way to neutralise CMOC's byte rule and its left-operand signedness is a **CoCo profile in the translator** that emits an explicit cast to the Turbo Pascal result type on every binary operation with byte-sized operands, and that also:
- emits native globals and native pointers (2 bytes) instead of DGROUP macros and `farptr`;
- emits struct layouts for records (keeping explicit byte offsets only where a record is read from or written to a file);
- routes every file record through big-endian-safe load and store helpers;
- hoists local types to global scope and avoids designated initializers;
- tags each routine with its bank (from the unit), so the build can link per bank and generate the far-call stubs.

Hand edits to generated C are then limited to the platform layer, as today. The alternative (hand-adapting the 48,000 lines of generated C once) loses the deterministic regeneration that Phase 7 relies on.

### 6.3 Coding rules for C that runs on the CoCo (summary; research 04 has the full list of 25)

1. Every binary operation on two byte operands gets an explicit widening cast (the translator does this; reviewers check hand code with the probe's cases in mind).
2. Use `int16_t`/`uint16_t` loop counters for ranges above 255 and `uint8_t` for byte loops; never rely on C's integer promotions.
3. Keep `long` only where Pascal had `LongInt`; replace `Real` in ovl03 and ovl07 with integer or fixed-point code proven against the host build.
4. No pixel or byte-per-iteration loops in C: call the engine.
5. No structs passed or returned by value in hot code; pass pointers.
6. Data from files is accessed through byte-order helpers, never by casting a buffer to a struct with multi-byte fields.
7. Code in a bank calls other banks only through generated stubs; no pointers into another bank's code or rodata survive a bank switch.
8. Build with `--no-relocate`, `-O2`, `-Wgives-byte -Wsign-compare`; evaluate `-fomit-frame-pointer`; link with our own lwlink scripts, not CMOC's one-line link [S] 04.
9. Keep the C compiler-neutral: compiler-specific syntax (`interrupt`, `asm`, `_CMOC_fpir_`, or gcc's `__attribute__`) only in a few platform files, behind macros, so the same generated C builds with CMOC, gcc6809 and the host compiler (decision D11).

### 6.4 Compiler choice: CMOC or gcc6809 (decision D11)

CMOC is the default. gcc6809 is the one alternative worth measuring, because it addresses three of the port's main constraints at once:

| | CMOC 0.1.100 | gcc6809 (GCC 4.3.x patches, `gitlab.com/dfffffff/gcc6809`, branch `dftools`) |
|---|---|---|
| Speed | about 2x the cycles of gcc6809 (CMOC 0.1.98, ten Vectrex kernels) [S] 04 | baseline; arguments in registers |
| Code size | about 1.28x gcc6809 on the same set [S] 04 | baseline; about 22% smaller could save roughly 50 KB of the estimated 210 to 350 KB [E] |
| Byte arithmetic | 8-bit results on byte operands (section 6.1) [V] | standard C integer promotions |
| Banking | none; hand-rolled trampolines (Space Bandits method, 3.5) [S] 04 | `__attribute__((far("page")))` with a far-call handler, about 70 cycles per call (FreeWPC) [S] 04 |
| Maintenance | active (0.1.100 in 2026), in `coco-dev`, used by shipping CoCo 3 games [S] 04 | 2008-era GCC, described as hard to build; reported crash of the native compiler on Apple Silicon for two-argument functions (prebuilt x86_64 works); prebuilt libgcc lacked `__mulsi3` (needed for LongInt) [S] 04 |
| CoCo support | `--coco` target, runtime, USim | none: own crt0, runtime helpers and lwlink or aslink integration to supply |

The evidence for the gap is a single benchmark of small Vectrex routines (src: https://vectrex.substack.com/p/cmoc-vs-vbcc-vs-gcc6809), not code like ours. Speed matters less here than in an arcade game: every pixel loop is assembly whatever the compiler, and the game is turn based, so CMOC's 2x mostly shows in combat AI and script interpretation per keypress. Code size and the byte-arithmetic rule matter more.

**Bake-off (step 8.1):**
1. Build gcc6809 in a Docker image on x86_64 (not inside the coco-dev image, not on the host Mac), with a working `__mulsi3` and the other 32-bit helpers; record how long it took and every patch needed.
2. Compile the same units with both compilers from the same generated C: ovl09 (combat AI, CPU bound), ovl07 (script interpreter, hot loop) and ovl16 (largest unit, 17.5 KB of x86).
3. Measure code size per unit, cycles in MAME for a fixed workload (a recorded combat round, an ECL script run), and correctness against the host build on the same inputs.
4. Try gcc6809's `far` attribute on a two-bank test, and its interaction with the engine's assembly calling convention.

**Decision rule:** one compiler for all game C (mixing compilers per bank means two calling conventions and two runtime libraries). Switch to gcc6809 only if it is clearly smaller (the target is at least 15% smaller on the three units), produces correct results on all three, and builds reproducibly in a pinned Docker image. Otherwise stay on CMOC. Either way, hot functions found by profiling are rewritten in assembly rather than solved by changing compilers.

---

## 7. Data pipeline (host side)

A deterministic host tool (Python, next to `tools/re/dax.py`) turns the original game folder into CoCo volumes:
1. Read every DAX block with the existing decoders (`tools/re/dax.py`, `pic.py`, `geo.py`, `ecl.py`, `walldef.py`).
2. Convert where it saves CoCo cycles: pictures stay 4bpp (already native) with palettes converted to GIME values; byte-swap the multi-byte fields of records the engine reads in hot paths; keep ECL and other script data byte for byte.
3. Recompress (RLE as shipped, or ZX0 for better ratio and fast 6809 decode [S] 05) and pack into per-volume containers with an id index and 256-byte aligned large blocks; group small blocks.
4. Until 8.9 (D13): emit one container image addressed by logical sector number for the development backend. After 8.9, as D9 decides: RS-DOS `.DSK` images with ToolShed `decb` (about 10 to 12 floppy images for data, code and saves [S] 03) and/or one large image for SDC and DriveWire users. The nine volumes of 8.4 already exist and stay for the floppy path.
5. The tool is reproducible (same input, same image bytes) so tests can diff images.

Legal note: the CoCo images contain SSI's data; like the PC files they are the player's own copy and are never committed (same rule as `poolrad/`).

---

## 8. Verification

The project's identity is proof, and Phase 8 keeps it:
1. **Host first.** The CoCo-profile C (6.2) builds with clang on the host against a host platform layer that models the CoCo screen (one 32,000-byte 4bpp buffer, GIME palette) and replays the existing sessions. Its checkpoints are compared with the Phase 7 goldens at the game-state level and with a new set of 4bpp screen goldens. This proves the new memory model and the translator profile before any 6809 code runs.
2. **CMOC on a simulator.** Unit-level tests compiled with CMOC run headless in USim (`cmoc --usim`, shown working here [V]) and are diffed against the host results: this catches CMOC semantics (6.1) cheaply.
3. **The full port in MAME.** The port has a replay input mode (the keyboard poll returns the next recorded key) and a checkpoint hook (a counter byte at a fixed address); a MAME Lua script runs headless (`-video none -sound none -nothrottle`), dumps the 32,000-byte screen and selected state at each checkpoint and compares at palette-index level with the host goldens [S] 08. Emulator keyboard injection is not used for goldens [S] 08.
4. **XRoar and hardware** for spot checks, both GIME revisions (`-vdg-type gime1986|gime1987`), `-ram 512 -ram-init clear -tv-input rgb` [S] 02, 08. XRoar's GDB stub (port 65520) for source-level debugging; MAME's GDB stub does not support the CoCo 3's CPU type [S] 08.
5. **Profiling** with MAME debugger cycle traces joined to the lwlink map files [S] 08.

Feature flags keep a slow reference path for each engine routine (Hewlett's practice [S] 05), so a fast routine can be bisected against its reference.

---

## 9. Proposed plan of work

| Step | Goal | Exit criterion |
|---|---|---|
| 8.0 Toolchain baseline **(done 2026-10-17, `ports/coco3/docs/PHASE-8.0.md`)** | Container check: `cmoc --help`, NEWS 0.1.86 to 0.1.100, USim and `writecocofile` present; rerun `probes/`; lwlink two-file test of resident symbol export (Q6) | Probe results recorded for 0.1.100; a banked hello world (core plus one window page, far call and return) runs in XRoar and MAME. Met: core plus two banks, nested far calls, both emulators; USim is not in the image, so tests run on the emulated machine |
| 8.1 Measure **(done 2026-10-17, `ports/coco3/docs/PHASE-8.1.md`)** | CMOC-compile the five largest units and one resident unit as they are (with shims) to get real 6809 sizes; measure DGROUP and heap peak on the host (instrument `c/rtl/heap.c` over the goldens) | Size table per unit; window size and data-bank decisions (D4) made from numbers. Met and exceeded: all 46 units compile (overlays 1.06 times the x86), D4 decided, DGROUP and heap measured; the data-bank decision became D12 |
| 8.1b Compiler bake-off | gcc6809 built in a pinned x86_64 Docker image; ovl09, ovl07 and ovl16 compiled with CMOC and gcc6809 from the same C; size, MAME cycles and correctness compared (6.4) | Compiler decision (D11) made from numbers |
| 8.1c Data model study **(done 2026-10-17, `ports/coco3/docs/PHASE-8.1c.md`)** | For each heap block class and the 40 largest globals: who dereferences them, how often per keypress, whether the engine can take the access; choose among the D12 options from numbers | D12 recommended from numbers (hybrid); the placement table and the list of C constructs CMOC cannot read (8.1 section 2.1) are the starting requirements of the profile |
| 8.2 Translator CoCo profile **(done 2026-10-17, `ports/coco3/docs/PHASE-8.2.md`)** | pas2c CoCo profile (6.2); host build with the CoCo memory model and a 4bpp screen model: native pointers for the mapped class only, accessors for the banked class, handles for the engine class, from a placement table | All seven sessions play on the host with the new model; 4bpp screen goldens recorded. Met for the coco profile (full state compared) and the placement model (screens, reads, Random calls, files compared); 971 4bpp checkpoints in `ports/coco3/goldens/4bpp`. Not done: compact 16-bit pointer fields (layout, with D7), the native engine (8.3) |
| 8.3 Engine core **(done 2026-10-18, `ports/coco3/docs/PHASE-8.3.md`)** | Boot and takeover, MMU map, trampolines, IRQ/FIRQ, keyboard scan, frame clock, DSKCON wrapper, RLE decode, fills and blits, glyphs, palette | Engine test program in MAME: draws a DAX picture, text and tiles loaded from a `.DSK`. Met: the original's two title screens, the font text, the 8x8 tiles, DrawBuf blits and flush, the palette registers all equal the original's (recorded screens, and the Phase 7 C game's own routines as reference) in MAME and XRoar; frame clock at 59.9 Hz, 237.9 Hz tick, keyboard scan and DSKCON with interrupts on work. Not done: asm per-row blit paths (a tile costs 7,300 cycles, a full DrawBuf flush 340 ms), the clipped/mirrored/remapped picture calls |
| 8.4 Data pipeline **(done 2026-10-18, `ports/coco3/docs/PHASE-8.4.md`)** | Host tool producing volumes and `.DSK` images (section 7) | Reproducible images; every block round-trips against `make dax`. Met: nine volumes, one container file each, the original's packed blocks untouched; images are byte-identical on a rebuild; all 1,246 blocks equal `tools/re/dax.py` on the host and are read, unpacked and summed by the engine from the images in MAME and XRoar (`make vol-tests`). Disk speed measured: 18 ms a sector in both emulators (12.6 KB/s through the engine). Not done: ZX0 (about 45% smaller), program and save volumes |
| 8.5 First light **(done 2026-10-18, `ports/coco3/docs/PHASE-8.5.md`)** | Title screens, main menu, character creation on the CoCo | `boot-title` and `create-character` sessions match on screen and state in MAME. **Met:** `make first-light` (MAME headless, storage by D13's development backend): the labelled screens of both sessions equal the goldens; `create-character` wrote the character list and the character record the original wrote (words turned, pointers left out) and 391 places of DGROUP equal the host's, 58 differ for reasons listed in `ports/coco3/data/state_ignore.txt` (pointers, the PC's System variables), none unexplained. **Not in 8.5:** the unlabelled per-key screens (16 of 23 equal; the others are the code wheel, whose runes depend on the clock, and mid-redraw captures), a window to play in (XRoar needs a DriveWire backend, after 8.9), the byte order of the files the game loads and reads as records (ITEMS, monsters, saves from the PC: the first session that needs them), sound |
| 8.6 Exploration **(done 2026-10-18, `ports/coco3/docs/PHASE-8.6.md`)** | 3D view, area map, ECL, shops, camp, save and load | `walk-explore`, `camp-save` match. **Met:** `make exploration` (MAME headless): all 8 labelled screens of `walk-explore` and the final screen of `camp-save` equal the goldens; the saved files (`CHRDATB1..6`, `SAVGAMB.DAT`, 13,137 bytes) equal the original's (words in the PC's order, record pointers left out); 387 and 390 places of DGROUP equal, the rest explained in `data/state_ignore.txt`. Needed: 128 picture handles, a 512 sector save area with a directory, swap descriptors for `BlockRead`/`BlockWrite`, a bigger mapped heap (combat peaks at 10.8 KB). **Not in 8.6:** the Real arithmetic (`ScaleMoney`, no float library), the picture records of res12 and ovl13 (combat), sound |
| 8.7 Combat **(done 2026-10-18, `ports/coco3/docs/PHASE-8.7.md`)** | Combat map, AI, animations | `camp-rest-combat`, `parley-combat` match; turn times measured. **Met:** `make combat` (MAME headless): both labelled screens of `camp-rest-combat` and all five of `parley-combat` (the fight to "Continue Battle" after twelve Q keys) equal the goldens, the dice of the two programs are the same sequence, 63 and 67 places of DGROUP explained (pointers, handles), none open; a party member's quick turn takes 5 to 8 s of the 1.79 MHz machine, a round 60 to 90 s (the AI's `ScanTargets`: step 8.9). Found: CMOC drops loops with constant negative bounds, monster records need their words turned (`LoadMonster`), the harness sorted its screens as text. **Open:** the mapped heap has 328 bytes left at the end of the fight (8.9), the Real arithmetic, sound |
| 8.7b Coverage and baseline **(done 2026-10-19, `ports/coco3/docs/PHASE-8.7b.md`)** | Not a step of the original plan: the answer to the review of the approach (goldens recorded by playing leave whole areas unproven) | `make coverage` (what the sessions run), new sessions on the original for the shop, temple, party menus, camp casting, spells in combat, the end of a fight and a scripted fight, `make risk-scan`, the CoCo against all of them. **Met:** 17 sessions (was 7): 52.7 % of the lines of the translated game run in a session (was 39.5 %), 524 of 806 routines; the new sessions found three defects of the translation (a procedure variable named as a statement was never called, so no spell had an effect; `Integer(Word) < 0`; a DAX record not turned round on the CoCo) and one of the original to copy (a local read before it is written); the CoCo plays most of them (table in the report). **Open:** the mapped heap is too small for the shop, a spell-casting combat and the City Hall fight (fatal 0x22, a D12 decision for 8.9), camp screens cannot be compared bit for bit, the wilderness, the ending and 110 of the 127 affect handlers have no session |
| 8.8 Sound **(done 2026-10-19, `ports/coco3/docs/PHASE-8.8.md`; PC speaker on the DAC only, GMC and Tandy dropped by the human)** | FIRQ tick, speaker backend | `make c-sound` equivalent on the CoCo backend. **Met:** the host model of the CoCo driver (generated from the proven host driver) makes the 7,045 speaker events of the golden `sound-driver`; the 6809 makes the same calls for all 20 tunes (MAME, XRoar); the GIME timer interrupt toggles the DAC at the pitch (the clock is exact: 237 ticks per 60 frames); the game plays its effects (18 to 41 per fighting session) and 16 of 16 sessions match with 0 DGROUP places open. **Open:** not heard through a real speaker; pitches above 3.6 kHz are lowered (9 of 1,822 tone ticks); the driver costs 1.2 ms a tick (8.9); the engine has 22 bytes left under `$7C00`, the core 62 |
| 8.9 Performance and release **(8.9a done 2026-10-20, `ports/coco3/docs/PHASE-8.9a.md`: profile, bank groups and LRU -65 % bank loads, drawing in assembly -23 % busy time; 8.9b `PHASE-8.9b.md`: a seventh bank slot (loads -86 % since the start of 8.9) and research on code size and assets with ranked ideas; 8.9c built ideas 1, 2, 4, 5, 6, 7 of that research, measured step by step: banks -5.9 %, image -19.7 % (1.43 MB), storage requests -30 %, busy -1.5 %, bank loads 2,760 to 3,652 (`PHASE-8.9b.md` section 4b); the distribution and the real backends are still to do)** | Profile and hand-optimise hot routines; **then, with the real sizes known, decide the distribution (D9) and write the real storage backends of D13**: floppy volumes with swap UX, SDC command mode, DriveWire; hardware test | Playable on real hardware from the chosen media; the development backend is no longer needed to run a session |
| 8.10 Distribution **(2026-10-23, `ports/coco3/docs/PHASE-8.10.md`)** | The real storage backends of D13 and the packing of D9, as numbers | Three media behind `sec_io`, told apart at boot by drive 0's directory: the development doorbell, **a set of 35 track floppy disks** (disk swaps asked for on the CoCo's text screen, the layout of entries on disks optimised for the swaps of the 16 sessions' reads: 2,513 swaps with two drives for the PC's order, 1,044 for the annealed layout, 54 with ZX0 of the unpacked blocks) and **one file for the CoCo SDC** (a bootable 35 track disk, then the image, read through the SDC's command mode). Floppy and DriveWire need no driver of their own beyond DSKCON. **Not run on hardware**; the SDC driver is proven against a model of the registers only |

---

## 10. Decisions for the human

| Id | Decision | Recommendation | Why |
|---|---|---|---|
| D1 | Minimum machine | CoCo 3, 512 KB, 6809 | Every high-end modern CoCo 3 game needs 512 KB; two screens alone take 64 KB [S] 02, 06 |
| D2 | 6309 support | Optional fast paths only, detected at boot | Enthusiast upgrade; CMOC emits 6809 only [S] 01, 04 |
| D3 | Operating environment | Bare metal, DSKCON through a DynoSprite-style wrapper | Scores highest; proven in DynoSprite [S] 03 |
| D4 | Code window | **16 KB (two slots), confirmed by 8.1**: only `ovl16` exceeds it (22.7 KB, splits at routine boundaries into 14.5 and 7.5 KB), 35 overlays pack into 14 banks; an 8 KB window is impossible without refactoring `CreateCharacter` (9,172 bytes) | [V] 8.1 |
| D12 | Data addressing model (new, from 8.1; studied in 8.1c) | **Confirmed by the human 2026-10-17, implemented on the host in 8.2.** **Hybrid**: pictures, screens, DAX buffers and the EGA tables are engine-owned handles (98.9% of all data references); about 22 KB of the most referenced game data stays mapped with native pointers; the cold rest (about 40 KB) is banked and reached through accessors; a placement table drives the translator. Two address spaces dropped | [V] 8.1c: game logic makes a median 135 and worst 22,392 data references per key; with 22 KB mapped the banked ones are 0 / 720 / 3,323 (median, p90, worst) |
| D5 | How to produce CoCo C | **Done in 8.2:** `pas2c --profile coco` (generator casts, named unions, memset, wrappers; the PC profile's output is unchanged). Extend pas2c with a CoCo profile | Neutralises CMOC's byte rule mechanically, keeps regeneration [V] 6.1 |
| D6 | Sound target | Built-in 1-bit or DAC backend always, GMC optional | GMC needs a Multi-Pak alongside the disk controller [S] 02 |
| D7 | Saved games | Native big-endian format, a few slots per save disk; PC save compatibility only through a host converter | Simpler engine; about 16 KB per slot [V] |
| D8 | Keyboard mapping for PC-only keys (Home, End, PgUp, PgDn diagonals; any function keys) | **Decided in 8.5, not yet play-tested on a real keyboard:** arrows, F1 and F2 as on the PC (the PC's two byte codes: 0, then the scan code); **SHIFT with the arrows is PgUp (up), PgDn (down), Home (left), End (right)**, the PC's diagonals; the translation is in `irq.asm` (`kext`) and the harness types the same codes into the key queue | The CoCo 3 has arrows, F1/F2, ALT and CTRL but no keypad [S] 02 |
| D9 | Media | **Revised 2026-10-18 by the human:** develop against a development storage backend (below) until 8.9 is complete; decide how to pack and distribute for players (floppy volumes with swap prompts, one large SDC or DriveWire image, or both) after 8.9, when the optimisations have shown how big the game really is | Floppy is universal and SDC is the common modern setup [S] 03, but fitting overlays and swapping disks costs more than it teaches while the game is still being brought up (8.5 found 22 banks and four volumes for one session against two 153 KB drives); the real sizes are unknown until 8.9 |
| D10 | Display | RGB default, composite palette option chosen at start | Exact colours on RGB; composite needs a tuned table [S] 02 |
| D11 | C compiler | CMOC by default; gcc6809 only if the 8.1b bake-off shows it clearly smaller, correct and reproducibly buildable; one compiler for all game C | gcc6809 is about 2x faster and 22% smaller on one benchmark and has standard integer promotions and native far calls, but is unmaintained and hard to build [S] 04; section 6.4 |
| D13 | Storage during development (new, 8.5) | **One storage interface, a development backend behind it until 8.9.** The engine reads and writes 256-byte sectors by logical sector number (`read N sectors at LSN`); everything the game loads (code banks, DAX blocks, ITEMS, saves) lives in one container image laid out by a host tool, addressed by LSN, with no FAT, no volumes and no disk prompts. The development backend is served by the test harness (the Lua script in MAME copies the sectors out of the image file through a mailbox request), so it needs no disk emulation. Real backends are written behind the same interface after 8.9, each testable alone: DriveWire (XRoar with a Becker server), SDC command mode (`$43` to `$FF40`, needs VCC's SDC simulator or hardware), and floppy (DSKCON, sector ranges mapped to disks, swap prompts). The current RS-DOS and volume code (`rsdos.c`, `vol.c`, the nine volumes of 8.4, `DSKCON` wrapper) stays as the floppy backend's starting point and is not deleted | 8.5 showed that bank files, FAT geometry and the two-drive MAME limit, not the game, were the obstacles to `create-character`. The SDC does not make a big image look like a big floppy (images above 2,880 sectors are hard disks, reachable only through its command mode, not through `DSKCON`), so every real large-image backend needs its own driver anyway; a single interface gets the game working first. Open: whether `LOADM` can boot from a small floppy image while the big image is mounted on an SDC, and the SDC's real command-mode speed [E] |

---

## 11. Where to read more

| Topic | File |
|---|---|
| CPU, cycle tables, 6309, interrupts, inner loop cookbook (fill, copy, tile and icon blits, RLE decode, 16/32-bit idioms) | `research/01-cpu-6809-6309.md` |
| GIME registers, video modes, palette table, MMU, timer, PIAs, keyboard, sound hardware, double buffering | `research/02-gime-video-memory-io-sound.md` |
| Disk format, DSKCON, SDC, DriveWire, OS-9 vs bare metal, loaders, data packaging, load times | `research/03-storage-os-runtime.md` |
| CMOC language and code generation, lwlink, banking method, alternatives, 25 coding rules | `research/04-cmoc-lwtools-toolchain.md` |
| Glen Hewlett, Sock Master, DynoSprite, Space Bandits, Nick Marentes: techniques and porting lessons | `research/05-masters-hewlett-sockmaster.md` |
| Showcase games, CoCo RPGs, the C64 and Apple II Gold Box ports, capability envelope | `research/06-prior-art-games.md` |
| Ranked reading list of the Color Computer Archive (40 documents, URLs, page pointers) | `research/07-archive-reading-list.md` |
| XRoar, MAME, Lua automation, golden tests, profiling, deployment | `research/08-emulators-testing-workflow.md` |
| The research brief the files were written to | `research/00-brief.md` |
| Independent fact check of this guide against the research files and primary sources | `research/09-factcheck-2026-10-17.md` |

---

## 12. Open questions (consolidated)

Numbered for reference; the research file in brackets has the detail.

1. Is DSKCON reliable at 1.79 MHz on real hardware and controllers (FD-502, SDC)? DynoSprite drops to 0.89 MHz around it. Test early. (01, 03)
2. **Answered in 8.0:** the byte rule holds on 0.1.100; `_CMOC_fpir_` and `--initial-s` exist; new `__gcccall` register convention (B, X, result in X); no 6309 or banking options; `switch` now allows Duff's device. (04; `ports/coco3/docs/PHASE-8.0.md` section 2, 3)
3. **Answered in 8.1:** CMOC output is 1.06 times the x86 for the 35 overlays (209,542 bytes of code, 10,832 of constants, against 197,641), 1.13 for the resident game units; `-fomit-frame-pointer` saves 2.5%, `-O1` costs 14.7%. (01, 04)
4. **Answered in 8.1:** heap peak 182,984 bytes (start-up), 118,936 to 142,560 live in play, 45 to 69 KB without the staging screens; DGROUP: constants image never written, 17,284 bytes of variables, the Borland runtime owns 708 bytes. (this guide 3.4)
5. Which saved-file fields are pointers (whitepaper appendix D says saved files contain heap pointers), and are they read back after a load? Decides how D7 handles them.
6. **Answered in 8.0: yes**, through a `constant` section of absolute symbols; no library search is involved. (04)
7. **Answered in 8.0:** `volatile` is rejected with a warning, but polling loops on a global reload it every pass at `-O2` in the shapes tested; keep ISR-shared flags behind asm accessors anyway. (04)
8. GMC: tone clock confirmed at 4 MHz on hardware (MAME source says 4 MHz); which Multi-Pak slot combinations work with an SDC; Multi-Pak sound mixing. (02, 05)
9. 1986 vs 1987 GIME differences beyond the timer reload and the odd-offset crash; the `$FF91` bit 6 memory type value BASIC writes on 512 KB. (02)
10. Composite palette table on a real TV. (02)
11. Default RS-DOS interleave and whether a custom one helps real floppies; SDC software mount command. (03)
12. Can interrupts stay enabled during DSKCON (for the sound tick)? (03)
13. A tested 6309 detection sequence for boot. (01)
15. Can gcc6809 still be built reproducibly (x86_64 Docker), with working 32-bit helpers, and how do its size and speed compare with CMOC on our own units? (6.4, step 8.1b)
14. Several archive scans (CoCo 3 Service Manual, Tepolt's CoCo 3 assembly book, Secrets Revealed, WD179x and MC6821 datasheets) have no text layer: OCR them locally if their content is needed. (07)

---

## 13. Errata to the research files

Found by the fact check (`research/09-factcheck-2026-10-17.md`); the research files are left as written.

- Step 8.0 results (2026-10-17, `ports/coco3/docs/PHASE-8.0.md`): the image has no `usim` binary (unit tests run as programs on the emulated CoCo, reported through a RAM mailbox); XRoar's `-trap-snap x.ram` is a raw dump of the 512 KB in physical order (the 08 open question); the far call costs 176 cycles; `-Wgives-byte` misses every byte-with-constant case.
- `research/05`, GIME register table and implication 5: `$FF9D`/`$FF9E` hold the screen start in **8-byte** units (physical address / 8), not 16-byte units (MAME `gime.cpp`).
- `research/01`, `research/05`: the field length is 29,868 cycles at 59.92 Hz (262 x 114); the 29,860 figure is DynoSprite's rounded benchmark.

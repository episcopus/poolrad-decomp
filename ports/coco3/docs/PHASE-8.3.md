# Step 8.3: the engine core (report)

Date: 2026-10-18. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.3. Tags: **[V]** verified here by running a tool,
an emulator or the original's own code, **[E]** estimate, **[?]** open.
Reproduce with `make eng-tests` (every engine test, each in MAME and XRoar, with the screen digests compared) and
`make gfx-ref` (the reference), from `ports/coco3`. The commits are 8.3a (`b5ef644`), 8.3b (`18acc24`) and this one.

## Exit criterion

| Criterion | Result |
|---|---|
| boot and takeover, MMU map, trampolines | done in 8.0 and used by every test here (`boot.asm`, `mmu.asm`, `farcall.asm`) |
| DSKCON wrapper, a file system | done: `disk.asm`, `rsdos.c` read the `.DSK` through Disk BASIC's DSKCON from the all-RAM engine (8.3a) |
| RLE decode, DAX containers, pictures | done: `rle.asm`, `dax.c`, `gfx.c`; the original's two title screens come out bit for bit (8.3b) |
| glyphs, tiles, fills, blits, palette | done: `gfx.c` (`gfx_glyph`, `gfx_item`, `db_item`, `db_fill`, `db_flush`, `gfx_pal_reg`) with the kernels in `kernels.asm` (8.3c, e) |
| IRQ/FIRQ, keyboard scan, frame clock | done: `irq.asm` (8.3d) |
| **engine test program in MAME: a DAX picture, text and tiles loaded from a `.DSK`** | **met**: `make eng-test T=t_scene` draws the title picture, the font text and a strip of tiles, all read from one disk image; `t_pic` and `t_gfx` prove each part against the original (below) |

Two reference points judge the drawing: the **recorded screens of the original game** for the pictures (`goldens/4bpp`,
the same digests the Phase 7 host reproduces) and a **reference run of the Phase 7 C game's own routines** for text,
tiles and blits (`goldens/engine/t_gfx.s4`, section 2). Every digest is the SHA-256 of the 32,000 screen bytes and the 16
palette registers, so the palette is part of the proof.

## 1. The engine so far [V]

| File | What |
|---|---|
| `boot.asm`, `mmu.asm`, `farcall.asm` | takeover, the four window slots (shadowed), the far-call trampoline (8.0) |
| `disk.asm`, `rsdos.c` | `dsk_read` (DSKCON through the ROM, the interrupt mask handed back), a read-only RS-DOS reader: directory, FAT, granule chains, a one-sector cache |
| `rle.asm`, `dax.c` | the resumable RLE decoder (a state machine over 256-byte input and any output window), DAX header and block search, `dax_unpack` into RAM or physical blocks from any offset |
| `gfx.c` | the screen (physical blocks 0 to 3), palette, text, pictures in physical blocks, the staging buffer DrawBuf with exact dirty-row tracking |
| `kernels.asm` | `k_copy`, `k_fill` (PSHU, 4 bytes a push), `k_mcopy` (masked), `k_glyph8` (font rows to screen rows) |
| `irq.asm` | frame clock, GIME timer tick, keyboard matrix scan and queue |

**Memory map of the engine's blocks** (physical, 8 KB each, 64 on 512 KB): `$00..$03` the screen (160 bytes a row, rows run on
across block borders, which is why every blit checks that its span stays in a block); `$04..$05` DrawBuf (168 rows of 84
bytes, rows 0 to 96 in block 4, 97 to 167 in block 5, so no row crosses a block); `$08..$37` pictures (a picture and its mask
fit one block, allocated in order; `pic_load`); `$38` the mailbox (and the system pages), `$39..$3F` the machine's
low RAM and BASIC. Window slot 6 is the engine's data window, slot 7 is **not** remapped (it holds the top of the last
block, where the CPU may fetch interrupt vectors, section 4).

**Engine API** (all in `src/engine/eng.h`, the same signatures the translated game will call):

| Group | Calls | Original |
|---|---|---|
| text | `gfx_font_load`, `gfx_glyph(col,row,color,count,glyph,textset)`, `gfx_text` | LoadGameFont, DrawGlyph, DrawTextAt (res06) |
| pictures | `pic_load(&pic, file, block, colorkey, masked)`, `gfx_item` (an item to the screen) | LoadPicture, UnpackPicturePixels, ShowPicture (res07) |
| staging | `db_init`, `db_item(pic,item,col,row,flags)`, `db_fill`, `db_flush` | AllocatePicture(DrawBuf), DrawPictureItem, FillPictureRect, FlushPictureChanges |
| palette | `gfx_palette` (EGA register value), `gfx_pal_reg` | SetPaletteRegister |
| time and keys | `irq_start`, `frame_count`, `tick_start`, `tick_count`, `kbd_get`, `kbd_mods` | the BIOS tick, the timer interrupt, INT 16h |

`Put8x8Symbol` (ovl34) stays game code: `src/engtest/t_gfx.c` writes it out from `db_item` and `gfx_item`.

## 2. The reference and the goldens [V]

`test/gfx_ref.c` runs the **Phase 7 translation of the original's own routines** (DrawTextAt, DrawGlyph, LoadGameFont,
Load8x8Bank, Put8x8Symbol, FillPictureRect, FlushPictureChanges, SetPaletteRegister, in the EGA profile the recorded sessions
use) on one script and prints a 4bpp digest after each of six steps. The CoCo test plays the same script on the engine:

| Checkpoint | Script |
|---|---|
| `blank` | the screen after start-up |
| `text` | DrawTextAt in three colours (lower case folds to upper), a raw glyph run, a run on the message line, clipped columns |
| `tiles` | eight tiles of bank 0 and two of bank 4 straight to the screen (Put8x8Symbol, Direct 0) |
| `flush` | text, then tiles through DrawBuf (masked with colour 13 transparent, opaque, a gap between two tiles of one row) and one flush, so the span rule (a flush copies everything between the first and last changed byte of a row) is exercised |
| `fill` | three rectangles in DrawBuf, clipped left, top, right and bottom, flushed |
| `palette` | two palette registers changed |

**Result [V]: all six checkpoints are equal in MAME (the real GIME rendering, per checkpoint) and in XRoar (the final
screen)**, and `make gfx-ref` confirms the Phase 7 engine still produces them (`goldens/engine/t_gfx.s4`). What the tests do
not reproduce, on purpose: a glyph run that overruns column 39 (the original writes into the next row; no caller does), a
glyph above 176 with the raw font set (the original reads past the font block), blits that do not fit DrawBuf (refused here,
written past the buffer in the original).

## 3. Cost of drawing [V, measured with the frame clock; 1 frame is 29,870 cycles]

`t_perf` times fixed numbers of operations. First the plain C version, then with the kernels and incremental addressing
(both in `git log`, section 5):

| Operation | C first | now | now in ms |
|---|---|---|---|
| one glyph (8 x 8) | 8,360 cycles | 2,840 | 1.6 |
| a 40-glyph line | 335 k | 114 k | 64 |
| one tile to the screen (8 x 8, 32 bytes) | 12,700 | 7,300 | 4.1 |
| one tile into DrawBuf, opaque | 13,200 | 8,800 | 4.9 |
| one tile into DrawBuf, masked | 17,700 | 9,600 | 5.4 |
| clear the screen (32,000 bytes) | 547 k | 146 k | 82 |
| fill all of DrawBuf and flush it (14,112 bytes, 168 rows) | 1.19 M | 606 k | 340 |

The kernels pay (the glyph is 3 times faster), but the tile and flush paths are still far from the 6809's limit: a flush
copies each row twice (DrawBuf to a RAM buffer, buffer to the screen) because slot 7 is not free to hold DrawBuf, and every row
maps a window twice and pays CMOC's call overhead. **[E]** a flush written as one asm loop with both blocks mapped could reach
about 15 cycles a byte (210 k for the whole window), a tile about 1.5 k. That is a task for 8.5, when the profiler of 8.1c can
say which of these the game actually spends its time in; the numbers above are the baseline.

The disk is the other cost: reading `TITLE.DAX` (33,898 bytes, 133 sectors) took 5.5 s of emulated time, 6.1 KB/s, in both emulators
[V, `t_irq`]. Pictures, area files and the 8X8D tile sets all come from the disk, so load times will dominate the feel of the port
until files are cached in banks. **[?]** how much of that is the emulators' disk model and how much a real drive does (a real
controller cannot beat one sector per revolution without interleave tuning, which `decb dskini` does not do).

## 4. Interrupts and the keyboard [V]

* **Frame clock**: PIA0 CB1, the vertical sync at 60 Hz (`$FF03` bit 0, acknowledged by reading `$FF02`), IRQ. 60 frames took
  1.0012 to 1.0014 emulated seconds in MAME, as expected from the 59.92 Hz of the NTSC machine. The GIME's own VBORD
  interrupt was not tried once the vectors were right.
* **Tick**: the GIME timer on FIRQ, a period of reload + 2 units of 63.7 us: reload 64 gives 237.9 Hz, the Phase 7 sound
  driver's rate. XRoar counts 237 to 238 ticks in 60 frames, MAME 236 (a 1% slower timer). The sound step (8.8) will choose the
  reload against whatever the backends need.
* **Vectors, a finding [V]**: in MAME the CPU reads `$FFF8` as `$FEF7` even with all RAM mapped (Disk BASIC's ROM vectors
  point into three-byte stubs in the constant page, `$FEF7` IRQ and `$FEF4` FIRQ, `LBRA $010C` and `LBRA $010F`). My first
  version wrote the handler addresses as words into the constant page and so overwrote those stubs, crashing at the first
  frame. The engine now writes `JMP handler` into both stubs (the way DynoSprite does, the guide's section 2) and also the
  words at `$FFF6`/`$FFF8`, so it works whichever of the two places a machine fetches vectors from. **[?]** which one a
  real CoCo 3 uses in all-RAM mode; both emulators work.
* **DSKCON with interrupts on**: `dsk_read` masks IRQ and FIRQ for its own set-up and hands the caller's mask back; DSKCON
  itself lets the frame interrupt through between sectors, so `frame_count` kept time over a 5.5 s read (331 frames in MAME,
  329 in XRoar) and the data read were correct.
* **Keyboard**: the PIA0 matrix is scanned once a frame (a key counts when two consecutive scans agree), decoded to codes
  by a table, queued (`kbd_get`). The matrix is: the row is the data bit of `$FF00` that reads low, the column the strobed bit
  of `$FF02`; key number = row x 8 + column, in the order `@ABCDEFG`, `HIJKLMNO`, `PQRSTUVW`, `XYZ` up down left right
  space, `01234567`, `89:;,-./`, Enter Clear Break Alt Ctrl F1 F2 Shift. Shift gives the lower case letters and the
  shifted digits and punctuation of the CoCo keyboard. Tested by typing `12 !A` and Enter through MAME's keyboard: the engine
  decodes `31 32 20 21 61 0D` (shift+A is a lower case `a`, as on the machine). XRoar has nobody typing, so the keys are
  checked in MAME only. The mapping of PC-only keys (decision D8) is not made here; the codes for Home, End and the rest are
  8.5's.

## 5. Things found and fixed on the way

| Finding | Fix |
|---|---|
| the mailbox's `MB_ACK` byte was the low byte of the failure count: a screen checkpoint cleared a failed check | moved to `$1008` |
| `k_copy` kept its counter in B, and LDD overwrites B | the counter lives in a direct page byte |
| the Phase 7 harness needs the scanline tables StartGame fills (`EgaScanlineOffsets`), or every ShowPicture lands on row 0 | `gfx_ref.c` fills them |
| DrawBuf and tile trackers: the original keeps flat offsets | the engine keeps first and last byte per row (the order within a row is the same, and only res07 reads them) |

## 6. Not done, and what comes next

* The rest of res07: `DrawPictureItemClipped` (with its save buffer), `MirrorPicture`, `RemapPictureColors`, the CGA/EGA
  branches (not needed on the CoCo). They are engine calls for 8.5, together with their goldens (the 4bpp session goldens
  already cover them in the large).
* Asm versions of the per-row tile paths, the flush and `gfx_item` (section 3).
* Real-hardware checks: the vector fetch, the disk speed, the timer rate (all **[?]** above).
* 8.4, the data pipeline: the original's data files into the `.DSK` layout, the engine's file API over the whole game's file
  set; the same engine tests then run on the converted files.

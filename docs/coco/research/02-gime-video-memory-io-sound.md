# 02: The CoCo 3 machine around the CPU (GIME, video, memory, I/O, sound)

Scope: everything outside the 6809 that the Pool of Radiance (PoR) port touches: the GIME (TCC1014) registers, graphics and text modes, the palette, interrupts and timers, the MMU and physical memory, the PIAs (keyboard, DAC, sound mux), add-on sound hardware, and video timing. CPU instruction timings are only quoted where needed to cost an operation; the CPU research file is authoritative for those.

## Key takeaways for the Pool of Radiance port

1. **Use GIME graphics mode 320x200 at 16 colours**: `$FF98=$80`, `$FF99=$3E`. It is 160 bytes per line, 32,000 bytes per screen, 4 bits per pixel with the **high nibble as the left pixel**. That is byte for byte the same layout as PoR's DAX picture format, so a decoded 320x200 picture can be copied straight into screen RAM. Only the palette needs translating (src: MAME gime.cpp and mc6847.h, see Sources).
2. **The EGA 64-colour palette and the GIME RGB palette are the same 2-bit-per-channel colour space**, with the bits in a different order. GIME = `((ega & 7) << 3) | (ega >> 3)`, which swaps the two 3-bit halves. The table of 16 default EGA colours is in the Palette section. Composite (TV) output uses a completely different encoding, so it needs its own lookup table.
3. **Require 512 KB.** Two full screens (64 KB) plus overlays and a decompressed-data cache do not fit in 128 KB next to BASIC's areas. Physical blocks `$00` to `$2F` exist only on 512 KB machines. The commercial precedent is Sierra's King's Quest III for the CoCo 3, which needs 512 KB.
4. **Double buffer with the vertical offset registers** `$FF9D/$FF9E`. They are latched at the top of the frame, so a write at any time flips the page cleanly at the next frame. Put each screen at the start of an 8 KB block (for example at physical `$00000` and `$08000`), which avoids the documented odd-offset crash on the 1986 GIME.
5. **There is no text mode that can show PoR's text.** GIME 40x25 text exists (200 lines with 8 lines per row), but its 128-character font is fixed inside the GIME and only 8 foreground and 8 background colours are available. Draw the game's 177-glyph 8x8 font in software in the bitmap. An 8-pixel glyph is exactly 4 bytes wide, so all 40 text columns are byte aligned.
6. **Sound tick**: run the GIME timer from the 63.695 us line clock at 66 lines, which gives 237.9 Hz (0.5% fast against 236.7 Hz), and route it to FIRQ. The reload is N+1 on the 1987 GIME and N+2 on the 1986 GIME, so write 65 or 64 depending on the chip and detect the revision at boot. The 279 ns source cannot reach 236.7 Hz, because its 12-bit counter tops out at 1.14 ms.
7. **Sound hardware**: the Games Master Cartridge (GMC, John Linville) has an SN76489AN at `$FF41`, the same family as the Tandy 1000's PSG. It is emulated by both MAME (`gmc`) and XRoar (`-cart-type gmc`). Make it an optional backend, with a 1-bit or 6-bit DAC square-wave fallback driven from the timer FIRQ. On the GMC, rescale tone dividers by 4.0/3.579545 because the clocks differ. Note: the "CoCo PSG" is Ed Snider's YM2149 cartridge, not a Linville AY-3-8913 design as the task brief assumed. The AY-3-8913 is in Tandy's Speech/Sound Cartridge.
8. **Video costs no CPU cycles.** The GIME fetches video in the other half of each E cycle. A frame is 262 lines x 114 cycles = 29,868 CPU cycles at 1.79 MHz. A 32,000-byte full-screen copy takes about 4 frames with PSHS/PULU stack blasting, or 6 to 12 frames with plain LDD/STD loops.

---

## 1. The GIME (TCC1014) register map, $FF90 to $FFBF

The GIME ("Graphics Interrupt Memory Enhancement", also called ACVC, VC2645QC or TCC1014) replaces the CoCo 1/2's SAM and VDG and adds the MMU, interrupt controller, timer and palette (src: https://exileinparadise.com/tandy_color_computer:graphics_interrupt_memory_enhancement). It was designed by VLSI. There are two production revisions, 1986 ("Tequila") and 1987 ("Tortilla"). The 1986 part "contained some bugs that were fixed in a second revision" (src: https://www.cocopedia.com/wiki/GIME).

The bit definitions below were cross-checked against three sources: Sock Master's reference as republished by CoCo Community (src: https://www.cococommunity.net/socks-gime-register-reference/), the NitrOS-9 "Inside" reference, which is a transcription of the Tandy spec plus an addendum (src: https://nitros9.sourceforge.io/wiki/index.php/Inside_-_REFERENCE), and the MAME GIME emulation source (src: https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/gime.cpp). Where they disagree, the table says so.

**Readability.** Only `$FF92` and `$FF93` (pending interrupts) and the MMU and palette registers can be read back. Every other GIME register reads the floating bus (src: MAME gime.cpp `read_gime_register`, Mametesters bug 05135). MMU and palette reads return only the low 6 bits, and bits 7 and 6 float, so mask with `$3F`. **Keep a RAM shadow of every GIME register you write.**

### $FF90 INIT0

| Bit | Name | Meaning |
|---|---|---|
| 7 | COCO | 1 = CoCo 1/2 compatible mode (SAM/VDG video). Must be **0** for GIME graphics and text modes. |
| 6 | MMUEN | 1 = MMU enabled. When 0, the CPU sees physical blocks `$38` to `$3F` (MAME: `block = bank + 56`). |
| 5 | IEN | 1 = GIME IRQ output to the CPU enabled (master switch for `$FF92`). |
| 4 | FEN | 1 = GIME FIRQ output to the CPU enabled (master switch for `$FF93`). |
| 3 | MC3 | 1 = `$FE00` to `$FEFF` is fixed to physical `$7FE00` to `$7FEFF` ("constant RAM" / vector page), whatever the MMU says. |
| 2 | MC2 | 1 = standard SCS (spare chip select, `$FF40` to `$FF5F`, used by disk controllers and the GMC). |
| 1-0 | MC1, MC0 | ROM map when in ROM mode: `0x` = 16K internal + 16K external, `10` = 32K internal, `11` = 32K external (except the interrupt vectors). |

RS-DOS (Disk BASIC) uses `$C4` (196) for CoCo 2 resolutions and `$44` (68) for CoCo 3 graphics (src: cococommunity Sock reference). Recommended value for the port: `$7C` (GIME mode, MMU on, IRQ and FIRQ on, constant page on, standard SCS). The ROM bits do not matter once the machine is in all-RAM mode (`$FFDF`).

### $FF91 INIT1 (write only)

| Bit | Name | Meaning |
|---|---|---|
| 7 | | unused |
| 6 | MTYP | Sock: "Memory type 1=256K, 0=64K chips". MAME and XRoar ignore it. See Open questions. |
| 5 | TINS | Timer clock source: **1 = 279.365 ns, 0 = 63.695 us** (one scan line). |
| 4-1 | | unused |
| 0 | TR | MMU task select: 0 = task 0 (`$FFA0` to `$FFA7`), 1 = task 1 (`$FFA8` to `$FFAF`). |

The Tandy documents describe the fast timer clock as "70 ns". MAME's comments explain that this is wrong: the real clock is 279 ns, one eighth of the 28.636 MHz crystal, and Gault's FAQ agrees (src: MAME gime.cpp TIMER comment). The NitrOS-9 transcription even has the polarity reversed ("0 is 70 ns") and its addendum doubts it. Trust Sock and MAME: TINS=1 selects the fast clock. Changing TINS reloads the timer with its original value (MAME: "This is correct!").

### $FF92 IRQENR and $FF93 FIRQENR

Both registers use the same bit layout. **Writing** enables sources. **Reading** returns the sources that fired and acknowledges them: "Reading from the register tells you which interrupts came in and acknowledges and resets the interrupt source" (src: cococommunity Sock reference).

| Bit | Name | Source |
|---|---|---|
| 7-6 | | unused |
| 5 | TMR | GIME timer reached zero |
| 4 | HBORD | Horizontal border (once per scan line, about 15.7 kHz) |
| 3 | VBORD | Vertical border (once per frame, at the bottom of the active area) |
| 2 | EI2 | Serial data input |
| 1 | EI1 | Keyboard (a row line pulled low) |
| 0 | EI0 | Cartridge (CART line) |

Quirks:
- MAME clears pending flags when a source is disabled by a write ("the act of disabling these interrupts has the exact same effect", credited to Glen Hewlett). Tim Lindner's hardware tests state that on real hardware disabling has no effect on whether the flags are set (src: https://tlindner.macmess.org/?p=762). These two claims conflict. Always acknowledge by reading.
- The NitrOS-9 transcription's author was unsure whether one source can be enabled in IRQ and FIRQ at once. Do not do that.
- The GIME IRQ and FIRQ outputs are wired together with the PIA interrupt outputs (PIA0 drives IRQ, PIA1 drives FIRQ; src: MAME coco.cpp header). If you use GIME sources, disable the PIA sources, and the other way round, or every handler has to poll both.

### $FF94/$FF95 Timer (12 bits, write only)

| Register | Bits |
|---|---|
| `$FF94` | bits 3-0 = timer bits 11-8 (bits 7-4 unused) |
| `$FF95` | bits 7-0 = timer bits 7-0 |

Behaviour (src: cococommunity Sock reference; MAME gime.cpp `reset_timer`; tlindner timer tests):
- The timer counts down continuously. At zero it flags TMR, reloads, and starts again.
- **Writing `$FF94` (MSB) reloads and restarts the counter.** Writing only `$FF95` does not. Write `$FF95` first and `$FF94` last. Do not use `STD $FF94`: the 6809 stores A at `$FF94` before B at `$FF95`, so the restart would use the old LSB. Sock flags the MSB-then-LSB order as giving unexpected behaviour.
- **Off by one or two:** "The 1986 GIME adds 2 to the loaded value and the 1987 GIME adds 1." MAME implements exactly this (`m_timer_value += 1` for 1987, `+= 2` for 1986). So the period is (N+1) ticks on a 1987 GIME and (N+2) ticks on a 1986 GIME.
- **Zero:** the docs say 0 stops the timer. Real hardware instead "re-asserts the interrupt immediately" when 0 is written (tlindner, found while debugging Arkanoid, which "abuses TIMER = 0 for ball ricochet sounds", per MAME). **Never write 0 unless you mean it.**
- Tick periods: slow = 1824 crystal clocks = 63.695 us; fast = 8 crystal clocks = 279.365 ns (MAME: `clock * 3648 * value / 2` and `clock * 16 * value / 2` at 28.636363 MHz).
- Range: slow, 2 to 4097 lines (127 us to 261 ms); fast, 0.56 us to 1.144 ms.
- Text-mode blink is derived from the timer (Sock: blink toggles every 4 timer interrupts). Irrelevant in graphics modes.

### $FF98 VMODE (video mode)

| Bit | Name | Meaning |
|---|---|---|
| 7 | BP | 0 = text (alphanumeric), 1 = graphics (bit plane) |
| 6 | | unused |
| 5 | BPI | Composite burst phase invert (artifact colour set). Selects MAME's alternate composite palette. |
| 4 | MOCH | 1 = monochrome on composite output |
| 3 | H50 | 1 = 50 Hz, 0 = 60 Hz |
| 2-0 | LPR | Lines per row |

LPR values. The sources disagree:

| LPR | Sock and MAME | NitrOS-9 transcription of the Tandy spec |
|---|---|---|
| 000 | 1 | 1 |
| 001 | 1 | 2 |
| 010 | 2 | 3 |
| 011 | 8 | 8 |
| 100 | 9 | 9 |
| 101 | 10 | 10 |
| 110 | 11 | 11 (marked "??") |
| 111 | infinite | 12 (marked "??") |

Graphics at full vertical resolution use 000. Text uses 011 (8 lines). Trust Sock and MAME, which come from hardware testing.

### $FF99 VRES (video resolution)

| Bits | Name | Meaning |
|---|---|---|
| 7 | | unused |
| 6-5 | LPF | Lines per field: 00 = 192, 01 = 200, 10 = zero/infinite (undefined, do not use), 11 = 225 |
| 4-2 | HRES | Graphics: bytes per row 000=16, 001=20, 010=32, 011=40, 100=64, 101=80, 110=128, 111=160. Text: `0x0` = 32, `0x1` = 40, `1x0` = 64, `1x1` = 80 characters |
| 1-0 | CRES | Graphics: 00 = 2 colours (8 pixels per byte), 01 = 4 colours (4 per byte), 10 = 16 colours (2 per byte), 11 = undefined (MAME treats it like 10). Text: bit 0 = 1 enables attribute bytes |

(src: cococommunity Sock reference; MAME gime.cpp `write_gime_register` and the scanline record switch.) The NitrOS-9 transcription has LPF 10 = 210 lines, but Sock and MAME say undefined. MAME's border geometry: 192 lines leaves 25 top-border lines, 200 lines leaves 23, and 225 lines leaves 8.

### $FF9A BRDR (border colour)

Bits 5-0 hold a colour in the same format as a palette register. It is not a palette index. Bits 7-6 are unused. The port should set `$00` (black).

### $FF9B (2 MB / 8 MB upgrade register; not in the Tandy docs)

This register only matters with Disto-style 2 MB boards. MAME: "it affects both the video position, but it also affects normal memory mapping. However, changing $FF9B alone won't affect the MMU; writes to $FFAx are required to latch in the $FF9B value." MAME ORs `($FF9B >> 4) & 3` in as MMU block bits 7-6. XRoar's `-ram 1024`/`-ram 2048` enables the extended MMU bits, which are "write-only" for compatibility with early 2M boards (src: https://www.6809.org.uk/xroar/doc/xroar.shtml). **Do not touch it.** Write 0 at startup if anything.

### $FF9C VSC (vertical scroll)

Bits 3-0 give the smooth-scroll offset in scan lines within a character row. They apply in text and in multi-line-per-row modes and are latched at the top of the frame (MAME `new_frame`). Bits 7-4 are reserved. Not needed by the port.

### $FF9D/$FF9E Vertical offset (screen start address)

| Register | Holds |
|---|---|
| `$FF9D` | physical address bits 18-11 |
| `$FF9E` | physical address bits 10-3 |

Start address = `($FF9D << 11) | ($FF9E << 3)`: a 19-bit physical address (anywhere in 512 KB) in **8-byte steps** (src: MAME `get_video_base`; NitrOS-9 reference "FF9D holds bits 18-11, and FF9E holds bits 10-3"). The video base **ignores the MMU**. Video fetches use physical addresses directly and run linearly across 8 KB block boundaries.

- **Latched once per frame:** "you don't have to worry about registers $FF9D/$FF9E being changed mid-frame ... The video address only gets latched at the top of the frame" (MAME header, quoting John Kowalski, that is Sock Master). This makes page flipping trivial and tear free.
- **Odd values:** "According to JK, if an odd value is placed in $FF9E on the 1986 GIME, the GIME crashes" (MAME). Sock: "Some GIME versions crash on odd values in certain resolutions, so 16-byte steps are safer". Keep `$FF9E` even. Better still, keep screens 8 KB aligned so that `$FF9E = 0`.
- In CoCo-compatible mode, `$FF9D` is masked with `$E0` and `$FF9E` with `$3F`, and the SAM offset is added (MAME). This does not apply to the port.

### $FF9F Horizontal offset

| Bit | Name | Meaning |
|---|---|---|
| 7 | HVEN | 1 = horizontal virtual screen: each row is **256 bytes** whatever HRES says, and only HRES bytes of it are shown |
| 6-0 | X6-X0 | Horizontal start offset in **2-byte** units (0 to 254 bytes) |

Unlike `$FF9D/E`, `$FF9F` can be changed mid-frame. Scan lines wrap at 256-byte boundaries whatever bit 7 says (MAME). The NitrOS-9 addendum reports crashes with offsets above about 5 in graphics mode on some chips [unverified, early report].

### $FFA0 to $FFAF MMU

Task 0 is `$FFA0` to `$FFA7` and task 1 is `$FFA8` to `$FFAF`. Each register maps one 8 KB logical slot: `$FFA0`/`$FFA8` maps `$0000` to `$1FFF`, and so on up to `$FFA7`/`$FFAF`, which maps `$E000` to `$FFFF`. Bits 5-0 select the physical block (0 to 63, physical address bits 18-13). Details are in section 5.

### $FFB0 to $FFBF Palette

There are 16 registers of 6 bits each. Writes are masked to `$3F`. Reads return bits 5-0 plus floating bits 7-6, so `POKE &HFFB1,255:PRINT PEEK(&HFFB1)` gives 127 (MAME comment). "Both reading and writing to the palette registers causes a small 'glitch' on the screen", so change the palette "while the video is in the vertical or horizontal border" (Sock). In text mode, `$FFB0` to `$FFB7` are the background colours and `$FFB8` to `$FFBF` the foreground colours. The format is in section 3.

### Neighbours: $FFC0 to $FFDF (SAM compatibility) and $FFE0 to $FFFF

- `$FFD8` / `$FFD9`: write selects 0.89 MHz / **1.79 MHz** CPU clock (Sock).
- `$FFDE` / `$FFDF`: write selects ROM mode / **all-RAM mode** (Sock).
- `$FFE0` to `$FFFF` (the 6809 vectors) always read from the internal ROM image (MAME `coco3_mem`: `map(0xffe0, 0xffff).rom()`). "You can't change the $FFxx vectors" (Sock). They point into the `$FExx` page (section 4).

### 1986 vs 1987 GIME: summary of documented differences and bugs

| Item | 1986 GIME | 1987 GIME | Source |
|---|---|---|---|
| Timer reload | N + 2 | N + 1 | Sock, MAME |
| Odd `$FF9E` | can crash the GIME | (not reported) | MAME quoting JK; Sock says "some GIME versions" |
| Timer = 0 | re-asserts the IRQ immediately (tested on an '86 GIME) | [unverified] | tlindner |
| Composite colours | XRoar offers `-vdg-type gime1986` / `gime1987`, implying visible differences | | XRoar manual |
| "Bugs fixed in the second revision" | yes | | CoCoPedia GIME |

I could not reach a complete published per-revision bug list ("the GIME bug list") during this session. The CoCo Community copy of Sock's page is the closest. Everything above that is marked [unverified] should be tested in XRoar with both `-vdg-type` settings and, if possible, on real hardware.

---

## 2. Graphics and text modes

### Mode table (graphics, `$FF98` bit 7 = 1)

Pixels per line = bytes per row x pixels per byte. The rows below are the useful combinations (src: Sock HRES/CRES table; MAME render switch; exileinparadise mode list).

| HRES (bytes/row) | CRES | Bits/pixel | Width x colours | `$FF99` (200 lines, LPF=01) | Bytes per 200-line screen |
|---|---|---|---|---|---|
| 111 (160) | 10 | 4 | **320 x 16** | **`$3E`** | **32,000** |
| 111 (160) | 01 | 2 | 640 x 4 | `$3D` | 32,000 |
| 110 (128) | 10 | 4 | 256 x 16 | `$3A` | 25,600 |
| 110 (128) | 01 | 2 | 512 x 4 | `$39` | 25,600 |
| 101 (80) | 10 | 4 | 160 x 16 | `$36` | 16,000 |
| 101 (80) | 01 | 2 | 320 x 4 | `$35` | 16,000 |
| 101 (80) | 00 | 1 | 640 x 2 | `$34` | 16,000 |
| 100 (64) | 10 | 4 | 128 x 16 | `$32` | 12,800 |
| 100 (64) | 00 | 1 | 512 x 2 | `$30` | 12,800 |
| 011 (40) | 01 | 2 | 160 x 4 | `$2D` | 8,000 |
| 011 (40) | 00 | 1 | 320 x 2 | `$2C` | 8,000 |
| 010 (32) | 00 | 1 | 256 x 2 | `$28` | 6,400 |

For 192 lines, clear bit 5 (for example `$1E` for 320x192x16: 30,720 bytes). For 225 lines, set bits 6 and 5 (`$7E`: 36,000 bytes). There are no 16-colour modes at 512 or 640 pixels wide (exileinparadise table).

**Pixel packing.** MAME's `emit_graphics` takes pixel j of a byte as `data >> (8 - (j+1)*bpp)`, so **the most significant bits are the leftmost pixel**. In 16-colour mode the **high nibble is the left pixel** and the low nibble the right pixel, exactly as in the DAX picture format (src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/video/mc6847.h). In 4-colour mode, bits 7-6 are the leftmost pixel.

### Comparison with EGA mode 0Dh (320x200x16)

| | EGA mode 0Dh | GIME 320x200x16 |
|---|---|---|
| Memory organisation | 4 bit planes, 40 bytes per plane per line, 8,000 bytes per plane | Packed (chunky) 4 bpp, 160 bytes per line, linear |
| Bytes per screen | 32,000 (4 x 8,000) | 32,000 |
| CPU view | 8 KB window at A000:0000, plane select via Map Mask/Read Map | Physical RAM, mapped by the MMU in 8 KB slots; the whole screen fits in a 32 KB logical window |
| Write helpers | Write modes 0 to 2, latches, bit mask, set/reset, logical ops | None. Every pixel change is a CPU read-modify-write of a byte (masking nibbles for odd x) |
| Page flip | CRTC start address (pages within 256 KB) | `$FF9D/$FF9E`, anywhere in 512 KB in 8-byte steps, latched per frame |
| Palette | 16 attribute registers, each selecting 1 of 64 (2 bits per channel) | 16 registers, each selecting 1 of 64 (2 bits per channel, different bit order) |
| Scan lines | 200 at about 60 Hz on a 15.7 kHz monitor | 200 at 59.92 Hz, 15.7 kHz (RGB or composite) |
| Border | overscan register | `$FF9A` |

Porting consequence: the emulated EGA (planes, latches, write modes) in `c/platform` should be **replaced, not ported**. Every EGA drawing path in the game reduces to packed-nibble blits. Latch-based copies (EGA write mode 1 screen-to-screen copies) become plain byte copies. The "bit mask" style single-pixel plotting in the line-drawing unit becomes nibble masking.

### Screen start, page flipping and double buffering

- Screen start = any 8-byte-aligned physical address (16-byte aligned to be safe, 8 KB aligned to be safest), set through `$FF9D/$FF9E` (section 1).
- Writing `$FF9D/$FF9E` takes effect at the next frame. Standard sequence: finish drawing into the back buffer, write the new start address, wait for the next VBORD (or the PIA field sync), then treat the old front buffer as the new back buffer.
- Because 160 is a multiple of 8, **vertical hardware scrolling** by whole lines also works (start = base + 160 x y). PoR does not need it.
- **Horizontal hardware scrolling:** set `$FF9F` bit 7 (256-byte virtual rows) and step bits 6-0 in 2-byte units (4 pixels at 16 colours). A 256 x 200 virtual screen is 51,200 bytes. PoR has no use for this.

### Text modes (`$FF98` bit 7 = 0)

- 32, 40, 64 or 80 columns (HRES), optionally with attributes (CRES bit 0). With attributes, even bytes are characters and odd bytes are attributes (NitrOS-9 reference).
- Attribute byte (MAME `emit_gime_text_samples`; NitrOS-9): bit 7 = blink, bit 6 = underline, bits 5-3 = foreground (palette `$FFB8` + n), bits 2-0 = background (palette `$FFB0` + n).
- **40x25 is achievable:** `$FF98 = $03` (text, LPR 8 lines), `$FF99 = $25` (LPF 200, 40 columns, attributes). 200 / 8 = 25 rows, 2,000 bytes.
- **Why not for PoR:** the glyphs come from a 128-character font built into the GIME (MAME's `hires_font[data & 0x7f]`), and no source documents a way to redefine them. PoR has a 177-glyph custom font, draws text over pictures, and mixes text windows with graphics on one screen. MAME records `$FF98` and `$FF99` per scan line, and Sock lists `$FF99` resolution and LPR among the registers demos change mid-frame. A raster split between a text band and a graphics band is therefore conceivable, but BP (bit 7) is not on that list, so it is [unverified] and not worth the risk.

**Software text cost in 320x200x16.** An 8x8 glyph at 4 bpp is 4 bytes x 8 rows = 32 bytes. One way to expand it: split each font row byte into four 2-bit pairs and look each pair up in a 4-entry table per (foreground, background) pair, giving one output byte each. That is roughly 60 to 80 cycles per row, or 500 to 650 cycles per glyph [estimate]. A full 1,000-cell 40x25 redraw is then about 0.55 M cycles (about 0.3 s at 1.79 MHz). Typical menu updates touch tens of cells, a few milliseconds.

---

## 3. The palette

### RGB format (the CM-8 analog RGB monitor, or any RGB/scart/VGA adapter)

| Bit | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|
| | R1 | G1 | B1 | R0 | G0 | B0 |

Each channel is `(X1 << 1) | X0`, a 2-bit intensity 0 to 3. MAME renders the levels 0, `$55`, `$AA`, `$FF` (src: MAME `get_rgb_color`: red = `((c>>4)&2)|((c>>2)&1)` scaled by `$55`). NitrOS-9: "In RGB mode, the bits hold R1, G1, B1, R0, G0, B0, giving 64 combinations".

### Composite format (TV through RF, or the composite jack)

Bits 5-4 are intensity (I1 I0) and bits 3-0 are phase/hue (P3 to P0): 4 intensities x 16 phases (NitrOS-9). Phase 0 is grey: MAME's composite table has `$00` black, `$10` = `#2D2D2D`, `$20` = `#747474`, `$30` = `#FDFDFE`, with `$3F` also white. `$FF98` bit 5 (BPI) shifts the hues to MAME's alternate table, and bit 4 (MOCH) turns the output monochrome. **The same palette byte gives unrelated colours on RGB and composite**, so the port needs two palette tables and a user choice. Super Extended BASIC handles this with its `PALETTE RGB` / `PALETTE CMP` commands [general knowledge, not re-checked].

### EGA vs GIME: the same 64-colour space

The EGA 64-colour attribute value is laid out `r g b R G B` (bits 5 to 0), with uppercase bits worth 2/3 and lowercase bits 1/3. The GIME is `R G B r g b`. Both have 2 bits per channel and 64 colours on the same 4-level grid, so the mapping is **exact** in RGB. It is a swap of the two 3-bit halves:

```
gime_rgb = ((ega64 & 0x07) << 3) | (ega64 >> 3);   /* exact, both directions */
```

Default EGA 16-colour palette (attribute registers 0 to 15 = EGA values 0,1,2,3,4,5,20,7,56,...,63). The RGB values and GIME bytes were computed with the formula and checked against MAME's RGB decoder. The composite column is the nearest match (CIELAB distance) to **MAME's emulated** NTSC composite table, with greys forced to the grey column. It is a starting point only, [unverified] on a real TV:

| EGA index | Colour | EGA 64 value | RGB | **GIME RGB byte** | Composite suggestion (MAME approx.) |
|---|---|---|---|---|---|
| 0 | black | 0 | 000000 | **$00** | $00 |
| 1 | blue | 1 | 0000AA | **$08** | $0A |
| 2 | green | 2 | 00AA00 | **$10** | $11 |
| 3 | cyan | 3 | 00AAAA | **$18** | $2E |
| 4 | red | 4 | AA0000 | **$20** | $16 |
| 5 | magenta | 5 | AA00AA | **$28** | $18 |
| 6 | brown | 20 | AA5500 | **$22** | $15 |
| 7 | light grey | 7 | AAAAAA | **$38** | $20 |
| 8 | dark grey | 56 | 555555 | **$07** | $10 |
| 9 | light blue | 57 | 5555FF | **$0F** | $2B |
| 10 | light green | 58 | 55FF55 | **$17** | $21 |
| 11 | light cyan | 59 | 55FFFF | **$1F** | $3E |
| 12 | light red | 60 | FF5555 | **$27** | $27 |
| 13 | light magenta | 61 | FF55FF | **$2F** | $29 |
| 14 | yellow | 62 | FFFF55 | **$37** | $33 |
| 15 | white | 63 | FFFFFF | **$3F** | $30 |

Composite has only 4 greys (0, `#2D`, `#74`, `#FD` in MAME), so EGA's 4 greys map to `$00`/`$10`/`$20`/`$30`. Composite also has 16 hues per intensity rather than an RGB cube, so several EGA colours land on approximate hues. Ship the composite table as data that can be tuned by eye.

Strategy: keep pixel data as EGA indices 0 to 15. Translate each palette entry, whether a picture's own palette or the EGA default, through a 64-byte `ega64 -> gime` table (the swap above for RGB, a hand-tuned table for composite), then write the 16 bytes to `$FFB0` to `$FFBF` during the vertical border. A 16-register update is about 16 x (LDA ,X+ then STA ext) = 16 x 11 = 176 cycles [standard 6809 timings], well inside the border. If a scene uses one picture palette for the window and another for the frame, the two must be merged into one 16-entry set, as on EGA.

---

## 4. Interrupts and timing

### Video timing (NTSC)

- Crystal 28.636363 MHz. CPU E clock = crystal / 16 = **1.789773 MHz** in fast mode (MAME sets the GIME and CPU from `XTAL(28'636'363)`; the coco3 driver's E is `/32` x 2 internally). Slow mode is 0.894886 MHz.
- One scan line = 912 dot clocks at 14.318 MHz = **63.695 us = 114 CPU cycles** at 1.79 MHz (MAME `set_raw(28.636363_MHz_XTAL/2, 912, ..., 262, ...)`).
- Frame = **262 lines** (non-interlaced) = 16.688 ms = **59.92 Hz** = **29,868 CPU cycles** (14,934 at 0.89 MHz).
- Frame regions at 192 lines (MAME): top border 25, body 192, bottom border 26, vertical retrace 6, vertical blanking 13. At 200 lines the top border is 23.

### Does video steal CPU cycles?

No. On a stock CoCo 3 "video memory access occurs in the low half of the E cycle, and CPU access in the high half". The GIME "accesses memory in 16 bit amounts": a video read fetches 16 bits and saves one byte (src: https://www.go4retro.com/?p=1416). There is no DMA stall at either clock speed. MAME models none, and every program sees the full 29,868 cycles per frame whatever mode or resolution is displayed [stated by the go4retro hardware description; no source found that explicitly says "zero stall"].

### Cost of a full-screen (32,000-byte) copy

These use standard 6809 cycle counts: LDD/STD indexed with autoincrement-by-2 8 cycles; 5-bit offset indexed 6 cycles; PSHS/PULU 5 + 1 per byte. Cross-check with the CPU research file.

| Method | Cycles per byte | Total | Frames at 1.79 MHz |
|---|---|---|---|
| `LDD ,X++ / STD ,Y++ / CMPX / BNE` loop | about 11.5 | about 368,000 | 12.3 |
| Unrolled `LDD n,X / STD n,Y` | about 6 | about 192,000 | 6.4 |
| Stack blast `PULU D,X,Y / PSHS D,X,Y` (6 bytes per 22 cycles) | about 3.7 + loop | about 120,000 | **about 4.0** |
| HD6309 `TFM` (6 + 3n) | 3 | about 96,000 | 3.2 |
| Clear with `PSHU D,X,Y,S,DP` (9 bytes per 14 cycles) | about 1.6 | about 50,000 | 1.7 |

So a full-screen copy costs about 7% of one second at best. The game should redraw dirty regions (3D view, text window, combat icons) rather than copying whole frames. PoR has no vsync dependency, so a 4-frame full-screen update when changing scenes is acceptable.

### Interrupt sources available

| Source | Rate | Route | Enable / acknowledge |
|---|---|---|---|
| GIME TMR | programmable | GIME IRQ or FIRQ | `$FF92/$FF93` bit 5; read to acknowledge |
| GIME VBORD | 59.92 Hz | GIME IRQ or FIRQ | bit 3 |
| GIME HBORD | 15.7 kHz | GIME IRQ or FIRQ | bit 4 |
| GIME EI1 keyboard | on key press | GIME IRQ or FIRQ | bit 1 |
| GIME EI0 cartridge | CART line | GIME IRQ or FIRQ | bit 0 |
| PIA0 CA1 = HSYNC | 15.7 kHz | CPU IRQ | `$FF01` bit 0 enable, bit 1 edge; read `$FF00` to clear |
| PIA0 CB1 = field sync (VSYNC) | 59.92 Hz | CPU IRQ | `$FF03` bit 0 enable, bit 1 edge; read `$FF02` to clear |
| PIA1 CA1 = RS-232 carrier detect | | CPU FIRQ | `$FF21` bit 0 |
| PIA1 CB1 = CART (cartridge autostart) | | CPU FIRQ | `$FF23` bit 0 |

(src: CoCoPedia PIA page, https://www.cocopedia.com/wiki/PIA; MAME coco.cpp PIA comments; Sock.) A PIA control register's bit 7 is that input's interrupt flag.

### Vectors and what BASIC does

| Vector | CPU reads | Points to (`$FExx`, constant page) | BASIC's RAM jump |
|---|---|---|---|
| SWI3 | `$FFF2` | `$FEEE` | `$0100` |
| SWI2 | `$FFF4` | `$FEF1` | `$0103` |
| FIRQ | `$FFF6` | `$FEF4` | `$010F` |
| IRQ | `$FFF8` | `$FEF7` | `$010C` |
| SWI | `$FFFA` | `$FEFA` | `$0106` |
| NMI | `$FFFC` | `$FEFD` | `$0109` |
| RESET | `$FFFE` | | `$8C1B` |

(src: cococommunity Sock reference.) Each `$FExx` entry is a 3-byte JMP. With MC3=1 the `$FExx` page is physical `$7FE00` and is visible in every task and every mapping. The port should **write its own `JMP handler` directly into `$FEF4` (FIRQ) and `$FEF7` (IRQ)**, skipping BASIC's second hop through `$010C`/`$010F` and saving a 4-cycle extended JMP per interrupt. Keep NMI (`$FEFD` and `$0109`) pointing at Disk BASIC's handler if the port calls DSKCON, because the floppy controller uses NMI to end transfers [general knowledge; check in the disk research file].

What BASIC leaves running when a program takes over [general knowledge, unverified in this session]: Color BASIC enables the PIA0 CB1 60 Hz field-sync IRQ. Its handler at `$010C` updates the TIMER variable, the PLAY/SOUND timing and the Disk BASIC motor-off countdown. Cartridge FIRQ (PIA1 CB1) is enabled for autostart. GIME interrupts are normally off (RS-DOS INIT0 `$C4`/`$44` has IEN = FEN = 0, per Sock). Takeover sequence: `ORCC #$50`; disable PIA0 HSYNC and VSYNC IRQs (clear bit 0 of `$FF01` and `$FF03`) and the PIA1 CART FIRQ (`$FF23` bit 0); read `$FF00`, `$FF02`, `$FF92`, `$FF93` to clear pending flags; install vectors in `$FExx`; program the GIME; `ANDCC #$AF`. Turn the drive motor off before taking over the IRQ, because BASIC's motor timeout will no longer run.

### Getting the 236.7 Hz sound tick

236.7 Hz is a period of 4224.8 us = 66.33 lines.

| Value written N | Period on 1987 GIME (N+1 lines) | Rate | Period on 1986 GIME (N+2 lines) | Rate |
|---|---|---|---|---|
| 64 | 65 lines, 4140.2 us | 241.5 Hz | 66 lines, 4203.9 us | **237.9 Hz** |
| 65 | 66 lines, 4203.9 us | **237.9 Hz** | 67 lines, 4267.6 us | 234.3 Hz |
| 66 | 67 lines | 234.3 Hz | 68 lines | 230.9 Hz |

- Best fit: **66 lines = 237.88 Hz, +0.50%** against 236.7 Hz. Write 65 on a 1987 GIME and 64 on a 1986 GIME. The fast 279 ns source cannot be used (4224.8 us needs 15,123 ticks, more than the 12-bit maximum of 4,095).
- **Revision detection at boot:** program the slow timer with N=1 (period 2 or 3 lines) and count TMR flags across one field-sync period of 262 lines. About 131 counts means 1987, about 87 means 1986. It costs about 1/60 s once. Exact counts depend on phase, so threshold at 109.
- Alternatives: run the timer at an audio sample rate and derive the tick in software (every 33 samples at 2 lines per sample gives 7,851 / 33 = 237.9 Hz). This is the natural choice if the DAC/1-bit sound backend needs a high-rate interrupt anyway (section 7). A 60 Hz-only approach (4 ticks per frame, 240 Hz average) would bunch the ticks and is not recommended.
- **Route the timer to FIRQ.** Entry pushes only PC and CC: 10 cycles, plus 6 for RTI, against IRQ's 19 + 15 [standard 6809 timings]. Acknowledge with `LDA $FF93` (5 cycles). The handler must save any registers it uses.
- Use **VBORD on IRQ** (or PIA0 field sync) for the 60 Hz frame counter, the time of day (PoR uses the time of day and Delay), page-flip completion and palette updates.

---

## 5. The MMU and physical memory

### Blocks, tasks and the physical map

- 8 KB blocks. A 512 KB machine has 64 blocks, `$00` to `$3F` (physical address = block x `$2000`).
- **128 KB machines** have only blocks `$30` to `$3F` (physical `$60000` to `$7FFFF`). "On a 128K CoCo, you can't even use blocks 00 to 2F" (src: https://www.cocopedia.com/wiki/Understanding_and_Using_the_MMU). In MAME, lower block numbers alias (address modulo RAM size). exileinparadise's map shows blocks `$00` to `$2F` mirroring. Sock's page says "56-63 on 128K machines", which conflicts; CoCoPedia, exileinparadise and MAME all agree on `$30` to `$3F`.
- **2 MB / 8 MB boards** extend the block number through `$FF9B` (section 1). XRoar supports 1024K and 2048K. Do not depend on it.
- Two register sets: task 0 (`$FFA0` to `$FFA7`) and task 1 (`$FFA8` to `$FFAF`), selected by `$FF91` bit 0. Switching tasks swaps all 8 slots in one write.
- BASIC's power-up task 0 values are `$38` to `$3F` (written as `$78` to `$7F`; bit 6 is ignored) (CoCoPedia MMU page).

Physical map as Super Extended BASIC uses it (src: https://exileinparadise.com/_export/raw/tandy_color_computer:memory_map; NitrOS-9 reference):

| Blocks | Physical | BASIC use |
|---|---|---|
| `$00`-`$2F` | `$00000`-`$5FFFF` | 512 KB only. Free for programs. |
| `$30`-`$33` | `$60000`-`$67FFF` | HSCREEN hi-res graphics pages |
| `$34` | `$68000`-`$69FFF` | HGET/HPUT buffer |
| `$35` | `$6A000`-`$6BFFF` | secondary stack area |
| `$36` | `$6C000`-`$6DFFF` | 40/80-column text screen |
| `$37` | `$6E000`-`$6FFFF` | unused |
| `$38`-`$3B` | `$70000`-`$77FFF` | the "64K" machine's low 32 KB: BASIC variables, program, PMODE screens |
| `$3C`-`$3F` | `$78000`-`$7FFFF` | ROM area: Extended BASIC, Color BASIC, Disk BASIC/cartridge, Super Extended BASIC (ROM in ROM mode; RAM in all-RAM mode) |
| (`$3F`) | `$7FE00`-`$7FEFF` | constant vector page when MC3=1 |
| | `$FF00`-`$FFFF` logical | I/O and vectors in every mapping |

ROM quirks (CoCoPedia MMU RAMROM page; MAME `update_memory`): in ROM mode, blocks `$3C` to `$3F` read ROM, and "the MMU ignores the lower two bits of the written value and substitutes the slot number's lower two bits". `$3C` appears only in slots 0 and 4, `$3D` in 1 and 5, `$3E` in 2 and 6, `$3F` in 3 and 7. In all-RAM mode (`$FFDF`) they are ordinary RAM. The CoCo 3 BASIC startup copies the ROMs into this RAM and runs from RAM [widely reported; not confirmed from a primary source in this session]. If the port keeps Disk BASIC's DSKCON, it must leave the Disk BASIC image in block `$3E` (logical `$C000` to `$DFFF`) intact and map it in when calling.

### Constant RAM at $FE00 to $FEFF

With INIT0 bit 3 (MC3) set, logical `$FE00` to `$FEFF` always maps to physical `$7FE00` to `$7FEFF`, whatever slot 7 maps (MAME: bank 8 is forced to RAM with offset `$1E00` in block `$3F`). This is the one 256-byte page that is guaranteed visible in every task and mapping. Put the interrupt vectors (`$FEEE` to `$FEFF`), the FIRQ and IRQ entry stubs, the MMU shadow registers and the far-call trampoline here.

### Bank switching safely

1. Never remap the slot that the executing code, the stack, or a live pointer occupies. Keep the code that switches banks in an unswitched slot or in `$FE00` to `$FEFF`.
2. Interrupt handlers must live in memory mapped in every configuration (the `$FExx` page plus a permanently mapped "home" slot). They must not assume what the switchable slots hold. If an ISR itself banks (for example to read sound data), it must save and restore the shadow and the register.
3. Updating a shadow and the register together is a two-step sequence. Either disable interrupts around it (`ORCC #$50` ... `ANDCC #$AF`, 6 cycles) or make sure no ISR touches that slot.
4. MMU registers can be read back (`& $3F`), but keep a RAM shadow anyway: it is faster with direct-page addressing, and readback is unreliable beyond 512 KB.

**Cost:** `LDA #blk; STA $FFA2` = 2 + 5 = **7 cycles**. With DP = `$FF`, `STA <$A2` is 4 cycles. Map and restore with shadow upkeep inside a far-call trampoline: about 30 to 50 cycles [estimate]. A task switch (`LDA #shadow|1; STA $FF91`) is 7 cycles. Remember that `$FF91` also holds TINS (timer source), so write the full shadowed value.

### 128 KB vs 512 KB: evidence for requiring 512 KB

- The CoCo 3 shipped with 128 KB (cat. 26-3334, $219.95 at launch on 30 July 1986). Tandy's 512 KB upgrade (26-3335) cost "an additional $149.95". Later, a 1991 listing had the board without chips at $39.95 plus RAM chips at $59.95 (src: https://www.cocopedia.com/wiki/Color_Computer_3).
- Third-party 512 KB boards were common. The archive's Manuals/Hardware folder holds manuals for the Tandy 512K Expansion RAM Card, Performance Peripherals, Cloud-9 SIMM, Speech Systems "512K Turbo RAM", and a modern "Coco 3 512K SRAM Upgrade (Canadian Coco Nut)" (src: https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/).
- Commercial precedent: Sierra's King's Quest III for the CoCo 3 lists "Minimum RAM: 512 KB" (src: https://wiki.sierrahelp.com/index.php/King%27s_Quest_III:_To_Heir_is_Human_Technical).
- Emulators default to 512 KB: MAME's coco3 `RAM(...).set_default_size("512K").set_extra_options("128K,2M,8M")` (src: MAME coco3.cpp). XRoar takes `-ram 512`.
- Arithmetic: two 32 KB screens (64 KB) + the largest overlay (17.5 KB of x86, probably more as 6809) + resident code (about 70 KB of x86) + DGROUP (17 KB) + a 16 KB stack + the heap + a DAX block buffer (up to 36 KB packed, plus unpacked) is well above the 128 KB that BASIC already occupies. Only 512 KB works.

Conclusion: **require 512 KB** and say so in the loader. Check at boot by writing different patterns into block `$00` and block `$30` through one MMU slot and reading them back: on 128 KB they alias.

---

## 6. PIAs: keyboard, joystick, DAC, sound mux

### Register map

| Address | PIA0 | PIA1 |
|---|---|---|
| `$FF00` / `$FF20` | Port A data (or DDR): PA0-PA6 keyboard rows; PA7 joystick comparator; PA0-PA3 also read joystick buttons | Port A: PA7-PA2 6-bit **DAC**; PA1 RS-232 out; PA0 cassette in |
| `$FF01` / `$FF21` | CRA: bit 0 HSYNC IRQ enable, bit 1 edge, bit 2 DDR/data select, bits 5-3 CA2 control (**bit 3 = SEL1**, mux LSB), bit 7 flag | CRA: CA1 = RS-232 CD; CA2 = cassette motor |
| `$FF02` / `$FF22` | Port B: PB0-PB7 keyboard column strobes (write 0 to select) | Port B: PB7 VDG A/G (CoCo 1/2 modes); **PB1 = 1-bit sound**; PB0 RS-232 in; PB2 RAM-size input; PB3-PB6 VDG mode bits |
| `$FF03` / `$FF23` | CRB: bit 0 VSYNC IRQ enable, bit 1 edge, **bit 3 = SEL2** (mux MSB), bit 7 flag | CRB: CB1 = CART (FIRQ); **CB2 bit 3 = sound enable** |

(src: CoCoPedia PIA; MAME coco.cpp PIA1 comment block.) The registers mirror through `$FF04` to `$FF1F` and `$FF24` to `$FF3F` (exileinparadise memory map).

### Keyboard matrix (CoCo 3)

Strobe a column by writing a byte with that bit 0 to `$FF02`, then read `$FF00`. A pressed key reads 0 in its row bit (src: MAME coco3.cpp input ports; CoCoPedia PIA).

| `$FF00` bit (row) | col 0 (`$FE`) | col 1 (`$FD`) | col 2 (`$FB`) | col 3 (`$F7`) | col 4 (`$EF`) | col 5 (`$DF`) | col 6 (`$BF`) | col 7 (`$7F`) |
|---|---|---|---|---|---|---|---|---|
| PA0 | @ | A | B | C | D | E | F | G |
| PA1 | H | I | J | K | L | M | N | O |
| PA2 | P | Q | R | S | T | U | V | W |
| PA3 | X | Y | Z | **UP** | **DOWN** | **LEFT** | **RIGHT** | SPACE |
| PA4 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| PA5 | 8 | 9 | : | ; | , | - | . | / |
| PA6 | **ENTER** | **CLEAR** | **BREAK** | ALT | CTRL | F1 | F2 | SHIFT |

Efficient checks:
- **Any key:** `CLR $FF02; LDA $FF00; ORA #$80; CMPA #$FF` (about 15 cycles). Not equal means something is pressed. First read `$FF00` with `$FF02 = $FF` to see whether a joystick button is holding a row low; button bits look like keys and must be masked.
- **Any arrow:** strobe `$87` (columns 3 to 6) and test PA3. Then strobe `$F7`/`$EF`/`$DF`/`$BF` individually to tell them apart.
- **ENTER / CLEAR / BREAK:** strobe `$FE`/`$FD`/`$FB` and test PA6 (`BITA #$40`).
- **Per key cost:** `STB $FF02` (5) + `LDA $FF00` (5) + `BITA #` (2) + branch (3) = 15 cycles. A full 8-column scan into a 7-bit x 8 bitmap is about 200 to 250 cycles. Polling at 60 Hz costs under 1% of the CPU.
- **Rollover/ghosting:** the matrix has no diodes. Three keys forming a rectangle make a fourth key ghost, and the hardware has no rollover logic. Use two-frame debouncing and treat SHIFT/CTRL/ALT as modifiers [general knowledge].
- **PC key mapping for PoR:** arrows map to arrows; Enter to ENTER; Esc to **BREAK**; letters as is. Home/End have no CoCo keys: suggest **F1/F2** (CoCo 3 only), with SHIFT+UP/SHIFT+DOWN as alternates, and CLEAR as a spare.
- The GIME keyboard interrupt (EI1) fires when a row line falls while columns are strobed low. It is not needed for menu polling.

### Joystick

Analog joysticks are read by successive approximation: select an axis with SEL1/SEL2 (mux Z channel: 00 right X, 01 right Y, 10 left X, 11 left Y), write a trial value to the DAC, and read the comparator on PA7 (MAME coco.cpp mux comment). This **shares the DAC and the mux select bits with sound**. PoR is keyboard only, so ignore joysticks. The fire buttons still show up on PA0 to PA3 and must be masked as above.

### 6-bit DAC and the sound mux

- DAC: write `value << 2` to `$FF20` (bits 7-2). Keep bit 1 (RS-232 out) at its idle level [assume 1 = idle mark, unverified]. Bit 0 is an input.
- Mux W channel (src: MAME coco.cpp, citing the Tandy Service Manual): SEL2:SEL1 = 00 DAC, 01 cassette, **10 cartridge SND pin**, 11 grounded. SEL1 = `$FF01` bit 3, SEL2 = `$FF03` bit 3 (with CA2/CB2 in output mode, CR bits 5-4 = 11).
- **Sound enable:** `$FF23` bit 3 (PIA1 CB2) = 1 routes the mux to the TV/monitor audio.
- **1-bit sound:** `$FF22` bit 1. "It is always connected thus cannot be disabled" (MAME, citing page 31 of the Service Manual). It does not need the mux.
- Selecting the DAC: `LDA $FF01; ANDA #$F7; STA $FF01; LDA $FF03; ANDA #$F7; STA $FF03; LDA $FF23; ORA #$08; STA $FF23`.
- Selecting cartridge sound (GMC): as above, but `ORA #$08` on `$FF03` (SEL2 = 1, SEL1 = 0).

---

## 7. Sound hardware options

PoR's sound is effects only, driven at 236.7 Hz through the PC speaker or the Tandy 3-voice PSG. On a Tandy 1000 that PSG is an SN76489-family part (NCR8496 or PSSJ-3) clocked at 14.318 MHz / 4 = **3.579545 MHz** and written at I/O port `$C0` (src: https://raw.githubusercontent.com/mamedev/mame/master/src/mame/pc/tandy1t.cpp `NCR8496(config, "sn76496", XTAL(14'318'181) / 4)`, `map(0x00c0, ...)`).

| Option | Hardware | Address | Emulation | Availability | Fit for PoR |
|---|---|---|---|---|---|
| 1-bit | built in, PIA1 PB1 | `$FF22` bit 1 | MAME, XRoar | every CoCo | PC-speaker effects, CPU toggled |
| 6-bit DAC | built in | `$FF20` bits 7-2 + mux 00 + `$FF23` bit 3 | MAME, XRoar | every CoCo | 1 to 3 software voices, CPU mixed |
| **Games Master Cartridge** | SN76489AN at 4 MHz + banked ROM up to 64K | **`$FF41`** (bank register `$FF40`) | MAME `gmc`, XRoar `-cart-type gmc` | Not sold standalone. Comes inside game cartridges; dev kits from John Linville | **Direct replacement for the Tandy PSG** |
| Orchestra-90 CC | two 8-bit DACs (stereo) | `$FF7A` left, `$FF7B` right | MAME `orch90`, XRoar `orch90` | rare vintage Tandy cart (26-3143) | CPU-mixed sample playback only |
| CoCo PSG (Ed Snider) | YM2149 (AY-compatible) + 512K flash/SRAM, 2 joystick ports | register select `$FF5E`, data `$FF5F`, control `$FF5D`, banks `$FF5A/$FF5B` | MAME `ccpsg`; not in XRoar's cart list | modern, small runs | 3 tone + noise, different chip family |
| Speech/Sound Cart (Tandy 26-3144) | AY-3-8913 + SP0256-AL2 behind a TMS7040 MCU | `$FF7D`/`$FF7E` | MAME `ssc` | vintage | indirect (through an MCU), awkward |

Sources: MAME coco_gmc.cpp ("The SN76489AN is tied to address $FF41. Cartridge by John Linville."; `SN76489A(config, m_psg, 4_MHz_XTAL)`), coco_orch90.cpp ("left channel was at $FF7A, and the right channel was at $FF7B"), coco_psg.cpp ("YM2149 ... Cartridge by Ed Snider"; scs offsets `$1D`/`$1E`/`$1F` of `$FF40`), coco_ssc.cpp ("TMS-7040 microcontroller, SPO256-AL2 speech processor, AY-3-8913"; handler at `$FF7D`-`$FF7E`), cococart.cpp option names; the XRoar manual (cart types `gmc`, `orch90`, `mpi`; "Games Master Cartridge, including the SN76489 sound chip"); testgmc.asm by R. Allen Murphey (`GMCPORTA: equ $FF40 ; GMC bank switching port`, `GMCPORTB: equ $FF41 ; GMC SN76489 port`) (src: https://exileinparadise.com/tandy_color_computer:testgmc.asm); the GMC availability article (src: https://www.vintageisthenewold.com/game-master-cartridge-enables-better-games-for-coco/).

### GMC details that matter for the port

- **Same command format** as the Tandy chip: latch byte `%1cctdddd` (channel cc, t = 1 for volume), then data byte `%0-DDDDDD` (high 6 bits of the 10-bit period). Volume is 4-bit attenuation, `%1111` = off. f = clock / (32 x N) (src: http://www.smspower.org/Development/SN76489). The game's PSG byte stream can be passed through almost unchanged.
- **Clock difference:** GMC 4.0 MHz against Tandy 3.579545 MHz. To keep pitch, scale each 10-bit tone period by 4.0 / 3.579545 = **1.11746** and clamp to 1023. A 64-entry or per-call fixed-point multiply is fine. Noise rates `00`/`01`/`10` are fixed clock divisions, so they come out 11.7% higher in pitch. Use rate `11` (tracks tone 2) where the game allows.
- **Noise LFSR differs:** SN76489A has 15-bit taps on bits D and E; the Tandy NCR8496 has taps on bits A and E with XNOR (src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/sound/sn76496.cpp). White noise will sound slightly different. Acceptable.
- **Write spacing:** "At 4MHz, the DCSG needs 32 clocks between register writes ... a delay of ~15 clocks per write at 1.789MHz" (testgmc.asm). Pad with NOPs or interleave other work.
- **Power-up:** "starts with all channels playing", so write attenuation `$9F`, `$BF`, `$DF`, `$FF` at init (testgmc.asm).
- **Detection:** the SN76489 is write only, so a GMC cannot be detected by reading the chip. Offer a menu or config option. XRoar and MAME can be configured with or without it.
- **Coexisting with the disk controller:** the floppy controller and the GMC both decode SCS (`$FF40` to `$FF5F`). Disk BASIC's DSKREG is `$FF40`, the same address as the GMC's bank register. With both in a Multi-Pak, `$FF7F` routes SCS: "bit 0-1 Target *SCS to this slot number; bit 4-5 Target *CTS and *CART" (src: MAME coco_multi.cpp). Write PSG bytes only while SCS is switched to the GMC slot, and switch back to the disk slot (normally slot 4, value `$33`) before any disk I/O. Keep the `$FF7F` shadow consistent inside the sound ISR. CoCo 3 owners also need the CoCo 3-compatible Multi-Pak, because the original MPI also decodes `$FF9F` (MAME coco_multi.cpp comment). Users with a CoCoSDC or DriveWire also need to check address conflicts [unverified]. **This conflict is the main practical cost of GMC support.**
- Emulator command lines [check spelling with `-listslots` / `xroar -help`]: MAME `mame coco3 -ramsize 512K -ext multi -ext:multi:slot1 gmc` (slot 4 defaults to `fdc`). XRoar `xroar -m coco3 -ram 512 -cart-type gmc` alone, or the `mpi` cart with the GMC in a slot and the disk controller in slot 4.

### Software sound on the built-in DAC or 1-bit output

- No hardware tone generator exists, so the CPU must produce every edge. A timer FIRQ at the sample rate (slow source, N chosen per revision): 2 lines = 7.85 kHz, 3 lines = 5.24 kHz, 4 lines = 3.93 kHz.
- **Cost per sample** [estimates from standard 6809 timings]: FIRQ entry 10 + `LDA $FF93` 5 + save/restore 2 registers about 14 + one 16-bit phase accumulator voice about 15 to 20 + DAC store 5 + RTI 6 gives **about 55 to 60 cycles for 1 voice** and about 100 to 110 for 3 voices. At 7.85 kHz: 1 voice is about 26% of the CPU and 3 voices about 45%. At 3.93 kHz: about 13% and 23%.
- **PC-speaker style (1 voice):** a 1-bit toggle on `$FF22` bit 1 (or full-scale DAC swings) at 3.9 to 7.85 kHz covers the PC speaker effects. Pitch resolution is coarse: tone frequency = sample rate / integer, so the phase accumulator approach is better.
- Turn the high-rate FIRQ on **only while an effect is playing**. Otherwise run the 66-line tick (2 to 3 interrupts per frame, negligible cost).

---

## Implications and recommendations for the port

### Graphics mode

- **320x200x16, `$FF90=$7C`, `$FF98=$80`, `$FF99=$3E`, `$FF9A=$00`, `$FF9C=$00`, `$FF9F=$00`.** This is the exact geometry and pixel order of EGA 0Dh as PoR stores pictures (4 bpp, high nibble left, 160 bytes per line, 32,000 bytes). DAX title pictures decode straight into the screen.
- Replace the planar EGA emulation in `c/platform` with a packed-nibble back end: `put_pixel` (nibble read-modify-write), byte-aligned blits for even x (combat icons 24 wide = 12 bytes, portraits 40/48 wide = 20/24 bytes, 8x8 tiles = 4 bytes x 8), and a nibble-shift path for odd x. The XOR frame-delta animation maps directly onto byte XOR.
- Text: software-render PoR's own 1-bit 8x8 font into the bitmap, using colour-pair expansion tables (4 lookups per glyph row). Do not use GIME text mode.
- Optional later: 225-line mode (`$FF99=$7E`, 36,000 bytes) for a status band below the 200-line game area. Not needed.

### Palette mapping

- Pixel data stays as EGA indices. Keep a 64-entry `ega64_to_gime[]` table: the 3-bit swap for RGB (exact) and a hand-tuned table for composite (start from the composite column above). Choose RGB or composite at startup (ask the player, default RGB).
- Write all 16 palette registers in the vertical border (from the VBORD IRQ, or right after the page flip) to avoid the palette-write glitch Sock describes.

### Screen memory and double buffer (512 KB required)

| Physical blocks | Use | `$FF9D` / `$FF9E` |
|---|---|---|
| `$00`-`$03` (`$00000`-`$07FFF`) | Screen A (32,000 bytes + 768 spare) | `$00` / `$00` |
| `$04`-`$07` (`$08000`-`$0FFFF`) | Screen B | `$10` / `$00` |
| `$08`-`$0B` | Optional clean background / 3D-view composition buffer | (`$20` / `$00` if displayed) |
| `$0C`-`$2F` | Overlays, DAX unpacked cache, heap (288 KB) | |
| `$30`-`$3B` | Resident code, data, stack (the memory-model file decides the split) | |
| `$3C`-`$3F` | ROM image (keep `$3E` if DSKCON is used), vector page `$7FE00` | |

- Logical window: in **task 1**, map the back buffer's 4 blocks into slots 4 to 7, so the screen appears linearly at **`$8000` to `$FCFF`**. 32,000 = `$7D00`, so it ends below the constant page at `$FE00`. Keep slots 0 to 3 identical in both tasks, so the code and stack never move when tasks switch. Draw in task 1, run game logic in task 0 (with its own overlay and data mapping in slots 4 to 7). A task switch is one 7-cycle store to `$FF91` (with TINS preserved).
- Flip: write `$FF9D/$FF9E` for the newly finished buffer. At the next VBORD, rewrite task 1's slots 4 to 7 (4 stores, about 28 cycles) to point at the other buffer, update the palette if it changed, and resume drawing.
- Where PoR draws incrementally into the visible screen (menus, text), it can draw straight into the front buffer and skip double buffering. Use double buffering for full-scene changes and animation.

### Interrupt plan

- Take over at boot: `ORCC #$50`, disable PIA0 HSYNC/VSYNC and PIA1 CART interrupts, clear pending flags, install `JMP` stubs at `$FEF4` (FIRQ) and `$FEF7` (IRQ), and set `$FF92 = $08` (VBORD on IRQ) and `$FF93 = $20` (TMR on FIRQ). Select 1.79 MHz (`$FFD9`) and all-RAM mode (`$FFDF`), program the GIME, then `ANDCC #$AF`.
- FIRQ (timer): the 236.7 Hz class sound tick at 66 lines (write 65 on a 1987 GIME, 64 on a 1986 GIME, detected at boot), or a 2-line (7.85 kHz) sample clock with a divide-by-33 tick while DAC sound is active. Always write `$FF95` before `$FF94`, and never write 0.
- IRQ (VBORD, 59.92 Hz): frame counter for Delay and the time of day (the 18.2 Hz BIOS tick count can be derived as frames x 18.2065 / 59.92), page-flip completion and palette loads.
- Keyboard: polled by the main code (menus already poll). Optionally scan once per VBORD into a debounced bitmap.
- All ISR code and data live in the `$FExx` page or in slots 0 to 3 (identical in both tasks). ISRs never assume slots 4 to 7.

### Sound plan

1. Write a PSG abstraction that takes the game's Tandy byte stream (port `$C0` writes) and its PC-speaker frequency/on/off calls.
2. **Backend A (default, always present):** DAC or 1-bit software synthesis. The PC speaker maps to 1 voice. For the Tandy path, mix the loudest 1 or 2 voices, or the most recent, at 3.93 to 7.85 kHz, and only while sound is active.
3. **Backend B (optional, user selected):** GMC at `$FF41`. Rescale periods by 1.11746, send writes at least 15 cycles apart, and silence all 4 channels at init. Select mux = cartridge (`$FF03` bit 3 = 1, `$FF01` bit 3 = 0) and set `$FF23` bit 3. If a Multi-Pak is present, switch SCS through `$FF7F` around every write and restore it before any disk access.
4. Test both in XRoar (`-cart-type gmc`, `-vdg-type gime1986` / `gime1987`) and in MAME (`-ext gmc` / `-ext multi`).

---

## Open questions

1. `$FF91` bit 6 (memory type): does writing 0 on a 512 KB machine with 256K chips break RAM addressing on real hardware? Emulators ignore it. Recommended: write the same value BASIC uses (find it by disassembling the CoCo 3 ROM reset code at `$8C1B`).
2. Exact 1986 vs 1987 GIME differences beyond the timer reload and the odd-`$FF9E` crash. I could not reach the full published bug list. Test with XRoar's `gime1986`/`gime1987` and with real hardware.
3. Do the GIME pending-interrupt flags survive disabling a source? MAME (Glen Hewlett) and the tlindner hardware tests appear to disagree. The port avoids the question by always acknowledging through a read.
4. LPR codes 001 and 010: Sock and MAME say 1 and 2 lines; the Tandy transcription says 2 and 3. Irrelevant for the port (uses 000), but worth noting for anyone using multi-line graphics modes.
5. Mixing text and graphics in one frame (changing `$FF98` bit 7 mid-frame): plausible but unconfirmed on hardware. Not needed if text is software rendered.
6. GMC with CoCoSDC or other SCS-decoding controllers through a Multi-Pak: which slot and `$FF7F` values work on real setups? Does the Multi-Pak mix SND from all slots or only the selected one?
7. Composite palette: the table above comes from MAME's emulated NTSC palette. It needs eyeballing on a real CoCo 3 on a TV (and differs with BPI).
8. Whether the CoCo 3 ROM copies BASIC into RAM at reset, and the exact task 1 defaults BASIC sets. Matters only if the port keeps calling ROM routines (DSKCON).

## Sources

- https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/gime.cpp : MAME GIME emulation: register bit comments, timer reload (+1/+2), video base calculation, LPR/LPF/HRES/CRES tables, RGB and composite palettes, text attributes, mid-frame notes quoting John Kowalski.
- https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/gime.h : MAME GIME header (interrupt constants).
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/video/mc6847.h : `emit_graphics`, which proves MSB-first pixel order (high nibble = left pixel).
- https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/coco3.cpp : CoCo 3 address map (vectors from ROM at `$FFE0`), keyboard matrix, screen raw timing (912 x 262), default 512K RAM.
- https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/coco.cpp : PIA bit assignments, the sound mux table (from the Tandy Service Manual), 1-bit sound always connected, the IRQ/FIRQ wiring diagram.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_gmc.cpp : Games Master Cartridge: SN76489AN at `$FF41`, 4 MHz clock, Linville credit.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_psg.cpp : CoCo PSG (Ed Snider, YM2149) registers.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_orch90.cpp : Orchestra-90 DACs at `$FF7A/$FF7B`.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_ssc.cpp : Speech/Sound Cartridge (AY-3-8913, SP0256, TMS7040) at `$FF7D/$FF7E`.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/cococart.cpp : cart option names (`gmc`, `orch90`, `ccpsg`, `ssc`, `multi`) and the SCS range.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_multi.cpp : Multi-Pak `$FF7F` slot select semantics and the `$FF9F` decoding issue.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/sound/sn76496.cpp : SN76489/A vs NCR8496 (Tandy) noise LFSR differences.
- https://raw.githubusercontent.com/mamedev/mame/master/src/mame/pc/tandy1t.cpp : Tandy 1000 PSG = NCR8496 at 3.579545 MHz on port `$C0`.
- https://www.cococommunity.net/socks-gime-register-reference/ : Sock Master's GIME register reference (vectors, INIT0/1, timer quirks, LPR/LPF/HRES/CRES, `$FF9F`, palette glitch).
- https://nitros9.sourceforge.io/wiki/index.php/Inside_-_REFERENCE : transcription of the Tandy GIME spec plus addendum; physical memory map; palette and attribute formats (some entries garbled or contradicted).
- https://tlindner.macmess.org/?p=762 : GIME timer hardware tests (timer = 0 behaviour, Arkanoid, MAME interrupt bugs).
- https://www.cocopedia.com/wiki/GIME : GIME revisions (1986 "Tequila", 1987 "Tortilla"), 256-colour rumour.
- https://exileinparadise.com/tandy_color_computer:graphics_interrupt_memory_enhancement : GIME aliases and the CoCo 3 mode list.
- https://www.cocopedia.com/wiki/Understanding_and_Using_the_MMU : 128K uses blocks `$30`-`$3F`; BASIC's task 0 defaults.
- https://www.cocopedia.com/wiki/MMU_RAMROM_Mode : ROM page pinning to slots.
- https://exileinparadise.com/_export/raw/tandy_color_computer:memory_map : CoCo 3 physical block usage by Super Extended BASIC; I/O map.
- https://www.cocopedia.com/wiki/PIA : PIA0/PIA1 pin assignments and the keyboard matrix.
- https://www.go4retro.com/?p=1416 : GIME memory timing (video in the low half of E, CPU in the high half, 16-bit fetches).
- https://www.cocopedia.com/wiki/Color_Computer_3 : models, prices, 512K upgrade 26-3335.
- https://wiki.sierrahelp.com/index.php/King%27s_Quest_III:_To_Heir_is_Human_Technical : KQ3 CoCo 3 requires 512 KB.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/ : archive listing (CoCo 3 Service Manual, 512K upgrade manuals, CM-8 manual). The Service Manual PDF is a scan with no text layer, so it could not be read here.
- https://colorcomputerarchive.com/repo/Documents/Datasheets/ : datasheet listing (MC6809E, MC6821, AY-3-891x; no GIME datasheet).
- https://www.6809.org.uk/xroar/doc/xroar.shtml : XRoar manual: cart types incl. `gmc`/`orch90`/`mpi`, `-vdg-type gime1986|gime1987`, `-ram`, extended MMU bits.
- https://pkgsrc.se/emulators/xroar : XRoar feature list ("Games Master Cartridge support, including SN76489 sound chip"; Orchestra 90).
- https://www.cocopedia.com/wiki/Game_Master_Cart : GMC overview (SN76489AN, Linville, 2018, games using it).
- https://exileinparadise.com/_export/raw/tandy_color_computer:game_master_cartridge : GMC resource links (programming doc, testgmc, cyd-gmc player).
- https://exileinparadise.com/tandy_color_computer:testgmc.asm : GMC port equates (`$FF40` bank, `$FF41` PSG), write spacing, power-up state.
- https://www.vintageisthenewold.com/game-master-cartridge-enables-better-games-for-coco/ : GMC availability (built into game carts; dev kits from Linville; MAME support).
- https://www.6809.org.uk/dunjunz/gmc.shtml : example GMC release (Dunjunz, 27512 EPROM image).
- http://www.smspower.org/Development/SN76489 : SN76489 register format, frequency formula, noise modes, chip variants.

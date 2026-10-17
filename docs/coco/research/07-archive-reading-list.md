# 07: Color Computer Archive reading list for the CoCo 3 port

Scope: a curated, ranked list of the documents on the Color Computer Archive (colorcomputerarchive.com) that matter most for writing the Pool of Radiance CoCo 3 port in C (CMOC) and 6809/6309 assembly (LWTOOLS). Every URL below was taken from the archive's own directory listings and percent-encoded the way the server expects (space as `%20`, `&` as `%26`, apostrophe as `%27`, the curly apostrophe as `%E2%80%99`; parentheses left literal). "Opened" means WebFetch retrieved the file through that exact URL on 2026-10-17.

## Key takeaways for the Pool of Radiance port

1. The single most useful text-searchable document is **Super Extended BASIC Unravelled II** (907K): its chapters 3 to 7 (pp. 6 to 29) are a full GIME, MMU, palette, timer and interrupt reference with page numbers; the ROM disassembly appendices exist but their text layer did not come through WebFetch (src: https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/super-extended-basic-unravelled.pdf).
2. **Disk BASIC Unravelled** gives everything needed to read RS-DOS disks from our own code: DSKCON parameter block at $00EA to $00F0 (p. A4), WD1793 registers $FF48 to $FF4B and the $FF40 latch bits (pp. 13 to 14), FAT/directory layout (pp. 9 to 11), and the NMI/HALT transfer trick (p. 14) (src: https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/disk-basic-unravelled.pdf).
3. For CPU work use **Darren Atkinson's 6809/6309 Programming Reference** (504K, one page per instruction, cycle counts shown as "emulation / native") plus **The 6309 Book** and the **HD63B09EP Technical Reference Guide** for native mode, TFM (6+3n cycles), MULD/DIVD/DIVQ and the $FFF0 trap.
4. Many of the "classic" CoCo 3 references on the archive are **image-only scans with no text layer**: the CoCo 3 Service Manual, Tepolt's Assembly Language Programming for the CoCo3, CoCo III Secrets Revealed, the WD177X/WD179X datasheets, the MC6821 datasheet, the Orchestra-90 and Multi-Pak manuals, the Color Computer Technical Reference Manual, and Inside OS-9 Level II. Their URLs work, but an agent must OCR them (or read them visually) to get facts; WebFetch returns nothing.
5. There is **no SN76489 datasheet** in the Datasheets folder (29 files, listed below). The SN76489 matters because the Games Master Cartridge (GMC) puts an SN76489AN at $FF41, which would let the port reuse the Tandy 1000 3-voice sound effects almost directly (src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_gmc.cpp). The archive does have the AY-3-891x datasheet (Speech/Sound Cartridge PSG).
6. For OS-9 (if the port ever targets NitrOS-9 rather than bare metal), the **NitrOS-9 EOU Level 2 Technical Reference Manual v0.21** is text-searchable, current, and documents F$MapBlk (p. 22, p. 141), the IRQ polling table (pp. 27 to 29) and VIRQ (pp. 29 to 31).
7. The **CoCo SDC User Guide v4** is text-searchable and is the deployment reference for real hardware: FAT16/FAT32, 8.3 names only (p. 5), `DRIVE n,"path"` mounting (pp. 9 to 10), AUTOEXEC.BAS autostart (p. 13), command mode by writing $43 to $FF40 (p. 34).
8. Overlap with other research files: 01 (CPU), 02 (GIME/video/sound), 03 (storage/OS) cover the same hardware from other sources; this file is the map of where in the archive PDFs a later agent should look to confirm a detail.

## How the archive is organised (what was browsed)

| Listing | What is there | Notes |
|---|---|---|
| https://colorcomputerarchive.com/repo/Documents/Manuals/ | 7 subfolders: Applications, Educational, Games, Hardware, Operating Systems, Programming, Utilities | No files at top level. |
| https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/ | About 280 files: Tandy service manuals, schematics, cartridges, FDC datasheets, SDC, Multi-Pak, Orchestra-90 | The default listing is too long for WebFetch (cut off at "Joystick"); the reverse-sorted view https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/?C=N;O=D shows J to Z. |
| https://colorcomputerarchive.com/repo/Documents/Manuals/Programming/ | 94 files: assemblers, C compilers, BASIC09, debuggers, MC6809 Preliminary Programming Manual | Mostly tools we will not use; a few references. |
| https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/ | 54 files: OS-9 Level 1/2, NitrOS-9, FLEX, ADOS, RGB-DOS | NitrOS-9 manuals are the text-searchable ones. |
| https://colorcomputerarchive.com/repo/Documents/Books/ | 123 files plus 5 folders (Basic Software Library, Dragon, Japanese, Portuguese, Unravelled Series) | Contains the 6309 Book, Atkinson reference, Tepolt books, Secrets Revealed, Inside OS-9 Level II. |
| https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/ | 5 files: color-basic-unravelled.pdf, extended-basic-unravelled.pdf, disk-basic-unravelled.pdf, super-extended-basic-unravelled.pdf, Unravelled II.xls | First fetch of the folder failed with a client error; the sorted view `?C=N;O=A` worked. |
| https://colorcomputerarchive.com/repo/Documents/Datasheets/ | 29 PDFs: HD63x09E, HD68x09E, MC6809/MC6809E, MC6821 (2 versions), MC6829, MC6839, MC6840, MC6847/MC6847T1, MC6883 SAM, AY-3-891x, SP0256, DRAMs, CRTCs, SY6591 FDC | No GIME (TCC1014) datasheet, no WD17xx (those are under Manuals/Hardware), no SN76489. |
| https://colorcomputerarchive.com/repo/Documents/Microprocessors/HD6309/ and .../MC6809/ | 7 and 8 files: 6309 technical reference guides, "Secret features of 6309.txt", 6309 indexed cycle counts, Motorola programming manuals | Not one of the three starting points, but reached from the Documents index; worth it for the 6309. |

## Ranked reading list (40 documents)

Rank reflects usefulness to the port, not quality. Status codes: **T** = opened, text readable; **S** = opened, scan with no text layer (needs OCR or visual reading); **L** = present in the listing, not fetched (usually too large or lower priority).

### A. CoCo 3 system, GIME, MMU, video, interrupts

**1. super-extended-basic-unravelled.pdf** (907K) [T]
https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/super-extended-basic-unravelled.pdf
Spectral Associates' "Super Extended BASIC Unravelled II": CoCo 3 hardware differences, memory management, hi-res graphics, palettes, interrupts, then the full commented disassembly of the CoCo 3 ROM, symbol table, chip control registers, entry points. Serves: MMU, video, palette, interrupts, timer, BASIC ROM entry points, boot process. The best first read for whoever writes the CoCo 3 platform layer.

**2. Color Computer 3 Service Manual (Tandy).pdf** (9.4M) [S]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%203%20Service%20Manual%20(Tandy).pdf
Tandy's service manual: the GIME (TCC1014) theory of operation, register descriptions, memory map, schematics and timing. Serves: video, MMU, interrupts, hardware truth when other sources disagree. Scan only: the text layer is empty.

**3. Assembly Language Programming for the CoCo3 (1987) (Laurence A Tepolt).pdf** (2.5M) [S]
https://colorcomputerarchive.com/repo/Documents/Books/Assembly%20Language%20Programming%20for%20the%20CoCo3%20(1987)%20(Laurence%20A%20Tepolt).pdf
Tepolt's CoCo 3 follow-up book: GIME programming from assembly (graphics modes, palettes, MMU, interrupts) with example programs. Serves: video, MMU, interrupts, keyboard. Scan only.

**4. CoCo III Secrets Revealed (Spectrum Projects).pdf** (468K) [S]
https://colorcomputerarchive.com/repo/Documents/Books/CoCo%20III%20Secrets%20Revealed%20(Spectrum%20Projects).pdf
Classic early disclosure of the GIME registers and undocumented CoCo 3 features. Serves: video, MMU, register details. Scan only.

**5. Coco III Secrets Revealed (Microcom Software).pdf** (1.6M) [L]
https://colorcomputerarchive.com/repo/Documents/Books/Coco%20III%20Secrets%20Revealed%20(Microcom%20Software).pdf
The Microcom edition of the same title (larger scan). Fallback if the Spectrum Projects copy is illegible.

**6. Color Computer 3 Revised Schematic (Ty Sopko).pdf** (415K) [L]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%203%20Revised%20Schematic%20(Ty%20Sopko).pdf
Redrawn, legible CoCo 3 schematic. Serves: confirming which PIA lines go where (keyboard, DAC, sound mux, cartridge FIRQ, VSYNC/HSYNC into PIA0 CA1/CB1).

**7. Color Computer 3 Extended Basic (Tandy).pdf** (9.7M) [S]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%203%20Extended%20Basic%20(Tandy).pdf
The CoCo 3 BASIC owner's manual: HSCREEN modes, PALETTE (RGB vs CMP defaults), WIDTH 40/80, colour charts, memory map appendix. Serves: palette value tables for composite vs RGB, quick checks of BASIC's video setup. Scan only.

**8. 300 Pokes Peeks 'n Execs for the CoCo III (Microcom Software).pdf** (2.0M) [L]
https://colorcomputerarchive.com/repo/Documents/Books/300%20Pokes%20Peeks%20%27n%20Execs%20for%20the%20CoCo%20III%20(Microcom%20Software).pdf
Collection of CoCo 3 memory locations and tricks (speed poke, ROM/RAM mode, palette pokes). Serves: quick lookup; useful for test harness one-liners typed into BASIC. A 24M second printing also exists.

**9. 512K Expansion RAM Card (Tandy).pdf** (1.4M) [L]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/512K%20Expansion%20RAM%20Card%20(Tandy).pdf
Tandy's 512K upgrade documentation: confirms the 512K physical layout ($00000 to $7FFFF, 64 blocks of 8K). Serves: MMU planning for the 512K target.

### B. CPU: 6809 and 6309

**10. Motorola 6809 and Hitachi 6309 Programming Reference (Darren Atkinson).pdf** (504K) [T]
https://colorcomputerarchive.com/repo/Documents/Books/Motorola%206809%20and%20Hitachi%206309%20Programming%20Reference%20(Darren%20Atkinson).pdf
Modern typeset reference, one page per instruction, both CPUs. Serves: CPU, cycle budgeting for hand-written assembly and for judging CMOC output. (The first two fetches failed with client errors; the third worked.)

**11. The 6309 Book (Burke & Burke).pdf** (953K) [T]
https://colorcomputerarchive.com/repo/Documents/Books/The%206309%20Book%20(Burke%20%26%20Burke).pdf
Complete 6309 programmer's guide: programming model, addressing modes, every instruction, and an applications section (detecting the 6309, native mode switching, native-mode interrupts, trap vector, TFM, multiply/divide, bit instructions). Serves: CPU, optional 6309 fast paths (TFM for blitting, MULD for maths).

**12. HD63B09EP Technical Reference Guide.pdf** (121K) [T]
https://colorcomputerarchive.com/repo/Documents/Microprocessors/HD6309/HD63B09EP%20Technical%20Reference%20Guide.pdf
Compact 6309 reference with opcode/cycle tables in "6809 (6309)" form. Serves: CPU, native-mode cycle savings.

**13. Secret features of 6309.txt** (30K) [T]
https://colorcomputerarchive.com/repo/Documents/Microprocessors/HD6309/Secret%20features%20of%206309.txt
Hirotsugu Kakugawa's memo (from Oh!FM, April 1988) that first documented the 6309 extras. Serves: CPU history and MD register semantics; it flags its own uncertain areas.

**14. 6309 Indexed Cycle Counts.pdf** (16K) [L]
https://colorcomputerarchive.com/repo/Documents/Microprocessors/HD6309/6309%20Indexed%20Cycle%20Counts.pdf
Table of extra cycles for each indexed post-byte on the 6309. Serves: exact cycle costs of `,X+`, `n,X`, `[,X]` forms.

**15. MC6809E HMOS 8 Bit Microprocessor (Motorola) (OCR).pdf** (2.1M) [T]
https://colorcomputerarchive.com/repo/Documents/Datasheets/MC6809E%20HMOS%208%20Bit%20Microprocessor%20(Motorola)%20(OCR).pdf
The datasheet for the E (external clock) part the CoCo 3 actually uses, with an OCR text layer. Serves: interrupt vectors, interrupt stacking, SYNC/CWAI, cycle tables. The non-OCR scan (3.6M) sits next to it.

**16. Motorola MC6809-MC6809E 8-Bit Microprocessor Programming Manual.pdf** (2.3M) [L]
https://colorcomputerarchive.com/repo/Documents/Microprocessors/MC6809/Motorola%20MC6809-MC6809E%208-Bit%20Microprocessor%20Programming%20Manual.pdf
Motorola's official programming manual (a 13M scan of the same title is also there). Serves: authoritative instruction semantics and condition codes.

**17. HD63x09E CMOS MPU (Hitachi).pdf** (1.2M) [L]
https://colorcomputerarchive.com/repo/Documents/Datasheets/HD63x09E%20CMOS%20MPU%20(Hitachi).pdf
Hitachi datasheet for the 63B09E/63C09E (only the 6809-compatible behaviour is officially documented). Serves: electrical/timing confirmation for 6309-equipped machines.

**18. 6809 Assembly Language Subroutines (Lance Leventhal).pdf** (13M) [L]
https://colorcomputerarchive.com/repo/Documents/Books/6809%20Assembly%20Language%20Subroutines%20(Lance%20Leventhal).pdf
Library of tested routines: multi-byte arithmetic, multiply/divide, BCD, string, array, bit-field and block-move code. Serves: hand-written replacements for slow CMOC runtime paths (16x16 multiply, 32-bit divide, memmove).

**19. 6809 Assembly Language Programming (Lance Leventhal).pdf** (20M) [L]
https://colorcomputerarchive.com/repo/Documents/Books/6809%20Assembly%20Language%20Programming%20(Lance%20Leventhal).pdf
The standard textbook. Serves: background for agents new to 6809 idioms (position-independent code, stack frames, DP usage).

### C. Keyboard, PIA, SAM, sound

**20. color-basic-unravelled.pdf** (1.0M) [T, partial]
https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/color-basic-unravelled.pdf
Color BASIC disassembly: memory map, RAM vector table, console I/O (keyboard scan, POLCAT), interrupts appendix. Serves: keyboard matrix scanning, DAC/sound bits, RAM hooks, BASIC ROM entry points (still valid on the CoCo 3 because Super Extended BASIC patches a RAM copy of this code).

**21. extended-basic-unravelled.pdf** (1.0M) [L]
https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/extended-basic-unravelled.pdf
Extended BASIC disassembly (PMODE graphics, SOUND/PLAY, DRAW). Serves: the PLAY/SOUND DAC routine as a model for 6-bit DAC sound effects; LINE/DRAW algorithms if the line drawing unit needs a reference.

**22. MC6821 Peripheral Interface Adapter (Motorola).pdf** (1.2M) [S]
https://colorcomputerarchive.com/repo/Documents/Datasheets/MC6821%20Peripheral%20Interface%20Adapter%20(Motorola).pdf
The PIA datasheet: data/DDR selection by control register bit 2, CA1/CB1 edge and interrupt flags, CA2/CB2 modes, flag clearing by reading the data register. Serves: keyboard scan (PIA0 $FF00 to $FF03), VSYNC/HSYNC interrupts, sound enable and DAC (PIA1 $FF20 to $FF23). Scan only.

**23. MC6821 NMOS Peripheral Interface Adapter (Motorola).pdf** (2.2M) [L]
https://colorcomputerarchive.com/repo/Documents/Datasheets/MC6821%20NMOS%20Peripheral%20Interface%20Adapter%20(Motorola).pdf
Alternate scan of the PIA datasheet; try it if item 22 is unreadable.

**24. MC6883 Synchronous Address Multiplexer (Motorola).pdf** (838K) [L]
https://colorcomputerarchive.com/repo/Documents/Datasheets/MC6883%20Synchronous%20Address%20Multiplexer%20(Motorola).pdf
The SAM datasheet. On the CoCo 3 the GIME emulates the SAM control bits at $FFC0 to $FFDF, including the CPU rate bits ($FFD8/$FFD9) and the ROM/RAM map type ($FFDE/$FFDF). Serves: setting 1.79 MHz and all-RAM mode.

**25. Color Computer Technical Reference Manual (Tandy).pdf** (5.5M) [S]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%20Technical%20Reference%20Manual%20(Tandy).pdf
CoCo 1 technical reference: PIA bit assignments, keyboard matrix, joystick comparator, 6-bit DAC, sound multiplexer, SAM. Most of it is unchanged on the CoCo 3. Scan only.

**26. Orchestra-90 CC Stereo Music Synthesizer (Tandy).pdf** (5.2M) [S]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Orchestra-90%20CC%20Stereo%20Music%20Synthesizer%20(Tandy).pdf
Owner's manual for the stereo 8-bit DAC cartridge (left DAC $FF7A, right DAC $FF7B per MAME's emulation, src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_orch90.cpp). Serves: optional better-quality sound; the manual is mostly about the music application. Scan only.

**27. Speech-Sound Cartridge (Tandy).pdf** (206K) [L]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Speech-Sound%20Cartridge%20(Tandy).pdf
Manual for the Speech/Sound Cartridge (SP0256 speech plus an AY-3-8913 PSG). Serves: an alternative hardware PSG for sound effects. The service manual (1.9M) and schematic (501K) are next to it.

**28. AY-3-891x Programmable Sound Generator (General Instruments).pdf** (906K) [L]
https://colorcomputerarchive.com/repo/Documents/Datasheets/AY-3-891x%20Programmable%20Sound%20Generator%20(General%20Instruments).pdf
PSG datasheet for the SSC's sound chip. Serves: sound, only if the SSC is chosen as a target.

**29. Multi-Pak Interface Owners Manual (Tandy).pdf** (1.4M) [S]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Multi-Pak%20Interface%20Owners%20Manual%20(Tandy).pdf
Multi-Pak (MPI) manual: slot switch, slot select register $FF7F (bits 0 to 1 route SCS, bits 4 to 5 route CTS/CART, per MAME src: https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_multi.cpp), disk controller in slot 4. Serves: running FDC plus a sound cartridge (GMC or Orchestra-90) at the same time. Scan only.

**30. Multi-Pak Interface Service Manual (26-3024) (Tandy).pdf** (1.6M) [L]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Multi-Pak%20Interface%20Service%20Manual%20(26-3024)%20(Tandy).pdf
Service-level detail of $FF7F decoding and the CoCo 3 version differences. Serves: confirming slot select bit layout.

### D. Disk

**31. disk-basic-unravelled.pdf** (1.2M) [T]
https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/disk-basic-unravelled.pdf
Disk BASIC 1.0/1.1 disassembly: FCBs, FAT, directory, the 1793 FDC description, machine language file I/O, RAM variables. Serves: disk (bare metal reads of DAX archives and save games via DSKCON or our own FDC driver).

**32. Western Digital Floppy Controller - WD179X.pdf** (1.7M) [S]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Western%20Digital%20Floppy%20Controller%20-%20WD179X.pdf
WD1791/1793 datasheet (the FD-500/501 controllers use the 1793). Serves: disk, command bytes and status bits. The text layer is only a repeated copyright line.

**33. Western Digital Floppy Controller - WD177X.pdf** (1.0M) [S]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Western%20Digital%20Floppy%20Controller%20-%20WD177X.pdf
WD1770/1772/1773 datasheet (the FD-502 uses the 1773). Serves: disk. Same unreadable text layer as item 32.

**34. Color Computer Disk System Programming Manual (Tandy).pdf** (21M) [L]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%20Disk%20System%20Programming%20Manual%20(Tandy).pdf
Tandy's programming manual for Disk BASIC, including the DSKCON machine language interface. Serves: disk, second source for DSKCON usage.

**35. CoCo SDC User Guide v4 (Darren Atkinson).pdf** (3.3M) [T]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/CoCo%20SDC%20User%20Guide%20v4%20(Darren%20Atkinson).pdf
Manual for the CoCo SDC (SD card floppy emulator with flash). Serves: real hardware deployment, image formats, low-level command interface (fast sector reads that bypass WD1793 emulation). (The first two fetches failed with client errors; a later one worked.)

**36. HDB-DOS User Manual (Cloud-9).pdf** (435K) [L]
https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/HDB-DOS%20User%20Manual%20(Cloud-9).pdf
HDB-DOS (Disk BASIC replacement for hard disks and DriveWire). Serves: DriveWire/Becker based test deployment and multi-disk virtual drives.

### E. OS-9 / NitrOS-9 (only if the port runs under an OS)

**37. NitrOS-9 EOU Level 2 Technical Reference Manual v0.21 (L. Curtis Boyle).pdf** (1.1M) [T]
https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/NitrOS-9%20EOU%20Level%202%20Technical%20Reference%20Manual%20v0.21%20(L.%20Curtis%20Boyle).pdf
Current Level 2 technical reference (kernel, CoCo 3 MMU use, IRQ polling, VIRQ, RBF/SCF, all system calls). Serves: OS-9 port option, and as a well written explanation of the GIME MMU from an OS point of view.

**38. NitrOS-9 Technical Reference Manual v0.1 (Boisy Pitre).pdf** (1.5M) [L]
https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/NitrOS-9%20Technical%20Reference%20Manual%20v0.1%20(Boisy%20Pitre).pdf
Earlier NitrOS-9 technical reference. Serves: cross-check for item 37.

**39. OS-9 System Programmer’s Manual (Microware Systems Corp).pdf** (617K) [T]
https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/OS-9%20System%20Programmer%E2%80%99s%20Manual%20(Microware%20Systems%20Corp).pdf
Microware's Level One system programmer's manual with a Level Two service request appendix. Serves: OS-9 module format, system call conventions, IRQ polling table.

**40. Inside OS-9 Level II (1987)(Kevin Darling).pdf** (18M) [S]
https://colorcomputerarchive.com/repo/Documents/Books/Inside%20OS-9%20Level%20II%20(1987)(Kevin%20Darling).pdf
Kevin Darling's internals book (system map, DAT images, GIME use, clock module). Serves: OS-9 port option. Scan only.

Other OS-9 items present but not ranked: `OS-9 Technical Reference (Tandy).pdf` (8.4M), `OS-9 Level 2 (Tandy).pdf` (17M), `OS-9 Windowing System (Tandy).pdf` (1.6M), `OS-9 Level Two Development System (Tandy).pdf` (20M), all in https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/ .

## Key facts and page pointers from the documents that were read

These come from the text layers that WebFetch could extract. Page numbers are the documents' own printed numbers. Where a fact is also covered in research files 01 to 03, treat this as the "where to look" pointer.

### Super Extended BASIC Unravelled II (item 1)

Table of contents (printed pages): Foreword 1, Introduction 3, Color Computer 3 Hardware Differences 6, Memory Management 10, Super High Resolution Graphics 13, Colors and Palettes 23, Interrupts 27, Super Extended BASIC 30; appendices A Memory Map, B Disassembly of Super Extended BASIC 2.0, C Symbol Table, D Chip Control Registers, E CoCo 3 Colors, F Data/ASCII Tables, G ROM Routines, H Routine Entry Points, I BASIC 1.2/Ext 1.1 vs Color Ext 2.0 differences, J Character Sets. The PDF text layer is only 68,273 characters, covering roughly pp. 1 to 25; the appendices did not come through as text (src: item 1 URL).

| Topic | Fact | Page |
|---|---|---|
| MMU | 512K physical RAM as 64 blocks of 8K; MMU registers $FFA0 to $FFA7 map logical blocks 0 to 7 ($0000 to $E000) | pp. 10 to 11 |
| MMU | BASIC loads blocks $38 to $3F into $FFA0 to $FFA7 (the top 64K of a 512K machine) | p. 11 |
| MMU | HSCREEN map (Figure 2): logical 0 = block 56 ($70000, DP and variables), logical 1 to 4 = blocks 48 to 51 ($60000 to $67FFF, the 32K hi-res screen), logical 5 = block 61, logical 6 = block 53 (HGET/HPUT buffer), logical 7 = block 63 | p. 12 |
| GIME | $FF90 INIT0: COCO, MMUEN, IEN (bit 5, GIME IRQ enable), FEN (bit 4, GIME FIRQ enable), MC3 (constant $FExx page), MC2, MC1/MC0 ROM map | pp. 13 to 14 |
| GIME | $FF91 INIT1: TINS (timer input select, bit 5), TR (task register select) | p. 14 |
| Interrupts | $FF92 IRQENR and $FF93 FIRQENR: bits 5 to 0 = TMR, HBORD, VBORD, EI2 (serial), EI1 (keyboard), EI0 (cartridge); FIRQENR is laid out identically | pp. 14 to 15 |
| Interrupts | Keyboard interrupt fires on a zero on PA0 to PA6 of PIA0; needs at least one zero in the column strobe; joystick buttons always trigger it | p. 15 |
| Timer | 12-bit interval timer $FF94 (MSB) / $FF95 (LSB), value 0 to 4095; writing the MSB starts the count; it reloads on zero; zero stops it; source is 14.31818 MHz (about 70 ns) or horizontal sync (about 63.5 us) per TINS | pp. 14 to 16 |
| Video | $FF98 video mode (BP bit 7 text/graphics, LPR lines per row), $FF99 resolution (LPF 192/200/210/225 rows, HRES bytes per row, CRES colours), $FF9A border | pp. 16 to 18 |
| Video | Figure 5 lists the guaranteed hi-res mode combinations (for example 320 x 16 colours, 640 x 4 colours); others are not guaranteed | pp. 18 to 19 |
| Video | $FF9C vertical scroll, $FF9D/$FF9E vertical offset (screen start address), $FF9F horizontal offset with HVEN (bit 7, 256-byte virtual width) | pp. 19 to 21 |
| SAM | SAM compatibility registers $FFC0 to $FFDF, including the CPU rate bits $FFD8/$FFD9 | pp. 21 to 22, also p. 9 |
| Palette | RGB palette byte: bits 5,4,3 = R1,G1,B1 (high), bits 2,1,0 = R0,G0,B0 (low), so each gun has 4 levels; example purple (R2 G1 B3) = %xx101011 = 43 | p. 23 |
| Palette | Composite palette byte: bits 0 to 3 hue (16), bits 4 to 5 intensity (4); $04 dark red, $14 red, $24 medium red, $34 bright red | pp. 23 to 24 |
| Palette | Palette registers $FFB0 to $FFBF; mask the top two bits after reading; 16-colour modes use all 16, 4-colour the first 4, 2-colour the first 2 | pp. 24 to 25 |
| Boot | The CoCo 3 ROM copies BASIC to RAM and patches it (PATCHxx, ALINKxx, BLINKxx labels); $C000 to $DFFF initialisation code is overwritten by Disk BASIC; BASIC runs from RAM | pp. 3 to 6 |
| Hooks | Secondary RAM vectors starting at $015E let ROMs redirect BASIC | pp. 3 to 4 |

Caution: the WebFetch summary of the vertical offset formula on pp. 19 to 20 was garbled. Commonly documented is "start address = ($FF9D:$FF9E) x 8" [unverified here]; read p. 19 directly (or research file 02) before relying on it.

### Disk BASIC Unravelled (item 31)

TOC: Foreword 1, Introduction 3, How to Use This Book 4, Description of Disk BASIC 5, File Control Block Structure 6, File Allocation Table 9, The Directory 11, 1793 Floppy Disk Controller Description 13, Machine Language File Input/Output 17, Disk BASIC RAM Variables/Buffers 18; Appendix A memory map pp. A1 to A5 (src: item 31 URL).

| Topic | Fact | Page |
|---|---|---|
| DSKCON block | DCOPC $00EA (op 0 to 3), DCDRV $00EB (drive 0 to 3), DCTRK $00EC (track 0 to 34), DSEC $00ED (sector 1 to 18), DCBPT $00EE to $00EF (buffer pointer), DCSTA $00F0 (status) | p. A4 |
| Geometry | 35 tracks x 18 sectors x 256 bytes; 2 granules of 9 sectors per track; track 17 holds FAT and directory, leaving 68 granules | p. 5 |
| FAT | Track 17 sector 2; one byte per granule, $FF = free; a "last granule" flag in the high bits with the sector count in the low bits. Unravelled describes the RAM copy with 6 control bytes ahead of the 68 granule bytes | pp. 9 to 10 |
| Directory | Track 17 sectors 3 to 11, 32-byte entries: name 0 to 7, extension 8 to 10, type 11, ASCII flag 12, first granule 13, bytes used in last sector 14 to 15 | p. 11 |
| FDC | $FF40 write-only latch: bits 0 to 2 drive select 0 to 2, bit 3 motor, bit 4 write precomp, bit 5 density, bit 6 drive select 3, bit 7 halt enable | p. 13 |
| FDC | $FF48 status/command, $FF49 track, $FF4A sector, $FF4B data | p. 14 |
| NMI | FDC INTRQ is wired to NMI; with HALT enabled, DRQ halts the CPU so a tight loop can move bytes; Disk BASIC sets NMIFLG and DNMIVC so the NMI at command end jumps out of the transfer loop | p. 14 |

Port implication: a 256-byte sector read through DSKCON costs one ROM call; the NMI/HALT mechanism means our own FDC driver must own the NMI vector during disk I/O.

### Color BASIC Unravelled (item 20, partial)

TOC: Foreword 1, Introduction 3, Color BASIC an Interpreter 4, Interpreter Mechanics 6, Variables 10, Console Input/Output 13; appendices A Memory Map (from p. A1), B Disassembly, C Routines and Entry Points, D Floating Point, E Data/ASCII tables, F Memory Map Description, G Interrupts, H Operator Precedence, I/J version differences, K ASCII chart. Extracted: DA (the DAC) = PIA1+0 = $FF20 (p. A1); IRQVEC at $010C (p. A4); TIMVAL $0112 (p. A4); RAM vector table RVEC0 to RVEC24 at $015E to $01A6 (pp. A5 to A6), for example RVEC4 console in, RVEC20 command loop. The ROM jump table at $A000 (POLCAT, CHROUT and so on) is in a part of the text the fetch did not return; look in Appendix C (src: item 20 URL).

### The 6309 Book (item 11)

TOC: Section 1 Processor Overview 1-1 (programming model 1-5, processor modes 1-9, address map 1-9); Section 2 Addressing Mode Reference 2-1 (post-bytes 2-3); Section 3 Instruction Reference 3-1; Section 4 Application Information 4-1: detecting the 6309 4-1, detecting native mode 4-2, switching modes 4-3, FIRQ mode 4-6, W in emulation mode 4-8, native mode interrupt processing 4-10, trap vector 4-14, 16-bit ops 4-18, 32-bit ops 4-19, TFM 4-21, multiply/divide 4-29, bit manipulation 4-31, D and W 4-38, V register 4-40, register-to-register 4-42; Appendix A programming card A-1 (src: item 11 URL).
Facts: MD bit 0 selects native mode (p. 1-9); native mode gives a "15% typical speed increase" and stacks W on interrupts (p. 1-4); E/F form W, D:W form Q, V survives reset (pp. 1-4 to 1-8); illegal opcode and divide-by-zero share the trap vector $FFF0 (p. 1-10); the new instructions work in both modes (p. 1-4).

### HD63B09EP Technical Reference Guide (item 12)

LDMD is immediate only, opcode $11 $3D, 5 cycles; MD bit 0 = native, bit 1 = FIRQ behaves like IRQ (p. 3, p. 4). Native-mode interrupt frame is 14 bytes (CC, A, B, E, F, DP, X, Y, U, PC), so code that patches the stacked PC at offsets 10 to 11 must use 12 to 13 (p. 3). Trap through $FFF0/$FFF1 (p. 7). TFM is listed as 6+3n cycles (opcode table pp. 16 to 17). MULD immediate 28 cycles, DIVD immediate 25, DIVQ immediate 36 (pp. 17 to 18). Native savings examples: CMPX direct 6 to 4, LBRA 5 to 4, JSR extended 8 to 7, NEG direct 6 to 5 (pp. 10 to 20) (src: item 12 URL).

### Secret features of 6309.txt (item 13)

MD read bit 7 = division by zero occurred, read bit 6 = illegal instruction; BITMD clears them, so the trap cause can be read only once. Native-mode interrupts push PC, U, Y, X, DP, W, D, CC. The author marks several details (TFM behaviour, divide result registers) as untested; the table even mislabels some opcodes (NEOR for BEOR), so prefer items 10 to 12 for exact encodings (src: item 13 URL).

### MC6809E datasheet, OCR (item 15)

Vectors: RESET $FFFE, NMI $FFFC, SWI $FFFA, IRQ $FFF8, FIRQ $FFF6, SWI2 $FFF4, SWI3 $FFF2, reserved $FFF0 (Table 1). FIRQ stacks only CC and PC; IRQ and NMI stack the entire state (Figures 8 and 9). FIRQ/IRQ are level sensitive and must be held at least three bus cycles. Indexed post-byte format: Figure 15, with extra cycles in Table 2. Cycle tables: Table 9 and Figure 18 (programming aid); bus-cycle detail in Figure 17. MUL = 11 cycles (src: item 15 URL). No page numbers in the OCR text; navigate by table/figure number.

### Motorola 6809 and Hitachi 6309 Programming Reference, Atkinson (item 10)

One instruction per page in alphabetical order starting with ABX on p. 4 (for example ADDR p. 10, AIM p. 11, BAND p. 20, BITMD p. 34, CMPR p. 52, DIVD p. 59, DIVQ p. 60, EXG pp. 65 to 66). Cycle cells show "6809-or-emulation / native", for example BSR "7 / 6"; a "+" in the indexed column means add the post-byte cost (src: item 10 URL). The fetch returned pages 4 to 68 only; the rest (LD..TFM..TST and the addressing-mode tables) is in the same PDF.

### NitrOS-9 EOU Level 2 Technical Reference Manual (item 37)

Pages: System Organization 10; Kernel 13; Memory Management 16; Color Computer 3 MMU Hardware 18; Multi-programming 22; Signals 25; Interrupt Processing 26; VIRQ 29; Memory Modules 32; Unified I/O 40; device drivers 48; descriptors 55; RBF 59; SCF 84; Pipes 101; VIRQ/RAM/NIL driver 104; System Calls 108 (user 114, I/O 159, privileged 182, GetStat 223, SetStat 265); appendices 327 (VIRQ example in Appendix F, p. 344).
Facts: $FE00 to $FFFF is not available to user processes (p. 18); F$MapBlk maps physical blocks into the caller's space, example maps blocks $3D to $3E (p. 22, call on p. 141); IRQ polling entries are XOR flip, AND mask, priority 255 first, service routines end with RTS and set carry if not theirs (pp. 27 to 28); F$IRQ is privileged (p. 29); the system tick is 60 Hz NTSC / 50 Hz PAL (p. 22); VIRQ packet Vi.Cnt/Vi.Rst/Vi.Stat (p. 30); system calls are SWI2 plus a code byte (p. 14) (src: item 37 URL).

### OS-9 System Programmer's Manual (item 39)

Level One manual (v1.2) with Level Two calls in Appendix E (p. 95). Module header: sync $87 $CD, size, name offset, type/language at byte 6 (type in the high nibble: 1 program, C system, D file manager, E driver, F descriptor), execution offset at bytes 9 to 10, permanent storage size at 11 to 12, 3-byte CRC (pp. 13 to 16). IRQ polling table: 9 bytes per entry, poll by XOR flip then AND mask, F$IRQ to install, handlers end in RTS (pp. 10 to 12) (src: item 39 URL).

### CoCo SDC User Guide v4 (item 35)

TOC: What is the CoCo SDC 1; Getting Ready 5; Using the SDC 9 (DRIVE status 9, mounting 9, multiple disks 10, wildcards 10, DIR 11, locking 12, new images 12, eject 12, DriveWire 12, real floppies 13, automatic program execution 13, step rate 13); Using the Flash 15; SDC Explorer 17; File Formats 19 (DSK, geometry table 20, JVC 20, VDK 21, SDF 21); Command Reference 25 (CommSDC 25, path names 25, mount image 26, read logical sector 31, write logical sector 32, low-level stream 32, low-level hardware interface 34); Glossary 43.
Facts: FAT16/FAT32 SD cards (p. 2); long file names unsupported, 8.3 only (p. 5), path components 8.3 separated by "/" (p. 25); `DRIVE n,"path"` mounts an image, optional third parameter selects a disk inside an HDB-DOS image (pp. 9 to 10); AUTOEXEC.BAS on a mounted image runs at startup unless SHIFT is held (p. 13); `RUN @n` boots flash bank n (p. 15); command mode is entered by storing $43 in $FF40, with $FF48 command/status and $FF49 to $FF4B parameters (p. 34) (src: item 35 URL).

## Notable documents that look relevant but could not be read

| Document | URL | Problem | Workaround |
|---|---|---|---|
| Color Computer 3 Service Manual (Tandy) | item 2 | Opened; no text layer | OCR the PDF (pdf-reading skill, rasterise and read pages) after downloading it through a host that can reach the archive; the cloud shell cannot (proxy 403). |
| Assembly Language Programming for the CoCo3 (Tepolt) | item 3 | No text layer | Same. |
| CoCo III Secrets Revealed (both editions) | items 4, 5 | No text layer (item 5 not tried) | Same. |
| WD179X and WD177X datasheets | items 32, 33 | Text layer is only "This Material Copyrighted By Its Respective Manufacturer" | Use research file 03 or another WD datasheet source for the command set. |
| MC6821 PIA datasheet | item 22 | No text layer | Try item 23, or the Motorola PIA datasheet from another archive. |
| Orchestra-90 manual, Multi-Pak owners manual, Color Computer Technical Reference Manual, CoCo 3 Extended Basic manual, Inside OS-9 Level II | items 26, 29, 25, 7, 40 | No text layer | MAME source gives the Orch-90 and MPI register facts already cited above. |
| Unravelled II.xls | https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/Unravelled%20II.xls | Not fetched (4.1M spreadsheet, WebFetch handles PDFs/HTML) | Probably a cross-reference/symbol table for Super Extended BASIC Unravelled; worth opening locally. |
| Super Extended BASIC Unravelled II appendices (memory map, disassembly, entry points) | item 1 | Text layer ends around p. 25 | Read the remaining pages as images. |
| Color Computer Memory Map (Bob Russell) | https://colorcomputerarchive.com/repo/Documents/Books/Color%20Computer%20Memory%20Map%20(Bob%20Russell).pdf | Not fetched (12M); CoCo 1/2 era | Low priority. |
| Ultimate Color Computer Reference Guide and Tool Kit (CMD Micro) | https://colorcomputerarchive.com/repo/Documents/Books/Ultimate%20Color%20Computer%20Reference%20Guide%20and%20Tool%20Kit%20(CMD%20Micro).pdf | Not fetched (11M) | May contain CoCo 3 tables; check if items 1 to 4 leave gaps. |
| Interlaced graphics for the Color Computer 3 (Greg Beeley) | https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Interlaced%20graphics%20for%20the%20Color%20Computer%203%20(Greg%20Beeley).pdf | Not fetched (5.9M) | Only relevant if the port ever tries 400-line interlace tricks; not needed for 320x200x16. |

Not present in the archive at all (checked against the listings): a GIME (TCC1014/ACVC) datasheet, an SN76489 datasheet, and a Games Master Cartridge manual.

## Implications and recommendations for the port

1. **Primary references per subsystem.** Video/MMU/interrupts: Unravelled II chapters 4 to 7 (item 1), confirmed against the Service Manual (item 2) when OCRed. CPU: Atkinson (item 10) for every cycle count; The 6309 Book section 4 (item 11) for any 6309 path. Disk: Disk BASIC Unravelled (item 31). Keyboard/sound bits: Color BASIC Unravelled appendices (item 20) plus the PIA datasheet (item 22).
2. **Cite pages in code comments.** For platform code, cite e.g. "Unravelled II p. 15" next to every GIME register write; it makes later audits cheap.
3. **DSKCON first, own FDC driver later.** DSKCON's block at $00EA is documented precisely (p. A4). A first port can load DAX blocks through DSKCON with the ROM mapped in; a later optimisation can replace it with an NMI/HALT driver modelled on p. 14, or with CoCo SDC's low-level sector command (SDC guide p. 31 to 34) where available.
4. **Sound target decision.** The archive confirms the options: built-in 6-bit DAC ($FF20, item 20 p. A1), Orchestra-90 (8-bit stereo DAC), SSC (AY-3-8913), and the GMC (SN76489, no documentation in the archive; use MAME/XRoar source). The GMC is the closest match to the original Tandy 3-voice code path.
5. **OCR pass.** Schedule one agent task to OCR items 2, 3, 4, 22, 32, 33 into text files in the repo; most "hard" facts the port needs are in those six scans.
6. **6309 is optional.** The references are good enough to write an optional 6309 native-mode path (TFM blits at 3 cycles per byte plus 6, MULD), but the stock target should be the 6809E.

## Open questions

- Does the vertical offset formula on Unravelled II p. 19 match the "x 8" form in other references? (The extracted summary was garbled.)
- Are the Super Extended BASIC Unravelled II appendices (B, D, G, H) present as images in the same 907K PDF, or was the archive copy truncated? The text layer stops near p. 25.
- Is Unravelled II.xls a symbol table we can import into the MAME/XRoar debuggers?
- What exactly is in "Color Computer 3 Diagnostics Manual (Tandy).pdf" (179K, Manuals/Hardware)? It might contain a GIME self-test register sequence useful for emulator validation.
- Which archive document, if any, documents the Games Master Cartridge bank and PSG registers? None found.

## Sources

- https://colorcomputerarchive.com/repo/Documents/Manuals/ : top-level manuals index (7 folders).
- https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/ : hardware manuals listing (A to J).
- https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/?C=N;O=D : same listing reverse sorted (J to Z: Multi-Pak, Orchestra-90, WD datasheets, Speech-Sound).
- https://colorcomputerarchive.com/repo/Documents/Manuals/Programming/ : programming manuals listing.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/ : OS manuals listing (OS-9, NitrOS-9).
- https://colorcomputerarchive.com/repo/Documents/Books/ : books listing.
- https://colorcomputerarchive.com/repo/Documents/Books/Unravelled%20Series/?C=N;O=A : Unravelled series listing.
- https://colorcomputerarchive.com/repo/Documents/Datasheets/ : datasheets listing (29 PDFs).
- https://colorcomputerarchive.com/repo/Documents/ : Documents index (found Microprocessors folder).
- https://colorcomputerarchive.com/repo/Documents/Microprocessors/HD6309/ and https://colorcomputerarchive.com/repo/Documents/Microprocessors/MC6809/ : CPU folders.
- Item URLs 1, 10, 11, 12, 13, 15, 20, 31, 35, 37, 39 : read through WebFetch; facts above.
- Item URLs 2, 3, 4, 7, 22, 25, 26, 29, 32, 33, 40 : opened, no usable text layer.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_gmc.cpp : GMC SN76489AN at $FF41.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_orch90.cpp : Orchestra-90 DACs at $FF7A/$FF7B.
- https://raw.githubusercontent.com/mamedev/mame/master/src/devices/bus/coco/coco_multi.cpp : Multi-Pak $FF7F slot select bits.

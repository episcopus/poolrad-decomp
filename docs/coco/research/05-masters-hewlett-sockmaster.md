# 05: What the CoCo 3's most accomplished modern developers know (Hewlett, Sock Master, and others)

Scope: techniques published by Glen Hewlett (arcade ports of Pac-Man, Defender, Joust, Robotron, Space Invaders), John Kowalski "Sock Master" (GIME reference, Donkey Kong, Gloom, demos), plus Nick Marentes, Richard Goedeken (DynoSprite), Jamie Cho (Space Bandits, CMOC on DynoSprite), John Linville (Game Master Cartridge) and Ciaran Anscomb (XRoar). Each technique is given with its mechanism, a source, and a note on whether it helps the Pool of Radiance (PoR) port.

## Key takeaways for the Pool of Radiance port

1. Every successful whole-game port (Hewlett's Pac-Man, Defender, Joust; Sock's Donkey Kong) ran the original game logic translated into native 6809 code and replaced only the hardware layer with "work-alike" routines. Nobody emulated the original CPU. PoR already has matching C; the same rule applies: keep the game logic, rewrite the platform layer.
2. The 512 KB CoCo 3 is used as a bank of 8 KB MMU blocks with a written block map (one EQU per block, its purpose and physical address). Hewlett's Defender and Joust maps are the model to copy for PoR's overlays, DAX caches and screen buffers.
3. Two MMU task register sets ($FFA0 to $FFA7 and $FFA8 to $FFAF, selected by $FF91 bit 0) let an interrupt routine see a different memory map for a few cycles without disturbing the main map. Hewlett uses this for sample playback; PoR can use it for a disk or decompression interrupt helper.
4. Verification workflow: first make the original source reassemble byte-identical to the original binary, then port; keep the original address beside each routine; use MAME `-debug` traces, input recording, and a border-colour CPU meter. PoR's matching C makes the "golden reference" step already done; build a trace and screenshot comparison harness against the DOS build early.
5. Fast drawing comes from compiled sprites (code that stores pixels), stack blasting (PSHU/PULU about 2.2 cycles per byte for fills), unrolled loops with computed entry, and self-modifying operands. For PoR, 24x24 icons and 8x8 tiles are byte-aligned at 4 bits per pixel, so the odd-pixel variants that arcade ports need are unnecessary.
6. Palette writes cause visible "sparkle" glitches; change $FFB0 to $FFBF only during the vertical border (VBORD IRQ). This bit both Hewlett (Pac-Man 1.01) and Marentes.
7. Budget: one 60 Hz field is 29,860 CPU cycles at 1.7897725 MHz (DynoSprite benchmarks). A full 320x200x16 screen is 32,000 bytes, so even the fastest fill (about 2.2 cycles per byte) costs more than two fields. PoR should redraw only the 3D viewport and changed cells, or compose off screen and page flip with $FF9D/$FF9E.
8. Loading: the community standard is LOADM plus a close-hook loader that streams into MMU blocks, with ZX0 compression (Einar Saukas, 6809 decompressor by Doug Masten) or DEFLATE (DynoSprite). CoCoSDC can stream a file at 512 bytes per sector through $FF4A. DynoSprite and Space Bandits show CMOC-compiled C loaded into fixed 8 KB code windows at run time, which is the closest existing analogue of PoR's overlay manager.
9. Sound: PoR's Tandy PSG effects can go to the Game Master Cartridge (SN76489 at $FF41) almost unchanged; the alternative is DAC samples on a GIME timer FIRQ, which costs a large slice of CPU (my estimate about a quarter at 6 kHz for Hewlett's routine).

## 1. Glen Hewlett ("nowhereman999")

### 1.1 Who and what

Glen Hewlett's blog is "Glen's Weblog" at https://nowhereman999.wordpress.com/ (src: https://nowhereman999.wordpress.com/). His GitHub user is nowhereman999 (repositories Defender_CoCo3, Joust_CoCo3, ROBOTRON_CoCo3, z80to6809, CoCoSDC_StreamFile, CoCo-3-Scan-Line-Demo, BASIC-To-6809) (src: https://github.com/dougmasten/awesome-coco and the repository clones).

Which arcade ports are his:

| Game | Original CPU | Status | Requirement | Source |
|---|---|---|---|---|
| Space Invaders | Intel 8080 | Complete, about six weeks of work (2016) | CoCo 3 | https://www.vintageisthenewold.com/space-invaders-trs-80-coco-3-port-directly-from-intel-8080-arcade-sources/ |
| Pac-Man | Z80 | Complete July 2017, version 1.01 | 512 KB CoCo 3, user supplies PACMAN.5E ROM | https://nowhereman999.wordpress.com/2017/07/01/zilog-z80-to-motorola-6809-transcode-part-024-pac-man-is-finally-complete-if-you-have-a-coco-3-with-512k-give-it-a-try/ |
| Joust | 6809 (Williams) | Released August 2021, V1.1 | 512 KB | https://nowhereman999.wordpress.com/2021/08/17/joust-is-now-available-for-the-coco-3/ |
| Defender | 6809 (Williams) | Released September 2021 | 512 KB, two disks | https://nowhereman999.wordpress.com/2021/09/25/defender-for-the-tandy-coco-3/ |
| Robotron 2084 | 6809 (Williams) | Shelved May 2022 "near playable", source released | 512 KB, two joysticks | https://nowhereman999.wordpress.com/2022/05/04/robotron-last-update/ |
| Rick Dangerous | 68000 (Amiga) | In progress 2023 | planned 6309, maybe 2 MB | https://nowhereman999.wordpress.com/2023/05/25/coco-3-256-x-200-x-16-colours-is-a-great-resolution/ |

Not his: Donkey Kong (Sock Master, see section 2) and "Pac-Man Tribute" (Nick Marentes, an original re-creation, not a code port; section 3.1).

### 1.2 The porting methodology (workflow lessons)

His overview article lists the steps he uses for any arcade conversion (src: https://nowhereman999.wordpress.com/2018/01/20/arcade-machine-conversion-to-the-coco-overview/):

1. Research: technical, repair and owner manuals, interviews with the original authors, and above all a commented disassembly (ideally for the same hardware family).
2. Make or obtain a disassembly; split big ones into small files (for example text data in its own file) so they are quick to navigate.
3. Annotated transcoding: keep the original address and bytes as a comment beside each converted line, for example `;08DE 3A0E4E` next to the 6809 code.
4. Start from the reset vector and the startup routine, not from the first byte. Fake the RAM/ROM self-test results so they pass.
5. Identify and label the text output routine, the sound routine and the input routines, and every call to them.
6. Work out how DIP switches or battery RAM configure the game before the IRQ starts.
7. Find the IRQ ("the heart of the game"). Most arcade games he saw run from a VSYNC IRQ, so he sets up a VSYNC IRQ on the CoCo and converts the IRQ routines one at a time, stubbing undecoded jumps.
8. Test early on real hardware or MAME; seeing the first converted screen is "very motivating"; startup sounds early, full audio later.
9. Debug by running the original in MAME's debugger side by side (breakpoints, watchpoints, stepping, memory views).
10. Tooling: write a translator to get started (his Z80/8080 to 6809 converter).

What the released sources add (from the Defender and Joust source zips in the GitHub repositories, inspected directly):

- Step zero is a byte-identical reassembly. Defender's change log begins "V 0.00 - Started with all the source assembles to match the Red ROMS almost perfectly"; the Joust source tree contains a file named `JOUST_BIG_01_Perfect_Ready_to_CoCoize.txt`; for Robotron he "made sure the output it produced was exactly the same as the latest ROMs that MAME uses" (src: https://github.com/nowhereman999/Defender_CoCo3 , https://github.com/nowhereman999/Joust_CoCo3 , https://nowhereman999.wordpress.com/2021/10/09/robotron-progress/). Only after the source is proven does he "CoCoize" it.
- Version-numbered changelog at the top of the main source file, one line per bug and its root cause (Defender reaches V0.32 with about 40 recorded fixes). Typical entries: an enemy shot with Y = $FF computed $FF*160 = $9F60 and drew into code; a sprite routine missing `TFR D,U` drew wherever U pointed; a list bound in the original (`CMPX #TLIST+64`) was wrong and had to be `+40`. Several "random crashes" were his own code overwriting data, so he added an assembly flag `SelfMod EQU 1` that disables all self-modifying code, to test whether a crash is the game overwriting itself (src: Defender_CoCo_3_Source/CoCo_32.asm in https://github.com/nowhereman999/Defender_CoCo3).
- Feature flags for every CoCo replacement (`UseCompiledSprites`, `CoCoLand`, `CoCo3Scanner`, `EnemyShotsCoCo`, `RAMTEST`, `Add_Audio`...), so the original code path can be reinstated to bisect a bug (same source).
- The makefile holds the MAME trace command used to compare behaviour: `trace output.tr.txt,0,noloop,{tracelog "A=%02X,B=%02X,X=%02X,Y=%02X,U=%02X,S=%02X,CC=%02X ",a,b,x,y,u,s,cc}` and runs the build with `mame -debug coco3 -flop1 DISK1.DSK -flop2 DISK2.DSK -frameskip 10 -autoboot_command "\n\nRUN\"CONFIG\n" -ui_active` (src: Defender_CoCo_3_Source/makefile).
- Crash hunting with MAME input recording: `mame defender -record defgameplay.ini` then debug playback at 5% speed; record/playback worked "about half the time", which he suspected was vsync dependence. A tester's register trace on his own machine found the decisive crash (src: https://nowhereman999.wordpress.com/2021/09/25/defender-for-the-tandy-coco-3/).
- Copy protection inside arcade code caused "random" crashes once he removed the ROM tests: Joust had three hidden checksum checks (table checksum at $85C1 on player death, ROM checksum at $6AC7, ROM sum loop at $ECF8 to $ED17 that corrupts a random byte in $A000 to $A0FF), each patched with RTS or NOPs (src: https://nowhereman999.wordpress.com/2021/06/23/found-some-copy-protection-code-in-joust/).
- Unit RAM/ROM tests are replaced with a fake "rug" pattern because a real test "would fail on his modified code" (src: https://nowhereman999.wordpress.com/2017/12/31/defender-conversion-for-the-coco-3-part-1/).

PoR relevance: high. PoR's matching Turbo Pascal and C are the equivalent of his byte-identical reassembly; the lessons are (a) keep a per-feature flag that can switch a platform routine back to a reference implementation; (b) keep a running changelog of root causes; (c) build a deterministic trace (game state per turn or per menu event, since PoR has no vsync dependence, record/playback should be fully reliable); (d) expect that the DOS game may contain integrity or copy protection checks that behave differently when code moves [unverified for PoR; check the decomp].

### 1.3 CPU translation: 8080, Z80 and 6502 to 6809

His Z80 translator is a 1,561-line C program `z80_to_6809_15_Pacman.c` (repository https://github.com/nowhereman999/z80to6809, linked from https://nowhereman999.wordpress.com/2017/07/02/zilog-z80-to-motorola-6809-transcode-part-025-my-z80-to-6809-program/). It reads a fixed-column disassembly (operands start at column 39, so "the text input file must have the correct spacing"), emits a best-guess 6809 instruction and keeps the Z80 line as a comment to the right. Register mapping from its `change()` function: HL to X, DE to Y, BC to U, IX to U, IY to Y, SP to S, AF to A,CC; DJNZ becomes DECB plus a branch; A stays A (src: z80to6809/z80_to_6809_15_Pacman.c). Conflicting mappings (BC and IX both to U) show that the output always needs hand review; his own words: "There are still some bugs in my translating program and it needs to be hand tweaked quite a bit" (src: https://nowhereman999.wordpress.com/2016/12/29/zilog-z80-to-motorola-6809-transcode-part-001/).

Data handling: data sections are split from code and placed at their original addresses with ORG; Z80 little-endian DW becomes FCB low,high or a byte-swapped FDB; jump tables get labels instead of numbers so the assembler fixes addresses, and he pre-swaps 16-bit table entries so the 6809 never swaps at run time (src: part 001 above and https://nowhereman999.wordpress.com/2016/12/30/zilog-z80-to-motorola-6809-transcode-part-002/).

Performance: his first literal Pac-Man transcode ran at "nearly 1/4 the speed of the original"; he measured routines in MAME with breakpoints at routine entry and exit, reading `beamy` and `frame`, assuming 29,666 cycles per frame (src: https://nowhereman999.wordpress.com/2017/02/03/zilog-z80-to-motorola-6809-transcode-part-014-mame-debug-and-how-fast-the-code-is/). (His "124 cycles per line" divides by 240 visible lines; with 262 total NTSC lines the true figure is about 114 cycles per line.) He planned to release the slow-but-correct version first and then the optimised one.

For 6502 sources he documents the carry inversion on subtraction (6502 carry is "not borrow"), SBC/ADC workarounds, decimal mode and addressing modes (src: https://nowhereman999.wordpress.com/2023/02/15/mos-6502-to-motorola-6809-assembly-language-transcoding/).

PoR relevance: low for the translator itself (PoR is ported from C, not x86 assembly). Medium for the habit: get a slow but correct build running first, measure, then optimise the hot routines by hand.

### 1.4 Memory: 512 KB as a written block map

Defender and Joust each start with a table of all 64 blocks of 512 KB: label, block number, physical address, use. Extract from Defender (src: Defender_CoCo_3_Source/includes/Def_CoCo3_Memory_Description_and_Defines.asm):

| Block | Physical | Use |
|---|---|---|
| $00 | $00000 to $01FFF | CMOS (battery RAM image) and settings |
| $01 to $03, $07 | $02000 to $0FFFF | Defender ROM banks 1, 2, 3, 7 |
| $04, $05 | $08000 to $0BFFF | compiled sprite code |
| $06 | $0C000 to $0DFFF | explosions |
| $0A to $0E | | high score tables |
| $0F to $37 | $1E000 to $6FFFF | one or more 8 KB blocks per sound sample (Startup_Sound, Player_Fire1 to 4, ...) |
| $38 to $3F | $70000 to $7FFFF | the CPU's default 64 KB: video at logical $0000 to $97FF, direct page $A000 to $A0FF, code to $FDFF |

Joust uses blocks $00 to $04 as video RAM, $20 to $26 for compiled sprite and rectangle-blaster code, $27 for CMOS, and sixteen blocks $28 to $37 for "Text Messages and font code as compiled sprites", one block per palette colour (src: Joust_CoCo3_Memory_Description_and_Defines.asm in https://github.com/nowhereman999/Joust_CoCo3). That is 128 KB spent to make text drawing a direct call; with 512 KB that was the right trade.

Bank-switch emulation: Defender swaps a 4 KB ROM bank at $C000 to $CFFF by writing $D000. The CoCo MMU switches 8 KB at a time, so he copied the shared $D000 to $DFFF code into each of the four banks and redirected writes of the bank number to $FFA6 (the $C000 to $DFFF slot) (src: https://nowhereman999.wordpress.com/2017/12/31/defender-conversion-for-the-coco-3-part-1/).

Pac-Man: video RAM moved out of the CPU map into blocks 0 to 4, with a pristine backup copy of the screen in blocks $10 to $14; this freed about $5000 bytes. A 16-pixel sprite row can cross an 8 KB boundary, so two consecutive blocks are mapped at $A000 and $C000 (via MMU registers 5 and 6); the block number is derived from the high bits of the screen address (mask $E0, shift right five) and the backup is the same plus $10 (src: https://nowhereman999.wordpress.com/2017/01/31/zilog-z80-to-motorola-6809-transcode-part-013-sprites-and-more-ram/).

PoR relevance: high. Directly reusable patterns:
- One authoritative block map file shared by assembler and C (`#define`/EQU), naming every block.
- Duplicate small shared routines into each switchable bank instead of calling across banks (Defender's $D000 copy). For PoR, put the overlay calling stub and frequently used RTL helpers in a fixed region, and let overlays live in a switchable 8 KB or 16 KB window.
- Keep a clean background copy of the combat map in other blocks and restore under moving icons by copying from it (Pac-Man backup screen; his sprite compiler's `-rXXXX` restore-from-offset option, section 1.6).
- Map two consecutive blocks when a drawing operation may straddle an 8 KB boundary.

### 1.5 The two-task MMU trick for interrupt-time access

The Defender sample player FIRQ (src: CoCo_32.asm, labels FIRQ_Sound, FIRQNoAudio):

```
FIRQ_Sound:
        STA   FIRQ0Restore+1   ; save A into the operand of a later LDA # (self-modifying)
        LDA   FIRQENR          ; read $FF93: acknowledges and re-arms the GIME FIRQ
        LDA   #%00100001
        STA   INIT1_Register1  ; $FF91: fast timer clock, MMU Task 1 ($FFA8-$FFAF)
        INC   GetSample+2      ; advance self-modified 16-bit pointer
        BNE   >
        INC   GetSample+1
        BMI   SampleIsDone     ; pointer reached $8000: sample ended
GetSample:
!       LDA   SoundBytes       ; operand is the sample pointer
SendAudio:
        STA   PIA1_Byte_0_IRQ  ; $FF20: 6-bit DAC
        LDA   #%00100000
        STA   INIT1_Register1  ; back to MMU Task 0 ($FFA0-$FFA7)
        DEC   FIRQCount
        BEQ   Do_VideoBeam_IRQ
FIRQ0Restore:
        LDA   #$FF             ; patched with the caller's A
        RTI
```

Mechanism: Task 1's registers map the current sample's 8 KB blocks into the lower half of the address space, while Task 1's upper registers match Task 0, so the FIRQ code at $E000 and above stays visible in both. Switching tasks is one store to $FF91 each way. The sample can be anywhere in 512 KB without the main program ever unmapping its own data. Setup: timer $0254 = 596 counts at 279.365 ns = 166.5 microseconds, "good for 6005.95 Hz samples", `STD $FF94`, `LDA #$20 / STA $FF93` enables the timer FIRQ, `LDA #$08 / STA $FF92` enables only VBORD for the IRQ, INIT0 = %01111100 (CoCo 3 mode, MMU on, GIME IRQ and FIRQ on, $FExx vectors constant) (same source; also https://nowhereman999.wordpress.com/2017/11/17/how-to-setup-and-use-irqs-on-the-trs-80-color-computer-part-5-advanced-interrupt-settings-and-using-coco-3-specific-interrupts/).

Cost: my estimate from standard 6809 cycle counts for this routine is about 70 cycles per FIRQ including the 10-cycle FIRQ entry and 6-cycle RTI, so roughly 6,006 x 70 = 420,000 cycles per second, about 23% of a 1.79 MHz CPU [estimate, not measured by the author]. The source comment says "100 FIRQs per frame" and "Tested with MAME, 99 times the FIRQ was triggered between each VSYNC IRQ".

PoR relevance: medium. PoR needs no music, but the two-task trick is ideal for any interrupt-time helper that must touch data outside the current map (a streaming disk reader, a sound-effect player whose tables live in a high block). Keep the handler and its stack in the region common to both tasks.

### 1.6 Graphics: modes, compiled sprites, stack blasting, text

Screen modes he used:
- 320x225x16 for Pac-Man (scrolling the screen vertically to show the 288-row maze) and for Williams games whose screens are 304x256 (Defender shows 320x225 from a 304x256 world; the bottom 16 rows had to be cropped or scrolled) (src: Defender part 1 above). Joust's map entry says "16 Colour 320 x 225 shown although part of the bottom will be hidden as Joust is bigger".
- 256x200x16 for Rick Dangerous because a 128-byte row makes address arithmetic trivial: `address = Y*128 + X/2`. Store coordinates as Y,X in memory and `LDD ,U` then `LSRD` gives the byte address in D in 10 cycles (6 with direct page), with the carry flag telling whether X was odd so code can `BCS DrawOddSprite` (src: https://nowhereman999.wordpress.com/2023/05/25/coco-3-256-x-200-x-16-colours-is-a-great-resolution/). A MUL-based Y*128 costs 20 cycles and shifting costs 23.

Compiled sprites: the sprite is assembled as code: `LDD #pixels / STD offset,X` and so on, ending in RTS. A 16x14 stack-blasted Pac-Man sprite took 529 cycles; compiled versions took about 263 to 450 depending on detail, and transparency comes free because only opaque bytes are stored (src: https://nowhereman999.wordpress.com/2017/04/12/zilog-z80-to-motorola-6809-transcode-part-021-compiled-sprites-are-faster-then-stack-blasting/). Sock Master's comment on that post: replace `LEAX 256,X` with `ABX` (3 cycles, 1 byte); L. Curtis Boyle: keep pixel data in A and the row step in B. Next refinement: draw bottom to top and replace runs of stores with `PSHU`, which updates U automatically so the `LEAU` row offsets stay within 8-bit range: a 10x13 sprite dropped from 220 cycles and 106 bytes to 193 cycles and 77 bytes (raw bitmap data would be 65 bytes) (src: https://nowhereman999.wordpress.com/2017/05/24/zilog-z80-to-motorola-6809-transcode-part-023-optimized-sprite-rendering-combining-compiled-sprites-with-stack-blasting/). Defender: a 3x8 character costs 129 cycles as a compiled sprite versus 291 on the original hardware; compiled sprites averaged about 20% slower than the arcade's own stack blasting on its column-ordered video RAM (src: Defender part 1).

His sprite compiler `cmpblsp` (QB64 source on pastebin) takes a raw 4-bit-per-pixel file with `-w` bytes and `-h` rows; palette index 0 is transparent at nibble granularity; `-odd` writes a second routine shifted one nibble for odd X; `-rvX` writes an erase routine that fills with colour X; `-rXXXX` writes an erase routine that copies from a backup screen at a hex offset; `-s256` targets 128-byte rows; `-cyc` emits lwasm cycle-count directives. Using colour $F at sprite edges avoids an `ANDB #$F0` mask step (src: https://nowhereman999.wordpress.com/2017/08/26/sprite-compiler-for-the-trs-80-color-computer-3/).

Stack blasting: an unrolled block of five `PSHU D,X,Y` (11 cycles each, 6 bytes) plus one `PSHU D` writes 32 bytes per 70 cycles including loop compare, about 2.2 cycles per byte; adding DP gives one more byte per instruction. Copying with `PULU D,X,Y,DP` then `PSHS D,X,Y,DP` moves 7 bytes in about 32 cycles (about 4.6 cycles per byte). Data must be laid out backwards because the stack grows down. Interrupts are the danger: with S used as a data pointer, an interrupt pushes onto your data; he notes FIRQ only stacks PC and CC (src: https://nowhereman999.wordpress.com/2017/09/16/optimizing-6809-assembly-code-part-3-stack-blasting-and-self-modifying-code/). The usual practice is to blast with U as the pointer and leave S as a real stack, or mask interrupts during an S-based blast.

Vertical lines at 160 bytes per row: simple loop 17 cycles per row; ABX loop 16 (+14 setup); self-modified end-compare 14 (+44); unrolled code entered by computed jump 7 cycles per row (+43 setup), fastest from about four rows up; when height is known at assembly time, JSR straight into the unrolled block. On 128-byte-row screens, draw bottom-up with `LEAX -128,X` (5 cycles, 3 bytes) instead of `LEAX 128,X` (8 cycles, 4 bytes) because -128 fits the 8-bit offset form (src: https://nowhereman999.wordpress.com/2021/11/06/6809-assembly-thoughts-on-how-to-optimize-drawing-a-vertical-line-on-a-320x225-16-colour-coco-3-screen/).

Text: inline strings after `JSR`, the routine pulls the return address to find the text; per-character loop `LDA ,Y+ / BEQ / STA ,X+ / BRA` is 18 cycles, or 17 with a length count; `JMP ,Y` (3 cycles) rather than `TFR Y,PC` (6) (src: https://nowhereman999.wordpress.com/2021/11/03/6809-assembly-print-text-routine/). Those examples write to the text screen; on a graphics screen Joust used one compiled routine per glyph per colour (section 1.4).

Racing the beam instead of double buffering: Williams hardware gives a scan-line counter and an IRQ each quarter screen. Hewlett emulates the beam position by counting audio FIRQs: the VSYNC IRQ resets a counter, every N FIRQs (20 at 5 kHz in the article; FIRQ_Count EQU 40 at 6 kHz in Defender) the code adds 64 to a fake `VERTCT` byte and calls the game's own scan-line IRQ handler, so the game draws only where the beam is not (src: https://nowhereman999.wordpress.com/2020/11/22/williams-hardware-scanline-interrupt-and-a-new-way-to-update-sprites-on-the-coco3/ ; demo https://github.com/nowhereman999/CoCo-3-Scan-Line-Demo). Joust's changelog records tuning these counts ("40 & 40, no tearing of sprites and no sparkles").

Palette glitch: Pac-Man 1.01 moved the power-pill flashing palette change into the vertical blank IRQ to remove flicker from a "GIME chip glitch", credited to Nick Marentes (src: Pac-Man part 024 above). Sock's GIME reference documents the same effect (section 2.2).

CPU meter: write a colour to $FF9A (border) when drawing starts and 0 when it ends; the height of the coloured band shows the fraction of the frame used. His 3D point animation erases and redraws 727 pixels per frame at 27 cycles per pixel pair using `PULU` from a precomputed table (old address, new address, background value, new value), just under 60% of a 60 Hz frame (src: https://nowhereman999.wordpress.com/2021/12/18/coco-3-3d-pixel-animation-and-how-to-see-how-much-cpu-usage-is-being-used-per-frame/).

PoR relevance:
- 24x24 combat icons are 12 bytes wide at 4 bits per pixel and sit on a cell grid, so draws are always byte-aligned: no `-odd` variants, half the sprite memory. 8x8 wall tiles are 4 bytes wide, also aligned. This removes the main cost of compiled sprites in arcade ports.
- Compiled icons: at roughly 1.2 to 1.6 times the raw data size (Pac-Man figures: 77 to 106 bytes versus 65 raw), each 24x24 icon (288 bytes raw) would be about 350 to 460 bytes of code [extrapolation]. Worth it only for icons drawn every turn (current combatants), not for the whole icon set; plain unrolled copy loops from packed data are the default.
- 256-wide modes give 128-byte rows and cheap address math; 320-wide gives 160-byte rows (Y*160 needs MUL or a 200-entry row table). PoR's art is 320x200 EGA, so 320x200x16 is the natural mode; use a row address table.
- The border-colour meter is a 10-line addition to the PoR debug build and answers "is the redraw of the 3D view fast enough" immediately.
- Unrolled loops entered at a computed offset are the right tool for fixed-width text window clears and for the 3D view's tile columns.

### 1.7 Sound

Arcade samples are captured from MAME, converted with ffmpeg, stored one or more 8 KB blocks per effect, and played by the timer FIRQ. Exact command from the Defender source: `ffmpeg -i source_audio.wav -acodec pcm_u8 -f u8 -ac 1 -ar 6006 -af aresample=6006:filter_size=256:cutoff=1.0 output.raw` (src: CoCo_32.asm in https://github.com/nowhereman999/Defender_CoCo3). Defender's 21 samples at 8-bit unsigned 6 kHz total 287,432 bytes; dropping the two low bits the 6-bit DAC ignores saves a quarter (src: Defender part 1). Pac-Man packed the high six bits of four samples into three bytes, and mixed two channels by `ADDA` then `RORA` (average) before the DAC write (src: https://nowhereman999.wordpress.com/2017/03/30/zilog-z80-to-motorola-6809-transcode-part-020-sound-ideas/). Audio setup: clear the analog mux select bits in $FF01 and $FF03 (bit 3), set the 6-bit sound enable (bit 3) in $FF23, then write samples to $FF20 (same sources). Speed tricks: put the handler at the vector target itself (Simon Jonassen's tip: code at $010F for FIRQ rather than a JMP), or use a direct-page `JMP` ($0E opcode, 1-byte address) at $FEF4 (src: IRQ part 5 above).

PoR relevance: medium to low. PoR only has PC speaker and PSG effects. If the port uses DAC samples, budget the FIRQ cost and play effects only while the game waits for input. See section 3.4 for the PSG route.

### 1.8 Loaders and storage

- 2017 "CoCo 3 Loader for big programs": stage 1 is LOADMed at $2000 and patches the Disk BASIC file-close vector at $A42E so it runs when the file closes; it reads the rest of the file byte by byte through ROM routine $A176 into an 8 KB window ($FFA2 maps $4000 to $5FFF), incrementing the block number every 8 KB; stage 2 copies itself to $FD00, then unpacks a stream of records (flag, 2-byte length, 2-byte address, data; non-zero flag carries the exec address) to anywhere in $0000 to $FCFF, including over the BASIC ROM area. Build: `lwasm -9bl -p cd` for part 1, `lwasm -9r -p cd` for part 2, `cat bigloader.bin myprogram.bin > bigprogram.bin` (src: https://nowhereman999.wordpress.com/2017/02/15/coco-3-loader-for-big-programs/).
- 2021 "CoCo3 Super Loader zx0" (in the Defender and Joust sources, written in QB64, loader idea by William Astle, ZX0 by Einar Saukas, 6809 decompressor by Doug Masten): the payload is compressed per 8 KB "row", loaded into free blocks, then decompressed backwards in place, block by block, with a progress bar on screen; the final record restores the MMU map the program expects. `CLR $FF40` turns off the drive motor before the game starts (src: Defender_CoCo_3_Source/CoCo3_Super_Loader_zx0/CC3_NewLoaderCode1.asm; Joust README V1.1 note). Defender uses two disks and asks for one or two drives; Joust fits on one 156,672-byte disk image thanks to ZX0 (src: Joust release post; memory map header "One DSK image max size is 156,672 bytes").
- Saving: the games keep high scores and settings in RAM; BREAK exits to BASIC with RAM intact and `RUN"SAVE"` writes them out (src: Defender README). Simple, but it shows that writing from the game itself was avoided.
- CoCoSDC streaming library: command mode via `LDA #$43 / STA $FF40`; mount with command $E0 to $FF48 and the name "M:" plus filename through $FF4A; set the 24-bit LSN in $FF49 (high) and $FF4A/$FF4B; read command $90 streams 512-byte sectors as 16-bit words from $FF4A, polling $FF48 bit 0 (busy) and bit 1 (ready); `CLR $FF40` returns to emulation mode. Files must be padded to 512 bytes and at least 79,360 bytes or the SDC locks up (src: https://github.com/nowhereman999/CoCoSDC_StreamFile and https://nowhereman999.wordpress.com/2022/11/30/streaming-large-files-on-the-cocosdc/).

PoR relevance: high. PoR must load overlays and DAX blocks during play and write saved games, which none of these arcade ports do. The close-hook loader is fine for boot; run-time loading should call Disk BASIC's DSKCON with the ROM mapped in (DynoSprite's method, section 3.2) or a private FDC driver. ZX0 decompresses fast and is a good candidate to re-pack DAX data offline (PoR's own RLE is simpler and already decoded in C; measure both).

### 1.9 Tooling summary (Hewlett)

LWTOOLS `lwasm -9bl -p cd -oNEW.BIN file.asm > listing.txt`; MAME imgtool `imgtool create coco_jvc_rsdos Disk1.dsk`, `imgtool put coco_jvc_rsdos Disk1.dsk NEW.BIN TEST.BIN`; `mame coco3 -window -debug -flop1 Disk1.dsk`; debugger commands `bp 4000`, `wp 4000,1,w`, trace as above; lwasm `opt c`, `opt cd`, `opt ct`, `opt cc` for cycle counts in the listing (src: https://nowhereman999.wordpress.com/2017/06/19/coco-6809-assembly-on-a-modern-computer/ and https://nowhereman999.wordpress.com/2021/09/02/lwasm-tricks-and-cool-features/). lwasm local labels `!` with `BNE <` / `BNE >`; reusable `1@` labels between blank lines; no spaces inside expressions or lwasm treats the rest as a comment (same LWASM post).

Small optimisations from his series (src: https://nowhereman999.wordpress.com/2017/09/14/optimizing-6809-assembly-code-part-1-quick-and-easy-changes-to-speedup-your-code/ and https://nowhereman999.wordpress.com/2017/09/16/optimizing-6809-assembly-code-part-4-odds-and-sods-more-tricks/): prefer X/U over Y (one byte and one cycle shorter); `LEAU ,Y` (4) over `TFR Y,U` (6); tail calls (`BRA` instead of `BSR`+`RTS`, saves 9 cycles); `PULS ...,PC` instead of `PULS` + `RTS`; `LDD #` instead of `LDA #`+`LDB #`; `STA $FFxx` instead of `CLR $FFxx` on hardware registers (CLR reads then writes, which can upset registers); `PULU D` instead of `LDD ,U++`; `LEAX ,X` to test X for zero. Sock Master's rule from the comments: make rarely run code slower if it makes hot code faster.

PoR relevance: medium. These are the patterns to look for when replacing CMOC output in hot loops.

## 2. Sock Master (John Kowalski)

Site: http://www.6809.org.uk/twilight/sock/ (the old https://www.6809.org.uk/sock/ redirects there) (src: http://www.6809.org.uk/twilight/sock/). Contents: Donkey Kong and Donkey Kong Remixed, Gloom-3D, demos (Demo 1, Demo 2, Moon, Boink), CoCoTracker MOD player, HiColor viewer, 4 MHz CoCo project, GIME register reference, Twilight Terminal, Digi-512 digitiser. "Gate Crasher" is not his; it is Nick Marentes' 2000 game built on Sock's Gloom algorithm (section 3.1).

### 2.1 Donkey Kong (2007) and Donkey Kong Remixed (2015)

Mechanism: not CPU emulation. "Traditional" emulation of a 3 MHz Z80 (about 0.43 MIPS) on a 1.79 MHz 6809 (about 0.79 MIPS) is unrealistic, but it "is fast enough to run the original game logic if it was translated into native 6809 operations"; the tile graphics and sound hardware are rebuilt as "work-alike" routines; the game still "accesses" its imaginary hardware and emulation code makes "all the correct stuff happen" (src: http://www.6809.org.uk/twilight/sock/dk/index.html and http://www.6809.org.uk/twilight/sock/dkremix/index.html). He "hand translated the original Z80 code" and compressed the 240-line arcade picture to the CoCo 3's 225 lines (src: https://lcurtisboyle.com/nitros9/donkeykong.html). Arcade hardware: 96 hardware 16x16 sprites, 4 colours per tile from 64 palettes, I8035 sound CPU plus discrete circuits; CoCo: bitmapped 16 colours, software sprites, DAC only. Requires 512 KB; on a 6309 it switches to native mode for speed; Nick Marentes wrote the options and DIP-switch loader (src: dk page). The Remix gained smoother frame rate and cleaner sound, and offers an alternate composite palette (src: dkremix page).

PoR relevance: high as a design pattern. Treat PoR's EGA, keyboard, timer and PSG as "imaginary hardware" behind a small platform API, and implement work-alikes on the CoCo. The existing C port's emulated EGA (planar, latches) is exactly such a layer; the lesson is to make the work-alike cheap by changing the interface where needed (Sock "cut some corners"), not to emulate the EGA faithfully.

### 2.2 GIME register reference (Sock's notes, with quirks)

Reproduced on CoCo Community (src: https://www.cococommunity.net/socks-gime-register-reference/; original https://www.6809.org.uk/sock/gime.html did not render fully for me). Key facts for the port:

| Register | Bits | Notes |
|---|---|---|
| $FF90 INIT0 | 7 COCO (0 for CoCo 3 modes), 6 MMUEN, 5 IEN, 4 FEN, 3 MC3 ($FExx constant RAM), 2 MC2, 1-0 ROM map | RSDOS writes 68 ($44) for CoCo 3 graphics |
| $FF91 INIT1 | 6 memory type, 5 TINS (1 = 279.365 ns timer clock, 0 = 63.695 microseconds), 0 TR (MMU task) | |
| $FF92 IRQENR / $FF93 FIRQENR | 5 TMR, 4 HBORD, 3 VBORD, 2 serial, 1 keyboard, 0 cartridge | reading reports and clears the sources |
| $FF94/$FF95 timer | 12 bits, 0 to 4095 | writing $FF94 restarts the count; a 16-bit STD writes the MSB first and so restarts with a partial value: write LSB then MSB. Value 0 stops counting but keeps interrupting. 1986 GIME behaves as value plus 2, 1987 as value plus 1 (marked "under investigation") |
| $FF98 VMODE | 7 BP (graphics), 5 BPI, 4 MOCH, 3 H50, 2-0 LPR (lines per row; 111 = infinite) | |
| $FF99 VRES | 6-5 LPF (00 = 192, 01 = 200, 11 = 225), 4-2 HRES (bytes per row 16, 20, 32, 40, 64, 80, 128, 160), 1-0 CRES (2, 4, 16 colours) | 320x16 = HRES 111 CRES 10; 256x16 = HRES 110 CRES 10 |
| $FF9A | border colour | CoCo 3 modes only |
| $FF9C | vertical fine scroll (scan lines) | for text and multi-line modes |
| $FF9D/$FF9E | screen start = physical address / 8 | some GIMEs crash on odd values in $FF9E in some modes; step in 16-byte units |
| $FF9F | 7 HVEN (256-byte virtual rows), 6-0 horizontal offset in 2-byte steps | |
| $FFA0 to $FFA7 / $FFA8 to $FFAF | MMU tasks 0 and 1, one 8 KB block each | read back needs masking of the top 2 bits |
| $FFB0 to $FFBF | palette, 6 bits RGB: bit5 R1, 4 G1, 3 B1, 2 R0, 1 G0, 0 B0 | read or write causes a brief screen glitch: change during horizontal or vertical border |
| $FFD8 / $FFD9 | 0.89 / 1.79 MHz | |
| $FFDE / $FFDF | ROM mode / all-RAM mode | |

Vectors: the CPU's $FFF6 (FIRQ) and $FFF8 (IRQ) point to $FEF4 and $FEF7 in constant RAM, which jump through $010F and $010C (same source).

Derived values for PoR (from the table above, my arithmetic): $FF98 = $80; $FF99 = $3E for 320x200x16, $7E for 320x225x16, $3A for 256x200x16, $1E for 320x192x16. A screen at physical $60000 needs $FF9D/$FF9E = $C000; Hewlett's default-map screen at $70000 needs $E000. Also: PoR's 236.7 Hz timer becomes the slow GIME clock (63.695 microseconds) with a count of about 66 (4,225 microseconds / 63.695 = 66.3; load 65 or 64 to allow for the +1 or +2 quirk) [derived; verify on both GIME revisions]. The fast clock cannot reach 236 Hz because 4,225 microseconds needs 15,123 counts, more than 4095.

Palette mapping tip [derived from general EGA knowledge, unverified here]: the EGA 6-bit palette value is laid out rgbRGB with the low-intensity bits on top (bit 5 r, 4 g, 3 b, 2 R, 1 G, 0 B), while the GIME RGB value is RGBrgb with the high bits on top; the conversion is `gime = ((ega & 7) << 3) | (ega >> 3)`. PoR's per-picture EGA palettes therefore map 1:1 to GIME RGB palettes; only composite monitors need a separate lookup table (every modern port ships both, see Defender's CONFIG "Monitor type" and DynoSprite's dual palettes).

### 2.3 Demos and what they demonstrate

From http://www.6809.org.uk/twilight/sock/cocofile/demo.html:
- Demo 1: more than 16 colours on screen, graphics in the border area, warping title, rainbow colour cycling and a scroller, all updated 60 times a second; fixed later for 6309 and 2 MB machines.
- Boink: static 16-colour background, 12-colour ball, 9-colour shadow, 20-colour text area, and "not a single thing is being redrawn while the demo is running". Sock's GIME notes say the LPR "infinite" setting was used for "a bouncing ball demo that controlled vertical position" (src: GIME reference above). The mechanism is palette and video-register changes timed to the beam, not drawing [the exact Boink register sequence is unverified].
- Moon demo: hardware scrolling of four screen areas at once plus sprites; hard because "every line of the screen could potentially be located in different areas in memory" (each area has its own $FF9D/$FF9E/$FF9F set mid-frame).
- HiColor viewer: palette rewritten every scan line (16 colours per line from 64), and two pages alternated with the dither shifted between them, giving about 1,000 apparent colours; a 4-page mode reaches 6,859 (src: http://www.6809.org.uk/twilight/sock/hicolor/hicolor.html).
- CoCoTracker: 4-channel digitised MOD playback, requires a 6309 at 2 MHz, optional stereo via Orchestra-90 (src: http://www.6809.org.uk/twilight/sock/mod/index.html).
- Gloom-3D: first-person flat-shaded maze in 256x192x16, Gloom 2 "about 20 frames per second full screen", three times faster than Gloom 1, runs on 128 KB, fish-eye partly corrected (src: http://www.6809.org.uk/twilight/sock/gloom/gloom.html; source GLOOM.ASM linked there, not read for this report).

PoR relevance: medium. Split-screen register changes (Moon demo) mean the 3D view, the text window and the party list could be separate memory areas shown on one screen, each scrolled or flipped independently; for example the message window could scroll by changing its start address instead of copying text. Per-line palette changes are not needed (PoR has 16 colours per picture). Mid-frame register changes need a timed interrupt (HBORD or the timer) and cost CPU every frame, so use them only if the screen layout needs it.

## 3. Other high-signal developers

### 3.1 Nick Marentes

Project archive: https://nickmarentes.com/ProjectArchive/index.html (src). Relevant points:
- Pac-Man Tribute (1997): an original re-creation, not a code port. 320x225, 30 fps target, sounds sampled from a real machine on tape, two-channel sample routines from Cosmic Ambush with minimal CPU use, ghost AI invented because the original was unknown (src: https://nickmarentes.com/ProjectArchive/pacman.html).
- Gate Crasher (2000): solid 3D free-movement game "based on John Kowalski's Gloom algorithm", an unofficial 128x96x16 mode, double buffered with each screen about 6 KB, heavy self-modifying code, dual-channel interrupt sound (src: https://nickmarentes.com/ProjectArchive/crasher.html). The 6 KB figure fits 128x96 at 4 bits per pixel (64 bytes x 96 rows = 6,144); how the mode is set (probably 128-pixel HRES with doubled lines) is [unverified].
- Pop*Star Pilot (2016): 320x225x16, "split screen smooth 1 byte hardware scrolling", double buffered, 2-channel interrupt sample effects, raster background effects; assembled on a real CoCo 3 with EDTASM6309, art on an Amiga, level editor in BASIC (src: https://nickmarentes.com/ProjectArchive/popstar.html).
- GunStar (2020): 128x112x16, "3-plane graphics engine", double buffered, 2-channel samples, designed for the 6309 (10% to 30% faster), 512 KB (src: https://nickmarentes.com/ProjectArchive/gunstar.html).
- "In Search of 256" research: a rumoured 256-colour mode is unconfirmed; designer John Prickett remembers 64 colours only; the '87 GIME changed horizontal scrolling and video timing; FF99 CRES=11 is undefined (src: https://nickmarentes.com/ProjectArchive/256mode.html). Do not plan around 256 colours.
- He identified the palette-change glitch fix used in Hewlett's Pac-Man 1.01 (section 1.6).

PoR relevance: Gate Crasher's choice is instructive: halving resolution in both axes cut the 3D view's fill cost by four. PoR's 3D view is built from 8x8 tiles at full resolution, so no such trade is needed, but the double-buffered-small-viewport idea is (compose the viewport off screen, then copy or flip).

### 3.2 Richard Goedeken: DynoSprite engine

DynoSprite is "a sophisticated, object oriented game engine for the TRS-80 Color Computer 3, written in 6809 assembly", needing 512 KB and a disk system; build on a PC with make, Python, lwasm, ffmpeg (src: https://github.com/richard42/dynosprite README). Features: 320x200x16, tile-mapped background of 16x16 tiles scrolling in 2-pixel horizontal and 1-pixel vertical steps, sprites compiled to 6809 or 6309 code by a Python sprite compiler (`sprite2asm.py`), 2-voice DAC or Orchestra-90 audio, variable frame rate, DEFLATE-compressed data, composite and RGB palettes (src: doc/DynoSpriteUsage.txt in the repository).

Memory discipline (src: doc/AddressMap.txt): the engine fixes $2000 to $3FFF (global code, data, stack) and $E000 to $FDFF (secondary code, "only swapped out when calling DSKCON"); every other 8 KB slot is remapped per operation. For disk I/O, BASIC RAM page 0, Color BASIC ROM and Disk BASIC ROM images are mapped at $0000, $A000 and $C000 and the upper ROM at $E000 only while DSKCON runs. For drawing: tilemap at $0000, texture window $4000, screen even buffer $6000 to $9FFF, odd buffer $A000 to $DFFF. For decompression: input page $4000, history page $6000, output page $8000. Level and object code is loaded into a code window at $6000 to $7FFF and must be position-independent (except two level entry points); a script (`symbol-extract.py`) turns the engine's lwasm listing into EQUs so separately assembled game code can call the engine (src: DynoSpriteUsage.txt).

Benchmarks (src: doc/Benchmarks.txt): "field duration is 16.683333 milliseconds = 29,860 cycles"; empty main loop 145 cycles; base overhead with no objects 1,315 (6809) and 1,020 (6309); scrolling with objects 10,840 to 17,605 cycles per field; 6309 21% to 51% faster. DEFLATE: 21,037 bytes of object data compressed to 6,914; loading a level took 14.3 s from floppy with DECB, 5.8 s with HDB-DOS.

PoR relevance: very high. This is the nearest existing design to what PoR needs: a fixed core, game code in position-independent blocks loaded on demand into a fixed window (PoR's overlays), DSKCON called with the ROM mapped in and only the secondary code page sacrificed, and a heap in a separate page. Also a model for the build: data converted and packed by host scripts, symbol export from the core's listing into overlay builds.

### 3.3 Jamie Cho: Space Bandits (CMOC C on DynoSprite)

Space Bandits is "a CoCo 3 and macOS video game based on the Dynosprite engine" with a 3-voice wavetable music engine; game objects are written mostly in C (`game/objects/03-badguy.c` and others) and built inside the coco-dev Docker image (src: https://github.com/jamieleecho/space-bandits README and tree). Its `scripts/cmoc-wrapper.py` runs `cmoc -S --intermediate --raw -O<n>`, appends an entry-point section, runs cpp, assembles with lwasm `-fobj --pragma=forwardrefmax`, and links with `cmoc --org=0x6000` for level code or `--org=0x0` for object code (src: scripts/cmoc-wrapper.py). Build options include `OBJPAGES=N` (8 KB pages for levels and objects, default 2), `OBJPAGEGUARD=N` (bytes reserved at the top of each object code page, default 256), `SPEEDTEST=1` (count idle loop iterations, 15 cycles each on 6809, before the vsync IRQ) and `VISUALTIME=1` (switch to 256x200 and colour the border blue while working, green if a frame overran one field, red if it overran two) (src: README). It keeps a macOS build of the same game with 49 unit tests as a development aid (src: CLAUDE.md in the repository).

PoR relevance: very high. It proves the default PoR toolchain (CMOC plus lwasm in jamieleecho/coco-dev) can produce C code that is loaded per level into fixed 8 KB pages, and it shows the dual host and CoCo build that PoR already has (the portable C) used as a test oracle. The VISUALTIME colour scheme is a ready-made performance indicator.

### 3.4 John Linville: Game Master Cartridge (GMC)

The GMC is a flash ROM cartridge with a Texas Instruments SN76489AN sound generator for CoCo 1, 2 and 3, created by John W. Linville (2018) (src: https://www.cocopedia.com/wiki/Game_Master_Cart). Programming facts from a test program: the PSG is written at $FF41; select MPI slot with $FF7F; enable cartridge sound through the analog mux (`LDA #$34 / STA $FF01`, `LDA #$3F / STA $FF03`, `LDA #$38 / STA $FF23`); writes use the normal SN76489 latch/data byte format (`%1cc0dddd` latch with low 4 bits of tone, then 6 high bits; `%1cc1vvvv` attenuation); comment: "At 4MHz, the DCSG needs 32 clocks between register writes", so about 15 CPU cycles between writes at 1.79 MHz (src: https://exileinparadise.com/tandy_color_computer:testgmc.asm). His "Programming the Game Master Cartridge" guide is a Google Doc listed in awesome-coco (could not fetch; robots disallowed).

PoR relevance: high for sound. PoR's Tandy path already drives an SN76489-family chip from a 236.7 Hz tick; on a GMC the same byte stream can be written to $FF41 with a short delay between writes. Tone dividers must be rescaled if the GMC's PSG clock differs from the Tandy 1000's 3.579545 MHz [GMC clock unverified; the comment suggests about 4 MHz]. Fallback without a GMC: PC speaker style square waves on the 1-bit sound output or the DAC.

### 3.5 Ciaran Anscomb: XRoar, Dunjunz, tools

XRoar emulates Dragon 32/64, CoCo 1, 2, 3 and MC-10 (src: https://www.6809.org.uk/xroar/). Developer options from the manual: `-machine coco3` (or `coco3p`), `-machine-cpu 6309`, `-ram 512`, `-ram-init random` (finds uninitialised-memory bugs), `-vdg-type gime1986` or `gime1987` (test both GIME revisions), `-tv-input rgb`, `-load` and `-run`, `-load-fd0`; debugging `-gdb` (GDB remote target on 127.0.0.1:65520), `-gdb-pseudo-regs` (GIME state as registers), `-trace`, `-trap condition` with `-trap-snap`, `-trap-trace`, `-trap-timeout`, and `-timeout n` to quit after n seconds (src: https://www.6809.org.uk/xroar/doc/xroar.shtml). Dunjunz (2018) is his conversion of a BBC Micro game to Dragon and CoCo, with a Games Master Cartridge ROM build that has CoCo 3 enhancements (src: https://www.6809.org.uk/dunjunz/). He also publishes `dzip`, a simple compressor, and 6809 routines such as CRC-16 (src: https://github.com/dougmasten/awesome-coco).

PoR relevance: medium to high for testing: `-ram-init random`, both GIME types, and `-timeout` plus traps give scripted regression runs; MAME is what Hewlett used, XRoar's GDB stub is the alternative for source-level debugging.

### 3.6 Others

- Steve Bjork: "6809 Assembly with Steve Bjork" video playlist (src: https://github.com/dougmasten/awesome-coco). Not reviewed in detail.
- Tim Lindner (MAME CoCo maintainer) tested the GIME timer on an '86 GIME: writing 0 to the timer does not stop interrupts on real hardware (it re-asserts immediately), and turning the interrupt source off works regardless of flags; MAME was fixed after Arkanoid's sound broke (src: https://tlindner.macmess.org/?p=762). He also fixed MAME's BREAK-to-BASIC interrupt initialisation for Defender (src: Defender README).
- L. Curtis Boyle and Doug Masten appear throughout as reviewers (cycle tricks, the ZX0 6809 decompressor, the drive motor fix).
- Jason Pittman and Ed Snider: nothing technical found for this topic.

## Implications and recommendations for the port

1. Treat the DOS platform layer as Sock's "imaginary hardware": keep PoR's game logic C intact and write cheap work-alikes for video, input, timer and sound with an interface designed for the CoCo (byte-aligned 4-bit-per-pixel blits of tiles, icons and glyphs, not EGA planes and latches).
2. Write the 512 KB block map first, as a single header shared by C and assembly, in the style of Hewlett's map: fixed core (RTL, overlay stub, interrupt handlers, stack) in slots that are never remapped (DynoSprite keeps $2000 to $3FFF and $E000 to $FDFF), one or two 8 KB windows for overlay code (DynoSprite's $6000 window; Space Bandits' OBJPAGES), one window for data blocks, two screen buffers, a background copy for the combat map, DAX caches.
3. Use the DynoSprite and Space Bandits path for overlays: compile each PoR overlay unit with CMOC as position-independent or window-fixed code, link it at the window address, export core symbols from the core's listing, and load it into free blocks at run time (or from a preloaded cache in RAM; with 512 KB most of GAME.OVR's 197 KB of x86, likely larger in 6809 code, may fit compressed).
4. Disk at run time: call DSKCON with the BASIC ROM images mapped as DynoSprite does, or write a private driver. Support CoCoSDC streaming as an option (512-byte sectors through $FF4A, files padded).
5. Graphics: 320x200x16 ($FF98 = $80, $FF99 = $3E) with a row address table; screen start through $FF9D/$FF9E in 16-byte units; page flip between two 32,000-byte screens for full redraws (picture changes, 3D view rebuild) and draw directly for small changes. Never touch $FFB0 to $FFBF outside the vertical border.
6. Drawing primitives in hand-written assembly: unrolled byte-aligned copies for 8x8 tiles and 24x24 icons (no odd variants needed), PSHU fills for window clears (about 2.2 cycles per byte), a 1-bit-to-4-bit glyph expander using a lookup table (or per-colour compiled glyphs if memory allows, as Joust did), restore-from-backup for combat icons.
7. Measure from day one: border-colour CPU meter (Hewlett, Space Bandits VISUALTIME), lwasm `opt c` cycle listings, idle loop counting against 29,860 cycles per field.
8. Testing: build a trace or screenshot comparison between the host C build and the CoCo build at deterministic points (menu entry, each combat round), run headless under MAME or XRoar with `-timeout`, test both GIME revisions and random RAM init. Keep feature flags that swap each CoCo work-alike back to a slow reference path.
9. Timer: drive PoR's 236.7 Hz tick from the GIME timer on the slow clock (count about 64 to 66); write $FF95 then $FF94; acknowledge by reading $FF92/$FF93.
10. Sound: support GMC ($FF41) as the "Tandy PSG" target; fall back to simple DAC or 1-bit tones. Avoid a permanent 6 kHz FIRQ unless sampled effects are wanted.

## Open questions

1. The exact mechanism of Gate Crasher's "unofficial 128x96" mode and of the Boink demo (which register sequence, which interrupt) [unverified]; GLOOM.ASM on Sock's site was not read.
2. The GMC's SN76489 clock frequency, needed to rescale PoR's Tandy tone dividers.
3. Whether CMOC's output is fully position-independent for statics and string literals, or whether Space Bandits relies on the fixed org per window (the wrapper links objects at org 0 and levels at $6000; how the engine relocates object code was not traced).
4. Whether the timer's +1/+2 offset (1986 vs 1987 GIME) matters at PoR's 236.7 Hz (about 1.5% to 3% speed difference at a count of 66).
5. Pac-Man transcode parts 003 to 019 (tile-to-bitmap conversion and vertical scrolling of the 288-row maze) were not read in detail; the Pac-Man source zip is on colorcomputerarchive.com.
6. Robotron's slowdown was never diagnosed; his blitter simulation for Joust was slower than compiled sprites and lacked transparency; details are only in the ROBOTRON_CoCo3 and Joust sources.
7. John Linville's GMC programming guide (Google Doc) could not be fetched.

## Lessons for porting a large existing game

1. Port the game's own logic, not its hardware: translate to native code and replace the hardware with work-alike routines (Sock's Donkey Kong, every Hewlett port). Never emulate the original CPU or video chip at full fidelity.
2. Before changing anything, prove the reference: Hewlett made each source reassemble byte-identical to the original ROMs before "CoCoizing". PoR's matching C is this reference; keep it buildable and runnable on the host forever.
3. Keep the original's identity visible in the port: original addresses or routine names beside converted code, original data at original layout where possible, so the original can be stepped side by side in a debugger.
4. Bring the game up in the original's boot order: reset, init, main loop or IRQ, text output, input, then graphics detail, then sound last. Fake self-tests and anything that will fail because code moved.
5. Expect integrity checks and protection in old code; "random" crashes after moving code are a classic symptom (Joust).
6. Write the memory map down first and give every 8 KB block a name and an owner. Duplicate small shared routines into each bank rather than calling across banks.
7. Give each replacement a feature flag and keep the reference path, so bugs can be bisected (Defender's flags, including one that turns off self-modifying code to test for self-overwrites).
8. Keep a versioned changelog of every root cause found; the same classes recur (pointer off the end of the screen into code, bank not mapped, wrong bounds).
9. Get a correct but slow build running first, then measure (MAME breakpoints, border colour, idle counters) and optimise only the hot routines by hand (Pac-Man went from about 1/4 speed to full speed this way).
10. Make testing deterministic and automatic: MAME trace logs with a fixed register format, input record and playback, headless runs with timeouts. Unreliable playback (Hewlett's 50%) came from vsync dependence, which PoR does not have, so PoR can do better.
11. Spend the 512 KB on speed where it pays: compiled routines for the few hot graphics, pre-expanded fonts, background copies, decompressed caches. Spend cycles in rare code to save them in hot code (Sock's rule).
12. Use proven community tools rather than inventing: lwasm with cycle listings, ZX0 with Doug Masten's decompressor, DynoSprite's memory and loading patterns, CMOC as in Space Bandits, GMC for PSG sound, CoCoSDC streaming.
13. Test on real hardware and both GIME revisions early; emulators had real bugs (MAME timer zero, BREAK green screen) that only showed because ports exercised them.
14. Release in stages and accept help: Hewlett's testers (Ron Klein) found the crash that his own runs did not; publishing source let others contribute fixes (Doug Masten's motor fix, Tim Lindner's MAME fix).

## Sources

- https://nowhereman999.wordpress.com/ : Glen Hewlett's blog index and archive; entry point for all his posts.
- https://nowhereman999.wordpress.com/2018/01/20/arcade-machine-conversion-to-the-coco-overview/ : his ten-step arcade conversion workflow.
- https://nowhereman999.wordpress.com/2017/12/31/defender-conversion-for-the-coco-3-part-1/ : Defender memory, bank swap, video size, compiled sprite timings, sample sizes.
- https://nowhereman999.wordpress.com/2021/09/25/defender-for-the-tandy-coco-3/ : MAME record/playback and trace crash hunting.
- https://nowhereman999.wordpress.com/2021/08/17/joust-is-now-available-for-the-coco-3/ : Joust release, ZX0 compression, save via BASIC.
- https://nowhereman999.wordpress.com/2021/07/18/joust-on-the-coco-3-update-now-plays-demo-screen/ : blitter simulation slower than compiled sprites; QB64 loader.
- https://nowhereman999.wordpress.com/2021/06/23/found-some-copy-protection-code-in-joust/ : hidden checksums causing crashes.
- https://nowhereman999.wordpress.com/2021/10/09/robotron-progress/ and https://nowhereman999.wordpress.com/2022/05/04/robotron-last-update/ : byte-identical reassembly, unfinished port lessons.
- https://nowhereman999.wordpress.com/2016/12/29/zilog-z80-to-motorola-6809-transcode-part-001/ and https://nowhereman999.wordpress.com/2016/12/30/zilog-z80-to-motorola-6809-transcode-part-002/ : translator approach, data and jump tables.
- https://nowhereman999.wordpress.com/2017/07/02/zilog-z80-to-motorola-6809-transcode-part-025-my-z80-to-6809-program/ and https://github.com/nowhereman999/z80to6809 : translator source and register mapping.
- https://nowhereman999.wordpress.com/2017/07/01/zilog-z80-to-motorola-6809-transcode-part-024-pac-man-is-finally-complete-if-you-have-a-coco-3-with-512k-give-it-a-try/ : Pac-Man release, palette glitch fix.
- https://nowhereman999.wordpress.com/2017/02/03/zilog-z80-to-motorola-6809-transcode-part-014-mame-debug-and-how-fast-the-code-is/ : measuring speed in MAME.
- https://nowhereman999.wordpress.com/2017/01/31/zilog-z80-to-motorola-6809-transcode-part-013-sprites-and-more-ram/ : video RAM in MMU blocks with backup copy.
- https://nowhereman999.wordpress.com/2017/03/30/zilog-z80-to-motorola-6809-transcode-part-020-sound-ideas/ : DAC setup, 6-bit packing, two-channel mixing, task-1 sample mapping.
- https://nowhereman999.wordpress.com/2017/04/12/zilog-z80-to-motorola-6809-transcode-part-021-compiled-sprites-are-faster-then-stack-blasting/ : compiled vs stack blasted sprite cycle counts.
- https://nowhereman999.wordpress.com/2017/05/24/zilog-z80-to-motorola-6809-transcode-part-023-optimized-sprite-rendering-combining-compiled-sprites-with-stack-blasting/ : PSHU compiled sprites, 193 cycles and 77 bytes.
- https://nowhereman999.wordpress.com/2017/05/18/zilog-z80-to-motorola-6809-transcode-part-022-quick-and-dirty-speed-test-five-sprites-and-2-audio-samples-at-the-same-time/ : five sprites plus two samples test.
- https://nowhereman999.wordpress.com/2017/08/26/sprite-compiler-for-the-trs-80-color-computer-3/ : sprite compiler options (transparency, odd, restore).
- https://nowhereman999.wordpress.com/2017/09/14/optimizing-6809-assembly-code-part-1-quick-and-easy-changes-to-speedup-your-code/ : basic 6809 optimisations with cycle counts.
- https://nowhereman999.wordpress.com/2017/09/16/optimizing-6809-assembly-code-part-3-stack-blasting-and-self-modifying-code/ : stack blasting 2.2 cycles per byte, self-modifying code.
- https://nowhereman999.wordpress.com/2017/09/16/optimizing-6809-assembly-code-part-4-odds-and-sods-more-tricks/ : more tricks (PULU, STA vs CLR on hardware).
- https://nowhereman999.wordpress.com/2017/11/17/how-to-setup-and-use-irqs-on-the-trs-80-color-computer-part-5-advanced-interrupt-settings-and-using-coco-3-specific-interrupts/ : GIME IRQ/FIRQ setup sequence and vectors.
- https://nowhereman999.wordpress.com/2017/02/15/coco-3-loader-for-big-programs/ : close-hook loader at $A42E into MMU blocks.
- https://nowhereman999.wordpress.com/2017/06/19/coco-6809-assembly-on-a-modern-computer/ : lwasm, imgtool and MAME debugger commands.
- https://nowhereman999.wordpress.com/2021/09/02/lwasm-tricks-and-cool-features/ : lwasm local labels and cycle options.
- https://nowhereman999.wordpress.com/2020/11/22/williams-hardware-scanline-interrupt-and-a-new-way-to-update-sprites-on-the-coco3/ and https://nowhereman999.wordpress.com/2021/06/08/4728/ : beam racing via FIRQ counting.
- https://nowhereman999.wordpress.com/2021/12/18/coco-3-3d-pixel-animation-and-how-to-see-how-much-cpu-usage-is-being-used-per-frame/ : border-colour CPU meter, PULU-driven point redraw.
- https://nowhereman999.wordpress.com/2021/11/06/6809-assembly-thoughts-on-how-to-optimize-drawing-a-vertical-line-on-a-320x225-16-colour-coco-3-screen/ : unrolled computed-entry loops.
- https://nowhereman999.wordpress.com/2021/11/03/6809-assembly-print-text-routine/ : inline text print routines.
- https://nowhereman999.wordpress.com/2023/05/25/coco-3-256-x-200-x-16-colours-is-a-great-resolution/ : 256-wide mode address math.
- https://nowhereman999.wordpress.com/2022/11/30/streaming-large-files-on-the-cocosdc/ and https://github.com/nowhereman999/CoCoSDC_StreamFile : CoCoSDC streaming registers and API.
- https://nowhereman999.wordpress.com/2023/02/15/mos-6502-to-motorola-6809-assembly-language-transcoding/ : 6502 to 6809 flag differences.
- https://github.com/nowhereman999/Defender_CoCo3 : Defender source (memory map, FIRQ, makefile with MAME trace, ZX0 loader).
- https://github.com/nowhereman999/Joust_CoCo3 : Joust source (memory map with per-colour font blocks, changelog).
- https://www.vintageisthenewold.com/space-invaders-trs-80-coco-3-port-directly-from-intel-8080-arcade-sources/ : Space Invaders 8080 port summary.
- https://github.com/dougmasten/awesome-coco : curated index of CoCo resources used to locate repositories and articles.
- http://www.6809.org.uk/twilight/sock/ : Sock Master's site index.
- https://www.cococommunity.net/socks-gime-register-reference/ : Sock's GIME register reference with quirks (full text).
- https://www.6809.org.uk/sock/gime.html : original location of the GIME reference (rendered only partially).
- http://www.6809.org.uk/twilight/sock/dk/index.html and http://www.6809.org.uk/twilight/sock/dkremix/index.html : Donkey Kong porting approach.
- https://lcurtisboyle.com/nitros9/donkeykong.html : Donkey Kong hand translation and 240 to 225 line compression.
- http://www.6809.org.uk/twilight/sock/gloom/gloom.html : Gloom-3D mode and frame rate.
- http://www.6809.org.uk/twilight/sock/cocofile/demo.html : Boink, Moon and other demos.
- http://www.6809.org.uk/twilight/sock/hicolor/hicolor.html : per-scanline palette and page alternation.
- http://www.6809.org.uk/twilight/sock/mod/index.html : CoCoTracker 4-channel player.
- https://nickmarentes.com/ProjectArchive/index.html : Nick Marentes' projects.
- https://nickmarentes.com/ProjectArchive/pacman.html , https://nickmarentes.com/ProjectArchive/crasher.html , https://nickmarentes.com/ProjectArchive/popstar.html , https://nickmarentes.com/ProjectArchive/gunstar.html : game technical summaries.
- https://nickmarentes.com/ProjectArchive/256mode.html : 256-colour mode research (unconfirmed mode, GIME revision notes).
- https://github.com/richard42/dynosprite : DynoSprite engine, address map, benchmarks, usage guide.
- https://github.com/jamieleecho/space-bandits : CMOC C on DynoSprite, build options, timing aids.
- https://www.cocopedia.com/wiki/Game_Master_Cart : GMC description.
- https://exileinparadise.com/tandy_color_computer:testgmc.asm : GMC SN76489 port and write sequence.
- https://www.6809.org.uk/xroar/ and https://www.6809.org.uk/xroar/doc/xroar.shtml : XRoar features and debugging options.
- https://www.6809.org.uk/dunjunz/ : Dunjunz overview.
- https://tlindner.macmess.org/?p=762 : GIME timer behaviour on real hardware vs MAME.
- https://fahrfall.blogspot.com/ : John Linville's Fahrfall blog (little technical content for this topic).

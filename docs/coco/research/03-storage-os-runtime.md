# 03: Storage, operating environment and loading large programs on the CoCo 3

Scope: how the Pool of Radiance (PoR) port gets its roughly 197 KB of code and 1,284,555 bytes of DAX data off mass storage on a 512 KB CoCo 3, how it reads blocks by id at run time, how it writes saved games, and which operating environment (bare metal over Disk BASIC, own format, OS-9/NitrOS-9, or a hybrid) it should use.

## Key takeaways for the Pool of Radiance port

1. One RS-DOS disk holds 68 granules of 2,304 bytes = 156,672 bytes of file data. The DAX data alone is 8.2 disks' worth; with 6809 code the game is about 10 to 11 standard 35-track images. A plain floppy release means disk swapping, exactly like the PC original (8 "game disks" plus STARTUP and OVERLAY).
2. The single portable I/O primitive is DSKCON, called with `JSR [$C004]` and a 7-byte parameter block whose address is at `$C006` (op, drive, track, sector, buffer pointer, status). It works on real floppies, on CoCo SDC (which emulates the FDC in hardware), on DriveWire through HDB-DOS, and in every emulator. Use it as the baseline backend.
3. A bare-metal game can keep DSKCON callable after taking over the machine by remapping MMU slot 0 (BASIC low RAM, direct page variables `$EA` to `$F0`, disk RAM from `$600`), slot 5 (Color BASIC image at `$A000`) and slot 6 (Disk BASIC image at `$C000`) back in for the duration of each call. DynoSprite (a 512 KB CoCo 3 game engine) does exactly this and is the best working reference.
4. Recommended: bare metal + a thin RS-DOS reader (directory and FAT read once, then pure DSKCON sector reads) + DAX data repacked into a few large container files with an id index and 256-byte aligned blocks + fixed-size pre-allocated save-game files rewritten in place (no FAT updates at run time). Add optional fast backends later (CoCo SDC logical sector mode, DriveWire) behind the same "read N sectors" interface.
5. OS-9/NitrOS-9 Level 2 gives real file I/O and memory management, but each process is still a 64 KB map built from 8 KB blocks, CMOC's OS-9 library support is partial, and few users boot NitrOS-9 to play games. It scores below bare metal for this port.
6. Estimated load time for a typical 10 KB block: floppy through DSKCON about 1.5 to 3 s with the motor running (up to about 4 s with spin-up and a long seek); CoCo SDC about 0.1 to 0.3 s; DriveWire at 115,200 bps about 1 to 1.5 s; Becker port in an emulator effectively instant. Design the game loop so that loads happen only at location changes, combat start and picture display, as on the PC.
7. Emulator testing: XRoar takes four floppy images at once (`-load-fd 0..3`) and a Becker DriveWire port; VCC now includes an "SDC Simulator"; MAME has headless CoCo 3 with the FDC. All three can run the DSKCON backend unchanged.

## 1. Disk hardware

### 1.1 Controller chips and the FD-502

The CoCo floppy cartridges use a Western Digital WD1793 (older controllers) or WD1773 (later controllers, including the FD-502 era cartridge, Cat. 26-3133). MAME's driver header says: "The CoCo uses either the WD1793 or the WD1773" (src: https://git.redump.net/mame/plain/src/devices/bus/coco/coco_fdc.cpp). The archive has the Tandy schematics for both the "Old FDC" and "New FDC" and the "Color Computer Disk Cart FD502 26-3133 Schematic" (src: https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/). The exact chip per board revision was not confirmed from the schematics in this pass [unverified]; the programming model is the same for software that goes through DSKCON.

Register map (src: Disk BASIC Unravelled, https://bitchin100.com/files/coco/disk-basic-unravelled.pdf, and MAME coco_fdc.cpp):

| Address | Read | Write |
|---|---|---|
| `$FF40` | (none) | DSKREG control latch, write-only, shadowed by Disk BASIC in RAM (DRGRAM, `$986`) |
| `$FF48` | Status | Command |
| `$FF49` | Track | Track |
| `$FF4A` | Sector | Sector |
| `$FF4B` | Data | Data |

DSKREG (`$FF40`) bits: 0, 1, 2 = drive select 0 to 2; 3 = motor on; 4 = write precompensation (Disk BASIC enables it above track 22); 5 = density (1 = double) and NMI enable; 6 = drive select 3 (also used as side select on double-sided setups, see VCC's comment "Bit 6 drive select 3 or side select", src: https://github.com/VCCE/VCC sdc/sdc.cpp); 7 = HALT enable (FDC DRQ halts the 6809 between bytes). MAME notes that reading `$FF48` to `$FF4F` clears bit 7 of DSKREG (src: coco_fdc.cpp).

Transfer mechanism: Disk BASIC enables HALT so the FDC's DRQ stalls the CPU between bytes, and runs a tight byte loop; the FDC's INTRQ is wired to NMI, and the NMI handler (`NMIVEC` at `$0109`, Disk BASIC value `$D7AE`) jumps through `DNMIVC` to leave the loop when the command completes (src: Disk BASIC Unravelled). Consequence for the port: during a sector transfer the CPU is either halted or in the loop; interrupts (the game's sound timer) do not get serviced normally, and NMI must reach Disk BASIC's handler. Any bare-metal vector setup must leave the NMI path (CPU vector to the `$FEFD` jump to `$0109`) intact.

Commands Disk BASIC issues (src: Unravelled): RESTORE `$03`, SEEK `$17`, STEP `$23`, STEP IN `$43`, STEP OUT `$53`, READ SECTOR `$80`, WRITE SECTOR `$A0`, READ ADDRESS `$C0`, READ TRACK `$E4`, WRITE TRACK `$F4`, FORCE INTERRUPT `$D0`. The low two bits of a type I command are the step rate; `$17` and `$03` use r1r0 = 11, which on the WD179x/177x at its 5.25-inch clock is the slowest rate, 30 ms per step (inference from the WD datasheet rate table; not stated in Unravelled) [unverified].

### 1.2 RS-DOS (Disk Extended Color BASIC) disk format

All numbers from Disk BASIC Unravelled unless noted (src: https://bitchin100.com/files/coco/disk-basic-unravelled.pdf):

- 35 tracks (0 to 34, `TRKMAX EQU 35`), 18 sectors per track numbered 1 to 18 (`SECMAX EQU 18`), 256 bytes per sector (`SECLEN EQU 256`), single sided, double density MFM. Raw capacity 35 x 18 x 256 = 161,280 bytes (FujiNet's guide gives the same 161,280-byte .DSK size, src: https://fujinet.online/wp-content/uploads/2026/06/fujinet-getting-started-coco.pdf).
- Granule = 9 sectors = 2,304 bytes; 2 granules per track; 68 granules on the 34 data tracks. `FREE(n)` reports granules of 2,304 bytes (src: https://colorcomputerarchive.com/repo/Documents/BASIC%20Commands/diskbasic.txt). Usable file space = 68 x 2,304 = 156,672 bytes.
- Track 17 holds the FAT (sector 2) and directory (sectors 3 to 11). 9 sectors x 8 entries = 72 slots, but at most 68 files can exist because each needs a granule.
- Directory entry, 32 bytes: 0 to 7 name (space padded; byte 0 = `$00` deleted, `$FF` never used), 8 to 10 extension, 11 type (0 BASIC, 1 BASIC data, 2 machine language, 3 text), 12 ASCII flag (0 binary, `$FF` ASCII), 13 first granule, 14 to 15 bytes used in last sector, 16 to 31 unused.
- FAT sector: granule bytes for 68 granules. `$FF` = free; `0` to `$43` = next granule; last granule has bits 6 and 7 set and the low bits hold the number of sectors used in it (so `$C1` to `$C9`). Unravelled describes six control bytes (active FCB count and a change counter) that Disk BASIC keeps in its RAM copy of the FAT; DynoSprite copies the first 68 bytes of sector 2 directly as the granule table (src: https://github.com/richard42/dynosprite engine/disk.asm), which is the on-disk layout.
- Granule to physical location: track = g / 2, plus 1 if that is 17 or more (skip the directory track); first sector = 1 for even g, 10 for odd g. DynoSprite's `Disk_FileSeekForward` implements exactly this (src: dynosprite engine/disk.asm).
- Disk BASIC spreads allocations across the disk to reduce head wear (src: Unravelled), so a file written by `SAVEM` or `decb copy` is not necessarily contiguous. A loader must follow the FAT chain, not assume contiguity.

Source disagreement: the techheap page and the archive's `diskbasic.txt` describe the DSKCON buffer as "128-byte" sectors (src: https://techheap.packetizer.com/computers/coco/diskbasic.html). This is wrong for Disk BASIC; Unravelled defines `SECLEN EQU 256` and every working loader (DynoSprite, NitrOS-9, SDC) transfers 256 bytes. Use 256.

Interleave: `DSKINI` formats with a skip factor (`DSKINI drive, skip`) so that Disk BASIC at 0.89 MHz can process one sector before the next logical one passes the head. The default skip factor was not confirmed from a source in this pass (commonly quoted as 4) [unverified]. Interleave matters a lot for throughput (section 7).

### 1.3 Larger drives

- 40-track and 80-track drives and double-sided drives exist, but stock Disk BASIC uses 35 tracks single sided. A 40-track RS-DOS has 78 granules, 80-track has 158; RS-DOS keeps one 74-byte FAT image per drive in RAM (4 drives, 296 bytes), and changing the track count needs patches (`4080DSK.BAS`); 80-track setups cannot read 35/40-track disks (src: https://www.cocopedia.com/wiki/Hacking_Disk).
- Third-party DOS ROMs (ADOS, RGB-DOS, HDB-DOS and others, manuals at https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/) add 40/80-track and double-sided support, but any game that depends on them cuts its audience. Do not rely on them.
- The CoCo SDC accepts floppy images up to 737,280 bytes (2,880 sectors, 80 cylinders, 2 sides), but images above 2,880 sectors are treated as hard disks and "floppy-interface mode can access only the first 1440 sectors" (src: CoCo SDC User Guide v4, https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/CoCo%20SDC%20User%20Guide%20v4%20(Darren%20Atkinson).pdf).

### 1.4 What Disk BASIC offers machine language

DSKCON is the only documented machine-language entry point (src: techheap page; William Astle's "CoCo Loaders", http://lost.l-w.ca/0x05/wp-content/uploads/2010/02/Coco-Loaders.pdf, which recommends calling DSKCON "via the officially sanctioned vector at C004h" so the loader works with any Disk BASIC ROM, including DriveWire and hard drive ROMs).

Calling convention:

```
        ldx   $C006        ; X -> DSKCON parameter block (it is the DP block at $00EA)
        lda   #2           ; 0 restore, 1 no-op, 2 read sector, 3 write sector
        sta   0,x          ; DCOPC  ($EA)
        lda   #drive       ; 0..3
        sta   1,x          ; DCDRV  ($EB)
        lda   #track       ; 0..34
        sta   2,x          ; DCTRK  ($EC)
        lda   #sector      ; 1..18
        sta   3,x          ; DSEC   ($ED)
        ldd   #buffer      ; 256-byte buffer
        std   4,x          ; DCBPT  ($EE-$EF)
        jsr   [$C004]      ; DSKCON; only CC is documented as changed
        lda   6,x          ; DCSTA  ($F0), 0 = OK, else filtered FDC status bits
```

(src: Unravelled direct page map `DCOPC $EA, DCDRV $EB, DCTRK $EC, DSEC $ED, DCBPT $EE, DCSTA $F0`; techheap page for `$C004`/`$C006`, op codes and "modifies only the condition code register"; DynoSprite engine/disk.asm and system.asm for the working pattern.) DCSTA bits follow the FDC status register: 7 not ready, 6 write protect, 5 write fault/record type, 4 record not found / seek error, 3 CRC, 2 lost data / track 0, 1 DRQ / index, 0 busy (src: Unravelled). Disk BASIC filters them rather than returning the raw register (src: Unravelled).

Other Disk BASIC facilities and their relevance:

- File manager (OPEN, GET/PUT, FCBs of 281 bytes = 25 control + 256 buffer, FCB types `$10` sequential in, `$20` sequential out, `$40` random) lives behind BASIC tokens and is not a stable ML API (src: Unravelled). Unravelled lists the command table and dispatch addresses (`$C17F` keyword lookup, `$C2C0` jump table) but no supported ML file API. Do not call it from the game; implement the tiny read-only file logic over DSKCON instead (DynoSprite does this in about 450 lines of asm).
- Disk RAM starts at `$600`: DBUF0 and DBUF1 (256 bytes each; DBUF1 is also scratch during DSKI$/DSKO$/DSKINI), then per-drive FAT images; `DOSBUF` = `$2600` (load address of the `DOS` boot track); Disk BASIC uses 9 direct page bytes (src: Unravelled). DRGRAM (the `$FF40` shadow) is at `$986`; DynoSprite clears both `$FF40` and `$986` when it stops the motor "so Disk BASIC knows that drive motor was shut off" (src: dynosprite engine/system.asm).
- BASIC level `DSKI$`/`DSKO$` read/write one sector into two strings; `DSKINI` formats; `LOADM`/`SAVEM`; `DOS` boots track 34 (src: diskbasic.txt; CMOC's `install-coco-boot-loader` tool installs a boot loader on track 34, src: https://perso.b2b2c.ca/~sarrazip/dev/cmoc-manual.html).

### 1.5 DECB machine-language binary format (`.BIN`, LOADM)

Each segment: preamble `$00`, 2-byte length, 2-byte load address, then data; repeat; then postamble `$FF 00 00` and 2-byte exec address (src: Unravelled; Astle). LOADM accepts many segments in one file, so a single `.BIN` can load non-contiguous areas of the 64 KB CPU map. Limits for the port:

- LOADM only sees the current 64 KB map. Astle notes LOADM reads back each byte it writes, so a segment that targets MMU registers (to switch blocks mid-load) is unreliable; use a loader program instead (src: Astle).
- LOADM cannot load over the BASIC/Disk ROM images or BASIC low RAM that it is using. DynoSprite works around this with `binsectionmover.py`: sections assembled for `$0E00-$1FFF` and `$E000-$FFFF` are relocated in the file to "benign" addresses (`$4000`, `$6000`) and moved into place after start (src: dynosprite makefile and doc/DynoSpriteUsage.txt).
- CMOC produces DECB `.bin` output directly; `--org`, `--data`, `--limit` and `--stack-space` control placement (src: CMOC manual). CMOC has no far pointers or banking support (the manual mentions none), so multi-bank code must be arranged by the build (separate links per bank window plus trampolines).

## 2. Modern mass storage real users have

### 2.1 CoCo SDC (Darren Atkinson)

Facts from the User Guide v4 (src: https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/CoCo%20SDC%20User%20Guide%20v4%20(Darren%20Atkinson).pdf) unless noted:

- Cartridge with an ATmega328P at 10 MHz and an SD card; "Emulates a Tandy Floppy Disk Controller" at the hardware level, so software with its own floppy routines works. CoCopedia: "basically 100% compatible with any CoCo software, including copy protected disks", emulating the WD1773 (src: https://www.cocopedia.com/wiki/CoCoSDC).
- 128 KB flash in 8 banks of 16 KB at `$C000-$FEFF`; bank 0 = SDC-DOS (a Disk Extended Color BASIC compatible ROM), bank 1 = stock Disk BASIC 1.1. Latest firmware listed: SDC-DOS 1.75, MCU 128, Feb 22 2024 (src: CoCopedia CoCoSDC).
- `DRIVE n,"path"` mounts an image on a drive; `DRIVE n,UNLOAD` ejects; `DRIVE n,OFF` passes the drive to a real FDC. Two images are floppy-emulated at a time (drives 0 and 1); drives 2 and 3 can be DriveWire (src: guide; https://exileinparadise.com/_export/raw/tandy_color_computer:cocosdc).
- Disk Set folders: images whose names end in a digit 1 to 9 form a set; the front button or the "Mount Next Disk" command advances to the next image. This is SDC's native answer to "Insert disk N".
- `STARTUP.CFG` can pre-mount images at power-on; `AUTOEXEC.BAS` runs automatically (hold SHIFT to skip); `RUN @n` boots a flash bank.
- Image rules: DSK images must be a multiple of 256 bytes, minimum 82,944 bytes; floppy images up to 737,280 bytes; above 2,880 sectors an image is a hard disk "as large as 2 gigabytes"; SDF images carry raw tracks for copy-protected disks.
- Command mode (bypassing FDC emulation): write `$43` to `$FF40`; parameters in `$FF49` (LSN bits 23-16) and `$FF4A:$FF4B` (LSN bits 15-0); command `$8x` = read logical sector, `$Ax` = write logical sector, `$C0`/`$E0` extended commands (the latter with a data block, used for mount and directory operations); status at `$FF48` (bit 0 busy, bit 1 ready, bit 7 failed); data is read as words from `$FF4A/$FF4B`; streaming commands `$90/$91` return 512-byte blocks (src: guide; NitrOS-9 `defs/cocosdc.d`, https://github.com/nitros9project/nitros9).
- NitrOS-9's `llcocosdc` driver shows the fastest 6809 read loop: `ldu ,y / stu n,x` four times per 8 bytes, 32 chunks per sector (src: nitros9 `level1/coco1/modules/llcocosdc.asm`). By cycle count (5+5 for `ldu ,y`/`stu ,x`, 5+6 for each indexed-offset pair, plus `abx`, `deca`, `bne`) that is about 51 cycles per 8 bytes, about 1,630 cycles per sector, 0.9 ms at 1.79 MHz, excluding the SD card's own latency (my arithmetic).
- No transfer-rate figure is published in the guide or on CoCopedia [no source found]; see section 7 for estimates.

### 2.2 DriveWire 4

Protocol (src: DriveWire Specification, https://github.com/boisy/DriveWire/wiki/DriveWire-Specification): host PC serves virtual disks over a serial link, 8-N-1; all transfers are 256-byte sectors addressed by drive number (0 to 255) and a 24-bit LSN.

| Transaction | Guest sends | Host replies |
|---|---|---|
| OP_READEX `$D2` | op, drive, LSN (3 bytes) | 256 data bytes (256 zeros on error); then guest sends 2-byte checksum; host replies 1 status byte (0 OK, 243 checksum mismatch, other = error) |
| OP_REREADEX `$F2` | same | retry |
| OP_WRITE `$57` | op, drive, LSN, 256 bytes, 2-byte checksum | 1 status byte |
| OP_TIME `$23` | op | 6 bytes year-1900, month, day, hour, minute, second |
| OP_NAMEOBJ_MOUNT `$01` | name | drive number (DW 4.0.4+) |

Both sides time out after 250 ms. Named objects let a guest ask the server to mount a file by name and get a drive number back, which would let the game request `PORDATA3.DSK` without the user typing a server command.

Speeds: the bit-banger (CoCo's built-in serial port, bit-banged with interrupts masked) runs at 38,400 bps on a CoCo 1, 57,600 bps on CoCo 2, 115,200 bps on CoCo 3 at 1.79 MHz (src: SDC guide DriveWire section; FujiNet guide model-switch table). NitrOS-9's `dwread_bb6809.asm` is headed "57600 (115200) bps using 6809 code and timing" and masks interrupts with `orcc #$50` for the whole transfer (src: nitros9 `level1/modules/dwread/dwread_bb6809.asm`). Effective throughput at 115,200 bps is at most about 11.5 KB/s before protocol overhead and host latency.

Variants: Becker port (`BECKBASE equ $FF41`, status `$FF41`, data `$FF42`; src: nitros9 `dwread_becker.asm`) is a fast byte-wide port used by emulators (XRoar, VCC, MAME) and some FPGA systems; MEGA mini MPI UARTs (`dwread_mmmpi.asm`) and other back ends exist in the same directory.

Disk BASIC access to DriveWire is through HDB-DOS (Cloud-9; manual at https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/HDB-DOS%20User%20Manual%20(Cloud-9).pdf), which replaces Disk BASIC and keeps DSKCON at `$C004` working (src: Astle). HDB-DOS can also expose many 35-track virtual RS-DOS disks inside one large image (via its `DRIVE #` offset) [details unverified in this pass].

### 2.3 FujiNet for CoCo, MEGA mini MPI, emulators

- FujiNet for CoCo (CoCoFuji, ESP32, WiFi): a cartridge that "carries DriveWire protocol over the Color Computer's built-in serial port"; HDB-DOS 1.5 in the cartridge; 4 drive slots holding .DSK images of 161,280 bytes; microSD and TNFS network hosts; 115,200 baud on CoCo 3 (src: https://fujinet.online/wp-content/uploads/2026/06/fujinet-getting-started-coco.pdf). For the port it behaves like DriveWire via HDB-DOS.
- MEGA mini MPI (Ed Snider): 4-slot Multi-Pak with two high-speed UARTs and a YMF-262 (OPL3) sound chip; extended features are not used automatically by existing software (src: https://www.cocopedia.com/wiki/MEGA_mini_MPI). An SDC sits in one of its slots; the MPI slot select register (`$FF7F`) must point at the SDC when talking to it, which `llcocosdc` handles (src: nitros9 llcocosdc.asm). 
- XRoar: `-machine-arch coco3 -ram 512`, `-load-fd X file` for drives 0 to 3, `-load-hd X file`, `-becker`, `-becker-ip` (default 127.0.0.1), `-becker-port` (default 65504), `-no-disk-write-back` (src: https://mankier.com/1/xroar). No CoCo SDC emulation is listed in the man page.
- VCC (Windows): FD-502 emulation with Becker port, virtual hard disk, SuperIDE, and an "SDC Simulator" (EJ Jaquay, 2025) that maps `$FF40`, `$FF42/$FF43` flash and `$FF48` to `$FF4B` like the real board (src: https://github.com/VCCE/VCC README.md and sdc/sdc.cpp).
- MAME: CoCo 3 with WD17xx FDC (coco_fdc.cpp) and a DriveWire socket device (`coco_dwsock`, src: https://git.redump.net/mame/tree/src/devices/bus/coco/coco_dwsock.h?h=xtal).

### 2.4 How modern multi-disk games ship

- Glen Hewlett's Defender (512 KB CoCo 3) ships as `DISK1.DSK` + `DISK2.DSK`. Its config program asks "Number of Disk drives"; with one drive the user swaps during loading. For CoCo SDC the README says: `DRIVE0,"DISK1`, `DRIVE1,"DISK2`, `RUN"CONFIG`, then choose "two or more drives" (src: https://github.com/nowhereman999/Defender_CoCo3 README.md). Everything is loaded into RAM at start; the disk is not used during play except to save settings and scores (`RUN"SAVE` after BREAK).
- Hewlett's "CoCo 3 Super Loader" turns one big CoCo 3 program into ZX0-compressed files (`GO-V32.000` to `.008` in Defender) spread across disks, with an option `-dx##` for "the number of 8k blocks to save on a disk", default 19; the ML stage copies compressed rows into MMU blocks, decompresses with Doug Masten's 6809 ZX0 decoder, restores the MMU map and jumps to the exec address; it supports 512 KB or 2 MB targets (src: Defender source zip, CoCo3_Super_Loader_zx0/CC3_NewLoaderLZX0V1.0.bas and CC3_NewLoaderCode1.asm in the Defender_CoCo3 repo).
- DynoSprite games ship as one `.DSK` built by a host tool (`file2dsk`) with data files `OBJECTS.DAT`, `LEVELS.DAT`, `TILES.DAT`, `SOUNDS.DAT`, `IMAGES.DAT` loaded per level at run time via DSKCON; requires "a 512K Coco 3 with a disk system (either 5 1/4" floppy drive, or CoCo SDC card, or CoCoNET ROM Pak, or similar)" (src: dynosprite README and engine/loader.asm).
- Sierra's official CoCo 3 ports (King's Quest III, Leisure Suit Larry) shipped on three 35-track single-sided disks under OS-9 Level 2; a later hard-drive guide moves all files into one directory tree and regenerates the game's table of contents (`tocgen toc.txt`, one line per original disk) (src: https://lcurtisboyle.com/nitros9/leisuresuitlarry.html; https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Running%20KQ3%20from%20hard%20drive.txt).
- On SDC, a multi-disk set is typically a folder of `.DSK` images, either named as a Disk Set (trailing digit) or mounted by the program/user with `DRIVE n,"name"` (src: SDC guide).

### 2.5 Mapping PoR's "Insert disk N"

The PC game has 8 logical game disks plus STARTUP and OVERLAY. On 5.25-inch drives these were packed as GAME DISK #1/2, #3/4, #5/6, #7/8; on 3.5-inch as #1/2, #3/4/5, #6/7/8; the save disk is separate, blank and formatted; play disks must be write-protected; a hard disk install puts everything in `C:\POOLRAD` with saves in a configurable path, and `POOL.CFG` line 3 is the data path and line 4 the save path (src: https://mocagh.org/ssi/pool-ibmrefcard.pdf; https://dosdays.co.uk/topics/Games/game_poolrad.php). The game asks for a disk number and the user presses Enter if it is already in the drive (src: refcard).

That design maps cleanly: keep a "volume id" for each container file, keep a table of which volume is in which drive (up to 4 drives with DSKCON), and when a needed volume is not mounted show "Insert PoR disk N in drive D". On SDC the game can mount the image itself (extended command) or ask the user to press the SDC button; on DriveWire it can request a named object; on a big single image no prompt is needed. The decomp already knows which DAX files the PC version expected on which disk number, so the volume assignment can follow the original grouping, which keeps swaps rare.

## 3. OS-9 Level 2 and NitrOS-9

### 3.1 Process memory model

- Physical RAM is managed in 8 KB blocks; a 512 KB CoCo 3 has 64 blocks (`$00` to `$3F`). "Each user process has the use of a map made up of up to eight 8K blocks"; program plus data can total "about 63.5K"; data areas are allocated in whole 8 KB blocks; program modules load at the top of the map and data at the bottom (src: Inside OS-9 Level II introduction, https://nitros9.sourceforge.io/wiki/index.php/Inside_-_INTRODUCTION).
- The vector page `$FE00-$FEFF` is mapped into every map so interrupts and system calls can switch to the system task; a module placed in the top block cannot extend into the last 512 bytes (src: same).
- Each process descriptor holds a 64-byte DAT image (`P$DATImg`) of its map; the kernel keeps per-block link counts so modules shared by several processes stay mapped (src: https://nitros9.sourceforge.io/wiki/index.php/Inside_-_THE_SYSTEM).
- Time slice is 6 ticks of the 60 Hz clock, about 0.1 s (src: same). Level 2 "is normally slower than Level 1 because of MMU switching and copying data between maps" (src: Inside introduction).

### 3.2 Handling programs bigger than 64 KB

- Split code into separate modules (`F$Link`, `F$Load`, `F$UnLink`). Under Level 2 `F$Link` "maps the module's memory blocks into the calling process's address space" (src: nitros9 docs/subroutine-modules.md). A position-independent, re-entrant subroutine module works as an overlay. Microware's suggestion to keep module files near 8 KB boundaries applies because modules loaded together are mapped together (src: Inside introduction).
- Data modules can be shared between processes (`F$Link` a data module by name).
- Extra RAM: `F$AllRAM` allocates blocks, `F$MapBlk` (`X` = starting physical block, `B` = count; returns `U` = logical address, allocating from the top of the process space down) maps them into the process, `F$ClrBlk` unmaps, `F$DelRAM` frees (src: https://nitros9.sourceforge.io/wiki/index.php/F$MapBlk; nitros9 defs/os9.d). This is the OS-9 equivalent of writing `$FFA0-$FFA7` on bare metal, but each remap is a system call (SWI2 entry, kernel DAT update) rather than a single `STA`.
- `F$CpyMem` and `F$Move` copy between maps.

### 3.3 Graphics through the windowing system

- Window types for `DWSet`: 1 = 40x24 text, 2 = 80x24 text, 5 = 640x192x2, 6 = 320x192x4, 7 = 640x192x4, 8 = 320x192x16 (32,000 bytes) (src: https://nitros9.sourceforge.io/wiki/index.php/The_NitrOS-9_Windowing_System). Note 192 lines, not 200: PoR's 320x200 title pictures would lose 8 lines in a standard window.
- Get/Put buffers: `DfnGPBuf` `1B 29`, `GPLoad` `1B 2B grp bfn sty hsx lsx hsy lsy hbl lbl data`, `GetBlk` `1B 2C`, `PutBlk` `1B 2D`, `KilBuf` `1B 2A`; groups 1 to 199 for applications; buffers are allocated in 8 KB blocks and are visible system wide (src: same). All drawing is escape sequences written to the window path, which costs a system call plus the GrfDrv interpretation per primitive.
- VDG windows exist for older software (Sierra's games need a VDG-type screen: `xmode /w1 type=1 pag=16` per the KQ3 hard drive note).
- Direct access: `SS.AScrn` (allocate a screen "for application poking"), `SS.DScrn` (display it), `SS.FScrn` (free), `SS.ScInf` ("Get Current screen info for direct writes") (src: nitros9 defs/os9.d). NitrOS-9 ships `hirestest` which allocates a 320x192 screen and draws into its mapped memory (src: nitros9 level2/cmds/hirestest.asm). So a game can draw at bare-metal speed into its own mapped screen blocks; but the screen's 32 KB then occupies four of the process's eight 8 KB slots while mapped.

### 3.4 Performance cost of OS-9 versus bare metal (assessment)

- The kernel's 60 Hz clock IRQ and the GIME/keyboard handling run regardless; with one process this is a few percent of CPU [estimate, no measured source].
- Every I/O call goes SWI2 to kernel to RBF file manager to driver; sector transfers then cross maps with `F$Move`. File reads are therefore slower than raw DSKCON per byte, but RBF does buffering and real files, so code simplicity is better.
- Memory: each process still sees 64 KB. PoR's resident code alone is about 70 KB x86; under OS-9 it must be split into modules swapped by `F$Link`/`F$UnLink` or `F$MapBlk`, with the same banking problems as bare metal plus system call costs.
- Sound: PoR's 236.7 Hz timer needs a device driver or a VIRQ (Sierra shipped `AGIVIRQDr` for KQ3, src: KQ3 hard drive note), which is more work than a bare-metal FIRQ handler.

### 3.5 Commercial OS-9 games on the CoCo 3

- King's Quest III and Leisure Suit Larry (Sierra On-Line, sold by Tandy, 1988): OS-9 Level II, 256 KB, three 35-track single-sided disks; they were the only two official Sierra AGI ports; the official engine never plays sound while animation is on screen because feeding the DAC is CPU intensive (src: https://lcurtisboyle.com/nitros9/leisuresuitlarry.html; https://forums.atariage.com/topic/311559-sierra-agi-ports-to-the-coco-3-any-sound-improvement/). Structure: an interpreter command (`sierra`) in a CMDS directory, data files per disk, a table of contents file mapping files to disks, a VIRQ driver module (src: KQ3 hard drive note).
- Thexder (Sierra/Tandy): an RS-DOS cartridge version (128 KB) in 1988 and an OS-9 disk version (256 KB) converted by Alan Dekok; code internals suggest it was originally written for OS-9 (src: https://www.lcurtisboyle.com/nitros9/thexder.html).
- Other OS-9 titles were not researched in depth in this pass [open].

### 3.6 CMOC and OS-9

CMOC can produce OS-9 executables; as of CMOC 0.1.43 OS-9 support is only available in monolithic mode, and under OS-9 the Y register points to the process data area and must be preserved by assembly code (src: CMOC manual, https://perso.b2b2c.ca/~sarrazip/dev/cmoc-manual.html). A fuller OS-9 C library and the CGFX graphics library are a separate community project, still porting parts of the Kreider C library (src: https://github.com/stahta01/cmoc_os9 README). The exact CMOC option name for the OS-9 target was not confirmed from the manual page fetched [unverified; check `cmoc --help` in the jamieleecho/coco-dev image].

## 4. Bare metal over RS-DOS: loading more than 64 KB and keeping disk I/O

### 4.1 CoCo 3 memory facts that matter for loaders

- MMU task 0 registers `$FFA0-$FFA7` map CPU `$0000`, `$2000`, ..., `$E000` to physical 8 KB blocks; `$FFA8-$FFAF` are task 1, selected by bit 0 of `$FF91`. On 512 KB, blocks `$00` to `$3F` are physical `$00000-$7FFFF`; on 128 KB only `$30` to `$3F` exist. BASIC's default map is `$38` to `$3F`; `$30-$33` HSCREEN, `$34` HGET/HPUT buffer, `$35` secondary stack, `$36` 40/80-column screen, `$37` unused, `$38-$3B` system RAM, `$3C-$3F` the ROMs copied into RAM (src: https://www.cocopedia.com/wiki/Understanding_and_Using_the_MMU). The page's claim that bit 6 "adds &H20 (64)" is internally inconsistent; its examples treat `$38` and `$78` as the same block, i.e. the upper bits are ignored on 512 KB.
- Because BASIC has copied ROM into blocks `$3C-$3F` and runs in all-RAM mode, "ROM" code at `$A000-$FEFF` is ordinary RAM that can be mapped out and back in. `$FFDE` selects ROM mode and `$FFDF` all-RAM mode (SAM style registers); Hewlett's loader does `STA $FFDF` "Make sure we are in RAM mode" (src: Defender CC3_NewLoaderCode1.asm). `$FF90` bits 1-0 select the ROM configuration (16 KB internal + 16 KB cartridge, 32 KB internal, 32 KB cartridge); when ROM pages are mapped in ROM mode, the MMU substitutes the slot number's low bits (src: https://www.cocopedia.com/wiki/MMU_RAMROM_Mode). Bit 3 of `$FF90` fixes `$FE00-$FEFF` to the top block; DynoSprite writes `$FC` then `$7C` to `$FF90` ("MMU enabled, coco3 IRQ and FIRQ enabled, fix $FE** page to high ram, standard SCS, rom: 16k internal / 16k cartridge") (src: dynosprite engine/system.asm).
- Interrupt vectors on the CoCo 3 go through jump slots in the `$FEEE-$FEFF` page (FIRQ `$FEF4`, IRQ `$FEF7`, SWI `$FEFA`, NMI `$FEFD`); DynoSprite and Defender patch the FIRQ/IRQ/SWI slots and leave NMI to Disk BASIC (src: dynosprite system.asm writes `$FEF5`, `$FEFB`; Defender `CoCo3_Start.asm` defines `FIRQ_Jump_position EQU $FEF4`, `IRQ_Jump_position EQU $FEF7`).

### 4.2 Loader patterns

From Astle's "CoCo Loaders" (src: http://lost.l-w.ca/0x05/wp-content/uploads/2010/02/Coco-Loaders.pdf):

1. BASIC loader: loop `POKE &HFFA2,block` then `LOADM` a file assembled at `$4000-$5FFF`, restore `$FFA2` to `$3A` (also the CoCopedia HR1 to HR4 example). Simple, needs one file per 8 KB block.
2. Machine-language first stage that loads the rest itself, either through DSKCON or its own file system code.
3. Multi-origin `.BIN` (several segments, one exec address).
4. Autoexec tricks (hooks at `$010C`, `$019A`, `$0176`).
5. Single file with payload after the postamble, read through the still-open file via ROM get-byte `$A176` and close `$A42D`.
6. Two-stage: stage one reads the entire payload into physical blocks starting at 0, then stage two remaps (`CLR $FFA0` and so on) and overwrites BASIC; "works best with 512K".

Hewlett's Super Loader is pattern 6 with ZX0 compression. DynoSprite is pattern 3 plus run-time DSKCON loading.

### 4.3 Keeping DSKCON callable after taking over (the DynoSprite recipe)

DynoSprite's memory manager reserves virtual handles for exactly the blocks Disk BASIC needs (src: dynosprite engine/memory.asm, engine/system.asm, doc/AddressMap.txt):

- `VH_BASIC0`: the original BASIC block at `$0000-$1FFF` (direct page variables, RAM vectors at `$0100`, disk RAM at `$600-$98x`); DynoSprite keeps its heap after `$0E00` in this same block.
- `VH_BASICROM`: Color BASIC image, mapped at `$A000`.
- `VH_DSKROM`: Disk BASIC image, mapped at `$C000`.
- `VH_HIGHROM`: the top 8 KB, mapped at `$E000` only during the call ("needed for CoCoNET MicroSD Pak").
- Its main code page with stack sits at `$2000-$3FFF` and is never swapped, so the stack and return address survive the call.

`System_EnterDiskMode` writes `$FFA0`, `$FFA5`, `$FFA6`; `System_CallDSKCON` maps `$FFA7`, saves DP and sets DP to 0, (on 6309 returns to emulation mode), writes `$FFD8` to drop to 0.89 MHz, does `JSR [$C004]`, restores DP, remaps its own `$E000` page, checks `DC.STA`, and writes `$FFD9` to return to 1.79 MHz. On error it stops the motor (`CLR $FF40`) and traps. It also clears `$FF40` and `$986` after a batch of reads to stop the motor.

Points to copy into the port:

- Treat the four BASIC blocks (`$38` low RAM and the three ROM image blocks) as reserved, never reuse them, and never overwrite Disk BASIC's RAM (`$600` to about `$0E00`) or its direct page bytes.
- Map them in only around the DSKCON call; the rest of the time those CPU windows hold game banks.
- Keep the stack, the sector buffer and the caller in windows that are not remapped (`$2000-$9FFF` in DynoSprite's case).
- Mask the game's interrupts or make the handlers robust to the disk-mode map; the PoR sound timer simply stops during disk I/O (acceptable; the PC version also blocks on disk).
- Whether slowing to 0.89 MHz is required for every controller is unclear: DynoSprite does it for all reads; HDB-DOS on DriveWire at 115,200 bps depends on 1.79 MHz timing [unverified, see Open questions]. Make the speed switch a backend parameter.

### 4.4 Other homebrew references

- Sock Master (John Kowalski): Donkey Kong emulator, Gloom-3D, demos (src: links in https://github.com/dougmasten/awesome-coco; http://www.6809.org.uk/twilight/sock/cocofile/demo.html). Their loader internals were not examined in this pass.
- Nick Marentes: no disk loader source found in this pass [open].
- Glen Hewlett: Defender, Joust, Pac-Man for 512 KB CoCo 3 with the Super Loader (sources in the GitHub repos above), plus blog posts on 6809 tooling (https://nowhereman999.wordpress.com/).

## 5. Recommendation matrix

Scores 1 (poor) to 5 (best), judged for this port.

| Criterion | A. Bare metal + RS-DOS files + DSKCON | B. Bare metal + own raw format on image | C. OS-9 / NitrOS-9 Level 2 | D. Hybrid: A as baseline + optional fast LSN backends |
|---|---|---|---|---|
| Ease with CMOC | 4: CMOC's default DECB target; one small asm shim for DSKCON | 4: same, slightly less code (no FAT) | 2: monolithic mode only, partial libc, Y register rule, module split by hand | 4: same as A; backends are small asm |
| Performance | 4: CPU free except during loads; DSKCON speed | 4: can tune interleave/contiguity, same DSKCON | 2: syscall and map-copy overhead, GrfDrv for drawing unless poking screens | 5: SDC/Becker backends much faster |
| Use of 512 KB | 5: direct MMU control (`$FFA0-$FFAF`) | 5 | 3: F$AllRAM/F$MapBlk work but every remap is a syscall; 64 KB map per process anyway | 5 |
| File I/O for DAX blocks by id | 4: index table + granule map, sector reads | 5: LSN arithmetic, no FAT | 4: RBF seek + read, simplest code | 5 |
| Saving games | 4: pre-allocated save files rewritten in place via DSKCON op 3 | 3: raw sectors, user cannot see/copy saves with normal tools | 5: real files | 4 |
| Compatibility: floppy / SDC / DriveWire | 5: works on all three (SDC FDC emulation, HDB-DOS DSKCON) | 3: floppy and SDC need images in exact geometry; tools (`decb`) cannot manage contents | 4: floppy, SDC, DW all have drivers, but user must boot NitrOS-9 | 5 |
| Emulator testing | 5: XRoar, VCC, MAME, headless MAME, 4 drives | 4 | 4: needs NitrOS-9 boot image | 5 |
| Total | 31 | 28 | 24 | 33 |

Recommended choice: D, built in two steps.

1. Step 1 (ship first): option A. Bare-metal CMOC program, multi-segment `.BIN` plus a small stage-1 loader that fills MMU blocks for the code banks; all data in a handful of RS-DOS files per disk, read with DSKCON through a `read_sectors(volume, lsn, count, dest_block, dest_off)` function that converts file-relative sectors to track/sector with a FAT chain cached at startup (as DynoSprite does).
2. Step 2 (optional): add backends behind the same interface: CoCo SDC command mode (`$43` to `$FF40`, `$8x` logical sector read from `$FF4A/$FF4B`) for a single large image, and DriveWire OP_READEX (reuse the NitrOS-9 `dwread`/`dwwrite` routines, which are documented and small). Detect the SDC by probing as `llcocosdc` does.

Why: it runs everywhere real users and emulators are, it matches CMOC's natural target, it keeps full control of the GIME/MMU that the graphics and banking design need, and the disk images remain normal RS-DOS disks that `decb dir`/`decb copy` can inspect, which helps agents debug. OS-9 offers nothing the port needs that a 500-line disk layer does not, and costs memory, speed and audience.

## 6. Data packaging

### 6.1 Repack the DAX archives

Yes, repack at build time on the host. Proposed format (one container per original PC disk group, e.g. `PORD1.DAT` ... ):

- Header sector(s): magic, volume number, count, then an index of entries `{dax_file_id (1 byte), block_id (1 or 2 bytes), start_sector (2 bytes, relative to file), packed_len (2 bytes), unpacked_len (2 bytes), flags (1 byte: RLE, preconverted picture, palette present)}`. At 9 bytes per entry, 1,000 entries fit in about 36 sectors; load all indexes into one 8 KB bank at startup so a lookup by id needs no disk access.
- Align every block to a 256-byte sector boundary. Average waste is about 128 bytes per block; for 1,000 blocks that is about 125 KB, so align only blocks bigger than a few sectors and pack small records (GEO 1,026-byte maps, ECL scripts, item/character tables) contiguously, or group small blocks per area so one read fetches a whole area. Alignment lets DSKCON read straight into the destination bank with no copying for all full sectors.
- Preconvert pictures to the GIME's native format and palette ordering at build time, so the CoCo only decompresses and copies. DAX pictures are already 4 bits per pixel with the left pixel in the high nibble, which is the expected GIME 16-colour packing [cross-check with the graphics research file]; the per-picture EGA palette becomes a 16-byte GIME palette in the entry.
- Keep the original byte RLE (cheap to decode, about 20 to 30 cycles per output byte in 6809 [estimate]) or move to ZX0, which Hewlett uses on CoCo 3 with Doug Masten's 6809 decoder (src: Defender loader). ZX0 would shrink data and therefore disk count and floppy load time, at a higher decode cost; measure both.
- Place each volume's blocks in the order the game uses them (by map area) to reduce seeks.
- Save games: ship pre-created fixed-size files (for example `SAVEA.DAT` ... ) of whole granules on a save disk image, so saving rewrites existing sectors with DSKCON op 3 and never changes the FAT or directory. This removes the most dangerous code (FAT writes) from the port. The exact size of a PoR save needs to be taken from the decomp (285-byte character records x party size plus game state) [open].

### 6.2 Disk count

1,284,555 bytes / 156,672 bytes per disk = 8.2, so at least 9 data disks before recompression, plus 1 to 2 disks of code (197 KB of x86 code will compile to roughly similar or larger 6809 code [estimate]) plus a save disk. A ZX0 repack might bring data to 6 to 7 disks [estimate, measure]. On SDC/DriveWire these are just files.

### 6.3 Load time estimates for a typical 10 KB block (40 sectors)

Assumptions are stated so later agents can recompute.

| Path | Model | Estimate |
|---|---|---|
| Floppy, DSKCON, stock format | 300 rpm = 200 ms per revolution, 18 sectors per track, about 11 ms per sector passing (SDC guide gives 250 kbps double density at 300 rpm). With a skip factor of about 4, consecutive logical sectors cost about 4 to 5 sector times each: 40 x about 50 ms = 2 s. Add track steps (2 to 3) and, if the motor was off, spin-up of about 0.5 to 1 s, and a seek of up to 17 tracks from the directory at up to 30 ms per step. | 1.5 to 3 s motor on; up to about 4 s cold [estimate] |
| Floppy, custom interleave tuned for DSKCON at the chosen CPU speed | about 2 to 3 revolutions for 40 sectors | about 0.6 to 1 s [estimate] |
| CoCo SDC via DSKCON (FDC emulation, no rotation) | per sector: Disk BASIC overhead plus HALT byte loop at 0.89 MHz, about 3 to 5 ms | about 0.15 to 0.3 s [estimate] |
| CoCo SDC command mode (own loop) | about 0.9 ms CPU per sector (51 cycles per 8 bytes) plus SD latency | about 0.05 to 0.1 s [estimate] |
| DriveWire bit-banger 115,200 bps | about 264 bytes on the wire per sector = about 23 ms, plus host turnaround | about 1 to 1.5 s [estimate] |
| Becker port (emulator) | byte-wide port, host speed | well under 0.1 s [estimate] |
| RLE decompression of 10 KB on the CoCo | about 25 cycles per byte at 1.79 MHz | about 0.15 s [estimate] |

Real-world anchor: DynoSprite's level load took 14.3 to 15.0 s on DECB floppy, 5.8 to 6.4 s on HDB-DOS and 8.2 to 10.1 s in MESS for the same data (src: dynosprite doc/Benchmarks.txt). Its data size is not given there, so only the ratios (floppy roughly 2.5x slower than HDB-DOS) are usable.

Acceptable targets: PoR on a PC floppy also paused for disk at area transitions and picture loads. Aim for under 1 s per load on SDC and under about 3 s on floppy, show a "loading" indicator, never load during combat turns, and cache recently used blocks in spare 512 KB banks (the CoCo has far more free RAM than the PC game's overlay buffer), which will hide most floppy latency after the first visit.

## Implications and recommendations for the port

1. Build a disk layer with one primitive, `read_sectors(volume, lsn, count, bank, offset)`, plus `write_sectors` for saves only. First backend: DSKCON over RS-DOS files with a cached FAT chain per open container; follow DynoSprite's `System_CallDSKCON` mapping recipe exactly (slot 0 = BASIC low block, slot 5 = Color BASIC image, slot 6 = Disk BASIC image, slot 7 = top ROM block, DP = 0, NMI vector untouched).
2. Reserve physical blocks `$38`, `$3C`, `$3D`, `$3E`, `$3F` (and `$3F`'s `$FE00` vector page) for BASIC/Disk BASIC; allocate everything else freely. Keep the stack and the I/O caller in windows that disk mode does not remap.
3. Do not use the Disk BASIC file manager, OPEN/GET/PUT, or FAT writes at run time. Pre-allocate save files.
4. Repack DAX into per-volume containers with an id index, sector-aligned large blocks, grouped small records and preconverted pictures; generate the `.DSK` images on the host with ToolShed `decb` (or CMOC's `writecocofile`), and keep the generator deterministic so tests can diff images.
5. Map PoR's "Insert disk N" to "volume N not mounted": with 4 DSKCON drives the user can mount 4 volumes at once; prompt only for a missing volume. On SDC, optionally mount the needed image automatically.
6. Ship: N `.DSK` images (floppy users, emulators), and later one large image for SDC/DriveWire users once the LSN backends exist.
7. Use DynoSprite (BSD licensed) as the reference implementation for the DSKCON wrapper, RS-DOS directory/FAT reader and MMU virtual-handle manager, and Hewlett's Super Loader for the stage-1 "fill 512 KB with compressed code" loader.
8. Test matrix: XRoar (`-machine-arch coco3 -ram 512 -load-fd 0 a.dsk -load-fd 1 b.dsk ...`), headless MAME with the FDC, VCC's SDC Simulator for the SDC path, XRoar `-becker` with a DriveWire server (pyDriveWire, https://github.com/n6il/pyDriveWire) for the DW path.

## Open questions

1. Default DSKINI skip factor and the actual sector order of Tandy-formatted disks; whether a custom interleave written at image build time (in the `.DSK` it is just data order, so it matters only on real floppies made with a raw-track writer) is worth it.
2. Does Disk BASIC 1.1 DSKCON work reliably at 1.79 MHz on all controllers (FD-502, Disto, SDC)? DynoSprite always drops to 0.89 MHz; HDB-DOS for DriveWire at 115,200 bps needs 1.79 MHz timing. Does HDB-DOS set the speed itself? Test both in XRoar and on hardware.
3. Does DSKCON range-check the track number (35 tracks) so that 40/80-track or double-sided images cannot be addressed through it? Read Disk BASIC 1.1's DSKCON disassembly in Unravelled.
4. Exact CoCo SDC extended-command syntax for mounting an image from software, and measured SDC sector throughput (through DSKCON and in command mode).
5. CMOC 0.1.100 in jamieleecho/coco-dev: exact OS-9 target option and whether any Disk BASIC file helper header ships with it (`ls` the include directory).
6. HDB-DOS: how DSKCON drive numbers map to virtual drives inside one large image (`DRIVE #` offset) and whether a game can change the offset itself.
7. Size of a PoR saved game and number of save slots in the original (from the decomp), to size pre-allocated save files.
8. Number of DAX blocks in total and their size distribution, to finalise the alignment policy and index size.
9. Whether interrupts can stay enabled during DSKCON (for a ticking clock/delay source) or must be masked; measure what Disk BASIC does to CC.

## Sources

- https://bitchin100.com/files/coco/disk-basic-unravelled.pdf : Disk Basic Unravelled; DSKCON direct page block, FAT/directory layout, binary format, FDC registers and commands, disk RAM map.
- https://techheap.packetizer.com/computers/coco/diskbasic.html : `JSR [$C004]`, `$C006` parameter block pointer, op codes, status bits (contains a wrong 128-byte sector claim).
- https://colorcomputerarchive.com/repo/Documents/BASIC%20Commands/diskbasic.txt : Disk BASIC command summary, FREE granule size, DSKI$/DSKO$.
- https://git.redump.net/mame/plain/src/devices/bus/coco/coco_fdc.cpp : WD1793/WD1773 statement, DSKREG bit layout, MAME FDC emulation.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/ : listing of FDC, FD502, SDC, HDB-DOS manuals and schematics.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Operating%20Systems/ : listing of OS-9, NitrOS-9 and third-party DOS manuals.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/CoCo%20SDC%20User%20Guide%20v4%20(Darren%20Atkinson).pdf : SDC registers, command mode, image limits, Disk Sets, DriveWire speeds, flash banks.
- https://www.cocopedia.com/wiki/CoCoSDC : SDC compatibility claims and firmware versions.
- https://exileinparadise.com/_export/raw/tandy_color_computer:cocosdc : SDC feature overview (drives 0/1 floppy, 2/3 DriveWire).
- https://github.com/nitros9project/nitros9 : `defs/cocosdc.d` (SDC registers), `llcocosdc.asm` (SDC driver and read loop), `dwread_bb6809.asm`, `dwread_becker.asm` (DriveWire back ends), `defs/os9.d` (system call and SS codes), `docs/subroutine-modules.md`, `level2/cmds/hirestest.asm`.
- https://github.com/boisy/DriveWire/wiki/DriveWire-Specification : DriveWire 4 protocol, OP codes, named objects, timeouts.
- https://fujinet.online/wp-content/uploads/2026/06/fujinet-getting-started-coco.pdf : FujiNet for CoCo hardware, HDB-DOS 1.5, 161,280-byte images, baud rates.
- https://www.cocopedia.com/wiki/MEGA_mini_MPI : MEGA mini MPI features.
- https://mankier.com/1/xroar : XRoar disk, hard disk, Becker and machine options.
- https://github.com/VCCE/VCC : VCC features including the SDC Simulator and Becker port.
- https://git.redump.net/mame/tree/src/devices/bus/coco/coco_dwsock.h?h=xtal : MAME DriveWire socket device.
- https://www.cocopedia.com/wiki/Understanding_and_Using_the_MMU : MMU registers, block numbering, BASIC default blocks, BASIC block-by-block LOADM example.
- https://www.cocopedia.com/wiki/MMU_RAMROM_Mode : `$FF90` ROM configuration bits and ROM page substitution.
- https://www.cocopedia.com/wiki/Hacking_Disk : 40/80-track granule counts, FAT RAM layout, compatibility.
- http://lost.l-w.ca/0x05/wp-content/uploads/2010/02/Coco-Loaders.pdf : William Astle's survey of CoCo loader techniques, LOADM read-back caveat, DSKCON via `$C004`.
- https://github.com/richard42/dynosprite : DynoSprite engine; DSKCON wrapper, RS-DOS reader, MMU manager, address map, benchmarks, disk image build.
- https://github.com/nowhereman999/Defender_CoCo3 : Defender README (two-disk shipping, SDC instructions) and Super Loader source (ZX0, MMU block filling).
- https://github.com/dougmasten/awesome-coco : index of CoCo homebrew, tools and documentation used to find the above.
- https://nitros9.sourceforge.io/wiki/index.php/Inside_-_INTRODUCTION : Level 2 per-process map, 63.5 KB limit, vector page, Level 2 speed remark.
- https://nitros9.sourceforge.io/wiki/index.php/Inside_-_THE_SYSTEM : DAT images, task tables, time slice.
- https://nitros9.sourceforge.io/wiki/index.php/F$MapBlk : F$MapBlk calling convention.
- https://nitros9.sourceforge.io/wiki/index.php/The_NitrOS-9_Windowing_System : window types and Get/Put buffer escape codes.
- https://lcurtisboyle.com/nitros9/leisuresuitlarry.html : Leisure Suit Larry CoCo 3 requirements and disks.
- https://www.lcurtisboyle.com/nitros9/thexder.html : Thexder RS-DOS and OS-9 versions.
- https://forums.atariage.com/topic/311559-sierra-agi-ports-to-the-coco-3-any-sound-improvement/ : official Sierra CoCo 3 ports and their sound limitation.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Running%20KQ3%20from%20hard%20drive.txt : KQ3 structure under OS-9 (CMDS, toc, VIRQ driver, VDG window).
- https://perso.b2b2c.ca/~sarrazip/dev/cmoc-manual.html : CMOC options (`--org`, `--data`, `--limit`, `--stack-space`), OS-9 monolithic note, `writecocofile`, `install-coco-boot-loader`.
- https://github.com/stahta01/cmoc_os9 : CMOC OS-9 C library and CGFX port status.
- https://mocagh.org/ssi/pool-ibmrefcard.pdf : Pool of Radiance PC disk sets, save disk rules, POOL.CFG, memory requirements.
- https://dosdays.co.uk/topics/Games/game_poolrad.php : Pool of Radiance PC distribution disks and install notes.
- https://github.com/n6il/pyDriveWire : Python DriveWire server for emulator testing.

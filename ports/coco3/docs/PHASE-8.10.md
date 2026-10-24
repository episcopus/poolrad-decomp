# Step 8.10: the distribution (floppy disk set, CoCo SDC file, compression experiments)

Date: 2026-10-23. Follows `docs/PHASE-8.9j.md`; decisions D9 and D13 of `docs/coco/PORTING-GUIDE.md`. Tags: **[V]** measured by running it in MAME, **[M]** proven only against a model of the hardware that this step wrote, **[E]** estimate, **[?]** open.

## 1. What there was, and what there is now

Until this step the game had one storage backend: the doorbell of `img.c`, which only MAME's Lua harness answers. A player could not run the game from anything. Now the engine has three media behind the one `sec_io(cmd, lsn, count, block, offset)` of D13, told apart at boot by what drive 0's directory says (`src/engine/flop.c`):

| Medium | What the player gets | Directory marker (track 17, first entry) | Tested |
|---|---|---|---|
| dev | `make play`, the sessions, the harness serves the sectors | none (`POOL.BIN` first) | all sessions [V] |
| floppy set | `build/floppy/disks/POOL01.DSK ... POOLnn.DSK`, 35 track disks | `POOLDSKn.DAT` | MAME with its FDC through `DSKCON`, the harness swaps disks when the engine asks [V] |
| CoCo SDC | one file `build/sdc/POOL.DSK`, the game's image behind a bootable 35 track disk | `POOLSDC.DAT` | MAME with a **model** of the SDC's command mode written from NitrOS-9's driver and the User Guide [M] |

DriveWire needs nothing of its own for now (section 6).

## 2. The floppy set

### 2.1 Format

`tools/mkimage.py --layout L --floppies DIR` cuts the image (the same PIM2 container as before) into disks. Disk n holds the image's sectors `dbase[n-1] .. dbase[n]-1`; the header (sector 0, from byte 24) says how many each holds: `01 nd` then a word per disk. `tools/decbfs.py` writes every disk as an RS-DOS disk (`decb` reads them: `decb dir`, `decb copy`): the data file `POOLDSKn.DAT` first, in **consecutive granules** from granule 0, so sector k of the file is at granule `k / 9` of the disk; disk 1 also holds `POOL.BIN` (so `LOADM"POOL":EXEC` boots it, as before). A disk says which it is by the name of its first directory entry. The save area (512 sectors, the seeded saves) is the first thing on the last disk, which therefore is the one the player may keep writable; it is asked for when the game saves or loads.

### 2.2 The engine side

* `flop_io` (src/engine/flop.c): disk of a sector by the `dbase` table, drive by LRU (disk 1 stays in drive 0 when there are two drives or more; the others take turns in the rest), sector by `dsk_read`/`dsk_write` (disk.asm: DSKCON op 2 and 3, new). A sector on a disk no drive holds raises the **prompt**.
* **The prompt** switches the GIME to the CoCo's own text screen (a 32 by 16 screen in a spare block, `$3E`; the video start is the SAM's F bits, because the CoCo mode takes only the upper bits from `$FF9D`; 192 lines; palette registers 4 and 5 green on black), says `INSERT DISK n IN THE SECOND DRIVE, THEN PRESS ENTER` (the drives are named first to fourth: Disk BASIC counts them from 0, XRoar from 1), waits for ENTER (or a key 1 to 4: how many drives the player has), looks at the drive named and then at every other one the engine knows of for the disk (after a failed try, at all four), and puts the game's screen back. A second try says what it found (`NO DISK OF THE GAME THERE`, or `THAT WAS DISK n`). Typed-ahead keys are thrown away first. The drive count is learnt at boot: a disk of the set in the second, third and fourth drive makes two, three or four drives.
* Drives: with one drive every change of disk is a swap and disk 1 is swapped out too. [?] whether a real CoCo with one drive tolerates the probe of drive 1 at boot (`DSKCON` on a drive that is not there).
* `SCRATCH` of img.c moved from `$0600` (Disk BASIC's variables, which DSKCON needs) to `dsk_buf`; the floppy volumes of 8.4 and RS-DOS reader were compiled out of the game's engine (they are the engine tests'): about 2.4 KB freed (`vol.o` 2,372 to 1,214 bytes, `rsdos.o` 947 to 19, 272 bytes of FAT buffers), and the new code takes about 2.2 KB (`flop.o` 1,874 + 136 + 76 of variables, `sdc.o` 133). **The engine has about 70 bytes left** (`$7C4A` of `$7C90`; the test-only `dax_find` and `gfx_font_load` were compiled out of the game build for the room).

### 2.3 What was found on the way

* `k_fill` (and the other kernels that use `FC_X`) must not be called from anything a bank load can run: the far call trampoline keeps the entry it is to call in `FC_X` across `api_bankload`. The prompt's first version cleared its screen with `k_fill`, so the next bank load ended in a jump to `$A004`. **Symptom: the game loaded a saved game, then ran `RunScriptFrom(0)` for ever** (`SkipAreaScriptLoad` set, the script never initialised). Found by comparing the harness's engine call sequence, the data of every `SaveRead`/`DaxRead`, then the entry sequence of the trampoline with the development backend's; the data were identical all the way, the control flow was not.
* MAME's GIME shows 200 lines in the CoCo mode when `$FF99` says so: two more rows of what lies behind the text screen.

### 2.4 Verification [V]

`make floppy-check` plays every session on the disks (five at a time, two drives, the harness mounts the disk the prompt names) and compares the labelled screens and the files the game wrote with the development run's. All 16 sessions play on the final set of 12 disks: **every labelled screen equals the original's and every file the game wrote equals the development run's** (character creation, the camp save, the saved-game load). The swaps the player would have made, per session (disk 1 is in drive 0 and disk 2 in drive 1 when the game starts; every prompt is a swap): boot-title 8, walk-explore 17, camp-save 18, character-view 18, camp-magic 20, character-menu 21, create-character 21, shop-buy 21, camp-rest-combat 22, camp-cast 26, temple-cast 26, parley-combat 123, battle-aftermath 127, temple-heal 133, combat-spells 176, council-guards 175: 952 in all (the simulation of the layout said 1,044).

Two harness changes were needed, neither a defect of the engine: the session driver (a) stops typing while the engine asks for a disk, and (b) on the disks waits until the game has waited for a key for 3 s and 4 s have passed since the last key, because a load takes minutes where the harness's storage takes none: a key typed 0.2 s after `E` for camp was lost while the camp menu loaded, so the rest never started (probably the game empties the keyboard when a menu is built [?]; the development backend never showed it because the menu is up in less than 0.2 s). The combat sessions need 4,500 emulated seconds (`MB_LIMIT`) instead of 2,500.

## 3. Which entry goes on which disk

The order of the entries in the image decides what is on which disk, so the layout is an ordering problem (`tools/mklayout.py`). The measure is the **swaps** a session would make with the drives the engine uses (disk 1 pinned in drive 0, LRU for the rest), simulated over the storage traces of the 16 sessions (`make floppy-traces`; kept as `data/floppy_runs.json`, entry names in the order read, 7,867 accesses).

* The sessions read 276 of the 1,286 entries (37 % of the bytes of an image without shared blocks): every code bank but three, the core, DGROUP, the town's tilesets. The rest (the other seven tilesets, the wilderness, the ending) no session touches. Those are placed by what the files say (an area's files together) and by content (the blocks the eight tileset families share are stored once on a disk).
* Algorithm: simulated annealing over the disk of every entry a session reads, with the disk's capacity (bytes after sharing identical blocks on the disk, `POOL.BIN` and the index out of disk 1, the save area on its own disk), cost = swaps for two drives + 0.2 for one and for three drives + 0.15 for a visit of each area (so an area stays together).
* Against the order of the PC's files (alphabetical, boot objects first):

| layout | disks (data + saves) | swaps of the 16 sessions, 2 drives | per session | 1 drive | 3 drives | 4 drives |
|---|---|---:|---:|---:|---:|---:|
| the PC's order (alphabetical, boot objects first) | 10 + 1 | 2,513 | 157 | 2,878 | 514 | 426 |
| annealed (`make floppy`) | 11 + 1 | **1,044** | 65 | 2,831 | 118 | 82 |

Leave one session out (optimise on the other 15, count the swaps of the one): **55 swaps a session** held out against 65 in sample (the spread is large: 9 for `boot-title`, 145 for `parley-combat`), so the layout is not an artefact of the 16 traces. 65 swaps in a five minute session is still one every five seconds: without compression no layout makes a two-drive floppy player happy, because the working set of a session (310 KB of code banks and 290 KB of data) is four disks. Four drives bring it to 82 swaps over all sixteen sessions.

## 4. The CoCo SDC file

`tools/mkimage.py --sdc` writes `build/sdc/POOL.DSK`: **630 sectors of 35 track RS-DOS disk** (`POOLSDC.DAT` as the marker, `POOL.BIN`), then the game's image (shared blocks stored once). 6,235 sectors = 1.6 MB, which the SDC treats as a hard disk image (more than 2,880 sectors): Disk BASIC sees only the first 630. The engine reads the image with the SDC's own sector commands (`src/engine/sdc.asm`): `$43` to `$FF40` (command mode), the sector number to `$FF49` and `$FF4A:$FF4B`, `$80` + drive to `$FF48` (read; `$A0` write), wait for the ready bit, 128 word transfers from `$FF4A`, wait for the end, `$00` to `$FF40`. No swaps: **the image is one file**. [?] The one thing nobody here has run: whether a real SDC boots drive 0 from the first 630 sectors of a hard-disk-size image (the User Guide says floppy mode reaches the first 1,440 sectors of such an image), and mounts it with `DRIVE 0,"POOL.DSK"` or a `STARTUP.CFG`. If it does not, the fallback is two files (`POOL.DSK` the 630 sectors as a normal disk in drive 0 and `POOL.IMG` the image on drive 1) and the engine would use drive 1 for the command (one byte: `$81`); the driver and the image are the same.

[M] `lua/watch.lua` (`MB_SDC`) models the registers; the engine's driver runs against it in MAME and every session plays on it. All 16 sessions play from the file on the model: every labelled screen equal to the original's, and the sectors the game wrote equal to the development run's (`make sdc` then `scripts/sdc_all.sh`). The sessions that fail on the disks for timing reasons play unchanged here, which is the point of the single file. It proves the driver does what the sources say, **not** that the card does: that is the first thing to run on a real machine.

## 5. Compression, as an experiment

`tools/compexp.py` computes, for every entry, what it would take stored three ways; `tools/mklayout.py make --sizes ... --scheme ...` lays the disks out for those sizes. **Nothing in the engine decodes anything yet**: these are the numbers a decoder would have to earn. The decoders are those of 8.9b (ZX0: 68 cycles an output byte, 25.6 KB/s of output on the emulated 6809).

Sizes by entry, all 1,286 entries (no shared blocks): as stored 1,613 KB; ZX0 of those bytes 951 KB; ZX0 of the unpacked blocks 840 KB (2,944 KB unpacked). The layouts (annealed, 60,000 steps; "data disks" are those holding anything but the saves):

| stored as | data disks | swaps, 2 drives (16 sessions) | held out, per session | 3 drives | 4 drives |
|---|---:|---:|---:|---:|---:|
| as now (RLE of the original, banks raw) | 11 | 1,044 | 55 | 118 | 82 |
| ZX0 of those bytes (RLE inside) | 7 | **128** | 12 | 33 | 33 |
| ZX0 of the unpacked block | 5 (two small ones left over) | **47** | 5 | 32 | 32 |

The reading and decoding of the reads of a session (average of the 16, in seconds; the swaps, which are a person's, are not counted; decoder speeds from 8.9b):

| stored as | read KB | floppy 12.6 KB/s | DriveWire 11 KB/s | SDC 100 KB/s [E] |
|---|---:|---:|---:|---:|
| as now | 2,648 | 221 s | 252 s | **33 s** |
| ZX0 of those bytes | 1,189 | 212 s | 226 s | 127 s |
| ZX0 of the unpacked block | 1,163 | **204 s** | **218 s** | 121 s |

What this says:

* **Compression is worth it on floppies and on DriveWire, for the swaps.** It cuts the swaps a two-drive floppy player makes in a five minute session from about 65 to between 3 and 8, and the data disks from 11 to between 5 and 7. The 8 percent saved in load time is a rounding error next to one swap (10 to 20 s of a person's time).
* **It is not worth it on the SDC**: the decoder, not the card, becomes the bottleneck (121 s against 33 s a session), and there are no disks to save. The SDC build keeps the data as it is.
* **Unpacking first and recompressing (ZX0 of the unpacked block) beats ZX0 of the original's RLE** on size and swaps, and costs the same time, and the engine would no longer need the RLE decoder for data (`rle.asm`, about 100 bytes). It still needs a ZX0 decoder of about 200 bytes where 67 are free: something would have to give way (8.9b lists the candidates).
* A single drive stays bad whatever is done: 2,169 swaps over the 16 sessions with ZX0 of the unpacked block, 135 a session.

So the build options are: floppy set with ZX0 (6 to 8 disks and 3 to 8 swaps in five minutes), SDC file as now, DriveWire as the floppy set. **Not built**: the decoder in the engine, the packer's `--compress` and the load path for it; `make floppy-layout` only lays out for the sizes of today.

## 6. DriveWire

* The floppy set is the DriveWire build: HDB-DOS and DriveWire's ROM answer `DSKCON`, and a DriveWire server mounts a `.dsk` in each of its drives. **With four drives a set of four disks needs no swap at all**; more disks are asked for by `dw disk insert n file` on the server (or, with a DriveWire 4 named object, by the game one day: OP_NAMEOBJ_MOUNT).
* A DriveWire driver of its own (the serial protocol from the bit banger) would give the single image and no swaps, as the SDC's does. It is worth doing only for speed: at 115,200 bps a sector costs about 23 ms on the wire. [E] Not started; XRoar's Becker port with pyDriveWire is the way to test it.

## 7. Open

1. A real CoCo 3 with a real disk drive, a real SDC (section 4), a real DriveWire: nothing of this step has run on hardware. DSKCON at 0.89 MHz around each read is as in 8.3; the 6309 case is as in 8.9h.
2. The **interleave** of the written disks. MAME's `.dsk` image has the sectors in order, and `DSKCON` reads one at a time: about 8 sectors a second. A disk formatted by `DSKINI` has its own skip factor; writing the images to real disks must keep the order of the file's sectors on the track as Disk BASIC would (research 03: 12.6 KB/s).
3. The layout is made from 16 scripted sessions; the player's real play is longer. A layout from more sessions (the wilderness, the ending, the other seven tilesets) is the way to improve it; `make floppy-traces` and `make floppy-profile` do it.
4. **XRoar**, found by the first player to try it (`make floppy-xroar` starts it): with disk 1 in the first drive only, the first prompt asked for disk 3 in the first drive (the engine assumed one drive, and the layout wanted disk 3 first), and putting disk 3 in the drives did not get past it. Not reproduced here (the harness answers in MAME; a real ENTER through the emulated keyboard works there, and the four drives read in XRoar headless). What was changed: the first disk the sessions ask for is now disk 2, the prompt names the drive as first to fourth instead of 0 and 1, looks at all drives, retries a disk that was just put in and says what it found. If it still loops, the second line of the prompt tells which disk it read. Run it from a copy of the disks: XRoar writes back to the image files it has loaded.
5. The prompt: the text is plain. A picture of which disk is which (the label to write on the disk) belongs to the box, not to the engine.

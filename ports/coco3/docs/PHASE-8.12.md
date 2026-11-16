# Step 8.12: the SuperIDE build (the game on a CompactFlash card, no disk swaps)

Date: 2026-10-25. Follows `docs/PHASE-8.11.md`; the third medium behind `sec_io` (decision D13), after the floppy set and the CoCo SDC file of `docs/PHASE-8.10.md`. Tags: **[V]** measured by running it in MAME, **[M]** proven only against a model of the hardware that this step wrote, **[E]** estimate from cycle counts, **[?]** open.

## 1. What it is

A build of the game for a CoCo 3 with a Cloud-9 **SuperIDE** (or a Glenside IDE interface) and a CompactFlash card or IDE drive on it. The engine reads the game's image straight off the card through the interface's registers: the whole image is on the card, so **there is nothing to swap and no disk is ever asked for**. `make ide` builds it:

| File | What |
|---|---|
| `build/ide/POOLIDE.IMG` | 3,780 card sectors (1.9 MB): one HDB-DOS virtual drive with `POOL.BIN`, then the game's image, filled up to whole drives with zeros |
| `build/ide/POOLBOOT.DSK` | the same boot drive as a plain 35 track disk file (an emulator, an SDC, DriveWire) |
| `build/ide/engine/POOL.BIN` | the engine with the IDE driver (the rest of the game, the core and the 27 banks, is `make game`'s and is in the image) |
| `tools/ide_card.py` | puts `POOLIDE.IMG` on the card from a card reader, without touching anything that is in use |

## 2. Why raw card sectors, and not HDB-DOS's drives

HDB-DOS gives the CoCo up to 256 "virtual floppy disks" of 630 sectors on the card, each 256 byte sector in the *first half* of a 512 byte card sector (HDB-DOS manual, section 4: it wastes the other half), the first disk at the card's **HDB-DOS offset** (the SuperIDE sheet of this card: `$052DDC` = 339,420 sectors; 339,420 + 256 * 630 = 500,700, the number of sectors of the card). Reading the image through HDB-DOS's DSKCON would keep the swap logic of the floppy build (a disk is a drive number) and waste half the card, and a sector is one DSKCON call at 0.89 MHz. The game's driver does not use HDB-DOS: it talks to the interface itself (registers at `$FF50`, `src/engine/ide_xfer.asm`) and only borrows HDB-DOS to load `POOL.BIN`, the way the SDC build borrows Disk BASIC.

* **Where on the card:** virtual drives 200 to 205 (`IDE_DRIVE=200`), card sectors 465,420 to 469,199. Drive 200 is the boot disk (HDB-DOS can read it: `DIR 200`), drives 201 to 205 hold the image, which HDB-DOS would show as garbage and never touch unless the owner writes there. The sheet says drives 4 (the HDB-DOS disk) and 5 (its backup) are in use and 255 is the NitrOS-9 boot disk, so 200 to 205 are in nobody's way, and the NitrOS-9 partition (496,896 sectors of 256 bytes = 248,448 card sectors, from sector 0) ends far below 339,420.
* **Two game sectors to a card sector, except the saves.** A bank load reads many sectors in a row, so the image is packed two to a card sector (one command moves 16 KB in 32 card sectors, no half left over). The saves area (512 sectors, the last of the image) has a card sector for each (the other half zeros): a save is the write of one sector and a card cannot write half of one. Nothing else is ever written, and **nothing is written before the first sector of the image has said `PIM2`**: a card that is not the game's is left as it is. `ide.c` has the mapping.

## 3. The driver (`src/engine/ide.c`, `ide_xfer.asm`)

* **Detection** (`flop_detect`, called by `img_mount` as for the other media): selects the master, then the slave (device byte `$E0`, `$F0`); a status of `$00` or `$FF` is no device. For each device that answers it enables 8 bit transfers (SET FEATURES `$01`), reads the first sector of the image (card sector `IDE_LBA_BASE`) and looks for `PIM2`; if that fails it goes back to 16 bit words (`$81`) and tries again. So it finds the card as master or slave, in either mode the card has been left in, and falls back by itself.
* **If nothing is found** the engine does not carry on to a hang: the splash screen's text screen says `NO IDE DEVICE ANSWERED`, `THE CARD DID NOT SEND A SECTOR` or `NO GAME DATA AT THE SET PLACE`, with the last status, the device byte, the mode (0 words, 1 bytes) and the first six bytes it read, and stops. That screen is what to send back from a first run.
* **Transfer, the fast way.** In 8 bit mode every read of the data register is the next byte, so a **6309** moves 256 bytes with one `TFM Y,X+` (fixed source, 3 cycles a byte; same instruction family as 8.9j) and a **6809** reads two bytes into A and B and stores them with one `STD` (9 cycles a byte). In word mode (the card's power-up mode, the fallback) a read of `+0` gives the low byte and `+8` (the latch) the high byte, 9 cycles a byte as well. Interrupts are masked for one half of 256 bytes at a time (about 0.5 to 1.8 ms), not for a sector or a command: the card waits for the CPU.
* **Multi-sector commands.** A run of sectors is one READ SECTORS command for up to 32 card sectors (16 KB), the data request checked before each sector. A command is retried twice on an error.
* **[E] Speed from cycle counts**, at 1.79 MHz (the engine runs there): 512 bytes cost about 1.0 ms on a 6309 (TFM) and 3.3 ms on a 6809, about 500 and 150 KB/s of transfer, before the card's own latency for the first sector of a command. The SDC's estimate in 8.10 was 100 KB/s. A session reads 236 KB of code on average since 8.11 (`make io-budget`), so a bank load is milliseconds and the long waits of the floppy build are gone. **Not measured on a card.**
* **Speed risk [?]:** some interfaces cannot keep up with `/IOR` at 1.79 MHz. If the error screen comes up with mode 1 and a status of `0` and garbage in the first bytes, `make ide IDE_SLOW=1` makes the driver switch the CPU to 0.89 MHz for the length of each call (`$FFD8`/`$FFD9`).

## 4. What was tested, and what was not

[M] Everything below is the engine's driver against `lua/watch.lua`'s model of the interface (`MB_IDE`), written from the SuperIDE manual's register list and the ATA PIO protocol: busy for a read of the status after a command, then data request; 8 bit transfers on and off; the word mode with the latch; a device selected as master or slave; saves written through WRITE SECTORS. There is no SuperIDE in MAME. It proves the driver does what the manual and ATA say, **not** that the card does.

**All 16 sessions play from the card file on the model** (`make ide-check`, 10.5 minutes of real time, five at a time): every labelled screen equals the original's and the sectors the game wrote (the saved game of `camp-save`, 77 sectors, the new character of `create-character`, 5) equal the development run's. The same tests on the variants of the model, on `boot-title` and `camp-save`: a **6309** (MAME's `coco3h`, where the engine's `_cpu6309` is 1: the TFM path; on `coco3` it is 0: the 6809 path), a card that **refuses 8 bit transfers** (`MB_IDE_NO8=1`: the engine falls back to words and the latch, saves written the word way), a card that is the **slave** (`MB_IDE_SLAVE=1`). All pass, and the saves of the variants equal the development run's. A card whose game data is not where the engine looks (`IDE_LBA0` off by one) gives the error screen of section 3 (`NO GAME DATA AT THE SET PLACE`, status 00, device E0, mode 00). The standard build's `POOL.BIN` is byte for byte what it was before this step.

## 4b. First run on a real SuperIDE [V]

2026-10-25, the owner's CoCo 3 (**a stock 6809**, not the 6309 it was thought to have), a Cloud-9 SuperIDE with HDB-DOS 1.1D (LBA) in flash and a 256 MB CompactFlash card, written with `tools/ide_card.py` (drives 200 to 205). **It worked the first time**: `DIR 200` listed `POOL/BIN`, `LOADM"POOL/BIN:200":EXEC` showed the splash with `LOADING...PLEASE WAIT`, then the SSI title, the code wheel prompt, the character menu, a saved game loaded (the seeded party of six in the town), a walk to a random encounter ("You spy a group of seedy-looking orcs", "A battle begins...") and a fight played on (movement, aim, attacks and misses) with the screens correct, in a three minute video (frames every 6 s: the boot from `EXEC` to the title is under 20 s, the saved game from the menu to the town about 20 s, the battle from "A battle begins" to the combat screen about 10 s). The owner's words: it "worked seamlessly in the first try" and "the performance is really good".

What that proves on the card: the card layout and the HDB-DOS offset of the sheet, the boot drive that HDB-DOS loads `POOL.BIN` from, the detection, the read path through the interface registers **on a 6809** (two reads and one `STD` in 8 bit mode, or the word mode: the screen does not say which the card used), the packed layout (two game sectors to a card sector) and the multi-sector commands, at 1.79 MHz without `IDE_SLOW`. Not yet seen on hardware: the 6309 TFM path, a **write** (a save, and a load of it after a power cycle), the slave position.

## 5. Putting it on the card and playing it

You need: a card reader on the Mac, the CF card of the SuperIDE, a CoCo 3 with 512 KB, the multi-pak with the SuperIDE in a slot (the sheet's example: slot 1, switch on 1: **the slot switch must stay on the SuperIDE**, it is the slot that gets `$FF40` to `$FF5F`; the SDC and the floppy controller are not used).

```bash
make ide                                    # about a minute: rebuilds the game, then the IDE engine and the card file
```

Back the card up first (the file is only 1.9 MB but a wrong offset would damage something that is not):

```bash
diskutil list                               # find the CF card: say /dev/disk4
diskutil unmountDisk /dev/disk4
sudo dd if=/dev/rdisk4 of=superide-backup.img bs=1m
sudo python3 tools/ide_card.py map /dev/rdisk4        # read only: which of the 256 drives hold something, and a free run to use
make ide IDE_DRIVE=200                                # only if map shows 200 to 205 are not all free: the number it suggests
sudo python3 tools/ide_card.py check /dev/rdisk4      # read only
sudo python3 tools/ide_card.py write /dev/rdisk4 --yes
```

**Where the game goes is decided in one place:** `IDE_DRIVE` (and `IDE_HDB_OFFSET`) of `make ide`. It is baked into `POOL.BIN` (the card sector the engine reads) and written to `build/ide/ide.env` next to the card file, which `ide_card.py` reads, so the tool writes exactly where the engine will look; if told another drive or offset it refuses. `map` reads all 256 drives (82 MB) and shows each as `.` blank (every sector all zeros or all `$FF`), `e` a **formatted disk with no files** or `#` in use. HDB-DOS writes a label sector (track 17 sector 17, `<DRIVE`) and a little bookkeeping on every drive it has set up, so almost every unused drive of a card has two sectors that are not uniform; the tool reads each drive as RS-DOS does (the allocation table says all 68 granules are free and no directory entry is a live file) and calls such a drive `e`, free. A drive with a file, or with anything that is not an RS-DOS disk, is `#`, and `map` lists the names in its directory. `check` and `write` look at the six drives of the file again and refuse unless each is `.`, `e` or already the game's.

`check` prints the size of the card (it must be 500,700 sectors for the HDB-DOS offset the sheet gives, and the tool says so otherwise), proves the offset by reading the directory of virtual drive 4 (it must show the HDB-DOS disk's files), and says whether drives 200 to 205 are free (all zeros or all `$FF`). `write` refuses unless all three hold (`--force` overrides, the drives' data is lost) and reads everything back. If the card is another size, `--hdb-offset N` takes the number from its own sheet, and `make ide IDE_HDB_OFFSET=N` builds for it.

Then, with the power **off** (the manual: never insert or remove the card with the power on): put the card in the SuperIDE, the SuperIDE in the multi-pak, switch on. HDB-DOS boots from its flash bank. At the `OK` prompt:

```
DIR 200                                     (should list POOL/BIN: proves the drive)
LOADM"POOL/BIN:200":EXEC
```

(HDB-DOS names a drive after a colon, `filename/ext:drive`, and drives 4 to 255 are always the card.) The splash screen with its progress bar comes up; the bar moves as the engine reads the card; the game starts as in `make play`. A save goes to the card (and is kept there: switch off, switch on, load).

**Adding a saved game to the card** (2026-11-14). An update keeps the card's saved games and drops the build's own, so a saved game from the PC (a SAVE folder's `SAVGAMx.DAT` and `CHRDATx*.*`) is put in with `--add-slot x`: its files get rooms in the save area's directory the way the game gives them, next to the card's saves. A slot the card already has is refused unless `--replace-slot` (the card's files of that slot are lost); the same files again are left alone. `--saves-from DIR` takes them from another SAVE folder than the game folder's (`poolrad/SAVE`). `saves` lists a save area, on the card or in a card file, read only:

```bash
sudo python3 tools/ide_card.py saves /dev/rdisk4                  # read only: the saved games on the card and the free room
sudo python3 tools/ide_card.py write /dev/rdisk4 --add-slot F --yes
```

Checked on a file of the card's size (an older build with a player's saves A and C, then the update: A and C byte for byte as before, the 19 files of F equal to the SAVE folder's, 100 of 512 units left; a different F refused without `--replace-slot`), and the IDE build in MAME (`MB_IDEFILE`) loaded F from that save area. A saved game takes up to 130 units (60 for the `.DAT`, 10 for each character), and the area has 512.

**Taking a saved game back to the PC** (2026-11-15). `pull DEVICE X` is the other direction, and it only reads the card: the files of slot X in the save area (`SAVGAMX.DAT`, `CHRDATX*.*`) are written to `--to DIR` (default `poolrad/SAVE`) unchanged, since the CoCo saves in the PC's byte order (8.6). This is how a game played on the CoCo carries on in the DOS port on the Tandy 1000. A folder that already has the same files is left alone. A folder with other files of that slot is refused unless `--replace-slot`, which first moves all of them (a `CHRDATX8` of a larger old party too) to `build/save-backup/X-<date>-<time>/`. Under sudo the new files are given to the user who ran it. Checked by `tests/unit/test_coco3_ide_pull.py` (a card file and a small card with the game at drive 2) and on the build's own card file (slot A pulled equal to `poolrad/SAVE`'s).

```bash
sudo python3 tools/ide_card.py pull /dev/rdisk4 F                 # into poolrad/SAVE; --to DIR for another SAVE folder
```

If something is wrong the engine says what (section 3). What to send back: the three lines of the error screen, or what `DIR 200` printed.

## 6. Open

1. **Real hardware** was checked once (4b): the three things it could have got wrong without the model knowing all went right for a read; what is left is the 6309 path, a save written to the card and read back after a power cycle, and which mode (bytes or words) the card used. The three things it could have got wrong: (a) the card refusing 8 bit transfers *and* the latch working differently from the manual's one line (then the first read fails and the screen says so); (b) the interface being too fast for `/IOR` at 1.79 MHz (`IDE_SLOW=1`); (c) HDB-DOS 1.1D's virtual drives not being at `offset + n * 630` (`ide_card.py check` proves the offset on the reference drive before anything is written; if the directory of drive 4 does not show, it refuses).
2. The word-mode **write** (only used when the card refuses 8 bit transfers): high byte to the latch first, then the low byte to the data register, which is the usual order of 16 bit IDE latches but is not in the SuperIDE manual.
3. The IDE medium is its own build (the engine has no room for the disks and the SDC with it: `ide.c` replaces `flop.c` and `sdc.asm`; the standard build is unchanged). One engine with all three would need the 8.11 code residency to free bytes.
4. After a re-banking (`make rebank`) nothing here changes: the card file is made from whatever `make game` built.

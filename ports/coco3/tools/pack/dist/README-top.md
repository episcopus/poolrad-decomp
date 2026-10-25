# Pool of Radiance for the Tandy CoCo 3: the builds

Six ways to play the same game, one folder each. **Pick the one that matches what you have.** Every folder has its own README with the steps.

| Folder | For | Disks / files | Swaps while playing |
|---|---|---|---|
| `01-floppy-35track` | a real CoCo 3 with 2 to 4 floppy drives, or any emulator (XRoar, MAME, VCC), or DriveWire | 12 disks of 35 tracks (the standard RS-DOS disk) | some: the game asks for a disk by name (about 20 in a long session with 2 drives) |
| `02-floppy-80track-xroar` | XRoar (4 drives), or 80 track drives | 5 disks of 80 tracks | almost none with 4 drives (the 5th disk holds the saved games) |
| `03-coco-sdc` | a CoCo with Darren Atkinson's **CoCo SDC** (SD card) | one file | none |
| `04-superide-card` | a CoCo 3 with a **SuperIDE / Glenside IDE** interface and a CompactFlash card | one card file + the tool that writes it | none |
| `05-xroar-ide` | **XRoar** on a PC or Mac, the simplest way | one data file + a launcher | none |
| `06-mame-ide` | **MAME** (`coco3`) | one data file + a launcher | none |

What every build needs
* A CoCo 3 with **512 KB** (real or emulated). The game does not run on 128 KB.
* An RGB monitor (or the emulator's RGB setting) for the right colours.

What is not in these folders
* **The firmware** of the CoCo 3 and Disk BASIC (`coco3.rom`, `disk11.rom` for emulators): Tandy's, not ours to give. Emulators need it in their ROM folder.
* Nothing needs the original DOS game files: they are inside the disks and card files.

**These folders contain the game's data (art, maps, text) and are for your own use. Do not post them.** See the project's README on why the public repository does not contain them and how everyone makes their own from a copy of the original game.

Where things stand (see `docs/PHASE-8.10.md`, `PHASE-8.11.md`, `PHASE-8.12.md` in the project)
* Every build was played through 16 recorded test sessions (character creation, shopping, camping, combat, saving) in MAME or XRoar and matches the original screen for screen.
* The SuperIDE build was played on a real CoCo 3 with a SuperIDE and worked the first time. The CoCo SDC driver was proven against a model of the hardware; the XRoar and MAME IDE packs against those emulators' own IDE adapters. Real hardware reports are welcome.

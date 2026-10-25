04-superide-card: one file on a CompactFlash card (SuperIDE / Glenside IDE)
===========================================================================

What this is
  POOLIDE.IMG (1.9 MB) goes onto the CF card of a SuperIDE (Cloud-9) or Glenside IDE interface: a boot drive that HDB-DOS loads POOL.BIN from, and the whole game behind it. The game talks to the interface itself, so there is nothing to swap. POOLBOOT.DSK is the same boot drive as a plain disk file (for an emulator, an SDC or DriveWire).

THIS BUILD IS FOR ONE CARD. It was made for HDB-DOS offset 339420 (a 256 MB card) with the game in HDB-DOS drives 200 to 205 (see ide.env). For another card, rebuild with the project's `make ide IDE_HDB_OFFSET=... IDE_DRIVE=...` (docs/PHASE-8.12.md).

Putting it on the card (macOS/Linux, with a card reader)
  1. BACK THE CARD UP FIRST:   sudo dd if=/dev/rdiskN of=card-backup.img bs=1m      (N: the card; diskutil list)
  2. Look at the card, read only:   sudo python3 ide_card.py map /dev/rdiskN
     and:   sudo python3 ide_card.py check /dev/rdiskN      (it must say the drives are free)
  3. Write:   sudo python3 ide_card.py write /dev/rdiskN --yes     (it reads everything back)
     ide_card.py reads ide.env from this folder: it writes exactly where the game will look and refuses anything else.

Playing it
  Put the card in the SuperIDE (the multi-pak slot switch on the SuperIDE; it must stay there while you play) and start HDB-DOS from it. Then:
      DIR 200                          (it should list POOL/BIN: that proves the drive)
      LOADM"POOL/BIN:200":EXEC
  The splash says LOADING...PLEASE WAIT, then the title comes up. No disk is asked for. (If you rebuilt with another IDE_DRIVE, use that number instead of 200.)
  If the game cannot find the card it says so on screen (NO IDE DEVICE ANSWERED, NO GAME DATA AT THE SET PLACE) with the device status: send the text. On an interface that cannot keep up, the project's `make ide IDE_SLOW=1` build runs the transfers at 0.89 MHz.

Known limits
  Played on one real machine (a stock 6809 CoCo 3, a Cloud-9 SuperIDE with HDB-DOS 1.1D, a 256 MB card): it booted at the first try and a saved game, a walk and a fight played. Not yet seen on hardware: writing a saved game and reading it back after a power cycle, a 6309 CPU, a card as the slave. Also proven in MAME and XRoar's IDE emulation (see 05 and 06).

03-coco-sdc: one file on the SD card
=====================================

What this is
  POOL.DSK, one file of 1.6 MB: a bootable 35 track disk at its start (it holds POOL.BIN) and the whole game behind it. The game reads its data through the CoCo SDC's own commands, so there is nothing to swap.

You need
  A CoCo 3 with 512 KB and a CoCo SDC (Darren Atkinson's SD card interface) with its SDC-DOS.

Playing it
  1. Copy POOL.DSK to the SD card.
  2. On the CoCo, mount it as drive 0:   DRIVE 0,"POOL.DSK"    (SDC-DOS; or put it in a STARTUP.CFG)
  3. Type:   LOADM"POOL":EXEC     and press ENTER.
  The game loads in about a minute and plays without disk prompts. Saved games are written into POOL.DSK itself: keep a copy to start over.

Known limits
  The SDC driver was written from the SDC User Guide and proven against a model of the registers in MAME, not (yet) a report from every hardware version. If the game stops on boot with an error text, send the text.
  VCC simulates the SDC but its command mode is not documented: use the XRoar or MAME builds there.

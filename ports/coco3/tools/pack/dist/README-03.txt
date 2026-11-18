03-coco-sdc: one file on the SD card
=====================================

What this is
  POOL.DSK, one file of 1.6 MB: a bootable 35 track disk at its start (it holds POOL.BIN) and the whole game behind it. The game reads its data through the CoCo SDC's own commands, so there is nothing to swap.

You need
  A CoCo 3 with 512 KB and a CoCo SDC (Darren Atkinson's SD card interface) with its SDC-DOS.

Playing it
  1. Copy POOL.DSK to the SD card.
  2. On the CoCo, mount it as drive 0:   DRIVE 0,"POOL.DSK"
     To have it mounted at every start instead, put the line   0=POOL.DSK   in a file named STARTUP.CFG at the top of the card. STARTUP.CFG.example in this folder is that
     file; copy it only if the card has no STARTUP.CFG of its own (it would replace yours), otherwise add its line to yours.
  3. Start the game. POOL.DSK holds an AUTOEXEC.BAS, so a Disk BASIC that runs one at start-up loads the game by itself. If yours does not, type:
     LOADM"POOL":EXEC     and press ENTER.
  The game loads in about a minute and plays without disk prompts. Saved games are written into POOL.DSK itself: keep a copy to start over.

Known limits
  The SDC driver was written from the SDC User Guide and proven against a model of the registers in MAME, not (yet) a report from every hardware version. If the game stops on boot with an error text, send the text.
  VCC simulates the SDC, but not everything of it, and its command mode is not documented. A report says this build starts on VCC for Android; it is not confirmed on every VCC. If it does not start there, send what the screen says, or use the XRoar or MAME builds.

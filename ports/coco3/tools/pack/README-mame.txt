Pool of Radiance for the Tandy CoCo 3, in MAME (one data file)
==============================================================

Files
  POOLIDE.chd     the whole game on a (virtual) IDE hard disk: 770 KB, the only data file; the game saves into it
  POOL.BIN        the program that starts it (the game's engine)
  mame-boot.lua   puts POOL.BIN into memory and starts it (MAME has no way to start a program without a disk controller otherwise)
  Play-MAME.command   the command below for macOS (double-click; right-click, Open the first time)

What you need
  MAME 0.28x with the CoCo 3 ROMs in its rom path (coco3.zip or coco3.rom: not part of this pack).

The command (from this folder)
  mame coco3 -ramsize 512K -ext ide -hard3 POOLIDE.chd -autoboot_script mame-boot.lua

Notes
  - `-ext ide` is MAME's Glenside IDE adapter. It takes the slot of the floppy controller, so there is no Disk BASIC: that is what the Lua file is for.
  - MAME writes the saved games into POOLIDE.chd. Keep a copy to start over.
  - The picture is for an RGB monitor (the Lua file sets it).

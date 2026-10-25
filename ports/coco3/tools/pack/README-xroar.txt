Pool of Radiance for the Tandy CoCo 3, in XRoar (one file)
==========================================================

What is in this folder
  POOLIDE.IMG   the whole game on a (virtual) IDE hard disk: 1.9 MB, the only data file; the game saves into it
  POOL.BIN      the program that starts it (the game's engine)
  Play.command  starts XRoar with both (macOS: double-click; if macOS refuses, right-click, Open)
  roms/         put the CoCo 3 ROM here: coco3.rom (XRoar's own ROM folder works too: ~/.xroar/roms)

What you need
  XRoar 1.x (https://www.6809.org.uk/xroar/; on a Mac: brew install xroar) and the CoCo 3 ROM (coco3.rom), which is not part of this pack.

Playing it with the mouse (no command line)
  1. Start XRoar. Hardware > Machine > Tandy CoCo 3 (it is the 512 KB machine).
  2. Hardware > Cartridge > IDE Interface. (The machine restarts.)
  3. File > HD 0 > Insert... and choose POOLIDE.IMG.
  4. File > Run... and choose POOL.BIN. The game starts by itself.
  5. Hardware > RAM pattern: clear, if XRoar offers it (the game expects a cleared memory; the command line below does it for you).
  6. View > TV input: RGB gives the right colours (the game is made for the CoCo 3's RGB monitor).
  Everything is on the one file: there are no disks to swap. Keep a copy of POOLIDE.IMG if you want to start over; the saved games are in it.

Playing it from the command line (the same thing)
  xroar -m coco3 -ram-init clear -tv-input rgb -cart ide -load-hd0 POOLIDE.IMG -run POOL.BIN

02-floppy-80track-xroar: four big disks, almost no swapping
============================================================

What this is
  The same game on 80 track disks (POOL01.DSK ... POOL05.DSK, 368,642 bytes each: JVC images with a 2 byte header). Disks 1 to 4 hold the game and fit in XRoar's four drives, so nothing is swapped while you play. Disk 5 holds the saved games and is asked for when the game saves or loads (and once at the start).

You need
  XRoar 1.x with the CoCo 3 ROMs, or a real machine with 80 track drives (rare on a CoCo). These images do NOT work on a standard 35/40 track drive.

Playing it in XRoar
  xroar -m coco3 -ram-init clear -tv-input rgb -cart rsdos -load-fd0 POOL01.DSK -load-fd1 POOL02.DSK -load-fd2 POOL03.DSK -load-fd3 POOL04.DSK -type 'LOADM"POOL":EXEC\r'
  When the game asks for disk 5: File > Drive n (the drive it names, counted 1 to 4 in XRoar) > Insert disk... > POOL05.DSK, then press ENTER in the game.

Known limits
  Not played through in XRoar yet (it boots and reads past track 45). In MAME with 80 track drives (-ext:fdc:wd17xx:0 525qd) two long sessions stopped on a read of track 63: use 05-xroar-ide or 06-mame-ide instead. Not tried in VCC (its FD-502 takes 80 track JVC images).

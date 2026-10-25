01-floppy-35track: the standard floppy disks
============================================

What this is
  The game on 12 ordinary 35 track disks (POOL01.DSK ... POOL12.DSK; 161,280 bytes each, JVC/DSK raw images). Disk 1 starts it. Disk 12 holds the saved games.
  The game keeps the disks it uses most in the drives and asks for another by number when it needs one.

You need
  A CoCo 3 with 512 KB and Disk BASIC 1.1, with 2, 3 or 4 floppy drives (more drives, fewer swaps), or an emulator that gives the CoCo 3 floppy drives (XRoar, MAME, VCC), or a DriveWire server.

Playing it
  1. Put POOL01.DSK in drive 0 and POOL02.DSK in drive 1 (with more drives, POOL03.DSK in drive 2 and POOL04.DSK in drive 3: the fewer the swaps).
  2. Type:   LOADM"POOL":EXEC     and press ENTER.
  3. The game starts. When it needs a disk that is not in a drive it shows a text screen: INSERT DISK n IN THE (FIRST, SECOND...) DRIVE, THEN PRESS ENTER. Do that and press ENTER. The drives are called first to fourth there (Disk BASIC calls them 0 to 3; XRoar 1 to 4).
     If the game asks for disk 12 when you save or load a game, that is the disk with the saved games: keep it writable (no write-protect tab).
  4. If the game keeps asking for the same disk, press 1, 2, 3 or 4 to tell it how many drives you have.

XRoar:    xroar -m coco3 -ram-init clear -tv-input rgb -cart rsdos -load-fd0 POOL01.DSK -load-fd1 POOL02.DSK -load-fd2 POOL03.DSK -load-fd3 POOL04.DSK -type 'LOADM"POOL":EXEC\r'
          (disks are asked for with File > Drive n > Insert disk...)
MAME:     mame coco3 -ramsize 512K -flop1 POOL01.DSK -flop2 POOL02.DSK   then type LOADM"POOL":EXEC  (swap with the Tab menu, File Manager)
DriveWire: mount POOL01.DSK ... POOL04.DSK in the server's drives 0 to 3 (dw disk insert 0 POOL01.DSK ...). Not tested here.

Known limits
  Loading from a floppy is slow (the game reads about 4 KB/s through Disk BASIC): the first screens take a minute, and a fight takes about half a minute to load the first time. Use the other builds for comfort.

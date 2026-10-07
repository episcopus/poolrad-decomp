# poolrad/: your copy of the game

Put the files of your own copy of Pool of Radiance for DOS, version 1.3, here: `START.EXE`, `GAME.OVR`, `ITEMS`, `CFG.EXE`, `POOL.CFG` and every `*.DAX` file, at the top of this folder. Nothing in this folder except this note is tracked by git (`.gitignore`), and none of it may be committed.

`make inputs` compares each file with the size and SHA-256 recorded in `re/inputs.toml`. The project targets one release; if a file differs, the matcher and the rebuild will not agree with it.

Some tools also need the unpacked image `start-unpack.exe` (`START.EXE` is EXEPACK-packed). `make unexepack` makes it from your `START.EXE` and checks it byte for byte.

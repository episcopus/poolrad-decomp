# Step 8.9i: the start of the game: a clean loading screen, the checks, the progress bar

Date: 2026-10-23. Follows `docs/PHASE-8.9h.md`. Built on the branch `feat/boot-splash`. Tags: **[V]** measured by running it in MAME (the `coco3` 6809 machine, the `coco3h` HD6309 machine, `-ramsize 128K` for the failure), **[E]** estimate.

## 1. What went wrong before: the lifecycle of the start

1. The player types `LOADM"POOL":EXEC`. Disk BASIC's **LOADM** reads `POOL.BIN` record by record and stores each record at its address; the screen is BASIC's own **text screen at `$0400..$05FF`**.
2. The engine's *shared code* (the interrupt handler, the keyboard, the engine call gate: 490 bytes) was linked **at `$0400`**, the one piece of memory that both MMU tasks see and that BASIC does not use. So LOADM wrote the engine's code **into the text screen**, and the VDG showed the bytes as the garbage in the screenshot: from the first record to the moment the game switched the video (several seconds on a real drive, 17 s of emulated time in MAME).
3. `EXEC` jumped to `boot.asm`, which took the machine over (all-RAM mode, GIME, MMU, stack) and read the core and the data from the storage; the screen stayed the garbled text screen until the game's own graphics (`gfx_init`) and its "Loading... Please Wait".

## 2. What it does now

* **The shared code moved from `$0400` to `$1D80..$1F6A`** (`core.link`), above the system stack, which now starts at `$1D80` (`SYSSTK_TOP`; the deepest stack of the 16 sessions reached 4,469 bytes below the old top, so about 520 bytes are left above `$0A00`). BASIC's text screen is nobody's memory but the display's.
* **LOADM draws the splash.** `tools/stripbin.py` (called by `mkgame.py` for the game's BIN only) puts a record at the start of `POOL.BIN` that writes the splash over BASIC's text screen (title, `LOADING...`, the frame of a progress bar), and cuts the engine's 19 KB record into 14 pieces with a one byte record after each that writes a cell of the bar (a cyan semigraphics block): **the bar moves while LOADM loads**, from the first record to the exec.
* **`boot.asm` checks the machine first** (before it changes anything): with BASIC's map still in place it points the MMU's slot 4 at four blocks 128 KB apart (`$00,$10,$20,$30`), writes a distinct byte to each and reads them back: a CoCo 1 or 2 (no MMU) and a CoCo 3 with 128 KB (the blocks repeat every 16) fail it. Then it restores BASIC's slot and ROM mode, clears BASIC's screen, prints `POOL OF RADIANCE NEEDS A COCO 3 WITH 512K RAM` through BASIC's own `CHROUT` (`JSR [$A002]`), and **returns to BASIC** (`RTS`: EXEC is a subroutine call; the stack and BASIC's state are as it left them).
* **It prints what it found**, line by line, as the boot goes: `COCO 3, 512K RAM: OK`, `CPU: 6809 (STOCK)` or `CPU: 6309 (HITACHI), NATIVE` (the detection of step 8.9h), and `STORAGE: DEV (MAME)`. The storage line is the one to extend: today the only backend is the development doorbell of `img.c` (the harness serves the sectors), the real ones (floppy through DSKCON, SDC, DriveWire) will name themselves there.
* **The second half of the bar is the engine's own reading** of the core and the game's data (`sec_io` calls `splash_adv`, a cell every 10 sectors, 148 sectors until the game's first screen), and `gfx_init` calls `splash_off`: the game's own screen takes over.

## 3. Verified [V]

* Snapshots in MAME at the second of the start (`MB_SNAPAT=t1,t2,.. ` in `lua/watch.lua`, `scripts/game_run.sh`): BASIC's screen with the typed command until LOADM's first record, then the splash with the bar growing (14 cells during LOADM), then the lines of the checks, then the game.
* The 6309 machine shows `CPU: 6309 (HITACHI), NATIVE`; `-ramsize 128K` prints the message and leaves BASIC at its `OK` prompt (the splash is cleared, no garbage).
* `make step-check` on the 6809 and on the 6309 machine, and the engine tests: see section 4.

## 4. Numbers and room

| | 6809 machine (`coco3`) | 6309 machine (`coco3h`) |
|---|---|---|
| `make step-check`: 16 sessions, 15 states with 0 DGROUP places open, party records, save area | pass, busy 1,860 s (was 1,848 s) | pass, busy 1,704 s (was 1,692 s) |
| engine tests `t_disk` to `t_task` (11 tests in MAME, 11 in XRoar) | pass (22 of 22) | pass (22 of 22: 11 in MAME's 6309 machine, 11 in XRoar) |

`t_vol2` stops at the build of its test disk in this worktree (full disk, environment, as before). The busy time is 0.65 % higher in both columns: the screen's row address is a `MUL` now instead of a table read (`gfx_item` calls it twice a tile: about 0.07 s for the 3,000 tiles of a menu screen).

**Engine room.** The table of the 200 row addresses of the screen (`rowa`, 400 bytes of the engine's RAM) is gone: `k_row160` (`MUL`, 12 bytes) replaces it where `k_flush` and `k_text` read it, and the C code calls it. That paid for the boot code (checks, three lines of text, the bar, the failure message: about 300 bytes). The engine ends at `$7C49` of `$7C90` (71 bytes left).

## 5. Not covered [E]

* A **real** CoCo 3, 1, 2: the memory test and BASIC's `CHROUT` call are the usual ones, but only MAME ran them. A CoCo 1 or 2 that reads `POOL.BIN` still gets the splash records (they write BASIC's text screen) before the message, and the message goes through the ROM output routine, which both have at `$A002`.
* A loader other than Disk BASIC's `LOADM` (a cartridge, a DriveWire boot, XRoar's `-load-bin`): the splash is made by the file's first records, so there it only appears from `EXEC` on, with the static text missing; the checks still run.
* LOADM's record into I/O space does not work (Disk BASIC reads every byte back and stops with `?IO ERROR`: tried with the SAM's display offset). That is why the splash is on BASIC's own text screen.

## 6. Tools

`MB_SNAPAT=4,8,12,17.5,18 MB_NOBUILD=1 MB_SESSION=/repo/tests/sessions/boot-title.keys MB_LIMIT=22 scripts/game_run.sh build/run/spl` writes `build/run/spl-t<second>.png`; `MB_RAM=128K` runs the machine with 128 KB, `MB_MACHINE=coco3h` with a 6309.

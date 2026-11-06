# Step 8.11: code residency (an I/O budget, then banks chosen by what the game runs)

Date: 2026-10-24. Follows `docs/PHASE-8.10.md` (the distribution), whose section 8 found why the floppy build is unplayable. Tags: **[V]** measured by running it, **[M]** measured on a model, **[E]** estimate, **[?]** open.

## 1. Why

Step 8.10 measured the player's wait: a floppy read through `DSKCON` is 4 KB/s, and **88 % of the bytes a session reads are code banks loaded again and again** (2.3 MB of 2.65 MB in a five minute session). The development backend (MAME's Lua harness answers a sector in no time) hid it for ten steps. The original on a PC reads 384 KB of overlays in a combat session and 33 KB in the fight itself.

The rule from here on: **the storage is a first class constraint.** A change that makes a session read more than its budget does not merge, whatever it does for the heap or the speed.

## 2. The I/O budget (`tools/iobudget.py`, `make io-budget`) [V]

`make io-budget` plays every session once on the development backend with the storage log on (`MB_SECLOG`, five at a time, `scripts/io_runs.sh`) and `tools/iobudget.py` reads each log against the image (`build/game/pool.img`): which sector belongs to a bank, the core, a picture or other data, the saves. Per session it prints

* kilobytes read, by kind (code banks, data, total) and the number of bank loads;
* the worst 30 seconds of code traffic (the stall a player sees when a mode starts, or the steady drain of a fight);
* the seconds of reading on each medium: floppy through DSKCON 4 KB/s, a track at a time 22 KB/s [E], DriveWire 11 KB/s [E], SDC 100 KB/s [E].

`data/io_budget.json` holds, per session, the code kilobytes and the worst window a session may not exceed (3 % above the last accepted run); `make io-budget CHECK=1 NORUN=1` fails when one is over, `WRITE=1` ratchets the numbers down after an improvement. Only code is budgeted: the data a session needs (pictures, maps, monster files) is what the original reads too.

### 2.1 The baseline, before this step (36 banks, 7 slots of 16 KB, LRU)

| session | code KB | data KB | loads | worst 30 s KB | seconds of reading: floppy / SDC |
|---|---|---|---|---|---|
| boot-title | 78 | 160 | 10 | 78 | 60 / 2 |
| create-character | 188 | 184 | 20 | 78 | 93 / 4 |
| camp-magic | 353 | 258 | 34 | 185 | 153 / 6 |
| camp-save | 280 | 400 | 28 | 174 | 170 / 7 |
| character-view | 293 | 258 | 29 | 176 | 138 / 6 |
| camp-rest-combat | 568 | 267 | 54 | 296 | 209 / 8 |
| camp-cast | 705 | 258 | 60 | 204 | 241 / 10 |
| temple-cast | 720 | 275 | 67 | 306 | 249 / 10 |
| character-menu | 940 | 273 | 88 | 464 | 303 / 12 |
| walk-explore | 1,274 | 253 | 122 | 642 | 382 / 15 |
| shop-buy | 2,383 | 277 | 228 | 806 | 665 / 27 |
| parley-combat | 4,404 | 273 | 389 | 1,304 | 1,169 / 47 |
| battle-aftermath | 4,519 | 276 | 400 | 1,304 | 1,199 / 48 |
| temple-heal | 4,952 | 298 | 439 | 1,304 | 1,313 / 53 |
| combat-spells | 6,117 | 273 | 533 | 1,468 | 1,597 / 64 |
| council-guards | 9,990 | 308 | 905 | 1,052 | 2,575 / 103 |
| mean of 16 | 2,360 | 268 | 212 | 1,468 (max) | 657 / 26 |

The mean session reads 2.4 MB of code, a fight 1.3 MB in 30 s: **a floppy player waits eleven minutes for code in a typical session.** The target of this step is the original's figure, about 400 KB of code for a combat session, and no window over about 150 KB (a mode switch, 40 s on a floppy, 1.5 s on the SDC).

## 3. What a session really runs (`tools/routine_profile.py`, `tools/codeprof.py`)

The oracle (the original DOS game in the Unicorn based emulator, `tools/oracle`) runs the same keystroke scripts. `routine_profile.py` hooks its call tracer and keeps, per session, the order of the routines that run (each call and each return to a caller, repeats folded; a session is 100,000 to 1,200,000 events), and the runtime routines that the port keeps in its own bank (heap, files, strings). `tools/codeprof.py` lists the routines of the banked units with their code size (from the compiler's symbol sizes) and the static call graph: 731 routine groups (a routine with the static helpers in front of it), 285 KB. `tools/profwatch.py` watches the runs.

**A tracer defect found on the way.** Some of the original's routines leave by unwinding the stack instead of returning. The oracle's tracer then never popped their frames: its depth, and the indentation of every line it writes, grew without bound, and a long session slowed down quadratically (a combat session ran for five hours and was not half done; a stack sample showed 99 % of the time in `str.lstrip`). `routine_profile.py` subclasses the tracer and drops a frame when a later call shows the stack is shallower than it was: the same sessions now take 5 to 15 minutes. `tools/oracle/trace.py` is untouched; its depth is wrong for such routines.

## 4. Banks of routines (`tools/rebank.py`, `data/routine_banks.json`, `tools/mkgame.py`)

A bank used to be a translated unit, a half of one, or a few merged by `tools/bankgroup.py`. Now a bank is a set of routines from any units (`partition_unit` in mkgame: one object per unit and bank, a static helper copied into every part whose routines use it, a string literal handed across banks copied to the caller's frame as before). The pool simulation of the tool is `tools/poolsim.c` (compiled on first use):

* a pool of N slots, least recently used out, a bank read whole (its routines, its constants, about 900 bytes);
* the runtime and the sound code as one bank that is always used (the sound driver runs about three times a second of game time; since this step they are one bank `rtlsnd`, 16,186 bytes with its 29 entries, one slot of the pool instead of two);
* **it reproduces the real runs.** The simulation of the layout of section 2.1 gives 498 loads for `battle-aftermath` (measured 499), 680 for `combat-spells` (717), 1,055 for `council-guards` (1,054), 491 for `parley-combat` (489). Before the runtime and sound banks were in the model it gave 28 where the run showed 500: **a model that leaves out the other users of the pool is useless**.

The search: greedy clustering by how often one routine runs right after another gives a start, then simulated annealing (14 chains of 150,000 moves or swaps of routines, the objective the bytes read over the 16 sessions, each weighted by one over the square root of what it read before). Banks hold at most 14,100 bytes of code (the rest of 16,000: constants 0.4 to 1.6 KB, the entry table 3 bytes an entry).

**Two things the first layouts got wrong.**

1. *The layout filled the pool exactly.* The fight used 7 banks (6 of code and `rtlsnd`), and a routine the profile does not show made it 8: `BriefWait`, which `PlaySound` calls (it is the port's own helper, added in step 8.9d by `mkgame.py` (commit `4b589657`) so a brief sound waits only as long as it sounds; the original has no such routine, so the oracle's profile cannot show it; 376 calls over the 16 sessions). It sat in a cold bank, and every call evicted a hot bank: 43 loads in `battle-aftermath`. Now (a) the model knows it (`FOLLOWERS` in `rebank.py`, found by comparing the entries the port's bank logs show with the profiles: 22 entries of 331, all runtime or sound except `BriefWait` and one start-up call) and (b) **the search makes the layout for one slot less than the pool has** (`--slots 6`), a margin for the next routine nobody saw.
2. *cmoc crashes* (`free(): invalid pointer`) on some of the new files; whether it does depends on the layout of the text and the length of the path, not on the code. `compile_c` compiles such a file again under another name with blank lines in front.

## 5. Result [V]

All 16 sessions play identically (every labelled screen, the state compared with the golden, the save area): `make step-check`. `make io-budget`:

| session | code KB before | code KB now | loads before / now | worst 30 s KB before / now |
|---|---|---|---|---|
| battle-aftermath | 4,519 | 423 | 400 / 33 | 1,304 / 128 |
| parley-combat | 4,404 | 315 | 389 / 25 | 1,304 / 128 |
| temple-heal | 4,952 | 422 | 439 / 34 | 1,304 / 128 |
| combat-spells | 6,117 | 454 | 533 / 37 | 1,468 / 128 |
| council-guards | 9,990 | 434 | 905 / 33 | 1,052 / 119 |
| shop-buy | 2,383 | 197 | 228 / 17 | 806 / 70 |
| walk-explore | 1,274 | 186 | 122 / 14 | 642 / 70 |
| camp-cast | 705 | 133 | 60 / 12 | 204 / 70 |
| mean of 16 | 2,360 | 236 | 212 / 19 | 1,468 / 128 |

A combat session now reads 423 KB of code against the original's 384 KB (the original 56 loads, ours 33), and a floppy player's wait for code in the mean session goes from about 10 minutes to 1 minute (SDC: 24 s to 2 s). The model said 306 to 386 KB for `battle-aftermath` at 7 slots. The worst 30 s window is 128 KB: entering a fight is a wait of about 30 s on a floppy through DSKCON, 1 to 2 s on the SDC.

**Does it hold for play the layout was not made from?** `rebank.py --holdout S` makes the layout from the other 15 sessions and runs S on it. For the first layout (before `BriefWait` and the margin) the held out sessions read, against the old banks: `battle-aftermath` 344 KB (2,957), `combat-spells` 941 KB (3,930), `walk-explore` 189 KB (857), `shop-buy` 225 KB (1,547): the layout does serve play it was not made from, but a held out combat costs 1.3 to 2.5 times what it costs in the sessions the layout was made from. A routine no session ran lives in a cold bank and costs a load when it runs.

### 5.1 The floppy set and the SDC file on the new banks [V]

`make floppy-traces floppy-profile floppy` made the layout again (the profile is by bank id, so the old one was void): 12 disks, and the swaps the simulation counts over the 16 sessions with two drives go from 1,044 to 274 (one drive 443, three 99, four 83). `make floppy-check` plays every session on the disks in MAME: **all 16 sessions equal on every labelled screen and every file the game wrote, in 8 minutes** (the combat sessions needed 4,500 emulated seconds, hours of wall time, before). The swaps the player would have made: battle-aftermath 18 (127), parley-combat 16 (123), combat-spells 17 (176), temple-heal 24 (133), council-guards 30 (175), walk-explore 15 (17), camp-save 14 (18), boot-title 7 (8); 276 in all against 952.

## 6. Four disks, no swaps: what fits, and what a byte pool is worth

**Compression to fit four standard disks does not.** The game's data is 1,358 KB once identical blocks are stored once (the image is 1,486 KB with the 128 KB of saves). Four 35 track disks hold 4 x 152 KB = 608 KB. `tools/compexp.py` on the current image (no shared blocks, 1,620 KB as stored): ZX0 of the stored bytes 954 KB, ZX0 of the unpacked blocks 843 KB (2,951 KB unpacked), so about 0.52 of the stored size, about 710 KB with the shared blocks: 17 % more than four disks hold, a fifth disk for the data and a sixth for the saves. Four 40 track disks (720 KB) would just hold it, with the decoder, the packer and no margin: not done. ZX0 also costs time: 68 cycles an output byte (25 KB/s of output) is 0.6 s for a 16 KB bank, 4 times the SDC's read.

**What fits without compression: four disks of 80 tracks** (364 KB each, 1,456 KB; the engine reads any track, `flop.c` has no limit of 35). `make floppy-xroar80` (`make floppy80` builds the set): `TRACKS=80` in `tools/mkimage.py`, `tools/mklayout.py` (disks of 1,422 sectors, `--drives 4`) and `tools/decbfs.py` (`Disk(tracks=)`): four data disks 95/83/98/89 % full and a fifth with the saves, asked for when the game loads or saves. With four drives the simulation counts **16 swaps over the 16 sessions** (one a session, the save disk) against 274 on the 35 track set with two drives. Two things XRoar needed: a two byte JVC header (`12 01`: 18 sectors, 1 side; a headerless 368,640 byte file is taken for 40 tracks of two sides), and `POOL.BIN` before the data file on disk 1 (Disk BASIC's FAT knows 68 granules; the data file reaches 155). [V] in XRoar headless: `LOADM"POOL":EXEC` reaches the engine's `main` in 9 s, as on the 35 track set, and the game goes on to read tracks 35 to 45. Not played through in XRoar, and MAME was not tried with these images. Real 80 track drives are rare on a CoCo.

**A byte granular pool is worth 15 to 25 %, not more.** `tools/poolsim.c` has a pool in bytes (no fragmentation, banks of any size, LRU until the bank fits); `rebank.py --pool-bytes 114688` anneals for it. Mean code read per session, the model (the slots layout of section 4: 187 KB in the real pool of 7 slots):

| bank size limit | hot banks | mean KB (made for the pool less 14 KB / in the whole pool) |
|---|---|---|
| 14,100 | 31 | 164 / 157 |
| 8,000 | 42 | 150 / **142** |
| 4,000 | 67 | 153 / 144 |
| 2,000 | 116 | 182 / 168 |

At best 24 % fewer bytes, from the pool that holds what the slots waste (banks of 14 KB in slots of 16 KB, small banks in a whole slot). Against that: the code of a bank is linked for the window at `$8000` (CMOC, `--no-relocate`), so a bank cannot sit at another address without relocation at load time (a table of every absolute address, with the code that applies it, in an engine that has 19 bytes left); the bank table has 64 entries (banks of 4 KB would need 90); each bank carries its constants and entry table (about 900 bytes, 20 % of an 8 KB bank). **Not worth it before the other things in section 7.**

### 6.1 MAME and the 80 track set [V], VCC [?]

MAME takes the images only with an 80 track drive type (`-ext:fdc:wd17xx:0 525qd`; its default drive is a 42 track 5.25" and refuses them: `Floppy disk has too many tracks for this drive`): `MB_FDTYPE=525qd scripts/floppy_run.sh` (and `lua/watch.lua`, which named the `525dd` drive for the disk swaps). **It does not play all of it.** `boot-title` and `camp-save` match every labelled screen, but `battle-aftermath` and `temple-heal` stop with "bank 14 cannot be read" (r29 = 1): DSKCON fails on track 63 sector 14 of disk 1 (the first sector of a bank) after a head move from track 16, 3 tries a time, for ever. The same 35 track set on the same 80 track drive type passes (`battle-aftermath`: 235 screens, status 0), and the 80 track set fails the same way on MAME's `35dd` drive; MAME's own loader returns the image byte for byte (`floptool flopconvert jvc jvc`), so the image is intact. Not found: whether MAME's FDC or Disk BASIC's DSKCON (a timeout in a long head move) is at fault. The failing read is a seek of 47 tracks, while MAME did a 52 track one a minute earlier. **Not proven in XRoar either**: the boot reads to track 45, a long session was not played. VCC's FD-502 takes JVC images of 35, 40 or 80 tracks, so the set should load there; not tried.

## 6.2 One file for XRoar: the IDE build [V]

XRoar 1.12 emulates the Glenside IDE cartridge (`-cart ide`, registers `$FF50` to `$FF58`, 512 byte sectors) with a hard disk image given by `-load-hd0`; an image named `.img` is raw sectors, without a header. The SuperIDE build of 8.12 (`make ide`: `ide.c`, `ide_xfer.asm`, the card file `POOLIDE.IMG`) talks to the registers itself, so it needs no DOS ROM: XRoar loads the engine's `POOL.BIN` straight into memory (`-run`) and the card file is the game. `make ide-xroar` builds it for a card file that starts at sector 0 (`IDE_HDB_OFFSET=0 IDE_DRIVE=0`, into `build/ide-xroar`, so that the build of the real card in `build/ide` is left as it is) and starts XRoar on a copy of the file (the game saves into `build/ide-xroar/run.img`). One image file of 1.9 MB, no disk to swap. [V] in XRoar: `main` after 2 s, the first screen set-up after 4 s, the sixth bank load after 8 s, the title screen on the display; XRoar's IDE accepts the driver's 8 bit mode or the fallback to words, which of the two was not looked at. Not played through, and the saves were not tried.

## 7. Not done, in the order of what it would buy [E]

1. Preload the working set of a mode (fight, camp, shop) behind a "Loading" message, instead of 30 s of stalls spread over the first turns.
2. More profiles (other spells, monsters, places) for the layout, and `--holdout` runs over all 16 sessions as a gate.
3. Then the storage speed: a track at a time driver, an IDE backend, compressed banks.

The profiles (`build/profile`, 25 MB) are not committed: `make routine-profile` makes them again (about 25 minutes, five sessions at a time), `make code-profile` the routine sizes, `make rebank WRITE=1` the layout. A build needs only the committed `data/routine_banks.json`; a routine it does not know goes to a bank `rest_<unit>` (and is over the limit if there are many: run `rebank` again).

Files: `tools/routine_profile.py`, `tools/codeprof.py`, `tools/rebank.py`, `tools/poolsim.c`, `tools/profwatch.py`, `tools/iobudget.py`, `scripts/io_runs.sh`, `scripts/io_one.sh`; `tools/mkgame.py` (`load_routine_banks`, `partition_unit`, the `rtlsnd` merge, `compile_c` retry); `data/routine_banks.json`, `data/io_budget.json`; make targets `routine-profile`, `code-profile`, `rebank`, `io-budget`. `REBANK=0` builds the old unit banks; `RTLSND=0` keeps the runtime and sound banks apart.

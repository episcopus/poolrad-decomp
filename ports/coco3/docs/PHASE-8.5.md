# Step 8.5: first light (report)

Date: 2026-10-18. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.5: the game's own code on the CoCo, title screens, main
menu, character creation; exit: the `boot-title` and `create-character` sessions match on screen and state in MAME. Tags:
**[V]** verified by running something, **[E]** estimate, **[?]** open.

## 0. Result

**Both sessions play on the emulated CoCo 3 (MAME, 512 KB, headless) and match the original's goldens [V]**, from the container
image of decision D13 (`make first-light`):

```
boot-title: 3 of 3 labelled golden screens shown in order            ssi-logo, title, credits: equal, bit for bit
create-character: 4 of 4 labelled golden screens shown in order      race-human, sheet, head-body-keep, icon-editor, final (the main menu): equal
                  16 of 23 unlabelled ones                           the per-key screens of the recorder; the 7 that are not are the code wheel's
  file CHARLIST.TXT  5 bytes: equal
  file RAD.CHA       285 bytes, character record: equal (words turned, pointers left out)
  dgroup: 391 places equal, 58 differ for a reason in data/state_ignore.txt (representation, platform), 0 open, 15 not on the CoCo (the engine's)
```

What the session does on the CoCo: the code wheel is answered (the harness reads which question the game asked), Create new character,
Human, Male, Fighter, Lawful good, the rolled sheet (the scores equal the original's: the random generator is lined up at the
main menu), the portrait window with the head and the body, the icon editor with its old and new icons, the character is saved
(the character list and the record), and the main menu comes back. The game is the translated Pascal, unchanged except for what
the CoCo forces (section 3).

What is not part of this step: a window to play in (section 5), the byte order of files the game loads and reads as records (ITEMS
as a record array, monsters, saves from the PC), sound, the engine routines the 3D view and combat need (section 6).

## 1. How it is built

Memory (physical 8 KB blocks of the 512 KB, `src/engine/gamemap.h`; unchanged by this step except the stack):

| Blocks | Use |
|---|---|
| `$00..$03` | the 320x200x16 screen |
| `$04,$05` | DrawBuf (the 168-row staging buffer of the blits) |
| `$06,$07` | the file table of the image (6 sectors at a time) |
| `$08..$0D`, `$28..$2F`, `$33..$37` | pictures: three runs, 19 blocks (152 KB), one linear store (`gfx.c`) |
| `$0E,$0F` | the stage: the unpacked DAX block the game is loading |
| `$10..$13` | the paged part of DGROUP (four pages) |
| `$14..$17` | the banked heap |
| `$18..$27` | the bank pool: 8 code banks of two blocks |
| `$30..$32` | the game core (task 0, `$2000..$7FFF`) |
| `$38` | slot 0 of both tasks: the shared code, the shared data, the mailbox, the stack |
| `$39..$3B` | the engine (task 1) |
| `$3C..$3F` | Disk BASIC's ROM images (DSKCON, unused by the image backend) |

**Slot 0, as of this step**: `$0400..$05DF` the shared code (the frame interrupt, the keyboard, the call gate), `$0600..$06FF` the
sector buffer, `$0700..$08FF` the shared data (variables, the call ring, the bank table, the key queue, the event log at `$0860`),
`$0900..$096F` the mailbox and the request block of the storage, `$0A00..$1F7F` **the stack, 5.5 KB (was 3.8 KB)**, `$1F80..$1FFF`
the bank stack. Disk BASIC keeps its buffers in `$0600..$0DFF` until `LOADM` is done with `POOL.BIN`: the shared data therefore is
not in `POOL.BIN` at its address but as one image at `$7400` that `boot.asm` copies into place (`tools/mkgame.py strip_low_records`;
`$7E00` and up is BASIC's own stack and string space, an image there was overwritten before the engine ran).

**Storage (D13)**: `sec_io(cmd, lsn, count, block, offset)` fills the request block and rings the doorbell; the harness (a write tap in
`lua/watch.lua`) copies sectors between the image file and physical RAM and answers in the status byte (`src/engine/img.c`). The image
is "PIM2" (`tools/mkimage.py`): a header, a table of files, the entries (file, id, byte offset, packed size, raw size: the same entries
as the volumes of 8.4), then the blocks of the 117 files (the 48 code banks, the core, DGROUP, every DAX block and ITEMS) and a **save
area of 256 sectors**. 6,718 sectors, 1.64 MB. The engine mounts it, loads the core and the initial DGROUP from it, and loads the banks
and DAX blocks on demand (`api_bankload`, `DaxLoad`). `rs_read` reads from the image when the file's drive is `IMG_DRIVE`, so the
unpacker and the picture loader are the ones of 8.4.

**Files the game writes**: `src/game/rtl_file.c`, in the runtime bank (no variables: the state of an open file is in the file variable's
UserData). A directory in the save area (header "PSAV" and the first free 256 byte unit, 31 entries: name as 8 + 3 characters, start unit, room in
units, size) and files of 4 KB (10 KB for `.DAT`) made when the file is rewritten. `SaveRead`/`SaveWrite` are the engine's byte
access to the area (one sector read, changed, written back). Text files read and write lines (`ReadLn`, `WriteLn`, `Eof`). The files of the volumes
(ITEMS) stay read-only. A real backend decides how files are stored after 8.9.

**The session driver** (`lua/watch.lua`): the keys of `tests/sessions/*.keys` go straight into the engine's key queue, one command when the
screen has been still for 2 s **and the game is waiting for a key** (the game counts its keyboard polls in the mailbox: a screen that does not change is not
a game that is idle: the editor computes for seconds); the `wheel` command reads the question the game chose (`wheel_pick`, set by
`Random(13)`), types the answer from the table of 13 words and, once the menu has settled, **sets the generator to the original's seed at that point**
(`0x074494E8`, the `RandSeed` of the host replay at the main menu), so the rolls are the recorded ones. `wait` and `shot` are not needed:
every screen that stays for 0.2 s is kept and compared by hash with the goldens in order.

**Keys (D8)**: the engine's key queue holds characters and the codes of keys that are not characters; `kbd_get` returns the PC's pair for
those (0, then the scan code) from a table (`kext`), `rtl_ReadKey` hands it out as two reads. Arrows, F1 and F2 as on the PC;
**SHIFT with an arrow is PgUp, PgDn, Home, End** (up, down, left, right): the harness types the same codes, so the matrix path (8.3) is
the only thing not exercised by the session.

## 2. Numbers

| | |
|---|---|
| Engine (task 1) | 20,668 bytes with data (`$2000..$70BC`; the shared image at `$7400`); 27 of 38 game routines written |
| Core (task 0) | 12,541 bytes, ends `$50FD` (the limit is `$5400`); the file runtime left it (700 bytes more room than before) |
| Code banks | 48, 330,812 bytes, largest 14,117 (limit 16,000); the runtime bank holds the heaps and the files |
| Stack | `$1F7F` down to `$0A00`; `create-character` reaches `$11F9`, 3.4 KB; the first run in the old 3.8 KB overran into the mailbox at the sheet |
| Image | 6,718 sectors; header, file table (117 files), 1,297 entries, the blocks, 256 sectors of saves |
| Time | the engine is up at 15 s of emulated time, the ssi-logo at 26 s, the title at 55 s, the credits at 84 s, the wheel question at 140 s; `create-character` ends at about 200 s and is given 700 (the harness waits for the screen to be still); a run takes 2 to 4 minutes of the host (the container, MAME at 30 times real time, the Lua taps) |

Not on the CoCo (the engine's, 11 routines): the PC's pixel/mirror helpers (`ColorMatchMask`, `PaletteColor`, `UnpackPicturePixels`, `MirrorByte`,
`MirrorWord`, `SwapNibbles`, `MirrorPicture`: the engine's pictures are 4bpp already) and `Load24x24Set`, `DrawCellPicture`, `LoadSpriteList`,
`Show3DSprite` (the 3D view and the area view, step 8.6).

## 3. Findings and defects (each one is in the build now)

1. **CMOC miscompiles assignments to a variable named like a global enum constant** (8.5 earlier; unchanged): the translator renames them.
2. **CMOC: `(u8)x0 < db_lo[y]` with `x0` an `s16` marks the wrong rows.** Four icons drawn, two of them half or not flushed. The cast of a signed
   word in a comparison with a byte array element is wrong; the fix is a `u8` local (`ux0`, `uy`) for both the index and the compare.
3. **CMOC 0.1.100 in general**: `u8 * constant` in 8 bits (use `(u16)`), `s8` byte arithmetic, a bare cast of a pointer (`| 0`), no compound literals.
4. **The write tap of MAME's Lua must stay referenced** (`secreq_tap` is global): when the collector freed it MAME crashed or dropped the tap (all later
   sector reads answered with nothing). A run that ends in 3 s with no output has crashed MAME: run it by hand and look at the exit code (139).
5. **Aliased tables and byte order** (`tools/mkvm.py`): the PC's data segment has tables declared over each other (an index base that lies over the next
   table: `StartingAgeTable` row 0 over the Human and Half-Orc rows of `RaceClassChoices`; `ExperienceTable` over `ConstitutionHitPointTable` and the
   spell slot tables; `TreasureItemRows` over `SpellLevelNames`). Reversing every word of a typed view corrupted the byte tables it overlaps: the class
   list of the Human was empty. The layout now leaves a value alone when it lies in the real extent (declaration cut to its storage array) of another
   global read as bytes, when it straddles the border of two storage arrays, and for two named index bases (`NOSWAP`); 61 values are left, 416 turned.
   **Open for 8.6**: bytes written at run time over a word view (`PartyMapRow`..`PartyCellEventByte` over `WallSetSlotPairs`, `PictureAnimationBase`, `LoadSlots`,
   `SpellTargetCount`): the values are right as long as they are read the way they were written (the state check accepts either order).
6. **The PC's picture records are not the engine's**: game code reaches into a picture (`Tail`, `Pixels`, `ByteSize`) in `MergePictureData`, the editor's
   `CopyPictureSlot`, `DrawIcon`, `Load24x24Set`, `LoadSpriteList`, `Show3DSprite`, res12 (combat animation) and ovl13. A picture is a handle on the CoCo; these
   are rewritten through the engine (`PATCHES` in `tools/mkgame.py` and `ENGINE_ROUTINES`: `DrawIconPic`, `PictureCopy`, `MergePictureData`,
   `DrawPictureItemClipped`). The ones left (res12, ovl13, `Load24x24Set`) fail loudly when reached (`vm_far` stops on a handle). Merge and copy are done on the
   engine's own pictures (colours OR, masks AND): the PC's two buffers are not the CoCo's one pixel and one mask plane.
7. **`ovl28` is game code** again (the whole unit had been given to the engine): `DrawSprite`, the head and body window, `FreeSpriteList` run on the handles. Only `LoadSpriteList` and
   `Show3DSprite` need the picture record's fields and stay in the engine (not written).
8. **Stack**: `create-character` needed more than 3.8 KB (the sheet, `DrawLocationLine` with five 256 byte string temporaries over the editor's frames). Slot 0 was
   rearranged (above) and **string temporaries are shared between statements** (`tools/c/p2c_expr.py`: a temporary lives inside one statement, so each routine declares `ts1..tn` once at the
   size of the busiest statement; the PC's C is regenerated, all seven goldens equal). Still room: 2.0 KB of the 5.5.
9. **The key queue and the wheel**: typing a word all at once loses letters (the game polls between keys); the driver types one key every 0.4 s.
10. **`SaveDir` had a wrong length** in `platform.c` (an octal escape: `\023` is 19, the 16 characters need `\020`): the game made file names with three bytes of the next global in them.

## 4. Tools added

`make first-light` (both sessions, screens and state), `make game-run S=` (a session in MAME and its screen check), `make game-state S=` (`tools/statecheck.py`:
the files written and DGROUP place by place, against the host replay, `data/state_ignore.txt` lists what cannot be equal and why), `make game-view S=` (a GIF of what the game showed),
`tools/mkimage.py` (the container image), `tools/scr4gif.py`, `lua/watch.lua` (the storage backend, the session driver, `MB_WATCH=lo-hi` to log writes to a range, `MB_PEEK`,
`MB_PCLOG=t0-t1` the program counter every frame, `MB_SECLOG` the sector requests, dumps of memory, DrawBuf and the picture table).

## 5. Decisions and open questions

D13 holds: one interface, the development backend in the harness; it made this step possible (the first plan needed disk swaps for 22 banks). **D8**: SHIFT with the arrows for the diagonal keys
(not yet tried on a keyboard). No window to play in until a real backend exists: XRoar would need the DriveWire (Becker) backend of D13 and a small host server for the image, a
good first task of the storage work after 8.9; `make run-game` says so, `make game-view` is the stand-in.

## 6. What 8.6 starts with

1. The area view and the 3D view: `LoadSpriteList`, `Show3DSprite`, `Load24x24Set`, `DrawCellPicture`, the combat animation (res12, ovl13), and the byte order of files read as
   records (ITEMS rows, monster records, saved characters of the PC).
2. The aliased runtime variables of finding 5.
3. The picture store: 19 blocks held `create-character`; combat and the 3D view hold more pictures at once.
4. Sound (8.9), the matrix keyboard in a session (the driver bypasses it), `RemapPictureColors` with the flicker (needs the game's Random: it stops with `0xF1`).
5. The unlabelled per-key screens: 7 are the wheel's, the others are screens caught while the game was still drawing; the labelled ones decide.

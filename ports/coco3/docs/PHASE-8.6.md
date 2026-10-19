# Step 8.6: exploration (report)

Date: 2026-10-18. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.6: 3D view, area map, ECL, shops, camp, save and load; exit: the
`walk-explore` and `camp-save` sessions match on screen and state in MAME. Tags: **[V]** verified by running something, **[E]** estimate,
**[?]** open.

## 0. Result

**Both sessions play on the emulated CoCo 3 and match the original's goldens [V]** (`make exploration`; `make first-light` still passes
for the two sessions of 8.5):

```
walk-explore: 8 of 8 labelled golden screens shown in order           the 3D view, the area map, the wall sets, the encounter text: equal, bit for bit
              12 of 19 unlabelled ones; 53 screens kept
  dgroup: 387 places equal, 62 differ for a reason in data/state_ignore.txt, 0 open, 15 not on the CoCo (the engine's)
camp-save: 1 of 1 labelled golden screens shown in order (the quit prompt after the save); 4 of 12 unlabelled ones
  files CHRDATB1..6 .SAV .ITM .SPC and SAVGAMB.DAT (13,137 bytes): equal (pointers of the records left out)
  dgroup: 390 places equal, 59 differ for a reason in data/state_ignore.txt, 0 open, 15 not on the CoCo
```

The game is again the translated Pascal; the files it saves are written in the PC's byte order, so a save made on the CoCo is the file the
original wrote (`SAVGAMB.DAT` byte for byte, the character records except for their pointers, which are addresses of two different heaps).
The seven sessions still play on the host after the translator changes (`c_golden.py`: all equal); `make test` of the port and the
repository's fast tests (385) pass.

Not part of this step: combat (the picture records of res12 and ovl13 are still the PC's, step 8.7), sound, the Real arithmetic of
`ScaleMoney` (below), a window to play in.

## 1. What changed

1. **Pictures** (engine, `src/engine/api.c`, `gfx.c`): the picture table holds 128 handles (it was 48: the 3D view loads wall sets and
   sprites at the same time), pictures remember their position (`SetPictureXY`) and carry the sprite lists the area view needs.
   New engine calls: `DrawIconPic`, `PictureCopy`, `MergePictureData`, `SetPictureXY`, `PictureBytes`, `PicData`, `DrawSpritePic`,
   `SaveRead`, `SaveWrite`. `ovl28`'s `LoadSpriteList` is written by hand (`PATCHES` in `tools/mkgame.py`): a sprite block can be 7,787 bytes,
   more than one page of a banked heap (0x1E00), so it is read from the DAX stage (`DaxLoad`, `DaxRead`) straight into the picture.
2. **Heaps** (`rtl_heap.c`): the mapped heap grew to about 8.8 KB (`HEAPDATA $4C80`), the layout is packed, and `MaxAvail`/`MemAvail` answer
   200000, as the host does. The first walk stopped with fatal 0x22 (mapped heap exhausted) before the repack. Combat peaks at 10.8 KB
   (step 8.7 decides: a larger mapped heap or moving the picture-table helpers out).
3. **Files and saves** (`rtl_file.c`): the save area is 512 sectors, with a directory ("PSAV", 127 entries, 16 bytes each: name, 16 bit start in
   256 byte units, capacity, size); a file's capacity is decided by its extension, so a character that grows (more items) is not moved.
   `mkimage.py` seeds the shipped `SAVE` folder in this format. The directory is written once at the end of a session by the harness
   (`.saves`), and the game waits out storage activity before the harness ends the session.
4. **Byte order of files** (translator, coco profile): `BlockRead` and `BlockWrite` turn the words of a record or an array round before a
   write and after a read (`rtl_swapdesc` with a table `swd_*` generated per type, `tools/c/p2c_builtin.py`), and `Move` between a byte buffer and a
   2 or 4 byte scalar does the same. On the host `rtl_swapdesc` is a no-op, so the PC's C is unchanged (all seven sessions equal).
   Three tables that are read as bytes through a word view stay in the PC's order (`NOSWAP`: `StartingAgeTable`, `ExperienceTable`,
   `SpecialBlocks`; the last was the grey ceiling of the 3D view).
5. **Strings** (`rtl_strx.c`, in the runtime bank): `Str(integer)`, `Val`, `Insert` with 16 bit division; the 32 bit `unsigned long`
   modulo of CMOC is not trusted.
6. **Translator**: octal escapes (`"\0010"` read as one character by CMOC: the digit after an octal escape is written `\060`), `Trunc`/`Round` of an
   integer argument, string temporaries shared per statement.

## 2. Numbers

| | |
|---|---|
| Engine (task 1) | 22,630 bytes from `$2000` (ends `$7866`); 31 of 40 game routines written |
| Core (task 0) | 11,290 bytes, ends `$4C1A`; the native data (`$4C80..`) is the mapped heap and the DGROUP part |
| Code banks | 48, the runtime bank holds the heaps, the files and `rtl_strx` |
| Image | 6,983 sectors (1,787,648 bytes) with the 512 sector save area |
| Slot 0 | shared image at `$7C00` in `POOL.BIN`, copied by `boot.asm` to `$0700..$08FF`; mailbox `$0900` |
| Time | `walk-explore` and `camp-save` take 3 to 6 minutes of the host each (MAME headless, Lua taps) |

## 3. Findings and defects (each one is in the build now)

1. **The save format was too small**: a full party's files and the saved game need more than the first 128 sectors and the first directory (8 bit start, 512 bytes
   units) allowed; hence 512 sectors, 16 bit starts and capacities by extension.
2. **Words read from files were in the PC's order** (TileSet 0 gave "Unable to load geo", the heap's first record was wrong): swap descriptors (above).
3. **CMOC**: an octal escape takes more digits than three (`"\0010"`), `u8 << 8` and `u8 * const` are 8 bit, a `(u8)s16` compare with a byte array element is wrong,
   unsigned long modulo is suspicious, and the void target has no float library (every `Single` routine is missing: `divSingleSingle`,
   `initSingleFromSignedWord`, `initSingleFromUnsignedWord`, `mulSingleSingle`, and `_rtl_trunc` of a real).
4. **Picture handle table full at 48** (the 3D view): 128.
5. **A save hung** when the harness wrote the sector list on every write and the game started the next file while it was busy: written once at the end;
   `press` (key down and up) and `key` differ in the driver; the driver now waits for storage to be quiet for 3 s.
6. **The big sprite block** (7,787 bytes) did not fit a heap page: `LoadSpriteList` reads it from the stage.
7. **ENG_TEST**: the engine tests of 8.3 and 8.4 are built without the game's picture helpers (`pic_wr`, `pic_combine`, `mirror_row`, `DrawPictureItemClipped`, ...);
   `pic_put` needs `pic_wr`, so the guard now ends after `pic_put` (the first `make test` of this step failed to link).

## 4. Tools added

`make exploration` (both sessions, screens and state). `statecheck.py` knows the directory format of the saves and the length of
`SAVGAMB.DAT`; `data/state_ignore.txt` gained the pointers to characters (`ViewedCharacter`, `SelectedCharacter`, `PartyListHead`, ...) and the sprite list's picture pointers
(`PictureAnimation`, `ds6ABE`); `lua/watch.lua` writes `.saves` once and can dump the picture table; `probes/strint.c` runs the location line's
`Str` and `'0' + m` as the translation writes them (the clock digits bug).

## 5. Decisions and open questions

None for the human. D13 holds (all storage is the development backend until 8.9); D8 keys are still not tried on a real keyboard.
The Real arithmetic: `ScaleMoney` is reached only by a script command; it is linked with five missing symbols (the build says so). A small
fixed point replacement or a Single library is part of 8.7 or 8.9, whichever first meets that command in a session.

## 6. What 8.7 starts with

1. Combat: the picture records of res12 (combat animation) and ovl13 are still the PC's (they stop the game with fatal 0x11 when reached),
   `Load24x24Set` and `DrawCellPicture` of the engine are not written, and the mapped heap peaks at 10.8 KB in combat.
2. `RemapPictureColors` flicker (stops with `0xF1`, needs the game's Random).
3. The aliased runtime variables of 8.5 finding 5 (the state check accepts either byte order).
4. Sound (8.8) and the real keyboard.

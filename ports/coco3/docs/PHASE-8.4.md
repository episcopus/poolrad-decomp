# Step 8.4: the data pipeline (report)

Date: 2026-10-18. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.4 and section 7. Tags: **[V]** verified here by running a
tool or an emulator, **[E]** estimate, **[?]** open.
Reproduce with `make data-verify`, `make vol-tests` and `make eng-tests` (from `ports/coco3`; the original game folder is
`../../poolrad`, or `POOLRAD_DATA=`).

## Exit criterion

| Criterion | Result |
|---|---|
| a host tool producing volumes and `.DSK` images | done: `tools/mkvolumes.py` with the policy `data/volumes.json` and the image writer `tools/rsdos.py`: nine volumes, `build/data/vol0.dsk` to `vol8.dsk` |
| reproducible images | **done**: `make data-verify` builds twice into separate directories and the bytes of every image, container and header are identical |
| every block round-trips against `make dax` | **done on two levels**: (1) on the host, every image is read back with the independent reader of `rsdos.py` and every one of the 1,246 blocks (the 1,245 of the DAX files that the original's own comments count, plus ITEMS) equals the decode of `tools/re/dax.py`, byte for byte, packed and unpacked; ToolShed's `decb` reads all nine containers unchanged; (2) **on the CoCo**, `make vol-tests` mounts each image in MAME and in XRoar, unpacks every block with the engine and compares its size and 16-bit sum with the host's: all 1,246 blocks equal in both emulators; a flipped byte in an image makes the test fail (checked) |

## 1. The format [V]

One RS-DOS floppy, one container file `POOLVOL.DAT` (`tools/mkvolumes.py` documents every byte). Big endian, the CoCo's order:
a 16-byte header, the names of the DAX files on the volume (8 characters), then one 10-byte entry per block (file number, block
id, offset of the packed bytes, packed size, unpacked size), the index padded to a multiple of 256 bytes, then the packed blocks
back to back. The packed bytes are the original's, untouched: the engine's RLE decoder reads them as they are, so the data
pipeline cannot introduce a decoding difference. ITEMS, the one raw file, is a pseudo file of one block (id 0) whose bytes are
stored as copy-only RLE.

Why one file per volume instead of one RS-DOS file per DAX file (the guide's section 7 sketch, and the first thing 8.3 did):

* **space**: RS-DOS hands out whole 2,304-byte granules: the 114 files alone need 620 granules (9.1 disks, 1.43 MB for 1.29 MB of
  data); the nine containers need 563 (8.3 disks);
* **time**: opening a file means scanning the directory (up to nine sector reads, 0.2 s) and walking the FAT; the original
  opened `COMSPR.DAX` 546 times in seven sessions (it opens a DAX file for every block). A mounted volume costs nothing per
  open: the index is in RAM, a lookup is a scan of up to 229 entries (**[E]** a few milliseconds at worst);
* **mounted volumes** are an answer to disk prompts: the engine asks "which mounted volume holds this file and block", and if
  none does, which volume to ask the player for (`build/data/volmap.h`, generated).

Blocks are not aligned to sectors: alignment would cost 128 bytes a block on average (160 KB over the game, one more disk) to
save half a sector read (about 10 ms) a block.

Not done, on purpose: the guide's step 2 "convert where it saves cycles" (pictures stay 4bpp as they are, byte-swapping records
waits for D7, the save format), and recompression (below).

## 2. The volumes [V]

The policy follows the game: the original asked for one disk per **TileSet** n (`InsertDiskPrompts[TileSet]`), and the loaders
name ECL, GEO, WALLDEF, ITEM, the 8x8 tile banks, PIC, CPIC, SPRIT and the monster files MONnCHA/ITM/SPC after TileSet
(`ovl07`, `ovl28`, `ovl29`, `ovl17`, `ovl03`, `ovl32`). HEAD and BODY are picked by picture number instead, the rest has no
number. Sizes in bytes, the capacity of a disk is 156,672:

| Volume | Holds | Blocks | Container | Free |
|---|---|---:|---:|---:|
| 0 BASE | 8X8D1 (the font), COMSPR, CHEAD, CBODY, ICON, ITEMS, DUNGCOM, RANDCOM, WILDCOM, BACPAC, SQRPACI | 229 | 137,906 | 18,766 |
| 1 SETS 1+3 | the files of TileSets 1 and 3 (set 1 and 3 together are 150 KB) | 165 | 150,365 | 6,307 |
| 2 SET 2 | TileSet 2 (the set the recorded sessions play in) | 143 | 144,136 | 12,536 |
| 3 SET 4 | TileSet 4 without PIC4, TITLE, FINAL5 | 145 | 143,027 | 13,645 |
| 4 ART 4 | PIC4 and BODY1..8 | 63 | 154,047 | 2,625 |
| 5 SET 5 | TileSet 5 and HEAD1..8 | 162 | 151,044 | 5,628 |
| 6, 7, 8 | TileSets 6, 7, 8 | 115, 111, 113 | 133,625, 131,124, 144,253 | |

Set 4 (164 KB) does not fit one disk, so its largest file PIC4 (92 KB) went to its own volume; that is a guess, not a measure.
**[?]** The right split needs the game's real pattern of use. What is known [V, `POOLRAD_TRACE` over the seven recorded
sessions]: they open 7 (boot-title) to 88 (camp-save, counting the save files) different files, and every game file among them is on BASE or in set 2, plus
`8X8D1` (the font) and HEAD3/BODY3 (character creation). The policy is data (`data/volumes.json`): the tool refuses a file in no
volume or two, a pattern that matches nothing, and a volume over capacity.

## 3. The engine side [V]

`src/engine/vol.c`: `vol_mount(vol, drive)` reads the index once into engine memory (physical blocks 6 and 7, 4 KB a drive, four
drives), `vol_find(vol, "ECL2    ", id, &entry)`, `vol_lookup` over every mounted volume (1 = on none, 2 = the file but not the
block), `vol_entry` to walk. The result is the `DaxEntry` that `dax_unpack` already took; `gfx_font_load_e` and `pic_load_e` are
`gfx_font_load` and `pic_load` from an entry. Also changed: `rsdos.c` keeps one FAT per drive (four), `dax_unpack` now returns
4 when the block unpacks to a size other than the index says (a short block used to go unnoticed), `kernels.asm` has `k_sum`.

Tests, all in MAME and XRoar:

| Test | What |
|---|---|
| `t_vol` (`make vol-test VOL=n`) | the program on drive 0, volume n on drive 1: every entry unpacked into physical blocks, size and sum compared; run for all nine |
| `t_vol2` | two volumes mounted at once (SET 2 on drive 0 with the program, BASE on drive 1): lookup finds a file on the right drive, tells a file on no volume from a block that does not exist, `vol_find` on the wrong volume says so |
| `t_gfxv` | `t_gfx` with the font and tile banks read through the BASE volume on drive 1: the six screens equal the same goldens |

MAME's disk controller has two drives, so the four-drive case (the engine has the FATs and indexes for it) is not run; XRoar
could do it. **[?]**

## 4. Disk speed, measured [V]

The 5.5 s for `TITLE.DAX` in step 8.3 turned out to be mostly the engine's: `rs_read` copied every byte of every sector in C and
walked the FAT. `t_skew` reads sectors in orders that step 1 to 9 sectors through a track: **18 ms a sector in both emulators,
whatever the order**, so neither models the rotation of the disk; a real controller and a real interleave would. `rs_read` now
reads a whole sector straight into the caller's buffer (`dsk_read_to`, buffer below `$8000`) and copies the rest with the 8.3
kernel: 132 sectors take 160 frames (1.2 frames, 20 ms a sector), **12.6 KB/s**, down from 239 frames. The title screen (33,898
bytes) loads in about 2.7 s, a full volume of 150 KB in about 12 s. The 237 Hz FIRQ running during reads makes no difference
(72 sectors in 72 to 78 frames with and without it).

**[?]** On a real drive the order will matter (RS-DOS formats with a sector interleave so that the next sector arrives after
DSKCON is ready); the images here are plain 1..18 and `decb` makes no interleave. 8.9 has the hardware test.

## 5. Compression, a measure for later [V]

The 1,246 blocks are 2,605,738 bytes unpacked, 1,273,124 as the game's RLE, and 698,289 with deflate level 9, a stand-in for what
ZX0 would give (ZX0 compresses a little worse than deflate): **about 45% less** to read and store, 5 disks instead of 8.3. Against
that, a ZX0 decoder reads back references from what it has already written, and the engine's output is a window of 8 KB blocks:
back references would cross block borders, or the decoder would need the whole block in contiguous RAM (a 31 KB picture is more than
the window). At 12.6 KB/s a byte of disk costs about 140 cycles, a ZX0 decoder costs on the order of 50 cycles per output byte [E]:
reading 45% fewer bytes pays. Not done now; it is the biggest available lever on load times and belongs to 8.9 with the real-drive
speed, and the container has room for it (a flags byte in the header; the entries would need a kind).

## 6. Not done

* Program volumes (the core, the code banks, the boot loader): 8.5 and later produce the code; the packer will take them with
  `rsdos.make_image`.
* The save disk: pre-allocated save files and their format wait for D7.
* The disk-prompt user interface ("insert the SET 2 disk"): the data is there (`volmap_prompt`), the screen is the game's in 8.5.
* Four drives under MAME; a real drive; the choice of volume 3/4 split from real use.

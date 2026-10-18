# Step 8.5: first light (report)

Date: 2026-10-18. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.5: the game's own code on the CoCo, title screens, main
menu, character creation; exit: the `boot-title` and `create-character` sessions match on screen and state in MAME. Tags:
**[V]** verified by running something, **[E]** estimate, **[?]** open.

## 0. Result

**`boot-title` plays on the emulated CoCo 3 (MAME, 512 KB, headless) and shows the original's three screens, bit for bit:
the SSI logo, the title picture and the credits** (the digests of `goldens/4bpp/boot-title.s4`), then goes on to the copy
protection prompt, as the original does. `make game-run S=boot-title` builds the game, runs it and prints the check [V]:

```
  ssi-logo       equal (our screen 4)
  title          equal (our screen 5)
  credits        equal (our screen 7)
boot-title: 3 of 3 golden screens shown in order, 9 screens kept
```

**`create-character` does not play yet.** The first screen it needs, the code wheel answer and the main menu, are blocked by
the items of section 6 (disk swaps, keys, file writes, byte order of loaded records, a few engine routines). The state
comparison (the host compares DGROUP, heap and planes at every checkpoint) is not built for the CoCo either: the layout, the
byte order and the pointer format all differ and need an inverse map. So the exit criterion is **met for the screens of
`boot-title`, not for state, not for `create-character`.**

The game is the translated Pascal, unchanged except for what the CoCo forces (section 3): 47 code banks, a resident core,
the engine in its own MMU task. The engine's API has 41 routines the game calls (the PC's res05 to res08 and parts of res06, ovl28, ovl32); 21 are written.

## 1. How it is built

Memory (physical 8 KB blocks of the 512 KB, see `src/engine/gamemap.h`):

| Blocks | Use |
|---|---|
| `$00..$03` | the 320x200x16 screen |
| `$04,$05` | DrawBuf (the 168-row staging buffer of the blits) |
| `$06,$07` | volume index (4 KB a drive) |
| `$08..$0D`, `$28..$2F`, `$33..$37` | pictures: three runs, 19 blocks (152 KB), one linear store (`gfx.c`) |
| `$0E,$0F` | the stage: the unpacked DAX block the game is loading |
| `$10..$13` | the paged part of DGROUP (four pages) |
| `$14..$17` | the banked heap |
| `$18..$27` | the bank pool: 8 code banks of two blocks |
| `$30..$32` | the game core (task 0, `$2000..$7FFF`) |
| `$38` | slot 0 of both tasks: BASIC's low RAM, the mailbox (`$1000`), the shared code (`$0400`) and data (`$0E00`), the stack |
| `$39..$3B` | the engine (task 1, `$2000..$7FFF`) |
| `$3C..$3F` | Disk BASIC's ROM images (DSKCON) |

Two MMU tasks. The engine runs in task 1 (its code at `$2000..$680D`, windows 0 and 1 at `$8000`/`$A000` for its data), the game
in task 0 (core at `$2000..$537F`, native DGROUP at `$5600`, the mapped heap to `$7FFF`, a code bank in slots 4 and 5, two data
windows in 6 and 7). Slot 0 and the constant page are shared: the interrupt handler, the call gate (`__engcall`), the bank table
and the keyboard state live there.

Calls into the engine are C calls through a gate [V] (`src/engine/engcall.asm`): the stub `_Name: ldb #n / bra tail` in the core
jumps to `__engcall`, which saves the game's return address, switches to task 1 and jumps to the table (`api_tab`, generated);
the engine routine finds its arguments on the shared stack exactly as the game's compiler pushed them. Pointers in the
arguments can therefore point only into the stack: `src/game/engapi.c` wraps the routines that take strings or give results back
(LoadPicture, AllocatePicture, ReleasePicture, RemapPictureColors) and implements Put8x8Symbol and LoadDaxBlock on the game side.
A far call into a bank that is not in memory lands in the same gate (routine 0, `api_bankload`): the engine reads `BANKnn.BIN`
from the disk into a free pool entry (never one on the bank stack) and the call is tried again.

Pictures are handles (1..48) in the low word of the game's picture variables; the pixels stay in the engine's store. DAX blocks the
game loads with `LoadDaxBlock` (maps, fonts, items, monsters) are unpacked by the engine into the stage and come over in 128 byte
pieces. The Pascal file runtime (`rtl_assign/reset/blockread/close`) knows the files of the mounted volumes (ITEMS is block 0 of
the pseudo file ITEMS).

Boot: BASIC `LOADM"POOL":EXEC` loads the engine (`POOL.BIN`); it clears the game's memory (a real CoCo's is not zero), reads `CORE.BIN`
and `DGROUP.IMG` from drive 0 into their blocks, mounts the data volume in drive 1, gives task 0 its slots and jumps to the game's
entry. `tools/mkgamedisk.py` writes the program disk (35 tracks, `decb`): POOL.BIN 14.5 KB, CORE.BIN 12.9 KB, DGROUP.IMG 11.9 KB
(run length coded, 36.8 KB raw), BANKS.IDX and the code banks the session needs (`data/bootbanks.txt`, 14 banks, 46 KB).

## 2. Numbers

| | |
|---|---|
| Engine (task 1) | 18,445 bytes with data (`$2000..$680D`); 21 of 41 game routines written |
| Core (task 0) | 13,183 bytes, ends `$537F`; limit `$5400` (the heap tables, 323 bytes, then 4,040 bytes of native DGROUP) |
| Code banks | 47, 327,174 bytes, largest 14,130 (limit 16,000); 14 are on the program disk for `boot-title` |
| Far stubs | 2 bytes an entry for banks with 8 or more entries (a `bsr` to a tail that turns the return address into the entry), 5 bytes below |
| Stack | `$1060..$1F7F`, 3.8 KB; the boot path uses all but about 100 bytes of it [V] (a guard in the interrupt handler stops the program if it goes below `$1100`) |
| Pictures in `boot-title` | SqrPaci banks 2 x 36 KB, the title 32 KB while it is shown, tile banks, 26 sprites: 152 KB of store is enough |
| Time to the first screen | about 25 s of BASIC loading the engine (one revolution a sector), 9 s of engine boot, about 60 s of "LOADING...PLEASE WAIT" (bank and picture loads from the floppy), ssi-logo at 122 s of emulated time, credits at 193 s |

## 3. Findings and defects (each one cost hours; each is now in the build)

1. **CMOC miscompiles assignments to a variable that shares its name with a global enum constant.** The translated DrawWindowFrame
   has a parameter `BottomRow`; the unit also has `enum { BottomRow = 24 }`. `BottomRow++` (or `BottomRow = BottomRow + 1`) was
   stored as a word, wiping the parameter. Every window frame came out one row short. Fix: the translator renames locals and
   parameters that spell a global constant or enumeration member (`tools/c/p2c_decl.py` `safe()`); verified on the PC profile
   (`make c-golden`, all seven sessions equal, state included) and on the host model.
2. **A bank sees only its own constants.** A string literal passed from one bank to a routine in another bank is read through the
   callee's window: garbage. `tools/mkgame.py` copies every literal argument of a call into another unit to the caller's frame
   (`copy_cross_literals`: 413 call sites); the string runtime and the engine wrappers are resident for the same reason (the core
   grew by about 4 KB, and that is why the heap tables moved twice).
3. **Byte order.** The CoCo is big endian, the game's data little endian. Done: the initial DGROUP image (468 values, from the
   swap specs the translator writes into `globals.txt`). Not done: everything the game loads and then reads as multi-byte fields
   (ITEMS rows, monster and save records), see 6.
4. **Pascal string temporaries were 256 bytes each**: frames of 1 to 2 KB, which overflowed the 3.8 KB stack in the loader. They are
   now sized by the longest value the expression can have.
5. **DSKCON.** It reads its time-out from direct page `$8A:$8B` (the engine kept its far-call variables there), needs a retry with a
   delay on "not ready" after the drive sat idle, and cannot be given a task while the MMU slots hold the engine's windows: the
   wrapper (`disk.asm`) parks the engine's direct page, maps BASIC's blocks, switches to ROM mode and 0.89 MHz, retries, puts it all back.
6. **MAME, the memory test, and the harness.** MAME has two floppy drives (XRoar four, but its traps fire at the wrong time under a
   four drive setup, so MAME is the reference). Physical RAM is not zero at power on (MAME fills `$FF`): the game's heap tables
   and the stack area must be cleared by the loader. The harness reads physical RAM through the RAM device's save item; screens
   are kept when stable for two looks (`lua/watch.lua`).
7. Smaller: the picture store is linear and pictures may cross block borders (the SqrPaci bank is 36 KB), the bank pool is eight
   banks (the rest of its blocks are pictures), `-fomit-frame-pointer` is not the culprit of any defect found (the enum defect is
   independent of it).

## 4. Tools added

`make game` (the whole build, in the container), `make game-run S=<session>` (MAME run and screen check),
`scripts/game_run.sh`, `scripts/game_xroar.sh` (fast, four drives, traps unreliable), `scripts/bank_probe_mame.sh` (which banks
a run needs), `lua/watch.lua` (screens, the engine's event log `DBG`, memory dumps, the stack depth), `tools/gamecheck.py`,
`tools/mkgame.py` (split, stubs, link, engine build), `tools/mkvm.py` (DGROUP.IMG), `tools/mkgamedisk.py`, `tools/dis6809.py` (a
6809 disassembler, used on Disk BASIC's ROM), `probes/strtest.c`.

## 5. Decisions

D12 stays (hybrid). New in this step: the engine is a second MMU task (answered in 8.5a); farptr stays 32 bits (the whole game is
about 330 KB of code; 16 bit would save a fifth, at the price of the CoCo's own record layouts); the picture store is a linear
space in three runs of blocks, not one picture per block; one program disk plus data volumes, with disk swap prompts the engine
does not do yet.

## 6. What is left of 8.5 (`create-character`), in the order it blocks

1. **Disk swaps.** The session needs 22 code banks (133 KB), the BASE volume and three more (CHEAD, CBODY, HEAD3, BODY3 are on
   other volumes), 354 KB in all against two 153 KB drives. The engine must ask for a volume (a mailbox word and a prompt on
   the screen), the harness must change the image in the drive (MAME's Lua can), the engine must remount, and the bank files need
   to live on volumes too.
2. **Keys.** The PC-only keys (the lists answer to END and HOME; Home, End, PgUp, PgDn move diagonally elsewhere) need a mapping
   (D8) and `rtl_ReadKey` must give the game the PC's two-byte codes for extended keys. The harness needs a key queue in the
   mailbox and a session driver that waits for a stable screen between keys; the code wheel question differs from the recorded
   one (the title loop's Random calls depend on CPU speed), so the driver reads the question off the screen and types the answer.
3. **Engine routines the session calls**: DrawPictureItemClipped, DrawIcon, DrawSprite, DrawHeadSprite, DrawBodySprite,
   ShowHeadBodyWindow, LoadHeadBodySprites, ShowHeadBodySprites, the flicker of RemapPictureColors (needs the game's Random).
4. **File writes** (`SAVE\RAD.CHA`, `.ITM`, `.SPC`, `CHARLIST.TXT`) and the text file runtime (`read_str`, `write_str`).
5. **Byte order of loaded data**: swap descriptors per file for ITEMS, monster and save records.
6. **Budgets**: the stack has about 100 bytes to spare on the boot path, the core 130 bytes below its limit; character creation will
   go deeper. Options: shrink frames further (the 135 string temporaries still 256 bytes), move more of the runtime to the engine
   (it has the room: task 1 has 24 KB and uses 18), or give the stack more of slot 0 (move the shared data to `$0E00` is done; the
   mailbox at `$1000` is next).
7. **State comparison** on the CoCo: read DGROUP (native area and four pages) from the RAM dump, undo the layout map and the byte
   order, compare with the host's digests at the checkpoints.

An honest estimate: items 1 to 5 are each a day of the kind of work this step was; item 1 is the one with design in it.

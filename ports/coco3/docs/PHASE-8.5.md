# Step 8.5: first light (working report, in progress)

Date: 2026-10-18. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.5: the game's own code on the CoCo, title screens, main menu,
character creation; exit: the `boot-title` and `create-character` sessions match on screen and state in MAME. Tags: **[V]**
verified by running something, **[E]** estimate, **[?]** open. This file is updated as the step proceeds.

## 1. Decisions of this step (and why)

**The engine gets its own address space [V, 8.5a].** The engine runs in MMU task 1 (windows 0 and 1 at `$8000` and `$A000`, its
own code), the game in task 0 (code bank at `$8000`, data windows at `$C000` and `$E000`). Slot 0 (stack, direct page, mailbox) and
the `$FE00` page are shared. A call into the engine is `eng_enter` ... `eng_leave` (a store to `$FF91`, 10 cycles); the game's
data windows are mirrored in task 1 (`mmu_set`), so a pointer into a window stays valid inside an engine call. This took away the
reason for a third window, and it is why the engine tests all run in task 1 now (`t_task`). Found on the way: Disk BASIC's
DSKCON uses direct page byte `$8B`; anything stored there makes every read fail with status 128.

**The game's data: native, paged, mapped and banked [V, 8.5b].** The generated game reaches a global as `pool_ds + offset`; the CoCo
cannot hold that 34,656 byte image. `tools/mkplan.py` and `tools/mkvm.py` lay it out: 7.5 KB of globals stay native (chosen from the
profiles of 8.1c by references per byte, plus the System unit's variables and the globals that are passed by reference to game
routines, which would leave a stale window pointer in a callee), the other 25.6 KB are in 8 KB pages reached through two data windows
(`VMV(o)`: map the page, return the pointer). Globals that overlap move together, none straddles the last 512 bytes of a page.
**All seven recorded sessions replay on the host with this layout and the screens equal the 4bpp goldens** (`scripts/vm_host.sh`,
`c/rtl/vm.c` models the windows and counts the accessor: 1.4 M accessor calls in `boot-title`, 2.1 M in `create-character`,
11.4 M in the longest session, with 81 to 8,821 page maps).

**farptr stays 32 bits for now [E].** Compiling the laid-out game with CMOC (`scripts/game_compile.sh`) shows what a 32-bit
`farptr` costs: ovl12 23.6 KB against 15.6 KB with a 16-bit one, ovl13 25.0 against 17.6, ovl03 20.7 against 18.0; the whole game
about 330 KB against 260 KB. A 16-bit farptr needs the CoCo's own record layouts (a pointer field is 2 bytes), the file formats
converted (byte order too: the CoCo is big endian and the game's files are little endian), the proc ids renumbered. That is
the work of 8.5 only if the game is to fit in the end; first light first.

## 2. Plan of the step

| | Work | State |
|---|---|---|
| 8.5a | the engine in task 1 | done (`f3a1aca`) |
| 8.5b | DGROUP layout, host replay of all seven sessions | done (`7812ba4`) |
| 8.5c | build: units to banks (split the oversize), far stubs, core, RTL on CMOC | in progress |
| 8.5d | engine API for the replaced routines (pictures, glyphs, files, clock) | |
| 8.5e | loader, harness, `boot-title` against the goldens in MAME | |
| 8.5f | `create-character` | |

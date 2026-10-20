/* gameboot.c: the program LOADM starts when the game is played (step 8.5c): the engine. It owns task 1 and the storage. Its job at
 * the start is to build the game's address space: read the core and the initial image of the game's data from the image (img.c,
 * tools/mkimage.py) into their physical blocks (no loader of Disk BASIC can: its LOADM writes where BASIC's map has memory, and the
 * game's map is not BASIC's), give task 0 its slots, and start the game in task 0 (game_launch, in shared memory).
 *
 *   CORE / 0     the game's core, raw, to logical $2000 of task 0: physical blocks GAME_BLK, +1, +2
 *   DGROUP / 0   the native base, the native size (words, big endian), the number of pages (a byte)
 *   DGROUP / 1   the paged globals, run length coded: four pages of 8,192 bytes to the blocks VMBLK_DS
 *   DGROUP / 2   the native globals, run length coded, to the core's blocks at the native base
 * The banks are read later, one at a time, when a far call finds its bank missing (api.c: api_bankload). */
#include "eng.h"
#include "mailbox.h"
#include "gamemap.h"

extern u8 banktab[64];

int main(void)
{
    u16 i;
    u8 b, h[8];
    DaxEntry e;
    u16 nat_base;
    k_fill(banktab, 0, 64);
    irq_start();                                                        /* the frame clock */
    for (b = 0; b < 3; b++) {                                           /* the game's native memory starts as zeros (heap tables, bss) */
        win_set(0, (u8)(GAME_BLK + b));
        k_fill(WIN0, 0, 0x2000);
    }
    MB_RESULT(0) = img_mount();
    MB_RESULT(1) = img_entry("CORE    ", 0, &e);
    if (MB_RESULT(1) == 0)
        MB_RESULT(1) = img_read_blocks(e.offset, e.raw, GAME_BLK);
    MB_RESULT(2) = img_entry("DGROUP  ", 0, &e);
    if (MB_RESULT(2) == 0)
        MB_RESULT(2) = img_read(e.offset, h, 5);
    nat_base = (u16)(((u16)h[0] << 8) | h[1]);
    MB_RESULT(3) = img_entry("DGROUP  ", 1, &e);
    if (MB_RESULT(3) == 0)
        MB_RESULT(7) = dax_unpack(&img_vol.f, &e, 0, 0, VMBLK_DS, 0, 0);
    MB_RESULT(3) = img_entry("DGROUP  ", 2, &e);
    if (MB_RESULT(3) == 0)
        MB_RESULT(8) = dax_unpack(&img_vol.f, &e, 0, 0, (u8)(GAME_BLK + (nat_base >> 13) - 1), (u16)(nat_base & 0x1FFFu), 0);
    for (i = 0; i < NBPAGES; i++) {                                     /* the banked heap starts zero */
        win_set(0, (u8)(i < 4 ? VMBLK_HEAP + i : VMBLK_HEAP2 + i - 4));
        k_fill(WIN0, 0, 0x2000);
    }
    for (b = 0; b < 3; b++)                                             /* task 0's slots 1..3: the core */
        *(u8 *)(0xFFA1 + b) = (u8)(GAME_BLK + b);
    k_fill((u8 *)0x0A00, 0xAA, 0x13FF);                                 /* DEBUG: paint the stack area ($0A00..$1DFF) */
    MB_RESULT(4) = 0xC0DE;
    game_launch();
    return 0;
}

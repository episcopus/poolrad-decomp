/* gameboot.c: the program LOADM starts when the game is played (step 8.5c): the engine. It owns task 1 and the disk. Its job at
 * the start is to build the game's address space: read the core and the initial image of the game's data from the program
 * disk into their physical blocks (no loader of Disk BASIC can: its LOADM writes where BASIC's map has memory, and the game's
 * map is not BASIC's), mount the data volume, give task 0 its slots, and start the game in task 0 (game_launch, in shared memory).
 *
 *   CORE.BIN     the game's core, raw, to logical $2000 of task 0: physical blocks GAME_BLK, +1, +2
 *   DGROUP.IMG   magic "DGIM", the native base, the native size (words, big endian), then the native bytes and four pages of
 *                8,192 bytes: the initial values of the globals (tools/mkvm.py)
 * The banks are read later, one at a time, when a far call finds its bank missing (api.c: api_bankload). */
#include "eng.h"
#include "mailbox.h"
#include "gamemap.h"

extern u8 banktab[64];
extern u8 bank_drive[64];
u32 eng_read_blocks(const char *name8, const char *ext3, u8 drive, u8 first_blk);

static u8 buf[256];

int main(void)
{
    u16 i;
    u8 b;
    k_fill(banktab, 0, 64);
    irq_start();                                                        /* the frame clock (DSKCON waits on it) */
    for (b = 0; b < 3; b++) {                                           /* the game's native memory starts as zeros (heap tables, bss) */
        win_set(0, (u8)(GAME_BLK + b));
        k_fill(WIN0, 0, 0x2000);
    }
    MB_RESULT(0) = rs_mount(0);
    MB_RESULT(1) = eng_read_blocks("CORE    ", "BIN", 0, GAME_BLK) > 0 ? 0 : 1;
    /* DGROUP.IMG: the header, then the paged globals (to the consecutive blocks VMBLK_DS) and the native bytes (into the core's
     * blocks at the native base), each a run length coded block that dax_unpack takes as a DaxEntry */
    {
        RsFile f;
        DaxEntry e;
        u16 nat_base, nat_size;
        u32 pos;
        MB_RESULT(2) = rs_open(&f, 0, "DGROUP  ", "IMG");
        MB_RESULT(3) = rs_read(&f, 0, buf, 9);
        nat_base = (u16)(((u16)buf[4] << 8) | buf[5]);
        nat_size = (u16)(((u16)buf[6] << 8) | buf[7]);
        (void)nat_size;
        pos = 9;
        for (i = 0; i < 2; i++) {
            rs_read(&f, pos, buf, 4);
            e.packed = (u16)(((u16)buf[0] << 8) | buf[1]);
            e.raw = (u16)(((u16)buf[2] << 8) | buf[3]);
            e.offset = pos + 4;
            MB_RESULT(6) = (u16)(2 + i);
            if (i == 0)
                MB_RESULT(7) = dax_unpack(&f, &e, 0, 0, VMBLK_DS, 0, 0);
            else
                MB_RESULT(8) = dax_unpack(&f, &e, 0, 0, (u8)(GAME_BLK + (nat_base >> 13) - 1), (u16)(nat_base & 0x1FFFu), 0);
            pos += 4 + e.packed;
        }
        MB_RESULT(6) = 8;
        for (i = 0; i < 4; i++) {                                       /* the banked heap starts zero */
            win_set(0, (u8)(VMBLK_HEAP + i));
            k_fill(WIN0, 0, 0x2000);
        }
    }
    {   /* where the banks are: BANKS.IDX, a byte a bank id, the drive of its file (the development disks: 0, 2, 3) */
        RsFile fi;
        u8 d;
        if (rs_open(&fi, 0, "BANKS   ", "IDX") == 0 && rs_read(&fi, 0, bank_drive, 64) == 0) {
            for (d = 2; d < 4; d++)
                for (i = 0; i < 64; i++)
                    if (bank_drive[i] == d) {
                        rs_mount(d);
                        break;
                    }
        }
    }
    MB_RESULT(6) = 9;
    MB_RESULT(5) = vol_mount(&vols[1], 1);                              /* the data volume (BASE) in drive 1 */
    /* task 0's slots 1..3: the core */
    for (b = 0; b < 3; b++)
        *(u8 *)(0xFFA1 + b) = (u8)(GAME_BLK + b);
    k_fill((u8 *)0x1060, 0xAA, 0x0DA0);                                 /* DEBUG: paint the stack area ($1060..$1F5F) */
    MB_RESULT(4) = 0xC0DE;
    game_launch();
    return 0;
}

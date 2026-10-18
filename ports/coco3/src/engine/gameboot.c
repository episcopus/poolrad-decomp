/* gameboot.c: the program LOADM starts when the game is played (step 8.5c): the engine. It owns task 1 and the disk. Its job at
 * the start is to build the game's address space: read the core and the initial image of the game's data from the program
 * disk into their physical blocks (no loader of Disk BASIC can: its LOADM writes where BASIC's map has memory, and the game's
 * map is not BASIC's), give task 0 its slots, and start the game in task 0 (game_launch, in shared memory).
 *
 *   CORE.BIN     the game's core, raw, to logical $2000 of task 0: physical blocks GAME_BLK, +1, +2
 *   DGROUP.IMG   magic "DGIM", the native base, the native size (words, big endian), then the native bytes and four pages of
 *                8,192 bytes: the initial values of the globals (tools/mkvm.py)
 * The banks are read later, one at a time, when a far call finds its bank missing (api.c: eng_bank_read). */
#include "eng.h"
#include "mailbox.h"
#include "gamemap.h"

static u8 buf[256];

/* a file into physical blocks, from the first, 8,192 bytes a block; returns the size or 0 */
static u32 read_blocks(const char *name8, const char *ext3, u8 first_blk, u8 skip_header)
{
    RsFile f;
    u32 size, off;
    u16 n;
    if (rs_open(&f, 0, name8, ext3) != 0)
        return 0;
    size = (u32)(f.sectors - 1) * 256UL + f.last_bytes;
    for (off = skip_header; off < size; off += 256) {
        u32 at = off - skip_header;
        n = (u16)((size - off) < 256UL ? (size - off) : 256UL);
        if (rs_read(&f, off, buf, n) != 0)
            return 0;
        win_set(0, (u8)(first_blk + (u8)(at >> 13)));
        k_copy(WIN0 + (u16)(at & 0x1FFFu), buf, (u8)(n > 255 ? 128 : n));
        if (n > 255)
            k_copy(WIN0 + (u16)(at & 0x1FFFu) + 128, buf + 128, 128);
    }
    return size;
}

int main(void)
{
    u16 nat_base, nat_size, i;
    u8 b;
    MB_RESULT(0) = rs_mount(0);
    MB_RESULT(1) = (u16)read_blocks("CORE    ", "BIN", GAME_BLK, 0) > 0 ? 0 : 1;
    /* DGROUP.IMG: the header, the native bytes into the physical blocks of the core's slots 2 and 3, the pages */
    {
        RsFile f;
        u8 hdr[8];
        u32 pos;
        u16 left, a;
        MB_RESULT(2) = rs_open(&f, 0, "DGROUP  ", "IMG");
        MB_RESULT(3) = rs_read(&f, 0, hdr, 8);
        nat_base = (u16)(((u16)hdr[4] << 8) | hdr[5]);
        nat_size = (u16)(((u16)hdr[6] << 8) | hdr[7]);
        pos = 8;
        for (left = nat_size, a = nat_base; left > 0;) {              /* a is a logical address of task 0: slot (a >> 13) is block GAME_BLK + slot - 1 */
            u16 chunk = left > 128 ? 128 : left;
            rs_read(&f, pos, buf, chunk);
            win_set(0, (u8)(GAME_BLK + (a >> 13) - 1));
            k_copy(WIN0 + (a & 0x1FFFu), buf, (u8)chunk);
            pos += chunk;
            a += chunk;
            left -= chunk;
        }
        for (i = 0; i < 4; i++) {                                       /* the four pages of paged DGROUP */
            u8 blk = (u8)(VMBLK_DS + i);
            u16 o;
            for (o = 0; o < 0x2000; o += 128) {
                rs_read(&f, pos, buf, 128);
                win_set(0, blk);
                k_copy(WIN0 + o, buf, 128);
                pos += 128;
            }
        }
        for (i = 0; i < 4; i++) {                                       /* the banked heap starts zero */
            win_set(0, (u8)(VMBLK_HEAP + i));
            k_fill(WIN0, 0, 0x2000);
        }
    }
    dsk_motor_off();
    /* task 0's slots 1..3: the core */
    for (b = 0; b < 3; b++)
        *(u8 *)(0xFFA1 + b) = (u8)(GAME_BLK + b);
    MB_RESULT(4) = 0xC0DE;
    game_launch();
    return 0;
}

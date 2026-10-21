/* t_hide.c: step 8.9. Does the RAM of physical blocks $3C..$3F survive a DSKCON call? The call (disk.asm) maps those blocks into slots 4..7 and
 * switches to ROM mode, where they show Disk BASIC's ROM; in all-RAM mode they are ordinary RAM. If what is written there before a read is still there
 * after it, a floppy backend does not need those four blocks kept free, and they can hold code banks.
 * Each block is filled with a pattern, a file is read through DSKCON, the blocks are summed again. Found in MAME and XRoar: $3C, $3D and $3E survive; with
 * $3F filled (below the constant page) the call never returns, so $3F is left out here and stays reserved.
 * r0..r2 the sums of blocks $3C..$3E (std $A000 each)   r4 the disk read   r5 the sum of the file as the host has it */
#include "eng.h"
#include "mailbox.h"
#include "expect.h"

#define PAT 0xA5

static u16 sum_blk(u8 blk, u16 n)
{
    win_set(0, blk);
    return k_sum(WIN0, n);
}

int main(void)
{
    RsFile f;
    u8 buf[256], st, b;
    u32 size, off;
    u16 sum = 0, i, n;
    scr_clear();
    scr_puts(0, 0, "ENGINE TEST: RAM UNDER ROM");
    mb_check(8, rs_mount(0), 0);
    st = rs_open(&f, 0, "TITLE   ", "DAX");
    mb_check(9, st, 0);
    for (b = 0x3C; b <= 0x3E; b++) {
        win_set(0, b);
        k_fill(WIN0, PAT, 0x2000);
    }
    size = (u32)(f.sectors - 1) * 256UL + f.last_bytes;
    for (off = 0; off < size; off += 256) {
        n = (u16)((size - off) < 256UL ? (size - off) : 256UL);
        st = rs_read(&f, off, buf, n);
        if (st != 0)
            break;
        for (i = 0; i < n; i++)
            sum += buf[i];
    }
    mb_check(4, st, 0);
    mb_check(5, sum, TITLE_SUM16);
    for (b = 0x3C; b <= 0x3E; b++)
        mb_check((u8)(b - 0x3C), sum_blk(b, 0x2000), (u16)(0x2000UL * PAT));
    dsk_motor_off();
    MB_CHECKPOINT = 1;
    mb_finish();
    return 0;
}

/* t_vol.c: step 8.4. Every block of one volume, read from its floppy image on drive 1 (the program is on drive 0): the
 * index is mounted, every entry is unpacked into physical blocks $30.. and its size and 16-bit sum compared with the
 * values the host computed from the original DAX files (build/eng/expectvol.h, from tools/mkvolumes.py). `make vol-test
 * VOL=n` builds this for volume n; `make vol-tests` runs all nine. */
#include "eng.h"
#include "mailbox.h"
#include "expectvol.h"

#define CAT2(a, b) a##b
#define CAT(a, b) CAT2(a, b)
#define EXP_N CAT(EXPECT_N_, VOLNUM)
#define EXP_SUM CAT(expect_sum_, VOLNUM)
#define EXP_RAW CAT(expect_raw_, VOLNUM)

#define TEST_BLK 0x30                       /* 8 blocks of scratch: 64 KB, the biggest block is smaller */

int main(void)
{
    Vol *v = &vols[1];
    DaxEntry e;
    u8 file, id, blk, st;
    u16 i, left, n, bad_sum = 0, bad_unpack = 0, first_bad = 0xFFFF;
    scr_clear();
    scr_puts(0, 0, "ENGINE TEST: VOLUME");
    mb_check(0, vol_mount(v, 1), 0);
    mb_check(1, v->num, VOLNUM);
    mb_check(2, v->nent, EXP_N);
    for (i = 0; i < v->nent; i++) {
        if (vol_entry(v, i, &file, &id, &e) != 0)
            break;
        st = dax_unpack(&v->f, &e, 0, 0, TEST_BLK, 0, 0);
        if (st != 0) {
            bad_unpack++;
            if (first_bad == 0xFFFF)
                first_bad = i;
            continue;
        }
        left = e.raw;
        n = 0;
        for (blk = TEST_BLK; left > 0; blk++) {
            u16 c = left > 0x2000 ? 0x2000 : left;
            mmu_set(6, blk);
            n = (u16)(n + k_sum((u8 *)0xC000, c));
            left = (u16)(left - c);
        }
        if (n != EXP_SUM[i] || e.raw != EXP_RAW[i]) {
            bad_sum++;
            if (first_bad == 0xFFFF)
                first_bad = i;
        }
        scr_hex(2, 0, i);
    }
    dsk_motor_off();
    mb_check(3, bad_unpack, 0);
    mb_check(4, bad_sum, 0);
    mb_check(5, i, EXP_N);
    MB_RESULT(6) = first_bad;
    mb_finish();
    return 0;
}

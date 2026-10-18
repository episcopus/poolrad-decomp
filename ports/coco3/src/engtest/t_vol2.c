/* t_vol2.c: step 8.4. Two volumes mounted at once: SET 2 on drive 0 (it carries TEST.BIN too) and BASE on drive 1. Files
 * are found on whichever volume holds them (vol_lookup), a missing file is told apart from a missing block, and blocks
 * from both drives unpack and match the host's sums. (MAME's disk controller has two drives; the engine keeps four FATs
 * and indexes, XRoar could mount four.) */
#include "eng.h"
#include "mailbox.h"
#include "expectmulti.h"

#define TEST_BLK 0x30

/* a block found by file and id on any mounted volume, unpacked, its drive, size and sum compared */
static u8 check(const char *name8, u8 id, u8 want_drive, u16 want_sum, u16 want_raw)
{
    Vol *v;
    DaxEntry e;
    u16 left, n = 0;
    u8 blk;
    if (vol_lookup(name8, id, &v, &e) != 0)
        return 1;
    if (v->drive != want_drive)
        return 2;
    if (dax_unpack(&v->f, &e, 0, 0, TEST_BLK, 0, 0) != 0)
        return 3;
    left = e.raw;
    for (blk = TEST_BLK; left > 0; blk++) {
        u16 c = left > 0x2000 ? 0x2000 : left;
        win_set(0, blk);
        n = (u16)(n + k_sum((u8 *)0x8000, c));
        left = (u16)(left - c);
    }
    return (n == want_sum && e.raw == want_raw) ? 0 : 4;
}

int main(void)
{
    DaxEntry e;
    Vol *v;
    scr_clear();
    scr_puts(0, 0, "ENGINE TEST: TWO VOLUMES");
    mb_check(0, vol_mount(&vols[0], 0), 0);
    mb_check(1, vol_mount(&vols[1], 1), 0);
    mb_check(2, vols[0].num * 10 + vols[1].num, 20);                              /* SET 2 on drive 0, BASE on drive 1 */
    mb_check(3, check("ECL2    ", EXPECT_ECL2_ID, 0, EXPECT_ECL2_SUM, EXPECT_ECL2_RAW), 0);
    mb_check(4, check("COMSPR  ", EXPECT_COMSPR_ID, 1, EXPECT_COMSPR_SUM, EXPECT_COMSPR_RAW), 0);
    mb_check(5, vol_lookup("TITLE   ", 1, &v, &e), 1);                              /* a file on no mounted volume */
    mb_check(6, vol_lookup("ECL2    ", 250, &v, &e), 2);                            /* a mounted file, no such block */
    mb_check(7, vol_find(&vols[1], "ECL2    ", 1, &e), 1);                          /* not on this volume */
    mb_check(8, vol_find(&vols[0], "ECL2    ", EXPECT_ECL2_ID, &e), 0);
    dsk_motor_off();
    mb_finish();
    return 0;
}

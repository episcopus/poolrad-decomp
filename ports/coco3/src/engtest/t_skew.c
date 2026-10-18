/* t_skew.c: step 8.4a. How fast does DSKCON read sectors, and does the order matter? A sector read is one DSKCON call;
 * after it the disk has turned on, so the next sector in the track order may already have passed. This reads 4 tracks
 * (72 sectors) in orders that step through a track by 1, 2, 3 ... sectors and counts frames (60 Hz) for each; r(k) is the
 * frames for step k = 1..9 (and track 0 first, to be past the first seek). Physical order in a .DSK image is the logical
 * order, the emulators place sector n at angle n, so the numbers show what an interleave would gain. */
#include "eng.h"
#include "mailbox.h"

int main(void)
{
    u8 step, t, i, s, n, left, used[19];
    u16 f0;
    gfx_init();
    irq_start();
    dsk_read(0, 1, 1);                                       /* spin up, seek */
    for (step = 1; step <= 11; step++) {
        if (step == 10)
            tick_start(64);                                  /* 237 Hz FIRQ running: sequential, then step 3 */
        if (step == 11)
            tick_stop();
        if (step >= 10) {
            u8 kk = (u8)(step == 10 ? 1 : 3);
            (void)kk;
        }
        f0 = frame_count();
        for (t = 1; t <= 4; t++) {
            for (i = 1; i <= 18; i++)
                used[i] = 0;
            s = 1;
            left = 18;
            while (left > 0) {
                n = 0;
                while (used[s] && n < 18) {                 /* next unread sector at or after s */
                    s = (u8)(s % 18 + 1);
                    n++;
                }
                used[s] = 1;
                mb_check(31, dsk_read(0, t, s), 0);
                left--;
                s = (u8)((s - 1 + (step == 10 ? 1 : step == 11 ? 3 : step)) % 18 + 1);
            }
        }
        MB_RESULT(step) = (u16)(frame_count() - f0);
    }
    {   /* the same 133 sectors as a file: TITLE.DAX through rs_read */
        RsFile f;
        u8 buf[256];
        u32 off;
        rs_mount(0);
        rs_open(&f, 0, "TITLE   ", "DAX");
        f0 = frame_count();
        for (off = 0; off < 33792UL; off += 256)
            rs_read(&f, off, buf, 256);
        MB_RESULT(12) = (u16)(frame_count() - f0);
        f0 = frame_count();
        for (n = 1; n <= 9; n++)                               /* the first granule's 9 sectors by hand */
            dsk_read(0, 0, n);
        MB_RESULT(13) = (u16)(frame_count() - f0);
    }
    irq_stop();
    dsk_motor_off();
    mb_finish();
    return 0;
}

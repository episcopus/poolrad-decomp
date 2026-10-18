/* t_irq.c: step 8.3d. The frame clock, the fast tick and the keyboard scan of src/engine/irq.asm.
 *
 *   cp 1..4   60 frames apart: MAME's .cp file timestamps them in emulated seconds (tools/engcheck.py: one second each,
 *             at the 59.92 Hz of the NTSC machine); the GIME timer ticks 237.9 Hz at reload 64, so about 238 ticks (XRoar 238, MAME 236 at reload 64: a tick is reload + 2 units of 63.7 us)
 *             must fall in the 60 frames between cp 1 and cp 2 (r1), in any emulator.
 *   cp 5      "press keys now": MAME's Lua script types a string (MB_KEYS) into the keyboard matrix; the program
 *             collects what kbd_get returns for four seconds (r2 = count, r3.. = codes). XRoar has nobody typing: 0 keys.
 * Last the whole of TITLE.DAX is read from the disk with the interrupts on: dsk_read masks them for each sector, hands
 * the caller's mask back, and the frame clock goes on (r20 = the checksum matches, r21 = frames counted after the
 * read, r22 = frames counted during it: about 330, DSKCON lets the interrupt through between sectors, so the clock
 * keeps time through a disk read). */
#include "eng.h"
#include "mailbox.h"
#include "expect.h"

static void wait_frames(u16 n)
{
    u16 target = (u16)(frame_count() + n);
    while ((s16)(frame_count() - target) < 0)
        ;
}

int main(void)
{
    u16 t0, t1, n = 0, i;
    u8 k;
    gfx_init();
    irq_start();
    tick_start(64);
    wait_frames(1);
    t0 = tick_count();
    MB_CHECKPOINT = 1;
    wait_frames(60);
    t1 = tick_count();
    MB_CHECKPOINT = 2;
    mb_check(0, (u16)(t1 - t0) >= 232 && (u16)(t1 - t0) <= 241, 1);
    MB_RESULT(16) = (u16)(t1 - t0);
    wait_frames(60);
    MB_CHECKPOINT = 3;
    wait_frames(60);
    MB_CHECKPOINT = 4;
    wait_frames(10);
    MB_CHECKPOINT = 5;
    for (i = 0; i < 240 && n < 8; i++) {
        wait_frames(1);
        while ((k = kbd_get()) != 0 && n < 8) {
            MB_RESULT(3 + n) = k;
            n++;
        }
    }
    MB_RESULT(2) = n;
    {
        RsFile f;
        u8 buf[256];
        u32 size, off;
        u16 sum = 0, j, m, f0, f1, f2;
        mb_check(24, rs_mount(0), 0);
        mb_check(25, rs_open(&f, 0, "TITLE   ", "DAX"), 0);
        size = (u32)(f.sectors - 1) * 256UL + f.last_bytes;
        f0 = frame_count();
        for (off = 0; off < size; off += 256) {
            m = (u16)((size - off) < 256UL ? (size - off) : 256UL);
            if (rs_read(&f, off, buf, m) != 0)
                break;
            for (j = 0; j < m; j++)
                sum += buf[j];
        }
        f1 = frame_count();
        wait_frames(5);
        f2 = frame_count();
        MB_RESULT(20) = sum == TITLE_SUM16;
        MB_RESULT(21) = (u16)(f2 - f1);
        MB_RESULT(22) = (u16)(f1 - f0);
        mb_check(26, sum == TITLE_SUM16 && (u16)(f2 - f1) >= 5, 1);
    }
    tick_stop();
    irq_stop();
    mb_finish();
    return 0;
}

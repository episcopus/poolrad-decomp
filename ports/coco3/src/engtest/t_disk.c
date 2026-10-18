/* t_disk.c: step 8.3a. Mount the disk, find TITLE.DAX in the directory, read all of it through DSKCON sector by sector
 * and compare the size and a 16-bit sum with what the host computed (build/eng/expect.h). */
#include "eng.h"
#include "mailbox.h"
#include "expect.h"

int main(void)
{
    RsFile f;
    u8 buf[256];
    u32 size, off;
    u16 sum = 0, i, n;
    u8 st;

    scr_clear();
    scr_puts(0, 0, "ENGINE TEST: DISK");
    mb_check(0, rs_mount(0), 0);
    st = rs_open(&f, 0, "TITLE   ", "DAX");
    mb_check(1, st, 0);
    size = (u32)(f.sectors - 1) * 256UL + f.last_bytes;
    mb_check(2, (u16)(size & 0xFFFFu), (u16)(TITLE_SIZE & 0xFFFFUL));
    mb_check(3, (u16)(size >> 16), (u16)(TITLE_SIZE >> 16));
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
    rs_read(&f, 0, buf, 2);                         /* the header size, little endian */
    mb_check(6, (u16)(buf[0] | ((u16)buf[1] << 8)), TITLE_HS);
    dsk_motor_off();
    MB_CHECKPOINT = 1;
    mb_finish();
    return 0;
}

/* strint.c: the minutes of the location line: Str(8, m), '0' + m, with the literal as the translation writes it.
 * r0 len of '0'+m (std 2)  r1 its first two chars (std $3038)  r2 the literal's length byte (std 1)  r3 its char (std $30) */
#include "mailbox.h"
#include "../src/game/rtl_strx.c"
#include "../src/game/rtl_str.c"

int main(void)
{
    u8 m[3], t1[256];
    const u8 *lit = (const u8 *)"\0010";
    memset(m, 0, sizeof(m));
    rtl_str_int(m, 2, 8, 0);
    rtl_str_assign(m, 2, rtl_str_cat_v(t1, 2, lit, m));
    MB_RESULT(0) = m[0];
    MB_RESULT(1) = (u16)(((u16)m[1] << 8) | m[2]);
    MB_RESULT(2) = lit[0];
    MB_RESULT(3) = lit[1];
    mb_finish();
    return 0;
}

/* strtest.c: the CoCo runtime's Pascal string routines (src/game/rtl_str.c) as the game calls them in Load8x8Bank:
 * rtl_str_int(NumSet, 1, TileSet, 0) then rtl_str_cat_v(t1, 2, "\0048x8d", NumSet).
 * r0 length of the result | std=5      r1..r3 its first characters '8x' 'd1'  | std=$3878 $6431 */
#include "mailbox.h"
#include "../src/game/rtl_str.c"

int main(void)
{
    u8 num[2], t1[256];
    const u8 *lit = (const u8 *)"\0048x8d";
    memset(num, 0, sizeof(num));
    rtl_str_int(num, 1, 1, 0);
    rtl_str_cat_v(t1, 2, lit, num);
    MB_RESULT(0) = t1[0];
    MB_RESULT(1) = (u16)((t1[1] << 8) | t1[2]);
    MB_RESULT(2) = (u16)((t1[3] << 8) | t1[4]);
    MB_RESULT(3) = (u16)((t1[5] << 8) | t1[6]);
    MB_RESULT(4) = (u16)((num[0] << 8) | num[1]);
    mb_finish();
    return 0;
}

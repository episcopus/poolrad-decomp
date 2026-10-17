/* byte-arith.c: how CMOC computes binary operations on byte operands (PORTING-GUIDE 6.1).
 * Runs on the CoCo (make probe P=byte-arith); every result word is compared with what
 * standard C and Turbo Pascal give ("std"). A mismatch is a CMOC difference.
 *
 * r0  row * 40, row = 10 (unsigned char)           | std=400
 * r1  a + b, 200 + 100 (unsigned char)              | std=300
 * r2  low word of (long)w1 + w2, 60000 + 10000      | std=4464
 * r3  high word of the same                         | std=1
 * r4  k - 10, k = 7 (unsigned char), stored in int  | std=65533
 * r5  (unsigned char)(a << 1), a = 200              | std=144
 * r6  si < 0u, si = -1                              | std=0
 * r7  sa / ub, sa = -8 (int), ub = 2 (unsigned)     | std=32764
 * r8  (a + b) >> 1, bytes 200 and 100               | std=150
 * r9  a + 100, a = 200                              | std=300
 * r10 u - v, u = 7, v = 10 (unsigned char)          | std=65533
 * r11 (unsigned int)row * 40  (the fix)             | std=400
 * r12 (unsigned int)a + b     (the fix)             | std=300
 * r13 (int)k - 10             (the fix, signed)     | std=65533
 */
#include "mailbox.h"

unsigned char row = 10, a = 200, b = 100, k = 7, u = 7, v = 10, ub = 2;
unsigned int w1 = 60000u, w2 = 10000u;
int si = -1, sa = -8;

int main(void)
{
    long l;
    unsigned int r;

    scr_clear();
    scr_puts(0, 0, "PROBE BYTE-ARITH");
    r = row * 40;                          mb_check(0, r, 400u);
    r = a + b;                             mb_check(1, r, 300u);
    l = (long)w1 + w2;                     mb_check(2, (unsigned int)l, 4464u);
                                           mb_check(3, (unsigned int)(l >> 16), 1u);
    r = (unsigned int)(k - 10);            mb_check(4, r, 65533u);
    r = (unsigned char)(a << 1);           mb_check(5, r, 144u);
    r = (si < 0u);                         mb_check(6, r, 0u);
    r = (unsigned int)(sa / ub);           mb_check(7, r, 32764u);
    r = (a + b) >> 1;                      mb_check(8, r, 150u);
    r = a + 100;                           mb_check(9, r, 300u);
    r = (unsigned int)(u - v);             mb_check(10, r, 65533u);
    r = (unsigned int)row * 40;            mb_check(11, r, 400u);
    r = (unsigned int)a + b;               mb_check(12, r, 300u);
    r = (unsigned int)((int)k - 10);       mb_check(13, r, 65533u);
    mb_finish();
    return 0;
}

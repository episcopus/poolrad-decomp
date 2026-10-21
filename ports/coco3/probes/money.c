/* money.c: ScaleMoney as the game has it on the CoCo (tools/mkgame.py PATCHES ovl07): Money * Keep / 100 on a 16 bit amount and a 16 bit percentage,
 * with the 32 bit product (CMOC's 32 bit multiply and divide on the 6809). The wanted values are the exact integer scaling, floor(Money * Keep / 100), from the host.
 * The original's 40 bit Real can differ from it by one coin in 0.03 % of the cases (docs/PHASE-8.9a.md section 9).
 * r0 cases tried (std 15)  r1 cases wrong (std 0)  r2 the first wrong case, 1 based, 0 = none */
#include "mailbox.h"
typedef unsigned char u8;
typedef unsigned short u16;
typedef short s16;
typedef long s32;

typedef struct { u16 money; s16 keep; u16 want; } Case;
static const Case cases[] = {
    {100, 100, 100}, {100, 70, 70}, {100, 0, 0}, {100, 50, 50}, {1, 99, 0}, {65535, 100, 65535}, {65535, 1, 655},
    {65535, 50, 32767}, {12345, 70, 8641}, {999, 33, 329}, {50, 30, 15}, {7, 90, 6}, {0, 80, 0}, {65535, 99, 64879},
    {1000, 85, 850},
};

static u16 scale(u16 money, s16 keep)
{
    u16 m = money;
    m = (u16)((s32)m * keep / 100);
    return m;
}

int main(void)
{
    u8 i, bad = 0, first = 0;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++)
        if (scale(cases[i].money, cases[i].keep) != cases[i].want) {
            if (!bad)
                first = (u8)(i + 1);
            bad++;
        }
    MB_RESULT(0) = (u16)(sizeof(cases) / sizeof(cases[0]));
    MB_RESULT(1) = bad;
    MB_RESULT(2) = first;
    mb_finish();
    return 0;
}

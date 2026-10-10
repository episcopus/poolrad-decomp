/* rtl_random.c: the Turbo Pascal 6.0 generator (WHITEPAPER 5.13).
 *
 *   RandSeed (DS:4428, low word first) := RandSeed * 08088405h + 1 mod 2^32.
 *   Random(range) = hi16(RandSeed) mod range (0 when range is 0).
 *
 * This is TP 6's div, not the multiply-and-shift of TP 7. Verified against
 * the oracle's log of every generator call (tests/unit/test_oracle.py) and
 * by isolated differential fuzz of 0AF8:11C0 (tools/fuzz/fuzz.py).
 */
#include "pool_rtl.h"

void rtl_random_step(void)
{
    G.RandSeed = G.RandSeed * (u32)0x08088405u + 1u;
}

u16 rtl_random_range(u16 range)
{
    /* The step runs first: with range 0 the original still advances RandSeed
     * and returns 0 (0AF8:11C0 calls 0AF8:120F before the jz). */
    rtl_random_step();
    if (range == 0u) {
        return 0u;
    }
    return (u16)(((G.RandSeed >> 16) & 0xFFFFu) % (u32)range);
}

void rtl_randomize(u8 hour, u8 minute, u8 sec, u8 hund)
{
    /* DOS GetTime AH=2Ch: CH=hour CL=min DH=sec DL=hund; the original
     * (0AF8:1247) stores DX:CX, seconds/hundredths high, hours/minutes low. */
    u32 hi = ((u32)sec << 8) | (u32)hund;
    u32 lo = ((u32)hour << 8) | (u32)minute;
    G.RandSeed = (hi << 16) | lo;
}

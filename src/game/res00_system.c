/* res00_system.c: the Turbo Pascal System unit (res00, 0AF8:0000..0C7C:0000).
 *
 * P3 spike: three leaf routines that prove the memory model (SPEC 7.3) in both
 * builds. The rest of the unit arrives in P4 in queue order.
 */
#include "pool_rtl.h"
#include "../game/res00_system.h"

/* 0AF8:1685 (unit 'System', res00) verified: L2 2026-10-10
 * Original: Pascal procedure Move(var source; var dest; count: Word),
 * callee pops 10 param bytes (retf 10). Overlapping-safe block move. */
void System_Move(farptr src, farptr dst, u16 count)
{
    rtl_move(src, dst, count);
}

/* 0AF8:16A8 (unit 'System', res00) verified: L2 2026-10-10
 * Original: Pascal procedure FillChar(var x; count: Word; value: Char),
 * callee pops 8 param bytes (retf 8). */
void System_FillChar(farptr dst, u16 count, u8 value)
{
    rtl_fillchar(dst, count, value);
}

/* 0AF8:11C0 (unit 'System', res00) verified: L2 2026-10-10
 * Original: Pascal function Random(range: Word): Word, callee pops 2 param
 * bytes (retf 2); calls the step at 0AF8:120F first, then hi16(RandSeed) div
 * range. A range of 0 still steps the seed and returns 0. */
u16 System_Random(u16 range)
{
    return rtl_random_range(range);
}

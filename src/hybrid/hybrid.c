/* hybrid.c: glue that runs C routines inside the oracle (SPEC 8.4).
 *
 * The hybrid library exports one entry point per lifted routine. FP() and G
 * address the buffer the harness binds. For a session that buffer is the
 * guest's conventional RAM (the oracle maps it with mem_map_ptr), so a store
 * in C is a store in the guest. No time is charged: session replays answer
 * the game's reads of the outside world from the original's recording
 * (tools/oracle/replay.py).
 *
 * P3 spike: the three System routines, plus the Randomize seed packing.
 * Later units add their exports here without changing the mechanism.
 */
#include "pool_rtl.h"
#include "../game/res00_system.h"

/* Pointer to G inside the bound buffer (guest DGROUP when a session is bound). */
pool_dgroup_t *pool_g_ptr(void)
{
    return &G;
}

/* 0AF8:1685 System_Move(src, dst, count); original pops 10 param bytes. */
void hybrid_System_Move(farptr src, farptr dst, u16 count)
{
    System_Move(src, dst, count);
}

/* 0AF8:16A8 System_FillChar(dst, count, value); original pops 8. */
void hybrid_System_FillChar(farptr dst, u16 count, u8 value)
{
    System_FillChar(dst, count, value);
}

/* 0AF8:11C0 System_Random(range); original pops 2. Seed handling is in G. */
u16 hybrid_System_Random(u16 range)
{
    return System_Random(range);
}

/* 0AF8:1247 System_Randomize: INT 21h AH=2Ch, then RandSeed := DX:CX.
 * The hybrid library does not call the platform; the caller passes the
 * four time fields the interrupt returned. */
void hybrid_rtl_randomize(u8 hour, u8 minute, u8 sec, u8 hund)
{
    rtl_randomize(hour, minute, sec, hund);
}

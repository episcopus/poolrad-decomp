/* hybrid.c: glue that runs C routines inside the oracle (SPEC 8.4).
 *
 * The hybrid library exports one entry point per lifted routine with the same
 * parameters the Pascal routine takes, operating through FP() and G on bound
 * memory. The Python harness (tools/oracle/hybrid.py) binds a mirror buffer,
 * syncs the bytes the routine touches, and calls these; timing.py charges the
 * original's recorded cost, so the run keeps the original's time.
 *
 * P3 spike: the three System routines only. Later units add their exports
 * here without changing the mechanism.
 */
#include "pool_rtl.h"
#include "../game/res00_system.h"

/* Access to the DGROUP mirror for routines that read/write globals (Random):
 * the harness copies RandSeed between the guest DGROUP and this pointer
 * around the call. */
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

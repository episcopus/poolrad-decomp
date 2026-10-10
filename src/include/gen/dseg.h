/* dseg.h: DGROUP mirror, GENERATED from re/dseg.toml by tools/re/gen_dseg.py.
 * Do not edit by hand; edit re/dseg.toml and regenerate. */
#ifndef POOLRAD_GEN_DSEG_H
#define POOLRAD_GEN_DSEG_H

#include "../types.h"
#include <stddef.h>

typedef struct {
    u8 _pad0[0x43EE];
    u16 HeapOrg_related;
    u8 _pad1[0x4];
    u16 HeapPtr_lo;
    u16 HeapPtr_hi_or_dup;
    u16 HeapEnd;
    u8 _pad2[0x8];
    u16 unk_4402;
    u8 _pad3[0x2];
    u16 unk_4406;
    u8 _pad4[0x2];
    u16 DosMemTop;
    u8 _pad5[0x2];
    u16 unk_440E;
    u8 _pad6[0x4];
    u16 unk_4414;
    u8 _pad7[0xC];
    u16 PspSegment;
    u8 _pad8[0x4];
    u32 RandSeed;
    u8 _pad9[0xBBD4];
} pool_dgroup_t;

extern pool_dgroup_t G;

POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, HeapOrg_related) == 0x43EE, HeapOrg_related);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, HeapPtr_lo) == 0x43F4, HeapPtr_lo);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, HeapPtr_hi_or_dup) == 0x43F6, HeapPtr_hi_or_dup);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, HeapEnd) == 0x43F8, HeapEnd);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, unk_4402) == 0x4402, unk_4402);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, unk_4406) == 0x4406, unk_4406);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, DosMemTop) == 0x440A, DosMemTop);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, unk_440E) == 0x440E, unk_440E);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, unk_4414) == 0x4414, unk_4414);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, PspSegment) == 0x4422, PspSegment);
POOL_STATIC_ASSERT(offsetof(pool_dgroup_t, RandSeed) == 0x4428, RandSeed);

#endif /* POOLRAD_GEN_DSEG_H */

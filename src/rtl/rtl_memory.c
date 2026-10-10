/* rtl_memory.c: arena, the DGROUP mirror, Move and FillChar (SPEC 7.3, 7.4).
 *
 * Move and FillChar keep the original's direction choice: forward (cld) unless
 * the ranges overlap with dst above src, in which case backward (std), one
 * byte at a time. A count of 0 moves nothing.
 */
#include "pool_rtl.h"

static u8 pool_arena[POOL_MEM_SIZE];

u8 *pool_mem_base = pool_arena;
u32 pool_mem_size = POOL_MEM_SIZE;

pool_dgroup_t G;

void pool_mem_init(void)
{
    pool_mem_base = pool_arena;
    pool_mem_size = POOL_MEM_SIZE;
}

void pool_hybrid_bind(u8 *base, u32 size)
{
    pool_mem_base = base;
    pool_mem_size = size;
}

void rtl_move(farptr src, farptr dst, u16 count)
{
    u32 s = POOL_LINEAR(src);
    u32 d = POOL_LINEAR(dst);
    u32 n = (u32)count;
    u32 i;

    if (n == 0u) {
        return;
    }
    /* Direction is the original's `cmp si,di; jae` on the offsets alone
     * (0AF8:1696): forward when the source offset is at or above the
     * destination offset, else backward from the end. Segments play no part.
     * QUIRK: with overlapping ranges the copy is destructive, like rep
     * movsb (a forward copy with dst below src smears the source); it is
     * not memmove. Both builds share this loop, so the quirk is identical. */
    if (POOL_OFF(src) >= POOL_OFF(dst)) {
        for (i = 0u; i < n; i++) {
            pool_mem_base[d + i] = pool_mem_base[s + i];
        }
    } else {
        for (i = n; i > 0u; i--) {
            pool_mem_base[d + i - 1u] = pool_mem_base[s + i - 1u];
        }
    }
}

void rtl_fillchar(farptr dst, u16 count, u8 value)
{
    u32 d = POOL_LINEAR(dst);
    u32 n = (u32)count;
    u32 i;

    for (i = 0u; i < n; i++) {
        pool_mem_base[d + i] = value;
    }
}

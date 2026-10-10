/* rtl_memory.c: arena, the DGROUP image, Move and FillChar (SPEC 7.3, 7.4).
 *
 * Move follows the bytes at 0AF8:1685: cld, then `cmp si,di; jae` so the
 * direction is the offsets alone (segments play no part). The backward path
 * executes std and does not cld before retf, so DF stays set whenever the
 * source offset is below the destination offset, including a count of 0.
 * The C function has no flags; the hybrid hook sets DF (tools/oracle/hybrid.py).
 *
 * rep movsb / rep stosb wrap the 16-bit offset and keep the segment. A copy
 * that starts near the top of a segment continues at offset 0 of that same
 * segment, which is not the next linear address.
 *
 * Within one segment the direction rule matches memmove. It smears when the
 * offset order and the linear order disagree: source offset above destination
 * offset (forward path) while the destination's linear address is above the
 * source, which happens when the segments differ and the ranges overlap.
 * A count of 0 moves nothing.
 */
#include "pool_rtl.h"

static u8 pool_arena[POOL_MEM_SIZE];

u8 *pool_mem_base = pool_arena;
u32 pool_mem_size = POOL_MEM_SIZE;
u32 pool_dgroup_linear = POOL_DGROUP_LINEAR;

void pool_mem_init(void)
{
    pool_mem_base = pool_arena;
    pool_mem_size = POOL_MEM_SIZE;
    pool_dgroup_linear = POOL_DGROUP_LINEAR;
}

void pool_hybrid_bind(u8 *base, u32 size)
{
    pool_mem_base = base;
    pool_mem_size = size;
}

void pool_hybrid_set_dgroup(u32 linear)
{
    pool_dgroup_linear = linear;
}

static u8 *byte_at(u16 seg, u16 off)
{
    u32 lin = ((u32)seg * 16u + (u32)off) & 0xFFFFFu;
    return pool_mem_base + lin;
}

void rtl_move(farptr src, farptr dst, u16 count)
{
    u16 s_off = POOL_OFF(src);
    u16 d_off = POOL_OFF(dst);
    u16 s_seg = POOL_SEG(src);
    u16 d_seg = POOL_SEG(dst);
    u16 i;

    if (count == 0u) {
        return;
    }
    /* cmp si, di; jae at 0AF8:1696. Forward when the source offset is at or
     * above the destination offset. */
    if (s_off >= d_off) {
        for (i = 0u; i < count; i++) {
            u16 so = (u16)(s_off + i);
            u16 ddo = (u16)(d_off + i);
            *byte_at(d_seg, ddo) = *byte_at(s_seg, so);
        }
    } else {
        for (i = count; i > 0u; i--) {
            u16 so = (u16)(s_off + (u16)(i - 1u));
            u16 ddo = (u16)(d_off + (u16)(i - 1u));
            *byte_at(d_seg, ddo) = *byte_at(s_seg, so);
        }
    }
}

void rtl_fillchar(farptr dst, u16 count, u8 value)
{
    u16 d_off = POOL_OFF(dst);
    u16 d_seg = POOL_SEG(dst);
    u16 i;

    for (i = 0u; i < count; i++) {
        *byte_at(d_seg, (u16)(d_off + i)) = value;
    }
}

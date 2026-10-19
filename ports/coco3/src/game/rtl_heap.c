/* rtl_heap.c: the game's two heaps on the CoCo (step 8.5c). The mapped heap is native memory from MAPPED_LO to
 * MAPPED_HI (the pointer is the address), for the records game logic keeps hold of; the banked heap is four pages of 7,680
 * usable bytes reached through the data windows, for the cold blocks. Both hand out 8 byte units. A block is never split over
 * a page, so a window always shows the whole of it. */
#include "pool.h"

/* This code lives in the runtime bank, which holds no variables: the heap's tables are at a fixed place in native memory. */
#define BHEAP_LIN0 0x2C7C0UL
#define NBLKM 128
#define NBLKB 16
/* A block is 4 bytes: its offset and its size, which is a multiple of 8, so bit 0 of the word says whether it is in use. The
 * mapped table is 128 entries: the shop lists (ovl06) hold more than 64 blocks, fatal 0x20 of step 8.9's first baseline run. */
typedef struct Blk { u16 off, sz; } Blk;
#define BSIZE(b) ((u16)((b).sz & 0xFFF8u))
#define BUSED(b) ((b).sz & 1u)
#define SETSZ(b, n, u) ((b).sz = (u16)((n) | (u)))
struct HeapData { Blk mblk[NBLKM]; Blk bblk[NBLKB]; u8 nm, nb, ready; };
#define HD ((struct HeapData *)HEAPDATA)
#define mblk (HD->mblk)
#define bblk (HD->bblk)
#define nm (HD->nm)
#define nb (HD->nb)
#define heap_ready (HD->ready)

static void rtl_heap_init(void);

static int alloc(Blk *t, u8 *cnt, u8 cap, u16 n)
{
    u8 i, j;
    for (i = 0; i < *cnt; i++) {
        if (!BUSED(t[i]) && BSIZE(t[i]) >= n) {
            if (BSIZE(t[i]) > n) {                        /* split */
                if (*cnt == cap)
                    rtl_fatal_code(0x20, n);
                for (j = *cnt; j > i + 1; j--)
                    t[j] = t[j - 1];
                (*cnt)++;
                t[i + 1].off = (u16)(t[i].off + n);
                SETSZ(t[i + 1], (u16)(BSIZE(t[i]) - n), 0);
                SETSZ(t[i], n, 1);
            }
            else
                t[i].sz |= 1;
            return i;
        }
    }
    return -1;
}

static void release(Blk *t, u8 *cnt, u16 off)
{
    u8 i, j;
    for (i = 0; i < *cnt; i++) {
        if (t[i].off == off && BUSED(t[i])) {
            t[i].sz &= 0xFFF8u;
            if (i + 1 < *cnt && !BUSED(t[i + 1]) && (u16)(t[i].off + BSIZE(t[i])) == t[i + 1].off) {
                SETSZ(t[i], (u16)(BSIZE(t[i]) + BSIZE(t[i + 1])), 0);
                for (j = i + 1; j + 1 < *cnt; j++)
                    t[j] = t[j + 1];
                (*cnt)--;
            }
            if (i > 0 && !BUSED(t[i - 1]) && (u16)(t[i - 1].off + BSIZE(t[i - 1])) == t[i].off) {
                SETSZ(t[i - 1], (u16)(BSIZE(t[i - 1]) + BSIZE(t[i])), 0);
                for (j = i; j + 1 < *cnt; j++)
                    t[j] = t[j + 1];
                (*cnt)--;
            }
            return;
        }
    }
    rtl_fatal_code(0x21, off);
}

static void rtl_heap_init(void)
{
    u8 k;
    heap_ready = 1;
    mblk[0].off = MAPPED_LO;
    SETSZ(mblk[0], (u16)((MAPPED_HI - MAPPED_LO) & 0xFFF8u), 0);
    nm = 1;
    for (k = 0; k < 4; k++) {                           /* four pages of 7,680 usable bytes */
        bblk[k].off = (u16)(k * 0x2000u);
        SETSZ(bblk[k], 0x1E00, 0);
    }
    nb = 4;
}

farptr rtl_getmem_m(u16 size)
{
    int i;
    if (size == 0)
        return 0;
    if (!heap_ready)
        rtl_heap_init();
    i = alloc(mblk, &nm, NBLKM, (u16)((size + 7u) & 0xFFF8u));
    if (i < 0)
        rtl_fatal_code(0x22, size);
    return POOL_FARPTR(POOL_DS_SEG, mblk[i].off);
}

farptr rtl_getmem(u16 size)
{
    int i;
    u32 lin;
    if (size == 0)
        return 0;
    if (!heap_ready)
        rtl_heap_init();
    if (size > 0x1E00u)
        rtl_fatal_code(0x23, size);
    i = alloc(bblk, &nb, NBLKB, (u16)((size + 7u) & 0xFFF8u));
    if (i < 0)
        rtl_fatal_code(0x24, size);
    lin = 0x2C7C0UL + ((u32)(bblk[i].off >> 13) << 13) + (bblk[i].off & 0x1FFFu);
    return POOL_FARPTR((u16)(lin >> 4), (u16)(lin & 15u));
}

void rtl_freemem(farptr p, u16 size)
{
    u16 seg = (u16)(p >> 16), off = (u16)p;
    u32 rel;
    (void)size;
    if (p == 0)
        return;
    if (seg == POOL_DS_SEG && off >= MAPPED_LO && off < MAPPED_HI) {
        release(mblk, &nm, off);
        return;
    }
    rel = (((u32)seg << 4) + off) - 0x2C7C0UL;
    release(bblk, &nb, (u16)rel);
}

/* MaxAvail and MemAvail: the PC's heap had hundreds of kilobytes free in every recorded session and the game only asks whether a
 * sprite fits (ovl28 FreeMemoryFloor): the CoCo's pictures are the engine's, so the answer is "plenty" */
s32 rtl_MaxAvail(void)
{
    return 200000L;
}

s32 rtl_MemAvail(void)
{
    return 200000L;
}

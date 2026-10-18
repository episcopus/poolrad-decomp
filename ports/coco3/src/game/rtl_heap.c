/* rtl_heap.c: the game's two heaps on the CoCo (step 8.5c). The mapped heap is native memory from MAPPED_LO to
 * MAPPED_HI (the pointer is the address), for the records game logic keeps hold of; the banked heap is four pages of 7,680
 * usable bytes reached through the data windows, for the cold blocks. Both hand out 8 byte units. A block is never split over
 * a page, so a window always shows the whole of it. */
#include "pool.h"

/* This code lives in the runtime bank, which holds no variables: the heap's tables are at a fixed place in native memory. */
#define BHEAP_LIN0 0x2C7C0UL
#define NBLK 32
typedef struct Blk { u16 off, size; u8 used; } Blk;
struct HeapData { Blk mblk[NBLK]; Blk bblk[NBLK]; u8 nm, nb, ready; };
#define HD ((struct HeapData *)HEAPDATA)
#define mblk (HD->mblk)
#define bblk (HD->bblk)
#define nm (HD->nm)
#define nb (HD->nb)
#define heap_ready (HD->ready)

static void rtl_heap_init(void);

static int alloc(Blk *t, u8 *cnt, u16 n)
{
    u8 i, j;
    for (i = 0; i < *cnt; i++) {
        if (!t[i].used && t[i].size >= n) {
            if (t[i].size > n) {                          /* split */
                if (*cnt == NBLK)
                    rtl_fatal_code(0x20, n);
                for (j = *cnt; j > i + 1; j--)
                    t[j] = t[j - 1];
                (*cnt)++;
                t[i + 1].off = (u16)(t[i].off + n);
                t[i + 1].size = (u16)(t[i].size - n);
                t[i + 1].used = 0;
                t[i].size = n;
            }
            t[i].used = 1;
            return i;
        }
    }
    return -1;
}

static void release(Blk *t, u8 *cnt, u16 off)
{
    u8 i, j;
    for (i = 0; i < *cnt; i++) {
        if (t[i].off == off && t[i].used) {
            t[i].used = 0;
            if (i + 1 < *cnt && !t[i + 1].used && (u16)(t[i].off + t[i].size) == t[i + 1].off) {
                t[i].size = (u16)(t[i].size + t[i + 1].size);
                for (j = i + 1; j + 1 < *cnt; j++)
                    t[j] = t[j + 1];
                (*cnt)--;
            }
            if (i > 0 && !t[i - 1].used && (u16)(t[i - 1].off + t[i - 1].size) == t[i].off) {
                t[i - 1].size = (u16)(t[i - 1].size + t[i].size);
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
    mblk[0].size = (u16)(MAPPED_HI - MAPPED_LO);
    mblk[0].used = 0;
    nm = 1;
    for (k = 0; k < 4; k++) {                           /* four pages of 7,680 usable bytes */
        bblk[k].off = (u16)(k * 0x2000u);
        bblk[k].size = 0x1E00;
        bblk[k].used = 0;
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
    i = alloc(mblk, &nm, (u16)((size + 7u) & 0xFFF8u));
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
    i = alloc(bblk, &nb, (u16)((size + 7u) & 0xFFF8u));
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

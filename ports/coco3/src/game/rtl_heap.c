/* rtl_heap.c: the game's two heaps on the CoCo (step 8.5c, the banked heap rewritten for HEAP-STUDY.md, option 1). The mapped heap is
 * native memory from MAPPED_LO to MAPPED_HI (the pointer is the address), for the blocks game logic keeps hold of through a plain
 * address; the banked heap is NBPAGES pages of 7,680 usable bytes reached through the data windows, for the blocks that scale with
 * the size of an encounter (characters, combatants, affects, items) and the cold ones. A banked pointer is BSEG + page in the high
 * word and the offset in the page in the low word (vm.asm: vm_bp turns it into a window address in about 100 cycles). Both heaps hand
 * out 8 byte units; a block is never split over a page, so a window always shows the whole of it. */
#include "pool.h"

/* This code lives in the runtime bank, which holds no variables: the heap's tables are at a fixed place in native memory. */
#define NBLKM 64
#define NBLKB 640
/* A block is 4 bytes: its offset and its size, which is a multiple of 8, so bit 0 of the word says whether it is in use. The banked
 * table is sorted by offset (page * $2000 + the offset in the page); a freed block stays a free entry until the table needs the room
 * (compact), so a free is a binary search and a sequential allocation (an encounter being built) takes the entry after the last. */
typedef struct Blk { u16 off, sz; } Blk;
#define BSIZE(b) ((u16)((b).sz & 0xFFF8u))
#define BUSED(b) ((b).sz & 1u)
#define SETSZ(b, n, u) ((b).sz = (u16)((n) | (u)))
struct HeapData { Blk mblk[NBLKM]; Blk bblk[NBLKB]; u16 nb, rover; u8 nm, ready; };
#define HD ((struct HeapData *)HEAPDATA)
#define mblk (HD->mblk)
#define bblk (HD->bblk)
#define nm (HD->nm)
#define nb (HD->nb)
#define rover (HD->rover)
#define heap_ready (HD->ready)

static void rtl_heap_init(void);

/* the mapped heap: first fit, free blocks merged at once */
static int alloc_m(u16 n)
{
    u8 i, j;
    for (i = 0; i < nm; i++) {
        if (!BUSED(mblk[i]) && BSIZE(mblk[i]) >= n) {
            if (BSIZE(mblk[i]) > n) {                     /* split */
                if (nm == NBLKM)
                    rtl_fatal_code(0x20, n);
                for (j = nm; j > i + 1; j--)
                    mblk[j] = mblk[j - 1];
                nm++;
                mblk[i + 1].off = (u16)(mblk[i].off + n);
                SETSZ(mblk[i + 1], (u16)(BSIZE(mblk[i]) - n), 0);
                SETSZ(mblk[i], n, 1);
            }
            else
                mblk[i].sz |= 1;
            return i;
        }
    }
    return -1;
}

static void release_m(u16 off)
{
    u8 i, j;
    for (i = 0; i < nm; i++) {
        if (mblk[i].off == off && BUSED(mblk[i])) {
            mblk[i].sz &= 0xFFF8u;
            if (i + 1 < nm && !BUSED(mblk[i + 1]) && (u16)(mblk[i].off + BSIZE(mblk[i])) == mblk[i + 1].off) {
                SETSZ(mblk[i], (u16)(BSIZE(mblk[i]) + BSIZE(mblk[i + 1])), 0);
                for (j = i + 1; j + 1 < nm; j++)
                    mblk[j] = mblk[j + 1];
                nm--;
            }
            if (i > 0 && !BUSED(mblk[i - 1]) && (u16)(mblk[i - 1].off + BSIZE(mblk[i - 1])) == mblk[i].off) {
                SETSZ(mblk[i - 1], (u16)(BSIZE(mblk[i - 1]) + BSIZE(mblk[i])), 0);
                for (j = i; j + 1 < nm; j++)
                    mblk[j] = mblk[j + 1];
                nm--;
            }
            return;
        }
    }
    rtl_fatal_code(0x21, off);
}

/* the banked heap: merge the runs of free entries that touch (the table has room again) */
static void compact_b(void)
{
    u16 i, o = 0;
    for (i = 0; i < nb; i++) {
        if (o > 0 && !BUSED(bblk[i]) && !BUSED(bblk[o - 1]) && (u16)(bblk[o - 1].off + BSIZE(bblk[o - 1])) == bblk[i].off)
            SETSZ(bblk[o - 1], (u16)(BSIZE(bblk[o - 1]) + BSIZE(bblk[i])), 0);
        else
            bblk[o++] = bblk[i];
    }
    nb = o;
    rover = 0;
}

static int find_b(u16 n)
{
    u16 k, i;
    for (k = 0; k < nb; k++) {
        i = (u16)(rover + k);
        if (i >= nb)
            i = (u16)(i - nb);
        if (!BUSED(bblk[i]) && BSIZE(bblk[i]) >= n)
            return (int)i;
    }
    return -1;
}

static int alloc_b(u16 n)
{
    int i = find_b(n);
    u16 j;
    if (i < 0) {                                          /* nothing fits: merge what was freed and look again */
        compact_b();
        i = find_b(n);
        if (i < 0)
            return -1;
    }
    if (BSIZE(bblk[i]) > n) {                             /* split */
        if (nb == NBLKB) {
            compact_b();
            i = find_b(n);
            if (i < 0)
                return -1;
            if (BSIZE(bblk[i]) > n && nb == NBLKB)
                rtl_fatal_code(0x20, n);
        }
        if (BSIZE(bblk[i]) > n) {
            for (j = nb; j > (u16)(i + 1); j--)
                bblk[j] = bblk[j - 1];
            nb++;
            bblk[i + 1].off = (u16)(bblk[i].off + n);
            SETSZ(bblk[i + 1], (u16)(BSIZE(bblk[i]) - n), 0);
            SETSZ(bblk[i], n, 1);
            rover = (u16)(i + 1);                         /* the rest of the free run: where the next block goes */
            return i;
        }
    }
    bblk[i].sz |= 1;
    rover = (u16)i;
    return i;
}

static void release_b(u16 off)
{
    u16 lo = 0, hi = nb, mid;
    while (lo < hi) {                                     /* the table is sorted by offset */
        mid = (u16)((lo + hi) >> 1);
        if (bblk[mid].off < off)
            lo = (u16)(mid + 1);
        else
            hi = mid;
    }
    if (lo < nb && bblk[lo].off == off && BUSED(bblk[lo])) {
        bblk[lo].sz &= 0xFFF8u;
        if (lo < rover)
            rover = lo;                                   /* the hole is where the next search starts */
        return;
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
    for (k = 0; k < NBPAGES; k++) {                     /* pages of 7,680 usable bytes: the last 512 of the window are I/O */
        bblk[k].off = (u16)(k * 0x2000u);
        SETSZ(bblk[k], 0x1E00, 0);
    }
    nb = NBPAGES;
    rover = 0;
}

farptr rtl_getmem_m(u16 size)
{
    int i;
    if (size == 0)
        return 0;
    if (!heap_ready)
        rtl_heap_init();
    i = alloc_m((u16)((size + 7u) & 0xFFF8u));
    if (i < 0)
        rtl_fatal_code(0x22, size);
    return POOL_FARPTR(POOL_DS_SEG, mblk[i].off);
}

farptr rtl_getmem(u16 size)
{
    int i;
    if (size == 0)
        return 0;
    if (!heap_ready)
        rtl_heap_init();
    if (size > 0x1E00u)
        rtl_fatal_code(0x23, size);
    i = alloc_b((u16)((size + 7u) & 0xFFF8u));
    if (i < 0)
        rtl_fatal_code(0x24, size);
    return POOL_FARPTR((u16)(BSEG + (bblk[i].off >> 13)), bblk[i].off & 0x1FFFu);
}

void rtl_freemem(farptr p, u16 size)
{
    u16 seg = (u16)(p >> 16), off = (u16)p;
    (void)size;
    if (p == 0)
        return;
    if (seg == POOL_DS_SEG && off >= MAPPED_LO && off < MAPPED_HI) {
        release_m(off);
        return;
    }
    if ((seg >> 8) == (BSEG >> 8) && (u16)(seg - BSEG) < NBPAGES) {
        release_b((u16)(((seg - BSEG) << 13) | off));
        return;
    }
    rtl_fatal_code(0x25, off);
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

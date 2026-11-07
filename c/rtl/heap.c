/* heap.c: the Turbo Pascal 6.0 heap manager, byte for byte as the System unit has it (0AF8:0308 HeapAllocate,
 * 0AF8:03D3 HeapFree, 0AF8:0432 HeapMergeFree, 0AF8:0491 HeapRoundSize), so heap pointers, and everything the game
 * writes that contains them (saved games, character files), come out as in the original.
 *
 * HeapOrg, HeapPtr, HeapEnd and FreeList live in DGROUP (the game reads and lowers HeapEnd). Blocks are multiples of
 * 8 bytes and pointers have an offset of 0 or 8. The free list is ordered by address; each free block holds
 * [+0] the pointer to the next block, [+4] its size as an offset (0 or 8) and [+6] its size in paragraphs. The list
 * ends with a pointer whose segment is HeapPtr's (the end marker: an empty list is FreeList = HeapPtr). A block
 * taken from the top of the heap makes the last link point at the new HeapPtr. */
#include "pool.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__APPLE__) || defined(__GLIBC__)
#include <execinfo.h>
#endif

/* -DPOOL_HEAP_STATS (cmake -DCMAKE_C_FLAGS=-DPOOL_HEAP_STATS): count the heap in use and print the peak
 * on exit (CoCo 3 port, step 8.1: how much RAM the heap needs). No effect on the heap itself. */
#ifdef POOL_HEAP_STATS
#define rtl_getmem real_getmem
#define rtl_freemem real_freemem
#endif

#define V32(off) (*(u32 *)DGS(off))
#define HEAP_ORG V32(0x4400)
#define HEAP_PTR V32(0x4404)
#define HEAP_END V32(0x4408)
#define FREE_LIST V32(0x440C)
#define HEAP_ERROR V32(0x4414)

static u32 lin(farptr p) { return POOL_LINEAR(p); }
static farptr far_of(u32 l) { return POOL_FARPTR(l >> 4, l & 15u); }

static u32 rd32(u32 l) { u32 v; memcpy(&v, pool_arena + l, 4); return v; }
static void wr32(u32 l, u32 v) { memcpy(pool_arena + l, &v, 4); }
static u32 blk_size(u32 b) { u16 ofs, paras; memcpy(&ofs, pool_arena + b + 4, 2); memcpy(&paras, pool_arena + b + 6, 2); return (u32)paras * 16u + ofs; }
static void set_size(u32 b, u32 bytes)
{
  u16 ofs = (u16)(bytes & 15u), paras = (u16)(bytes >> 4);
  memcpy(pool_arena + b + 4, &ofs, 2);
  memcpy(pool_arena + b + 6, &paras, 2);
}

/* the cell that holds the first link of the free list: FreeList itself (its "size" is FreeZero, zero) */
#define HEAD_CELL (POOL_DS_LINEAR + (u32)(DGS(0x440C) - pool_ds))

static int at_end(farptr p)
{
  return (p >> 16) == (HEAP_PTR >> 16);
}

farptr rtl_getmem(u16 size)
{
  u32 n, prev, cur;
  if (size == 0) {
    return 0;
  }
  for (;;) {
    n = ((u32)size + 7u) & ~7u;
    prev = HEAD_CELL;
    for (;;) {
      farptr next = rd32(prev);
      u32 sz;
      if (at_end(next)) {                              /* no block fits: take the space from the top */
        u32 at = lin(next), top = at + n;
        if (top <= lin(HEAP_END)) {
          HEAP_PTR = far_of(top);
          wr32(prev, HEAP_PTR);
          if (HEAP_ERROR) {
            ((int (*)(u16))rtl_proc(HEAP_ERROR))(0);   /* the System unit calls HeapError(0) here, a no-op for the game */
          }
          return far_of(at);
        }
        break;
      }
      cur = lin(next);
      sz = blk_size(cur);
      if (sz >= n) {
        farptr nxt = rd32(cur);
        if (sz == n) {
          wr32(prev, nxt);
        } else {                                        /* the allocation takes the front of the block */
          u32 rest = cur + n;
          wr32(rest, nxt);
          set_size(rest, sz - n);
          wr32(prev, far_of(rest));
        }
        return far_of(cur);
      }
      prev = cur;
    }
    if (HEAP_ERROR) {
      int r = ((int (*)(u16))rtl_proc(HEAP_ERROR))(size);
      if ((r & 0xFF) == 0) {
        rtl_fatal("runtime error 203: heap overflow");
      }
      if ((r & 0xFF) == 1) {
        return 0;
      }
      continue;                                         /* 2 or more: try again */
    }
    rtl_fatal("runtime error 203: heap overflow");
  }
}

/* HeapMergeFree(next, blk): blk lies below next; join them when they touch, else link blk to next. When blk ends at
 * the heap top, HeapPtr falls to blk instead. */
static void merge_free(u32 next, u32 blk)
{
  u32 end = blk + blk_size(blk);
  if (end != next) {
    wr32(blk, far_of(next));
    return;
  }
  if (next == lin(HEAP_PTR)) {
    HEAP_PTR = far_of(blk);
    return;
  }
  wr32(blk, rd32(next));                               /* blk.next := next.next; blk.size := blk.size + next.size */
  set_size(blk, blk_size(blk) + blk_size(next));
}

static int mapped_free(farptr p, u16 size);
static int is_mapped(farptr p);

void rtl_freemem(farptr p, u16 size)
{
  u32 n, at, prev, cur;
  if (size == 0) {
    return;
  }
  if (is_mapped(p)) {                                   /* a block of the mapped class (CoCo placement model) */
    mapped_free(p, size);
    return;
  }
  if ((p & 0xFFFFu) & 0xFFF7u) {
    rtl_fatal("runtime error 204: invalid pointer operation");
  }
  at = lin(p);
  if (at < lin(HEAP_ORG) || at >= lin(HEAP_PTR)) {
    rtl_fatal("runtime error 204: invalid pointer operation");
  }
  n = ((u32)size + 7u) & ~7u;
  set_size(at, n);
  prev = HEAD_CELL;
  cur = lin(rd32(prev));
  /* walk to the first block above `at` (the end marker counts as above everything) */
  while (!at_end(rd32(prev)) && cur < at) {
    prev = cur;
    cur = lin(rd32(prev));
  }
  if (cur == at) {
    rtl_fatal("runtime error 204: invalid pointer operation");
  }
  merge_free(cur, at);                                  /* with the block above (or the heap top) */
  merge_free(at, prev);                                 /* the block below, or the list head */
}

s32 rtl_MemAvail(void)
{
  s32 total = (s32)(lin(HEAP_END) - lin(HEAP_PTR));
  farptr next = rd32(HEAD_CELL);
  while (!at_end(next)) {
    u32 b = lin(next);
    total += (s32)blk_size(b);
    next = rd32(b);
  }
  return total;
}

s32 rtl_MaxAvail(void)
{
  s32 best = (s32)(lin(HEAP_END) - lin(HEAP_PTR));
  farptr next = rd32(HEAD_CELL);
  while (!at_end(next)) {
    u32 b = lin(next);
    if ((s32)blk_size(b) > best) {
      best = (s32)blk_size(b);
    }
    next = rd32(b);
  }
  return best;
}

#ifdef POOL_HEAP_STATS
#undef rtl_getmem
#undef rtl_freemem
#include <stdio.h>
#include <stdlib.h>
#include <execinfo.h>

#ifdef POOL_PROFILE                /* ports/coco3/prof: who touches which block (CoCo 3 port, step 8.1c) */
void pool_prof_alloc(farptr p, u32 n);
void pool_prof_free(farptr p, u32 n);
#endif

#define STATS_MAX 16384
static struct { u32 at, size; } live[STATS_MAX];
static int nlive;
static u32 live_bytes, peak_live, top_high, allocs, frees, unmatched;
static struct { u32 size, count; } peak_hist[96];
static int peak_nsizes;
static int registered;

static void stats_print(void)
{
  int i;
  if (getenv("POOL_DGROUP_DUMP")) {                        /* DGROUP as the session left it */
    FILE *f = fopen(getenv("POOL_DGROUP_DUMP"), "wb");
    if (f) {
      fwrite(pool_ds, 1, 0x8760, f);
      fclose(f);
    }
  }
  fprintf(stderr, "HEAPSTATS peak_live=%u top_highwater=%u allocs=%u frees=%u live_at_exit=%u unmatched_frees=%u\n",
          peak_live, top_high, allocs, frees, live_bytes, unmatched);
  fprintf(stderr, "HEAPSTATS live at exit, blocks of 1000 bytes or more:");
  for (i = 0; i < nlive; i++) {
    if (live[i].size >= 1000) {
      fprintf(stderr, " %u", live[i].size);
    }
  }
  fprintf(stderr, "\n");
  {
    u32 small = 0, nsmall = 0;
    for (i = 0; i < nlive; i++) {
      if (live[i].size < 1000) {
        small += live[i].size;
        nsmall++;
      }
    }
    fprintf(stderr, "HEAPSTATS live at exit, blocks under 1000 bytes: %u blocks, %u bytes\n", nsmall, small);
  }
  fprintf(stderr, "HEAPSTATS at the peak:");
  for (i = 0; i < peak_nsizes; i++) {
    fprintf(stderr, " %ux%u", peak_hist[i].count, peak_hist[i].size);
  }
  fprintf(stderr, "\n");
}

static void snapshot_peak(void)
{
  int i, j;
  peak_nsizes = 0;
  for (i = 0; i < nlive; i++) {
    for (j = 0; j < peak_nsizes && peak_hist[j].size != live[i].size; j++) {
    }
    if (j == peak_nsizes) {
      if (peak_nsizes == 96) {
        continue;
      }
      peak_hist[peak_nsizes].size = live[i].size;
      peak_hist[peak_nsizes++].count = 0;
    }
    peak_hist[j].count++;
  }
}

farptr rtl_getmem(u16 size)
{
  farptr p = real_getmem(size);
  if (size >= 1000 && getenv("POOL_HEAP_CALLERS")) {       /* who asks for the big blocks */
    void *bt[6];
    int k = backtrace(bt, 6);
    fprintf(stderr, "HEAPALLOC %u\n", (unsigned)size);
    backtrace_symbols_fd(bt + 1, k - 1, 2);
  }
  if (!registered) {
    registered = 1;
    atexit(stats_print);
  }
  if (p != 0 && nlive < STATS_MAX) {
    u32 n = ((u32)size + 7u) & ~7u;
    live[nlive].at = lin(p);
    live[nlive++].size = n;
    live_bytes += n;
    allocs++;
#ifdef POOL_PROFILE
    pool_prof_alloc(p, n);
#endif
    if (live_bytes > peak_live) {
      peak_live = live_bytes;
      snapshot_peak();
    }
    if (lin(HEAP_PTR) - lin(HEAP_ORG) > top_high) {
      top_high = lin(HEAP_PTR) - lin(HEAP_ORG);
    }
  }
  return p;
}

void rtl_freemem(farptr p, u16 size)
{
  int i;
  for (i = nlive - 1; i >= 0 && live[i].at != lin(p); i--) {
  }
  if (i >= 0) {
#ifdef POOL_PROFILE
    pool_prof_free(p, live[i].size);
#endif
    live_bytes -= live[i].size;
    live[i] = live[--nlive];
    frees++;
  } else if (size != 0) {
    unmatched++;
  }
  real_freemem(p, size);
}
#endif


/* ---- the mapped heap and the bank window (CoCo placement model, step 8.2) ----------------------------------------
 * Blocks of the mapped class live in the DGROUP segment between MAPPED_LO and MAPPED_HI (the 64 KB map of the CoCo:
 * the pointer is the 16-bit offset, the segment is DGROUP's). The banked class stays in the PC heap; FPB counts how
 * often a block has to be mapped into the data window (two windows, least recently used first out). */
#ifdef POOL_VM
#define MAPPED_LO ((u16)((vm_paged_end + 0xFFu) & ~0xFFu))   /* above the layout of mkvm.py */
#else
#define MAPPED_LO 0x8800u
#endif
#define MAPPED_HI 0xFE00u
#define MAPPED_MAX 1024

static struct { u16 off, size; u8 used; } mblk[MAPPED_MAX];
static int nmblk;
static u32 m_live, m_peak, m_allocs, m_frees;
static u32 bank_maps, bank_misses;
#ifdef POOL_PLACEMENT
static u32 fpm_derefs, fpm_nil, fpm_stack;
#endif

static void mapped_init(void)
{
  if (nmblk == 0) {
    mblk[0].off = MAPPED_LO;
    mblk[0].size = (u16)(MAPPED_HI - MAPPED_LO);
    mblk[0].used = 0;
    nmblk = 1;
  }
}

static void mapped_print(void)
{
  if (getenv("POOL_PLACEMENT_STATS")) {
    fprintf(stderr, "PLACEMENT mapped heap: peak %u bytes live of %u, %u allocations, %u frees; "
            "bank window: %u maps, %u misses\n", m_peak, MAPPED_HI - MAPPED_LO, m_allocs, m_frees, bank_maps, bank_misses);
#ifdef POOL_PLACEMENT
    fprintf(stderr, "PLACEMENT mapped dereferences %u, of which %u through nil and %u into the stack (every other one checked to be a 16-bit address of the mapped region)\n", fpm_derefs, fpm_nil, fpm_stack);
#endif
  }
}

farptr rtl_getmem_m(u16 size)
{
  static int registered;
  u32 n = ((u32)size + 7u) & ~7u;
  int i, j;
  if (!registered) {
    registered = 1;
    atexit(mapped_print);
  }
  if (size == 0) {
    return 0;
  }
  mapped_init();
  for (i = 0; i < nmblk; i++) {
    if (!mblk[i].used && mblk[i].size >= n) {
      if (mblk[i].size > n) {                         /* split */
        if (nmblk == MAPPED_MAX) {
          rtl_fatal("mapped heap: too many blocks");
        }
        for (j = nmblk; j > i + 1; j--) {
          mblk[j] = mblk[j - 1];
        }
        nmblk++;
        mblk[i + 1].off = (u16)(mblk[i].off + n);
        mblk[i + 1].size = (u16)(mblk[i].size - n);
        mblk[i + 1].used = 0;
        mblk[i].size = (u16)n;
      }
      mblk[i].used = 1;
      m_live += n;
      m_allocs++;
      if (m_live > m_peak) {
        m_peak = m_live;
      }
      return POOL_FARPTR(POOL_DS_SEG, mblk[i].off);
    }
  }
  rtl_fatal("mapped heap full: %u bytes asked, %u live", (unsigned)n, m_live);
  return 0;
}

static int mapped_free(farptr p, u16 size)
{
  int i;
  u16 off = (u16)(p & 0xFFFFu);
  (void)size;
  for (i = 0; i < nmblk; i++) {
    if (mblk[i].off == off && mblk[i].used) {
      mblk[i].used = 0;
      m_live -= mblk[i].size;
      m_frees++;
      if (i + 1 < nmblk && !mblk[i + 1].used) {       /* merge with the next, then the previous */
        mblk[i].size = (u16)(mblk[i].size + mblk[i + 1].size);
        memmove(&mblk[i + 1], &mblk[i + 2], (size_t)(nmblk - i - 2) * sizeof mblk[0]);
        nmblk--;
      }
      if (i > 0 && !mblk[i - 1].used) {
        mblk[i - 1].size = (u16)(mblk[i - 1].size + mblk[i].size);
        memmove(&mblk[i], &mblk[i + 1], (size_t)(nmblk - i - 1) * sizeof mblk[0]);
        nmblk--;
      }
      return 1;
    }
  }
  rtl_fatal("mapped heap: free of an address that is not a live block ($%04X)", off);
  return 0;
}

/* a pointer into the mapped region of the DGROUP segment */
static int is_mapped(farptr p)
{
  return (p >> 16) == POOL_DS_SEG && (p & 0xFFFFu) >= MAPPED_LO && (p & 0xFFFFu) < MAPPED_HI;
}

void *pool_bank_map(farptr p)
{
  static u32 win[2];                                  /* the block (its start) each of the two windows holds */
  static int last;
  u32 lin = POOL_LINEAR(p);
  int w;
  bank_maps++;
  for (w = 0; w < 2; w++) {
    if (win[w] && lin >= win[w] && lin < win[w] + 0x2000u) {   /* the window holds the 8 KB page of this block */
      last = w;
      return pool_arena + lin;
    }
  }
  bank_misses++;
  last ^= 1;
  win[last] = lin & ~0x1FFFu;
  return pool_arena + lin;
}

#ifdef POOL_PLACEMENT
void *pool_fpm(farptr p)
{
  fpm_derefs++;
  if (p == 0) {                       /* a nil pointer is read through (the Pascal reads Next of a possibly empty list and */
    fpm_nil++;                        /* does not use it): the same bytes as the PC build reads, counted */
    return pool_arena;
  }
  if (POOL_LINEAR(p) >= 0x8000u && POOL_LINEAR(p) < 0xF000u) {   /* a local whose address was taken: the pseudo stack of */
    fpm_stack++;                                                   /* core.c, which is part of the 64 KB map on the CoCo */
    return pool_arena + POOL_LINEAR(p);
  }
  if ((p >> 16) != POOL_DS_SEG || (p & 0xFFFFu) >= MAPPED_HI) {
#if defined(__APPLE__) || defined(__GLIBC__)
    void *bt[8];
    int k = backtrace(bt, 8);
    backtrace_symbols_fd(bt + 1, k - 1, 2);               /* who dereferenced it: the routine names of the game */
#endif
    rtl_fatal("a mapped-class pointer ($%08X) is not a 16-bit address of the DGROUP segment", (unsigned)p);
  }
  return pool_arena + POOL_LINEAR(p);
}
#endif

#ifdef POOL_PLACEMENT
#include <signal.h>
#include <unistd.h> /* _exit; this crash handler is POSIX only (POOL_PLACEMENT builds run on macOS and Linux) */
/* a crash prints the routines of the game on the stack (the placement model makes the game touch memory in new ways) */
static void on_segv(int sig)
{
#if defined(__APPLE__) || defined(__GLIBC__)
  void *bt[12];
  int k = backtrace(bt, 12);
  fprintf(stderr, "poolrad: signal %d\n", sig);
  backtrace_symbols_fd(bt, k, 2);
#endif
  _exit(139);
}

__attribute__((constructor)) static void install_segv(void)
{
  signal(SIGSEGV, on_segv);
  signal(SIGBUS, on_segv);
}
#endif

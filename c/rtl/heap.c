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

#define V32(off) (*(u32 *)(pool_ds + (off)))
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
#define HEAD_CELL (POOL_DS_LINEAR + 0x440Cu)

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

void rtl_freemem(farptr p, u16 size)
{
  u32 n, at, prev, cur;
  if (size == 0) {
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

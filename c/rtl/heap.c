/* heap.c: the Turbo Pascal heap: HeapOrg, HeapPtr, HeapEnd and a free list, kept in DGROUP where the game can
 * read them (it lowers HeapEnd at start up). Blocks are 8 byte units; a free block holds its successor and its
 * size in its first eight bytes. */
#include "pool.h"

#define V32(off) (*(u32 *)(pool_ds + (off)))
#define HEAP_ORG V32(0x4400)
#define HEAP_PTR V32(0x4404)
#define HEAP_END V32(0x4408)
#define FREE_LIST V32(0x440C)
#define HEAP_ERROR V32(0x4414)

static u32 lin(farptr p) { return POOL_LINEAR(p); }
static farptr far_of(u32 l) { return POOL_FARPTR(l >> 4, l & 15u); }

typedef struct FreeBlock {
  farptr next;
  u32 size;
} FreeBlock;

static FreeBlock *blk(u32 l) { return (FreeBlock *)(pool_arena + l); }

farptr rtl_getmem(u16 size)
{
  u32 n, prev = 0, cur;
  if (size == 0) {
    return 0;
  }
  n = ((u32)size + 7u) & ~7u;
  for (;;) {
    for (cur = FREE_LIST ? lin(FREE_LIST) : 0; cur; prev = cur, cur = blk(cur)->next ? lin(blk(cur)->next) : 0) {
      u32 sz = blk(cur)->size;
      if (sz >= n) {
        farptr next = blk(cur)->next;
        if (sz == n) {
          if (prev) blk(prev)->next = next; else FREE_LIST = next;
        } else {                                 /* the allocation takes the front of the block */
          u32 rest = cur + n;
          blk(rest)->next = next;
          blk(rest)->size = sz - n;
          if (prev) blk(prev)->next = far_of(rest); else FREE_LIST = far_of(rest);
        }
        return far_of(cur);
      }
      if (prev == cur) break;
    }
    if (lin(HEAP_PTR) + n <= lin(HEAP_END)) {
      u32 at = lin(HEAP_PTR);
      HEAP_PTR = far_of(at + n);
      return far_of(at);
    }
    if (HEAP_ERROR) {
      int r = ((int (*)(u16))rtl_proc(HEAP_ERROR))(size);
      if (r == 0) {
        rtl_fatal("runtime error 203: heap overflow");
      }
      if (r == 1) {
        return 0;
      }
      continue;                                  /* r = 2: try again */
    }
    rtl_fatal("runtime error 203: heap overflow");
  }
}

void rtl_freemem(farptr p, u16 size)
{
  u32 n, at, prev = 0, cur;
  if (p == 0 || size == 0) {
    return;
  }
  n = ((u32)size + 7u) & ~7u;
  at = lin(p);
  if (at + n == lin(HEAP_PTR)) {                 /* the top of the heap: lower HeapPtr and absorb free blocks below */
    HEAP_PTR = far_of(at);
    for (;;) {
      u32 last = 0, l;
      cur = 0;
      for (l = FREE_LIST ? lin(FREE_LIST) : 0; l; last = l, l = blk(l)->next ? lin(blk(l)->next) : 0) {
        if (l + blk(l)->size == lin(HEAP_PTR)) {
          cur = l;
          prev = last;
          break;
        }
      }
      if (!cur) {
        break;
      }
      if (prev) blk(prev)->next = blk(cur)->next; else FREE_LIST = blk(cur)->next;
      HEAP_PTR = far_of(cur);
    }
    return;
  }
  /* insert in address order and merge with the neighbours */
  for (cur = FREE_LIST ? lin(FREE_LIST) : 0; cur && cur < at; prev = cur, cur = blk(cur)->next ? lin(blk(cur)->next) : 0) {
  }
  blk(at)->size = n;
  blk(at)->next = cur ? far_of(cur) : 0;
  if (prev) blk(prev)->next = far_of(at); else FREE_LIST = far_of(at);
  if (cur && at + n == cur) {
    blk(at)->size += blk(cur)->size;
    blk(at)->next = blk(cur)->next;
  }
  if (prev && prev + blk(prev)->size == at) {
    blk(prev)->size += blk(at)->size;
    blk(prev)->next = blk(at)->next;
  }
}

s32 rtl_MemAvail(void)
{
  s32 total = (s32)(lin(HEAP_END) - lin(HEAP_PTR));
  u32 l;
  for (l = FREE_LIST ? lin(FREE_LIST) : 0; l; l = blk(l)->next ? lin(blk(l)->next) : 0) {
    total += (s32)blk(l)->size;
  }
  return total;
}

s32 rtl_MaxAvail(void)
{
  s32 best = (s32)(lin(HEAP_END) - lin(HEAP_PTR));
  u32 l;
  for (l = FREE_LIST ? lin(FREE_LIST) : 0; l; l = blk(l)->next ? lin(blk(l)->next) : 0) {
    if ((s32)blk(l)->size > best) {
      best = (s32)blk(l)->size;
    }
  }
  return best;
}

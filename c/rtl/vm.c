/* vm.c: the CoCo layout of DGROUP on the host (step 8.5, POOL_VM). Native globals are plain memory; paged ones are reached
 * through vm_ptr, which models the two 8 KB data windows of the CoCo (least recently used out) and counts what the
 * accessor would cost: calls, page maps, misses. The data itself stays in the DS segment of the arena (the new offsets of
 * ports/coco3/tools/mkvm.py), so a farptr to a global is still the segment of DGROUP and its new offset. */
#include "pool.h"
#ifdef POOL_VM
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern const u8 pool_image[];
extern const u32 pool_image_org, pool_image_size;

static int win_page[2] = {-1, -1};
static int win_age[2];
static int clock_;
static u32 calls, hits0, hits1, misses;
static int registered;

static void vm_report(void)
{
  if (getenv("POOL_VM_STATS")) {
    fprintf(stderr, "VMSTATS accessor calls %u, window 0 %u, window 1 %u, page maps %u\n", calls, hits0, hits1, misses);
  }
}

void *vm_ptr(u16 v)
{
  int page = v >> 13;
  if (!registered) {
    registered = 1;
    atexit(vm_report);
  }
  calls++;
  clock_++;
  if (win_page[0] == page) {
    hits0++;
    win_age[0] = clock_;
  } else if (win_page[1] == page) {
    hits1++;
    win_age[1] = clock_;
  } else {
    int w = win_age[0] <= win_age[1] ? 0 : 1;
    misses++;
    win_page[w] = page;
    win_age[w] = clock_;
  }
  return pool_ds + v;
}

void *vm_unplaced(u16 off)
{
  rtl_fatal("global at DGROUP offset %04X has no place in the CoCo layout (no unit names it)", off);
  return 0;
}

/* the initial image: each cluster that lies in the image of typed constants goes to its new place */
void vm_init(void)
{
  u16 i;
  for (i = 0; i < vm_cluster_count; i++) {
    const struct VmCluster *c = &vm_clusters[i];
    u32 lo = c->lo, hi = (u32)c->lo + c->size, a = lo > pool_image_org ? lo : pool_image_org;
    u32 b = hi < pool_image_org + pool_image_size ? hi : pool_image_org + pool_image_size;
    if (a < b) {
      memcpy(pool_ds + c->nw + (a - lo), pool_image + (a - pool_image_org), b - a);
    }
  }
}

void vm_export_ds(u8 *dst)
{
  u16 i;
  memset(dst, 0, 0x8760);
  for (i = 0; i < vm_cluster_count; i++) {
    const struct VmCluster *c = &vm_clusters[i];
    if ((u32)c->lo + c->size <= 0x8760) {
      memcpy(dst + c->lo, pool_ds + c->nw, c->size);
    }
  }
}
#endif

/* prof_rt.c: the runtime of the profiling build of the C game (CoCo 3 port, step 8.1c).
 *
 * The game's units are compiled with -finstrument-functions, game.h reaches DGROUP through
 * pool_prof_g and every FPD (a far pointer turned into a host pointer) goes through pool_prof_fpd.
 * This file keeps, per interval between two keys read by the game (ReadKey):
 *   E caller callee n    calls from one routine to another (a shadow stack gives the caller)
 *   G fn offset n        references to DGROUP offset made by routine fn
 *   H fn class n         dereferences of a far pointer into heap block class, by routine fn
 * and writes them to the file named by POOL_PROF_OUT (text, one interval after the other), with the
 * names of the routines (F id name) and of the heap classes (C class size allocator) at the end.
 * tools/prof_report.py reads that file. Not part of the game: only built by scripts/prof_run.sh.
 */
#define _GNU_SOURCE
#include "pool.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NOINSTR __attribute__((no_instrument_function))

typedef struct { uint64_t k; uint32_t n; } Slot;
typedef struct { Slot *s; uint32_t mask; } Map;

static Map m_edge, m_g, m_h;
static FILE *out;
static unsigned interval;

static NOINSTR void map_init(Map *m, int bits)
{
  m->s = calloc((size_t)1 << bits, sizeof(Slot));
  m->mask = (1u << bits) - 1;
}

static NOINSTR void map_add(Map *m, uint64_t key)
{
  uint64_t k = key + 1;                       /* 0 marks an empty slot */
  uint32_t i = (uint32_t)((k * 0x9E3779B97F4A7C15ull) >> 40) & m->mask;
  while (m->s[i].k != 0 && m->s[i].k != k) {
    i = (i + 1) & m->mask;
  }
  m->s[i].k = k;
  m->s[i].n++;
}

/* routines: address -> small id, name from dladdr */
#define MAXFN 4096
static void *fn_addr[MAXFN];
static char *fn_name[MAXFN];
static int nfn = 1;                           /* id 0 is "none" */

static NOINSTR int fn_id(void *fn)
{
  int i;
  for (i = 1; i < nfn; i++) {                 /* the routines called most are found first: move to front would help, */
    if (fn_addr[i] == fn) {                   /* but 800 entries is fast enough for a test run */
      return i;
    }
  }
  {
    Dl_info di;
    fn_addr[nfn] = fn;
    fn_name[nfn] = strdup(dladdr(fn, &di) && di.dli_sname ? di.dli_sname : "?");
    return nfn++;
  }
}

static int stk[2048];
static int sp;

static NOINSTR int cur(void)
{
  return sp > 0 ? stk[sp - 1] : 0;
}

NOINSTR void __cyg_profile_func_enter(void *fn, void *site)
{
  int id = fn_id(fn);
  (void)site;
  if (sp > 0) {
    map_add(&m_edge, ((uint64_t)stk[sp - 1] << 16) | (uint64_t)id);
  }
  if (sp < 2047) {
    stk[sp++] = id;
  }
}

NOINSTR void __cyg_profile_func_exit(void *fn, void *site)
{
  (void)fn;
  (void)site;
  if (sp > 0) {
    sp--;
  }
}

/* heap block classes: one per (size, allocating routine) */
#define MAXCLS 1024
static struct { u32 size; int alloc_fn; int live, maxlive, allocs; } cls[MAXCLS];
static int ncls = 3;                          /* 0 unknown or nil, 1 DGROUP, 2 video */
static uint16_t clsmap[0x110000u >> 3];

NOINSTR void pool_prof_alloc(farptr p, u32 n)
{
  u32 lin = POOL_LINEAR(p), i;
  int c, a = cur();
  for (c = 3; c < ncls; c++) {
    if (cls[c].size == n && cls[c].alloc_fn == a) {
      break;
    }
  }
  if (c == ncls && ncls < MAXCLS) {
    cls[ncls].size = n;
    cls[ncls++].alloc_fn = a;
  }
  for (i = lin >> 3; i < ((lin + n + 7) >> 3) && i < (0x110000u >> 3); i++) {
    clsmap[i] = (uint16_t)c;
  }
  cls[c].allocs++;
  if (++cls[c].live > cls[c].maxlive) {
    cls[c].maxlive = cls[c].live;
  }
}

NOINSTR void pool_prof_free(farptr p, u32 n)
{
  u32 lin = POOL_LINEAR(p), i;
  int c = lin < 0x110000u ? clsmap[lin >> 3] : 0;
  if (c >= 3) {
    cls[c].live--;
  }
  for (i = lin >> 3; i < ((lin + n + 7) >> 3) && i < (0x110000u >> 3); i++) {
    clsmap[i] = 0;
  }
}

NOINSTR void *pool_prof_fpd(farptr p)
{
  u32 lin = POOL_LINEAR(p);
  int c = 0;
  if (lin >= POOL_DS_LINEAR && lin < POOL_DS_LINEAR + 0x10000u) {
    c = 1;
  } else if (lin >= POOL_VIDEO_LO && lin < POOL_VIDEO_HI) {
    c = 2;
  } else if (lin < 0x110000u) {
    c = clsmap[lin >> 3];
  }
  map_add(&m_h, ((uint64_t)cur() << 16) | (uint64_t)c);
  return pool_arena + lin;
}

NOINSTR void *pool_prof_g(u32 off)
{
  map_add(&m_g, ((uint64_t)cur() << 20) | off);
  return pool_arena + POOL_DS_LINEAR + off;
}

static NOINSTR void dump_map(const char *tag, Map *m, int shift)
{
  uint32_t i;
  for (i = 0; i <= m->mask; i++) {
    if (m->s[i].k) {
      uint64_t k = m->s[i].k - 1;
      fprintf(out, "%s %u %llu %u\n", tag, (unsigned)(k >> shift), (unsigned long long)(k & ((1ull << shift) - 1)), m->s[i].n);
      m->s[i].k = 0;
      m->s[i].n = 0;
    }
  }
}

static NOINSTR void dump_interval(void)
{
  if (!out) {
    return;
  }
  fprintf(out, "I %u\n", interval++);
  dump_map("E", &m_edge, 16);
  dump_map("G", &m_g, 20);
  dump_map("H", &m_h, 16);
}

NOINSTR void pool_prof_key(void)
{
  dump_interval();
}

static NOINSTR void finish(void)
{
  int i;
  dump_interval();
  for (i = 1; i < nfn; i++) {
    fprintf(out, "F %d %s\n", i, fn_name[i]);
  }
  for (i = 3; i < ncls; i++) {
    fprintf(out, "C %d %u %d %d %d %d\n", i, cls[i].size, cls[i].alloc_fn, cls[i].allocs, cls[i].maxlive, cls[i].live);
  }
  fclose(out);
}

__attribute__((constructor)) static NOINSTR void start(void)
{
  const char *path = getenv("POOL_PROF_OUT");
  map_init(&m_edge, 16);
  map_init(&m_g, 17);
  map_init(&m_h, 16);
  if (path) {
    out = fopen(path, "w");
    atexit(finish);
  }
}

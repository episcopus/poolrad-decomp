/* core.c: memory, strings, sets, numbers and ports: the part of Turbo Pascal's System unit that is not files,
 * the heap or the console. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "ega.h"
#include "platform.h"

u8 pool_arena[POOL_ARENA_SIZE];

extern const u32 pool_image_org;
extern const u32 pool_image_size;
extern const u8 pool_image[];
typedef struct ProcEntry { u32 id; void (*fn)(void); } ProcEntry;
extern const ProcEntry pool_procs[];
extern const u32 pool_proc_count;

void rtl_fatal(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "poolrad: ");
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  va_end(ap);
  platform_quit(2);
}

/* ---- memory ----------------------------------------------------------------------------------------------- */
farptr rtl_far(const void *p)
{
  uintptr_t a = (uintptr_t)p, base = (uintptr_t)pool_arena;
  u32 lin;
  if (a < base || a >= base + POOL_ARENA_SIZE) {
    rtl_fatal("the address of a variable outside the emulated memory was taken");
  }
  lin = (u32)(a - base);
  if (lin >= POOL_DS_LINEAR && lin < POOL_DS_LINEAR + 0x10000u) {
    return POOL_FARPTR(POOL_DS_SEG, lin - POOL_DS_LINEAR);
  }
  return POOL_FARPTR(lin >> 4, lin & 15u);
}

void *rtl_mem_ptr(u16 seg, u16 off)
{
  return pool_arena + (((u32)seg << 4) + off);
}

static int in_video(const void *p)
{
  uintptr_t a = (uintptr_t)p - (uintptr_t)pool_arena;
  return a >= POOL_VIDEO_LO && a < POOL_VIDEO_HI;
}

u8 rtl_peek8(u16 seg, u16 off)
{
  u32 lin = ((u32)seg << 4) + off;
  if (lin >= POOL_VIDEO_LO && lin < POOL_VIDEO_HI) {
    return ega_read(lin - POOL_VIDEO_LO);
  }
  return pool_arena[lin];
}

u16 rtl_peek16(u16 seg, u16 off)
{
  return (u16)(rtl_peek8(seg, off) | (rtl_peek8(seg, (u16)(off + 1)) << 8));
}

void rtl_poke8(u16 seg, u16 off, u8 v)
{
  u32 lin = ((u32)seg << 4) + off;
  if (lin >= POOL_VIDEO_LO && lin < POOL_VIDEO_HI) {
    ega_write(lin - POOL_VIDEO_LO, v);
    platform_video_changed();
    return;
  }
  pool_arena[lin] = v;
}

void rtl_poke16(u16 seg, u16 off, u16 v)
{
  rtl_poke8(seg, off, (u8)v);
  rtl_poke8(seg, (u16)(off + 1), (u8)(v >> 8));
}

/* Copy and fill into video memory go byte by byte through the EGA, as the CPU's string instructions do. */
void rtl_Move(const void *src, void *dst, u16 count)
{
  if (in_video(dst) || in_video(src)) {
    u32 s = (u32)((const u8 *)src - pool_arena), d = (u32)((u8 *)dst - pool_arena);
    u16 i;
    int sv = in_video(src), dv = in_video(dst);
    for (i = 0; i < count; i++) {
      u8 v = sv ? ega_read(s + i - POOL_VIDEO_LO) : pool_arena[s + i];
      if (dv) {
        ega_write(d + i - POOL_VIDEO_LO, v);
      } else {
        pool_arena[d + i] = v;
      }
    }
    if (dv) {
      platform_video_changed();
    }
    return;
  }
  memmove(dst, src, count);
}

void rtl_FillChar(void *dst, u16 count, u8 value)
{
  if (in_video(dst)) {
    u32 d = (u32)((u8 *)dst - pool_arena) - POOL_VIDEO_LO;
    u16 i;
    for (i = 0; i < count; i++) {
      ega_write(d + i, value);
    }
    platform_video_changed();
    return;
  }
  memset(dst, value, count);
}

/* The bytes of a read go to memory the same way (BlockRead into a video buffer). */
void rtl_store(void *dst, const void *src, u32 count)
{
  if (in_video(dst)) {
    u32 d = (u32)((u8 *)dst - pool_arena) - POOL_VIDEO_LO;
    u32 i;
    for (i = 0; i < count; i++) {
      ega_write(d + i, ((const u8 *)src)[i]);
    }
    platform_video_changed();
    return;
  }
  memcpy(dst, src, count);
}

/* ---- ports -------------------------------------------------------------------------------------------------- */
static u8 port61;

u8 rtl_inp(u16 port)
{
  if (port >= 0x3B0 && port <= 0x3DF) {
    return ega_port_read(port);
  }
  switch (port) {
  case 0x40: return platform_pit_counter();
  case 0x61: return port61;
  default: return 0xFF;
  }
}

u16 rtl_inpw(u16 port)
{
  return (u16)(rtl_inp(port) | (rtl_inp((u16)(port + 1)) << 8));
}

void rtl_outp(u16 port, u8 v)
{
  if (port >= 0x3B0 && port <= 0x3DF) {
    ega_port_write(port, v);
    return;
  }
  switch (port) {
  case 0x61: port61 = v; break;
  case 0xC0: platform_tandy_write(v); break;
  default: break;
  }
}

void rtl_outpw(u16 port, u16 v)
{
  rtl_outp(port, (u8)v);
  rtl_outp((u16)(port + 1), (u8)(v >> 8));
}

/* ---- the pseudo stack for locals whose address is taken --------------------------------------------------- */
#define STACK_LO 0x8000u
#define STACK_HI 0xF000u
static u32 stack_top = STACK_LO;

u16 rtl_stack_mark(void)
{
  return (u16)stack_top;
}

void *rtl_stack_alloc(u16 size)
{
  void *p = pool_arena + stack_top;
  stack_top += (size + 1u) & ~1u;
  if (stack_top > STACK_HI) {
    rtl_fatal("stack overflow (locals with an address)");
  }
  memset(p, 0, size);
  return p;
}

void rtl_stack_release(u16 mark)
{
  stack_top = mark;
}

/* ---- procedure pointers ------------------------------------------------------------------------------------- */
void (*rtl_proc(farptr id))(void)
{
  u32 lo = 0, hi = pool_proc_count;
  while (lo < hi) {                                  /* the table is sorted by id */
    u32 mid = (lo + hi) / 2;
    if (pool_procs[mid].id == id) {
      return pool_procs[mid].fn;
    }
    if (pool_procs[mid].id < id) lo = mid + 1; else hi = mid;
  }
  rtl_fatal("call through a bad procedure pointer %08X", (unsigned)id);
  return 0;
}

/* ---- numbers ------------------------------------------------------------------------------------------------ */
s32 rtl_trunc(double x)
{
  return (s32)x;
}

s32 rtl_round(double x)
{
  return (s32)(x < 0 ? ceil(x - 0.5) : floor(x + 0.5));
}

/* RandSeed (DS:4428) := RandSeed * 08088405h + 1; Random(n) = hi16(RandSeed) mod n (TP 6.0, whitepaper 5.13). */
static u32 random_calls;

u32 rtl_random_calls(void)
{
  return random_calls;
}

void rtl_dbg2(u16 a, u16 b)
{
  static int rlog = -1;
  if (rlog < 0)
    rlog = getenv("POOL_RLOG") != NULL;
  if (rlog)
    fprintf(stderr, "R 0 %u %u\n", a, b);
}

u16 rtl_Random(u16 range)
{
  u32 *seed = (u32 *)(DGS(0x4428));
  u32 s;
  random_calls++;
  memcpy(&s, seed, 4);
  s = s * 0x08088405u + 1u;
  memcpy(seed, &s, 4);
  {
    u16 r = range == 0 ? 0 : (u16)((s >> 16) % range);
    static int rlog = -1;
    if (rlog < 0)
      rlog = getenv("POOL_RLOG") != NULL;
    if (rlog)
      fprintf(stderr, "R %u %u %u\n", (unsigned)random_calls, range, r);       /* debugging aid: the dice, to compare with the CoCo's (tools lua/watch.lua MB_RLOG) */
    return r;
  }
}

void rtl_Randomize(void)
{
  u16 h, m, s, hund;
  u32 seed;
  rtl_GetTime(&h, &m, &s, &hund);
  seed = (((u32)s << 8 | hund) << 16) | ((u32)h << 8 | m);
  memcpy(DGS(0x4428), &seed, 4);
}

/* ---- strings ------------------------------------------------------------------------------------------------ */
u8 *rtl_str_assign(u8 *dst, int maxlen, const u8 *src)
{
  u8 n = src[0];
  if (dst == src) {
    if (n > maxlen) {
      dst[0] = (u8)maxlen;
    }
    return dst;
  }
  if (n > maxlen) {
    n = (u8)maxlen;
  }
  memmove(dst + 1, src + 1, n);
  dst[0] = n;
  return dst;
}

u8 *rtl_str_cat(u8 *dst, int n, const u8 *const parts[])
{
  u8 tmp[256];
  int len = 0, i;
  for (i = 0; i < n; i++) {
    int l = parts[i][0];
    if (len + l > 255) {
      l = 255 - len;
    }
    memcpy(tmp + 1 + len, parts[i] + 1, l);
    len += l;
  }
  tmp[0] = (u8)len;
  memcpy(dst, tmp, len + 1);
  return dst;
}

u8 *rtl_str_cat_v(u8 *dst, int n, ...)
{
  const u8 *parts[16];
  va_list ap;
  int i;
  va_start(ap, n);
  for (i = 0; i < n && i < 16; i++) {
    parts[i] = va_arg(ap, const u8 *);
  }
  va_end(ap);
  return rtl_str_cat(dst, i, parts);
}

u8 *rtl_str_char(u8 *dst, u8 c)
{
  dst[0] = 1;
  dst[1] = c;
  return dst;
}

int rtl_str_cmp(const u8 *a, const u8 *b)
{
  int la = a[0], lb = b[0], n = la < lb ? la : lb, i;
  for (i = 1; i <= n; i++) {
    if (a[i] != b[i]) {
      return a[i] < b[i] ? -1 : 1;
    }
  }
  return la == lb ? 0 : (la < lb ? -1 : 1);
}

u8 *rtl_str_copy(u8 *dst, const u8 *s, int idx, int cnt)
{
  int len = s[0];
  u8 tmp[256];
  if (idx < 1) idx = 1;
  if (cnt < 0 || idx > len) cnt = 0;
  else if (idx + cnt - 1 > len) cnt = len - idx + 1;
  if (cnt > 0) {
    memcpy(tmp + 1, s + idx, cnt);
  }
  tmp[0] = (u8)cnt;
  memcpy(dst, tmp, cnt + 1);
  return dst;
}

u8 rtl_str_pos(const u8 *sub, const u8 *s)
{
  int ls = sub[0], l = s[0], i;
  if (ls == 0) return 0;
  for (i = 1; i + ls - 1 <= l; i++) {
    if (memcmp(s + i, sub + 1, ls) == 0) {
      return (u8)i;
    }
  }
  return 0;
}

void rtl_str_delete(u8 *s, int idx, int cnt)
{
  int len = s[0];
  if (idx < 1 || idx > len || cnt <= 0) return;
  if (idx + cnt - 1 > len) cnt = len - idx + 1;
  memmove(s + idx, s + idx + cnt, len - (idx + cnt - 1));
  s[0] = (u8)(len - cnt);
}

void rtl_str_insert(const u8 *src, u8 *s, int maxlen, int idx)
{
  u8 tmp[512];
  int ls = src[0], len = s[0], n;
  if (idx < 1) idx = 1;
  if (idx > len + 1) idx = len + 1;
  memcpy(tmp + 1, s + 1, idx - 1);
  memcpy(tmp + idx, src + 1, ls);
  memcpy(tmp + idx + ls, s + idx, len - idx + 1);
  n = len + ls;
  if (n > maxlen) n = maxlen;
  memcpy(s + 1, tmp + 1, n);
  s[0] = (u8)n;
}

void rtl_str_int(u8 *s, int maxlen, s32 v, int width)
{
  char buf[32];
  int n = snprintf(buf, sizeof buf, "%ld", (long)v), pad = width > n ? width - n : 0, total = n + pad;
  if (total > maxlen) total = maxlen;
  memset(s + 1, ' ', pad < total ? pad : total);
  if (total > pad) {
    memcpy(s + 1 + pad, buf, total - pad);
  }
  s[0] = (u8)total;
}

void rtl_str_real(u8 *s, int maxlen, double v, int width, int dec)
{
  char buf[64];
  int n;
  if (dec >= 0) {
    n = snprintf(buf, sizeof buf, "%*.*f", width, dec, v);
  } else {
    n = snprintf(buf, sizeof buf, "%*.*E", width > 0 ? width : 17, 10, v);
  }
  if (n > maxlen) n = maxlen;
  memcpy(s + 1, buf, n);
  s[0] = (u8)n;
}

/* Val: optional sign, then decimal digits or $hex; `code` is 0 or the 1-based position of the first bad character. */
void rtl_str_val(const u8 *s, void *v, int size, int is_signed, void *code)
{
  int len = s[0], i = 1;
  int neg = 0, base = 10, ndig = 0;
  double acc = 0;
  s16 err = 0;
  s32 result;
  while (i <= len && s[i] == ' ') i++;
  if (i <= len && (s[i] == '-' || s[i] == '+')) {
    neg = s[i] == '-';
    i++;
  }
  if (i <= len && (s[i] == '$' || s[i] == 'x' || s[i] == 'X')) {
    base = 16;
    i++;
  } else if (i < len && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X')) {
    base = 16;
    i += 2;
  }
  for (; i <= len; i++) {
    int c = s[i], d;
    if (c >= '0' && c <= '9') d = c - '0';
    else if (base == 16 && c >= 'a' && c <= 'f') d = c - 'a' + 10;
    else if (base == 16 && c >= 'A' && c <= 'F') d = c - 'A' + 10;
    else break;
    acc = acc * base + d;
    ndig++;
  }
  if (i <= len) {
    err = (s16)i;
  } else if (ndig == 0) {
    err = (s16)(len + 1);
  }
  if (neg) acc = -acc;
  if (err == 0) {
    double lo = is_signed ? -(double)(1u << (size * 8 - 1)) : 0.0;
    double hi = is_signed ? (double)((1u << (size * 8 - 1)) - 1u) : (size == 4 ? 4294967295.0 : (double)((1u << (size * 8)) - 1u));
    if (size == 4 && is_signed) { lo = -2147483648.0; hi = 2147483647.0; }
    if (acc < lo || acc > hi) err = (s16)i;
  }
  if (err == 0) {
    result = (s32)(long)acc;
    if (size == 1) { u8 b = (u8)result; memcpy(v, &b, 1); }
    else if (size == 2) { u16 w = (u16)result; memcpy(v, &w, 2); }
    else { memcpy(v, &result, 4); }
  }
  memcpy(code, &err, 2);
}

u8 rtl_upcase(u8 c)
{
  return (c >= 'a' && c <= 'z') ? (u8)(c - 32) : c;
}

u8 rtl_lowercase(u8 c)
{
  return (c >= 'A' && c <= 'Z') ? (u8)(c + 32) : c;
}

/* The game's own command line: ParamStr(1) = 'STING' skips the title screens and the code wheel question. */
static const char *game_args[8];
static int game_argc;

void rtl_set_args(int n, const char *const *args)
{
  int i;
  game_argc = n > 8 ? 8 : n;
  for (i = 0; i < game_argc; i++) {
    game_args[i] = args[i];
  }
}

u8 *rtl_paramstr(u8 *dst, int n)
{
  size_t len = (n >= 1 && n <= game_argc) ? strlen(game_args[n - 1]) : 0;
  if (len > 255) len = 255;
  if (n == 0) {
    memcpy(dst + 1, "POOL.EXE", 8);
    dst[0] = 8;
    return dst;
  }
  dst[0] = (u8)len;
  if (len) memcpy(dst + 1, game_args[n - 1], len);
  return dst;
}

u16 rtl_ParamCount(void)
{
  return (u16)game_argc;
}

/* ---- sets --------------------------------------------------------------------------------------------------- */
void rtl_set_clear(u8 *s, int n) { memset(s, 0, n); }
void rtl_set_add(u8 *s, int v) { s[(v >> 3) & 31] |= (u8)(1u << (v & 7)); }
void rtl_set_range(u8 *s, int lo, int hi) { int i; for (i = lo; i <= hi; i++) rtl_set_add(s, i); }
int rtl_set_in_at(const u8 *s, int first, int n, int v)
{
  int b = (v >> 3) - first;
  return v >= 0 && b >= 0 && b < n && ((s[b] >> (v & 7)) & 1);
}
int rtl_set_in(const u8 *s, int v) { return v >= 0 && v < 256 && ((s[v >> 3] >> (v & 7)) & 1); }
u8 *rtl_set_union(u8 *d, const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) d[i] = a[i] | b[i]; return d; }
u8 *rtl_set_diff(u8 *d, const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) d[i] = a[i] & (u8)~b[i]; return d; }
u8 *rtl_set_inter(u8 *d, const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) d[i] = a[i] & b[i]; return d; }
int rtl_set_eq(const u8 *a, const u8 *b, int n) { return memcmp(a, b, n) == 0; }
int rtl_set_le(const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) if (a[i] & ~b[i]) return 0; return 1; }
int rtl_set_ge(const u8 *a, const u8 *b, int n) { return rtl_set_le(b, a, n); }

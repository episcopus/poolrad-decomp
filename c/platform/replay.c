/* replay.c: the headless platform: plays a recording of the original game (tools/c/export_replay.py) against the
 * C translation and compares the screen with the original's at every recorded checkpoint.
 *
 *   poolrad_replay --data DIR [--save DIR] [--dump PREFIX] SESSION.rpl
 *
 * Each read of the outside world (key, clock, PIT, retrace) is answered with the value the original read at the
 * same point of its run. The game takes the same path only if the translation behaves like the original, so a
 * different read, a different screen at a checkpoint or different files at the end are findings, and the first one
 * is reported with the read number. See platform.h for the contract and tools/oracle/replay.py for the format's
 * origin. */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <direct.h>
#else
#include <unistd.h>
#endif

#include "ega.h"
#include "platform.h"
#include "sha256.h"

extern int rtl_written_files(void (*cb)(const char *, const char *, void *), void *ctx);
extern u32 rtl_random_calls(void);
extern int rtl_data_file(const char *dos_name, char *out, size_t cap);
extern void sound_trace_dump(FILE *f);

enum { K_WAIT = 0, K_PEEK = 1, K_TIME = 2, K_DATE = 3, K_PIT = 4, K_RETRACE = 5, K_SKIP = 9 };

typedef struct Run {
  u8 kind;
  u32 a, b, c, d, flags, irq, count;
} Run;

typedef struct Checkpoint {
  long at;                      /* after this read; -1 is the end of the recording */
  char label[64];
  char screen[65];
  char canon[65];
  u32 random_calls;
} Checkpoint;

typedef struct Written {
  char name[256];
  char sha[65];
} Written;

static Run *runs;
static size_t nruns, cur_run;
static u32 used_in_run;
static long idx;                 /* reads of the recording consumed so far, skipped ones included */
static long total_reads;
static Checkpoint *cps;
static size_t ncps, next_cp;
static u32 masks[256][2];
static int nmasks;
typedef struct Zero {
  char name[256];
  u32 lo[8], hi[8];
  int n;
} Zero;
static Zero zeros[32];
static int nzeros;
static Written *written;
static size_t nwritten;
static u32 expect_random;
static u32 irq_delivered;
static void (*timer_handler)(void);
static const char *g_data = ".", *g_save = "build/c/save", *g_dump;
static long g_snap = -2;
static long g_snap_call = -1, g_ncalls;           /* --snap-call N: snapshot at the N-th traced call */
static long g_trace_lo = -1, g_trace_hi = -1;     /* --trace-calls LO HI: routine names while the read count is in [LO, HI) */                 /* write DGROUP, heap and planes after this read */
static int screens_ok, screens_bad, state_ok, state_bad, skipped_cps;
static char first_problem[512];
static int failed;
static int g_screens_only;
static const char *session_name = "?";

/* ---- the recording ----------------------------------------------------------------------------------------- */
static void load(const char *path)
{
  FILE *f = fopen(path, "r");
  char line[1024];
  size_t cap_r = 1024, cap_c = 256, cap_w = 16;
  if (!f) {
    fprintf(stderr, "poolrad_replay: cannot open %s\n", path);
    exit(2);
  }
  runs = (Run *)malloc(cap_r * sizeof *runs);
  cps = (Checkpoint *)malloc(cap_c * sizeof *cps);
  written = (Written *)malloc(cap_w * sizeof *written);
  while (fgets(line, sizeof line, f)) {
    if (line[0] == 'H') {
      total_reads = atol(line + 2);
    } else if (line[0] == 'R') {
      Run r;
      unsigned k, a, b, c, d, fl, irq, n;
      if (sscanf(line + 2, "%u %u %u %u %u %u %u %u", &k, &a, &b, &c, &d, &fl, &irq, &n) != 8) continue;
      r.kind = (u8)k; r.a = a; r.b = b; r.c = c; r.d = d; r.flags = fl; r.irq = irq; r.count = n;
      if (nruns == cap_r) { cap_r *= 2; runs = (Run *)realloc(runs, cap_r * sizeof *runs); }
      runs[nruns++] = r;
    } else if (line[0] == 'C') {
      Checkpoint c;
      long at;
      char label[64], scr[80], can[80];
      unsigned rc;
      if (sscanf(line + 2, "%ld %63s %79s %79s %u", &at, label, scr, can, &rc) != 5) continue;
      c.at = at;
      snprintf(c.label, sizeof c.label, "%s", label);
      snprintf(c.screen, sizeof c.screen, "%s", scr);
      snprintf(c.canon, sizeof c.canon, "%s", can);
      c.random_calls = rc;
      if (ncps == cap_c) { cap_c *= 2; cps = (Checkpoint *)realloc(cps, cap_c * sizeof *cps); }
      cps[ncps++] = c;
    } else if (line[0] == 'M') {
      unsigned lo, hi;
      if (sscanf(line + 2, "%u %u", &lo, &hi) == 2 && nmasks < 256) {
        masks[nmasks][0] = lo;
        masks[nmasks][1] = hi;
        nmasks++;
      }
    } else if (line[0] == 'Z') {
      char *p = line + 2, *e;
      Zero *z = &zeros[nzeros < 32 ? nzeros : 31];
      size_t n = strcspn(p, " ");
      memset(z, 0, sizeof *z);
      snprintf(z->name, sizeof z->name, "%.*s", (int)n, p);
      p += n;
      for (;;) {
        unsigned long lo = strtoul(p, &e, 10), hi;
        if (e == p) break;
        p = e;
        hi = strtoul(p, &e, 10);
        if (e == p) break;
        p = e;
        if (z->n < 8) { z->lo[z->n] = (u32)lo; z->hi[z->n] = (u32)hi; z->n++; }
      }
      if (nzeros < 32) nzeros++;
    } else if (line[0] == 'F') {
      expect_random = (u32)atol(line + 2);
    } else if (line[0] == 'W') {
      Written w;
      if (sscanf(line + 2, "%255s %64s", w.name, w.sha) != 2) continue;
      if (nwritten == cap_w) { cap_w *= 2; written = (Written *)realloc(written, cap_w * sizeof *written); }
      written[nwritten++] = w;
    }
  }
  fclose(f);
}

/* ---- digests ----------------------------------------------------------------------------------------------------- */
static void screen_digest(char out[65])
{
  Sha256 c;
  u8 d[32];
  int p;
  sha256_init(&c);
  for (p = 0; p < 4; p++) {
    sha256_update(&c, ega.planes[p], 0x10000);
  }
  sha256_final(&c, d);
  sha256_hex(d, out);
}

/* The game's state: DGROUP without the masked ranges, the allocated heap, the screen digest (export_replay.py: masked_digest). */
static void canon_digest(char out[65])
{
  static u8 ds[0x10000];
  Sha256 c;
  u8 d[32];
  char scr[65];
  u32 org = POOL_LINEAR(*(u32 *)(pool_ds + 0x4400)), ptr = POOL_LINEAR(*(u32 *)(pool_ds + 0x4404));
  memcpy(ds, pool_ds, sizeof ds);
  {
    int i;
    for (i = 0; i < nmasks; i++) {                /* the runtime's own bookkeeping (tools/c/export_replay.py) */
      memset(ds + masks[i][0], 0, masks[i][1] - masks[i][0]);
    }
  }
  sha256_init(&c);
  sha256_update(&c, "MASKED", 6);
  sha256_update(&c, ds, sizeof ds);
  sha256_update(&c, "heap", 4);
  if (org > 0 && org <= ptr && ptr <= 0xA0000) {
    sha256_update(&c, pool_arena + org, ptr - org);
  }
  screen_digest(scr);
  sha256_update(&c, scr, 64);
  sha256_final(&c, d);
  sha256_hex(d, out);
}

static void problem(const char *fmt, const char *a, long n)
{
  if (!failed) {
    snprintf(first_problem, sizeof first_problem, fmt, a, n);
  }
  failed = 1;
}

static void dump_planes(const char *label)
{
  char path[512];
  FILE *f;
  if (!g_dump) {
    return;
  }
  snprintf(path, sizeof path, "%s-%s.planes", g_dump, label);
  f = fopen(path, "wb");
  if (f) {
    fwrite(ega.planes, 1, sizeof ega.planes, f);
    fclose(f);
  }
}

static void dump_screen(const char *label)
{
  dump_planes(label);
  int w, h;
  static u32 pix[640 * 350];
  char path[512];
  FILE *f;
  int i;
  if (!g_dump || !ega_size(&w, &h)) {
    return;
  }
  ega_render(pix);
  snprintf(path, sizeof path, "%s-%s.ppm", g_dump, label);
  f = fopen(path, "wb");
  if (!f) return;
  fprintf(f, "P6\n%d %d\n255\n", w, h);
  for (i = 0; i < w * h; i++) {
    fputc(pix[i] & 255, f);
    fputc((pix[i] >> 8) & 255, f);
    fputc((pix[i] >> 16) & 255, f);
  }
  fclose(f);
}

#ifdef POOL_TRACE_CALLS
static void canon_digest(char out[65]);
static void snapshot(void);
void pool_trace(const char *name)
{
  if (g_trace_lo >= 0 && idx >= g_trace_lo && idx < g_trace_hi) {
    char d[65];
    if (g_ncalls++ == g_snap_call && g_dump) {
      snapshot();
    }
    canon_digest(d);
    fprintf(stdout, "call %s %.16s\n", name, d);          /* the game's state on entry, as tools/c/export_replay.py */
  }
}
#endif

long pool_replay_index(void) { return idx; }

static void snapshot(void)
{
  char path[512];
  FILE *f;
  u32 org = POOL_LINEAR(*(u32 *)(pool_ds + 0x4400)), ptr = POOL_LINEAR(*(u32 *)(pool_ds + 0x4404));
  snprintf(path, sizeof path, "%s-snap.dgroup", g_dump);
  f = fopen(path, "wb");
  if (f) { fwrite(pool_ds, 1, 0x10000, f); fclose(f); }
  snprintf(path, sizeof path, "%s-snap.heap", g_dump);
  f = fopen(path, "wb");
  if (f) { if (org < ptr && ptr <= 0xA0000) fwrite(pool_arena + org, 1, ptr - org, f); fclose(f); }
  dump_planes("snap");
}

static void check_cps(long at)
{
  if (at == g_snap && g_dump) {
    snapshot();
  }
  while (next_cp < ncps && cps[next_cp].at <= at) {
    Checkpoint *c = &cps[next_cp++];
    char scr[65], can[65];
    if (c->at != at && at != -1) {
      skipped_cps++;                              /* a checkpoint that fell on a read the translation does not make */
      continue;
    }
    screen_digest(scr);
    if (strcmp(scr, c->screen) == 0) {
      screens_ok++;
    } else {
      screens_bad++;
      if (!failed) {
        snprintf(first_problem, sizeof first_problem, "screen differs at checkpoint %s (after read %ld)", c->label, c->at);
      }
      dump_screen(c->label);
      failed = 1;
    }
    canon_digest(can);
    if (strcmp(can, c->canon) == 0) {
      state_ok++;
    } else {
      state_bad++;
      if (!failed && !g_screens_only) {
        snprintf(first_problem, sizeof first_problem, "game state differs at checkpoint %s (after read %ld); see tools/c/bisect_state.py",
                 c->label, c->at);
        failed = 1;
      }
    }
    if (c->random_calls != rtl_random_calls() && c->at != -1) {
      /* the checkpoint's Random count is that of the original at the same read */
      if (!failed) {
        snprintf(first_problem, sizeof first_problem, "Random called %u times at checkpoint %s, the original %u",
                 rtl_random_calls(), c->label, c->random_calls);
      }
      failed = 1;
    }
  }
}

/* ---- finishing -------------------------------------------------------------------------------------------------- */
typedef struct WriteCtx {
  int bad;
  int seen;
} WriteCtx;

static void sha_file(const char *path, const char *dos, char out[65])
{
  FILE *f = fopen(path, "rb");
  Sha256 c;
  u8 d[32], buf[8192];
  size_t n;
  u32 pos = 0;
  const Zero *z = NULL;
  int i;
  for (i = 0; i < nzeros; i++) {
    if (dos && strcmp(zeros[i].name, dos) == 0) z = &zeros[i];
  }
  sha256_init(&c);
  out[0] = 0;
  if (!f) return;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) {
    if (z) {                                       /* known differences: those bytes count as zero */
      int k;
      u32 j;
      for (k = 0; k < z->n; k++) {
        for (j = z->lo[k]; j < z->hi[k]; j++) {
          if (j >= pos && j < pos + n) buf[j - pos] = 0;
        }
      }
    }
    pos += (u32)n;
    sha256_update(&c, buf, n);
  }
  fclose(f);
  sha256_final(&c, d);
  sha256_hex(d, out);
}

static void check_file(const char *dos, const char *host, void *ctx)
{
  WriteCtx *w = (WriteCtx *)ctx;
  char sha[65];
  size_t i;
  sha_file(host, dos, sha);
  for (i = 0; i < nwritten; i++) {
    if (strcmp(written[i].name, dos) == 0) {
      w->seen++;
      if (strcmp(written[i].sha, sha) != 0) {
        problem("file %s differs from the original's", dos, 0);
        w->bad++;
      }
      return;
    }
  }
  {
    /* a file the original opened for update but left as it was: the translation may have rewritten it unchanged */
    char pinned[1100], psha[65];
    if (rtl_data_file(dos, pinned, sizeof pinned)) {
      sha_file(pinned, NULL, psha);
      if (strcmp(psha, sha) == 0) {
        return;
      }
    }
  }
  problem("the translation wrote %s, the original did not", dos, 0);
  w->bad++;
}

static void finish(const char *why)
{
  WriteCtx w = {0, 0};
  check_cps(-1);
  dump_screen("final");
  rtl_written_files(check_file, &w);
  if (w.seen < (int)nwritten && !failed) {
    snprintf(first_problem, sizeof first_problem, "the original wrote %d files, the translation %d",
             (int)nwritten, w.seen);
    failed = 1;
  }
  if (rtl_random_calls() != expect_random && !failed) {
    snprintf(first_problem, sizeof first_problem, "Random called %u times, the original %u", rtl_random_calls(),
             expect_random);
    failed = 1;
  }
  printf("[%s] %s after %ld of %ld reads: screens %d ok, %d differ; state %d equal, %d differ; %d checkpoints on reads "
         "only the original makes; %d files written\n",
         session_name, why, idx, total_reads, screens_ok, screens_bad, state_ok, state_bad, skipped_cps, w.seen);
  printf("[%s] video mode %02Xh, %u video operations, %u Random calls\n", session_name, ega.mode, ega.dirty,
         rtl_random_calls());
  if (failed) {
    printf("[%s] FAIL: %s\n", session_name, first_problem);
  } else {
    printf("[%s] ok: the translation plays the session as the original did\n", session_name);
  }
  exit(failed ? 1 : 0);
}

/* ---- reads ---------------------------------------------------------------------------------------------------------- */
static const Run *take(int kind)
{
  const Run *r;
  /* reads the C runtime does not make (the BIOS tick word the original's Crt polls) pass unseen */
  while (cur_run < nruns && runs[cur_run].kind == K_SKIP) {
    idx += (long)(runs[cur_run].count - used_in_run);
    used_in_run = 0;
    cur_run++;
  }
  if (cur_run >= nruns) {
    finish("the recording ended");
  }
  r = &runs[cur_run];
  if (r->kind != kind) {
    char msg[200];
    snprintf(msg, sizeof msg, "read %ld: the game asked for kind %d, the original read kind %d", idx + 1, kind, r->kind);
    problem("%s", msg, 0);
    finish("diverged");
  }
  idx++;
  if (++used_in_run >= r->count) {
    used_in_run = 0;
    cur_run++;
  }
  if (r->irq > irq_delivered) {
    u32 n = r->irq - irq_delivered;
    irq_delivered = r->irq;
    if (timer_handler) {
      while (n-- > 0) timer_handler();
    }
  }
  check_cps(idx);
  return r;
}

u16 platform_key_peek(void)
{
  const Run *r = take(K_PEEK);
  return (r->flags & 0x40) ? 0 : (u16)r->a;
}

u16 platform_key_wait(void)
{
  return (u16)take(K_WAIT)->a;
}

void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund)
{
  const Run *r = take(K_TIME);
  *hour = (u8)(r->c >> 8);
  *min = (u8)r->c;
  *sec = (u8)(r->d >> 8);
  *hund = (u8)r->d;
}

void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow)
{
  const Run *r = take(K_DATE);
  *year = (u16)r->c;
  *month = (u8)(r->d >> 8);
  *day = (u8)r->d;
  *dow = (u8)r->a;
}

u8 platform_pit_counter(void)
{
  return (u8)take(K_PIT)->a;
}

u8 platform_retrace_status(void)
{
  return (u8)take(K_RETRACE)->a;
}

void platform_delay_ms(u16 ms) { (void)ms; }

extern void sound_trace_pit0(u16 reload);

void platform_timer_set(u16 divisor, void (*handler)(void))
{
  sound_trace_pit0(divisor);
  timer_handler = handler;
}

void platform_timer_reset(void)
{
  sound_trace_pit0(0);
  timer_handler = NULL;
}

/* The sound hardware writes are kept for the sound comparison (sound_trace). */
extern void sound_trace_speaker(u16 divisor, u8 gate);
extern void sound_trace_tandy(u8 v);

void platform_speaker_set(u16 divisor, u8 port61_low2) { sound_trace_speaker(divisor, port61_low2); }
void platform_speaker_off(void) { sound_trace_speaker(0, 0); }
void platform_tandy_write(u8 value) { sound_trace_tandy(value); }
void platform_video_changed(void) {}
void platform_pump(void) {}

void platform_quit(int code)
{
  char why[64];
  snprintf(why, sizeof why, "the game quit (code %d)", code);
  finish(why);
}

const char *platform_data_dir(void) { return g_data; }
const char *platform_save_dir(void) { return g_save; }

/* ---- main ------------------------------------------------------------------------------------------------------------- */
static void rmtree(const char *dir)
{
  char cmd[1100];
#ifdef _WIN32
  snprintf(cmd, sizeof cmd, "rmdir /s /q \"%s\" 2>nul", dir);
#else
  snprintf(cmd, sizeof cmd, "rm -rf '%s'", dir);
#endif
  if (system(cmd) != 0) {
  }
}

int main(int argc, char **argv)
{
  int i;
  const char *rpl = NULL;
  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--data") == 0 && i + 1 < argc) g_data = argv[++i];
    else if (strcmp(argv[i], "--save") == 0 && i + 1 < argc) g_save = argv[++i];
    else if (strcmp(argv[i], "--dump") == 0 && i + 1 < argc) g_dump = argv[++i];
    else if (strcmp(argv[i], "--screens-only") == 0) g_screens_only = 1;
    else if (strcmp(argv[i], "--trace-calls") == 0 && i + 2 < argc) {
      g_trace_lo = atol(argv[++i]);
      g_trace_hi = atol(argv[++i]);
    }
    else if (strcmp(argv[i], "--snap-call") == 0 && i + 1 < argc) g_snap_call = atol(argv[++i]);
    else if (strcmp(argv[i], "--snap") == 0 && i + 1 < argc) g_snap = atol(argv[++i]);
    else rpl = argv[i];
  }
  if (!rpl) {
    fprintf(stderr, "usage: poolrad_replay --data DIR [--save DIR] [--dump PREFIX] SESSION.rpl\n");
    return 2;
  }
  {
    const char *slash = strrchr(rpl, '/');
    session_name = slash ? slash + 1 : rpl;
  }
  load(rpl);
  rmtree(g_save);
  rtl_init();
  pool_init_units();
  pool_main();
  finish("the program ended");
  return 0;
}

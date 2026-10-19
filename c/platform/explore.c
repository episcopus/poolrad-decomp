/* explore.c: a headless host that plays a key script on the C translation, fast, and writes the screens it is asked for.
 *
 *   poolrad_explore --data DIR --save DIR --script FILE --out PREFIX [--max-polls N]
 *
 * It is a tool for finding out where things are in the game before a session is recorded on the original (tests/sessions,
 * playbook 40): a run takes seconds where the oracle takes a minute. It answers nothing from a recording, so it proves
 * nothing: a session is only a golden once the oracle has recorded it and `make c-golden` has replayed it here.
 *
 * The script is the oracle's (tools/oracle/keys.py): key, press, text, wait (ignored), shot NAME (writes PREFIX-NAME.ppm), clock,
 * wheel (answers the code wheel), quit. A key is handed over when the game has polled the keyboard four times in a row with
 * the screen unchanged, or blocks in a read, as the oracle does. Time is virtual: it moves with the game's polls. */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "game.h"
#include "ega.h"
#include "platform.h"

extern u8 rtl_wheel_pick;
extern u32 rtl_random_calls(void);

#define MAXOPS 4096
typedef struct Op { char kind; u16 key; char name[48]; } Op;   /* k key, p press, s shot, q quit, w wheel, t wait (key = ticks) */
static Op ops[MAXOPS];
static int nops, opi;
static const char *g_data = ".", *g_save = "build/explore/save", *g_out = "build/explore/x";
static long polls, idle_polls;
static unsigned long vus;                         /* virtual microseconds */
static unsigned long clock_hund = 12UL * 360000 + 1637;     /* 12:00:16.37 unless the script pins it */
static void (*timer_handler)(void);
static unsigned long timer_us = 54925, timer_next;
static long max_polls = 2000000000L;
static int pending_wheel;
static long op_since;                            /* polls since the script moved on */
static unsigned long hold_until;                 /* a wait: no key before this virtual time */
static u16 wheel_keys[16];
static int wheel_n, wheel_i;
static const char *WORDS[13] = {"BEWARE", "ZOMBIE", "NOTNOW", "COPPER", "DRAGON", "EFREET", "FRIEND", "JUNGLE", "KNIGHT", "SAVIOR", "TEMPLE", "VULCAN", "WYVERN"};

static u16 char_key(int c)
{
  static const char *rows[4] = {"1234567890-=", "qwertyuiop[]", "asdfghjkl;'`", "\\zxcvbnm,./"};
  static const int start[4] = {0x02, 0x10, 0x1E, 0x2B};
  int r;
  const char *p;
  if (c == ' ') return 0x3920;
  if (c == '\n') return 0x1C0D;
  for (r = 0; r < 4; r++) {
    p = strchr(rows[r], tolower(c));
    if (p && *p) return (u16)(((start[r] + (int)(p - rows[r])) << 8) | (c & 255));
  }
  return (u16)c;
}

static u16 named_key(const char *t)
{
  static const struct { const char *n; u16 k; } nk[] = {
    {"ESC", 0x011B}, {"ENTER", 0x1C0D}, {"RETURN", 0x1C0D}, {"SPACE", 0x3920}, {"TAB", 0x0F09}, {"BKSP", 0x0E08},
    {"UP", 0x4800}, {"DOWN", 0x5000}, {"LEFT", 0x4B00}, {"RIGHT", 0x4D00}, {"HOME", 0x4700}, {"END", 0x4F00},
    {"PGUP", 0x4900}, {"PGDN", 0x5100}, {"INS", 0x5200}, {"DEL", 0x5300}};
  size_t i;
  char up[16];
  for (i = 0; i < sizeof up - 1 && t[i]; i++) up[i] = (char)toupper((unsigned char)t[i]);
  up[i] = 0;
  for (i = 0; i < sizeof nk / sizeof nk[0]; i++) if (strcmp(up, nk[i].n) == 0) return nk[i].k;
  if (up[0] == 'F' && isdigit((unsigned char)up[1])) return (u16)((0x3B + atoi(up + 1) - 1) << 8);
  if (strncmp(up, "0X", 2) == 0) return (u16)strtol(up, NULL, 16);
  return char_key((unsigned char)t[0]);
}

static void add(char kind, u16 key, const char *name)
{
  if (nops >= MAXOPS) { fprintf(stderr, "explore: script too long\n"); exit(2); }
  ops[nops].kind = kind;
  ops[nops].key = key;
  snprintf(ops[nops].name, sizeof ops[nops].name, "%s", name ? name : "");
  nops++;
}

static void load_script(const char *path)
{
  char line[512];
  FILE *f = fopen(path, "r");
  if (!f) { perror(path); exit(2); }
  while (fgets(line, sizeof line, f)) {
    char *h = strchr(line, '#'), *cmd, *arg;
    if (h) *h = 0;
    cmd = line;
    while (isspace((unsigned char)*cmd)) cmd++;
    arg = cmd;
    while (*arg && !isspace((unsigned char)*arg)) arg++;
    if (*arg) *arg++ = 0;
    while (isspace((unsigned char)*arg)) arg++;
    { char *e = arg + strlen(arg); while (e > arg && isspace((unsigned char)e[-1])) *--e = 0; }
    if (!*cmd) continue;
    if (!strcmp(cmd, "key")) add('k', named_key(arg), "");
    else if (!strcmp(cmd, "press")) add('p', named_key(arg), "");
    else if (!strcmp(cmd, "text")) { for (; *arg; arg++) add('k', char_key((unsigned char)*arg), ""); }
    else if (!strcmp(cmd, "shot") || !strcmp(cmd, "digest")) { if (cmd[0] == 's') add('s', 0, *arg ? arg : "shot"); }
    else if (!strcmp(cmd, "state")) add('S', 0, *arg ? arg : "state");
    else if (!strcmp(cmd, "wait")) add('t', (u16)atoi(arg), "");
    else if (!strcmp(cmd, "quit")) add('q', 0, "");
    else if (!strcmp(cmd, "wheel")) add('w', 0, "");
    else if (!strcmp(cmd, "clock")) {
      int h = 0, m = 0, s = 0, hs = 0;
      sscanf(arg, "%d:%d:%d.%d", &h, &m, &s, &hs);
      clock_hund = (unsigned long)(((h * 60 + m) * 60 + s) * 100 + hs);
    }
  }
  fclose(f);
}

static void shot(const char *name)
{
  char path[600];
  int w, h;
  u32 *rgba;
  FILE *f;
  if (ega_size(&w, &h) <= 0 || w <= 0) return;
  rgba = (u32 *)malloc((size_t)w * (size_t)h * 4);
  if (!rgba) return;
  ega_render(rgba);
  snprintf(path, sizeof path, "%s-%s.ppm", g_out, name);
  f = fopen(path, "wb");
  if (f) {
    int i;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (i = 0; i < w * h; i++) {
      u8 px[3];
      px[0] = (u8)(rgba[i] & 255);
      px[1] = (u8)((rgba[i] >> 8) & 255);
      px[2] = (u8)((rgba[i] >> 16) & 255);
      fwrite(px, 1, 3, f);
    }
    fclose(f);
  }
  free(rgba);
}

static void dump_state(const char *name);
static void finish(const char *why)
{
  shot("final");
  fprintf(stderr, "explore: %s after %ld polls, %u Random calls\n", why, polls, (unsigned)rtl_random_calls());
  exit(0);
}

static void dump_state(const char *name)
{
  char path[600];
  FILE *f;
  snprintf(path, sizeof path, "%s-%s.json", g_out, name);
  f = fopen(path, "w");
  if (!f) return;
  fprintf(f, "{\"col\": %d, \"row\": %d, \"facing\": %d, \"areaview\": %d, \"viewmode\": %d", (int)PartyMapColumn, (int)PartyMapRow,
          (int)PartyFacing, (int)AreaViewKind, (int)ViewMode);
  if (SelectedCharacter) {
    const u8 *nm = (const u8 *)FPD(u8 *, SelectedCharacter);
    fprintf(f, ", \"selected\": \"%.*s\"", nm[0] > 15 ? 15 : nm[0], nm + 1);
  }
  if (GameVars) {
    const u16 *gv = (const u16 *)FPD(u8 *, GameVars);
    fprintf(f, ", \"geoblock\": %u, \"mapx\": %u, \"mapy\": %u", (unsigned)gv[VarGeoBlock], (unsigned)gv[VarMapX], (unsigned)gv[VarMapY]);
  }
  if (GeoCells) {
    TGeoCellBlock *g = FPD(TGeoCellBlock *, GeoCells);
    int i, pl;
    const u8 *planes[4] = {&g->WallsNE[0][0], &g->WallsSW[0][0], &g->Events[0][0], &g->Cells[0][0]};
    const char *names[4] = {"ne", "sw", "events", "cells"};
    for (pl = 0; pl < 4; pl++) {
      fprintf(f, ", \"%s\": \"", names[pl]);
      for (i = 0; i < 256; i++) fprintf(f, "%02x", planes[pl][i]);
      fprintf(f, "\"");
    }
  }
  fprintf(f, "}\n");
  fclose(f);
}

#ifdef POOL_TRACE_CALLS
/* a build with -DPOOLRAD_TRACE=ON: EXPLORE_WATCH=Name,Name prints where the party was when one of those routines was entered */
void pool_trace(const char *name)
{
  static const char *watch;
  static int init;
  if (!init) { watch = getenv("EXPLORE_WATCH"); init = 1; }
  if (watch) {
    size_t n = strlen(name);
    const char *p = watch;
    while ((p = strstr(p, name)) != NULL) {
      if ((p == watch || p[-1] == ',') && (p[n] == ',' || p[n] == 0)) {
        fprintf(stderr, "HIT %s col %d row %d facing %d op %d\n", name, (int)PartyMapColumn, (int)PartyMapRow, (int)PartyFacing, opi);
        break;
      }
      p += n;
    }
  }
}
#endif

static void tick(void)
{
  polls++;
  vus += 40;
  if (timer_handler) {
    while (vus >= timer_next) { timer_next += timer_us; timer_handler(); }
  }
  if (opi >= nops && !pending_wheel && polls - op_since > 30000) finish("the script ended");
  if (polls > max_polls) finish("poll limit");
}

/* the next key the script has ready, or 0 */
static u16 next_key(int idle)
{
  static int logged = -1;
  if (getenv("EXPLORE_LOG") && logged != opi && opi < nops && idle) { logged = opi; fprintf(stderr, "op %d (%c %04X %s) at poll %ld, vus %lu\n", opi, ops[opi].kind, ops[opi].key, ops[opi].name, polls, vus); }
  while (opi < nops) {
    Op *o = &ops[opi];
    if (o->kind == 's') { if (!idle && polls - op_since < 3000) return 0; shot(o->name); opi++; op_since = polls; continue; }
    if (o->kind == 'S') { if (!idle && polls - op_since < 3000) return 0; dump_state(o->name); opi++; op_since = polls; continue; }
    if (o->kind == 'q') finish("quit");
    if (o->kind == 't') { if (!hold_until) hold_until = vus + (unsigned long)o->key * 54925UL; if (vus < hold_until) return 0; hold_until = 0; opi++; continue; }
    if (o->kind == 'w') {
      int n;
      if (!idle) return 0;
      if (!(rtl_wheel_pick & 0x80)) return 0;                 /* the question is not asked yet */
      wheel_n = 0;
      for (n = 0; WORDS[rtl_wheel_pick & 0x7F][n]; n++) wheel_keys[wheel_n++] = char_key(WORDS[rtl_wheel_pick & 0x7F][n]);
      wheel_keys[wheel_n++] = 0x1C0D;
      wheel_i = 0;
      pending_wheel = 1;
      opi++;
      continue;
    }
    if (pending_wheel) return 0;
    if (o->kind == 'k' && !idle) return 0;
    opi++;
    op_since = polls;
    return o->key;
  }
  return 0;
}

static u16 queued;                                  /* a key peeked and not yet taken */

u16 platform_key_peek(void)
{
  u16 k;
  tick();
  if (queued) return queued;
  if (pending_wheel) {
    if (wheel_i < wheel_n && idle_polls >= 4) { idle_polls = 0; queued = wheel_keys[wheel_i++]; return queued; }
    if (wheel_i >= wheel_n) pending_wheel = 0;
  }
  idle_polls++;
  k = next_key(idle_polls >= 4);
  if (k) { idle_polls = 0; queued = k; return k; }
  if (opi >= nops && !pending_wheel && idle_polls > 40) finish("the script ended");
  return 0;
}

u16 platform_key_wait(void)
{
  for (;;) {
    u16 k;
    tick();
    if (queued) { k = queued; queued = 0; return k; }
    if (pending_wheel && wheel_i < wheel_n) return wheel_keys[wheel_i++];
    pending_wheel = 0;
    k = next_key(1);
    if (k) return k;
    if (opi >= nops) finish("the script ended in a key wait");
  }
}

void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund)
{
  unsigned long t;
  tick();
  t = clock_hund + vus / 10000UL;
  *hund = (u8)(t % 100); t /= 100;
  *sec = (u8)(t % 60); t /= 60;
  *min = (u8)(t % 60); t /= 60;
  *hour = (u8)(t % 24);
}

void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow) { *year = 1991; *month = 1; *day = 1; *dow = 2; }
void platform_delay_ms(u16 ms) { vus += (unsigned long)ms * 1000UL; }
u8 platform_pit_counter(void) { tick(); return (u8)(vus / 3); }
u8 platform_retrace_status(void) { tick(); return (u8)(((vus / 600) & 1) ? 8 : 0); }
void platform_timer_set(u16 divisor, void (*handler)(void))
{
  timer_us = (divisor ? divisor : 65536UL) * 838UL / 1000UL;
  timer_handler = handler;
  timer_next = vus + timer_us;
}
void platform_timer_reset(void) { timer_handler = NULL; }
void platform_speaker_set(u16 divisor, u8 port61_low2) { (void)divisor; (void)port61_low2; }
void platform_speaker_off(void) {}
void platform_tandy_write(u8 value) { (void)value; }
void sound_trace_pit0(u16 reload) { (void)reload; }
void platform_video_changed(void) { idle_polls = 0; }
void platform_pump(void) {}
void platform_quit(int code) { char why[48]; snprintf(why, sizeof why, "the game quit (code %d)", code); finish(why); }
const char *platform_data_dir(void) { return g_data; }
const char *platform_save_dir(void) { return g_save; }

int main(int argc, char **argv)
{
  int i;
  const char *script = NULL;
  char cmd[1100];
  for (i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--data") && i + 1 < argc) g_data = argv[++i];
    else if (!strcmp(argv[i], "--save") && i + 1 < argc) g_save = argv[++i];
    else if (!strcmp(argv[i], "--script") && i + 1 < argc) script = argv[++i];
    else if (!strcmp(argv[i], "--out") && i + 1 < argc) g_out = argv[++i];
    else if (!strcmp(argv[i], "--max-polls") && i + 1 < argc) max_polls = atol(argv[++i]);
  }
  if (!script) { fprintf(stderr, "usage: poolrad_explore --data DIR --save DIR --script FILE --out PREFIX\n"); return 2; }
  load_script(script);
  snprintf(cmd, sizeof cmd, "rm -rf '%s'; mkdir -p '%s'", g_save, g_save);
  if (system(cmd) != 0) {}
  rtl_init();
  pool_init_units();
  pool_main();
  finish("the program ended");
  return 0;
}

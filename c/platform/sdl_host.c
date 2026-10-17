/* sdl_host.c: the game you play: platform.h over SDL3 (window, keyboard, clock, audio) on macOS, Linux and
 * Windows.
 *
 *   poolrad [--data DIR] [--save DIR] [--scale N] [--fullscreen] [--aspect 4:3|square] [--filter nearest|linear]
 *           [--sound speaker|tandy|off] [--volume 0-100] [--mute] [--intro]
 *
 * The game starts at the main menu: the original's switch STING skips the title screens and the code wheel
 * question; --intro plays them (and asks the question).
 *
 * The data directory is the original game's folder (GAME.OVR, the .DAX files, ITEMS ...). The game's own saved
 * files go to the save directory (a per-user folder by default), so the data folder is never changed.
 *
 * Keys while playing (they never reach the game):
 *   F11 or Alt+Enter     full screen on/off
 *   Alt+1 .. Alt+6       window size 1x .. 6x the picture (leaves full screen)
 *   Alt+A                4:3 picture (the PC's tall pixels) or square pixels
 *   Alt+F                sharp or smooth scaling
 *   Alt+M                sound on/off          Alt+Minus, Alt+Plus   volume
 * On macOS Cmd works in place of Alt. The choices are remembered in poolrad.ini in the save directory.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <SDL3/SDL.h>

#include "ega.h"
#include "platform.h"

extern void rtl_init(void);

/* ---- settings ------------------------------------------------------------------------------------------------ */
typedef struct Settings {
  int scale;            /* window size as a multiple of the 320x200 picture */
  int fullscreen;
  int aspect43;         /* stretch the picture to 4:3 */
  int smooth;           /* linear filter instead of nearest */
  int volume;           /* 0..100 */
  int muted;
  char sound;           /* 'P' speaker, 'T' Tandy, 'N' none */
} Settings;

static Settings cfg = {3, 0, 1, 0, 70, 0, 'P'};
static char data_dir[1024] = "";
static char save_dir[1024] = "";
static char ini_path[1100] = "";

static void load_ini(void)
{
  FILE *f = fopen(ini_path, "r");
  char line[256];
  if (!f) return;
  while (fgets(line, sizeof line, f)) {
    int v;
    char c;
    if (sscanf(line, "scale=%d", &v) == 1 && v >= 1 && v <= 8) cfg.scale = v;
    else if (sscanf(line, "fullscreen=%d", &v) == 1) cfg.fullscreen = v != 0;
    else if (sscanf(line, "aspect43=%d", &v) == 1) cfg.aspect43 = v != 0;
    else if (sscanf(line, "smooth=%d", &v) == 1) cfg.smooth = v != 0;
    else if (sscanf(line, "volume=%d", &v) == 1 && v >= 0 && v <= 100) cfg.volume = v;
    else if (sscanf(line, "muted=%d", &v) == 1) cfg.muted = v != 0;
    else if (sscanf(line, "sound=%c", &c) == 1 && (c == 'P' || c == 'T' || c == 'N')) cfg.sound = c;
  }
  fclose(f);
}

static void save_ini(void)
{
  FILE *f = fopen(ini_path, "w");
  if (!f) return;
  fprintf(f, "scale=%d\nfullscreen=%d\naspect43=%d\nsmooth=%d\nvolume=%d\nmuted=%d\nsound=%c\n", cfg.scale,
          cfg.fullscreen, cfg.aspect43, cfg.smooth, cfg.volume, cfg.muted, cfg.sound);
  fclose(f);
}

/* ---- video --------------------------------------------------------------------------------------------------- */
static SDL_Window *win;
static SDL_Renderer *ren;
static SDL_Texture *tex;
static u32 pixels[640 * 350];
static u32 shown_dirty = (u32)-1;
static int video_pending = 1;
static Uint64 last_present_ns;
static int tex_w, tex_h;

static void apply_view(void)
{
  int w = 320, h = 200;
  ega_size(&w, &h);
  SDL_SetRenderLogicalPresentation(ren, w, cfg.aspect43 ? h * 6 / 5 : h,
                                   cfg.scale > 0 && !cfg.smooth ? SDL_LOGICAL_PRESENTATION_INTEGER_SCALE
                                                                : SDL_LOGICAL_PRESENTATION_LETTERBOX);
  if (tex) SDL_SetTextureScaleMode(tex, cfg.smooth ? SDL_SCALEMODE_LINEAR : SDL_SCALEMODE_NEAREST);
}

static void resize_window(void)
{
  int w = 320, h = 200;
  ega_size(&w, &h);
  SDL_SetWindowFullscreen(win, false);
  cfg.fullscreen = 0;
  SDL_SetWindowSize(win, w * cfg.scale, (cfg.aspect43 ? h * 6 / 5 : h) * cfg.scale);
}

static void present(void)
{
  int w, h;
  SDL_FRect dst;
  if (!ega_size(&w, &h)) {
    /* a text mode: the game never uses one; show black */
    SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
    SDL_RenderClear(ren);
    SDL_RenderPresent(ren);
    return;
  }
  if (!tex || tex_w != w || tex_h != h) {
    if (tex) SDL_DestroyTexture(tex);
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STREAMING, w, h);
    tex_w = w;
    tex_h = h;
    apply_view();
  }
  ega_render(pixels);
  SDL_UpdateTexture(tex, NULL, pixels, w * 4);
  SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
  SDL_RenderClear(ren);
  dst.x = 0;
  dst.y = 0;
  dst.w = (float)w;
  dst.h = (float)(cfg.aspect43 ? h * 6 / 5 : h);
  SDL_RenderTexture(ren, tex, NULL, &dst);
  SDL_RenderPresent(ren);
  shown_dirty = ega.dirty;
  video_pending = 0;
  last_present_ns = SDL_GetTicksNS();
}

/* ---- audio: the PC speaker and the Tandy SN76489 as square waves ------------------------------------------------ */
#define RATE 44100
static SDL_AudioStream *audio;
static SDL_Mutex *audio_lock;
static struct {
  int spk_on;              /* speaker gate and data bits both set */
  u16 spk_div;
  u8 tandy_latch;          /* last latched register */
  u16 tone[3];             /* tone periods */
  u8 vol[4];               /* attenuation 0 (loud) .. 15 (off) */
  u8 noise;                /* noise control */
} snd;
static struct {
  double spk_phase;
  double tone_phase[3];
  u16 lfsr;
  double noise_phase;
  float lp;
} syn = {0, {0, 0, 0}, 0x4000, 0, 0};

static float tandy_amp(int att)
{
  return att >= 15 ? 0.0f : (float)pow(10.0, -0.1 * att);       /* 2 dB per step */
}

static void synth(s16 *out, int n)
{
  int i, ch;
  float master = cfg.muted ? 0.0f : (float)cfg.volume / 100.0f * 0.35f;
  int spk_on = snd.spk_on;
  double spk_hz = snd.spk_div ? 1193181.0 / snd.spk_div : 0;
  for (i = 0; i < n; i++) {
    float mix = 0;
    if (spk_on && spk_hz > 0 && spk_hz < RATE / 2) {
      syn.spk_phase += spk_hz / RATE;
      if (syn.spk_phase >= 1.0) syn.spk_phase -= 1.0;
      mix += syn.spk_phase < 0.5 ? 0.5f : -0.5f;
    }
    for (ch = 0; ch < 3; ch++) {
      u16 p = snd.tone[ch];
      float a = tandy_amp(snd.vol[ch]);
      if (a > 0 && p > 1) {
        double hz = 3579545.0 / (32.0 * p);
        if (hz < RATE / 2) {
          syn.tone_phase[ch] += hz / RATE;
          if (syn.tone_phase[ch] >= 1.0) syn.tone_phase[ch] -= 1.0;
          mix += (syn.tone_phase[ch] < 0.5 ? 0.3f : -0.3f) * a;
        }
      }
    }
    {
      float a = tandy_amp(snd.vol[3]);
      if (a > 0) {
        static const int rates[3] = {512, 1024, 2048};
        int sel = snd.noise & 3;
        double hz = sel < 3 ? 3579545.0 / (rates[sel] / 1.0) : (snd.tone[2] > 1 ? 3579545.0 / (32.0 * snd.tone[2]) : 1000);
        syn.noise_phase += hz / RATE;
        while (syn.noise_phase >= 1.0) {
          int fb = (snd.noise & 4) ? ((syn.lfsr ^ (syn.lfsr >> 1)) & 1) : (syn.lfsr & 1);
          syn.lfsr = (u16)((syn.lfsr >> 1) | (fb << 14));
          syn.noise_phase -= 1.0;
        }
        mix += ((syn.lfsr & 1) ? 0.3f : -0.3f) * a;
      }
    }
    syn.lp += (mix - syn.lp) * 0.45f;                           /* a little smoothing against harsh aliasing */
    {
      float v = syn.lp * master * 32767.0f;
      out[i] = (s16)(v > 32767.0f ? 32767.0f : (v < -32768.0f ? -32768.0f : v));
    }
  }
}

static void SDLCALL audio_cb(void *ud, SDL_AudioStream *stream, int additional, int total)
{
  s16 buf[2048];
  (void)ud;
  (void)total;
  while (additional > 0) {
    int n = additional / 2;
    if (n > 2048) n = 2048;
    if (n <= 0) break;
    SDL_LockMutex(audio_lock);
    synth(buf, n);
    SDL_UnlockMutex(audio_lock);
    SDL_PutAudioStreamData(stream, buf, n * 2);
    additional -= n * 2;
  }
}

static void audio_start(void)
{
  SDL_AudioSpec spec;
  audio_lock = SDL_CreateMutex();
  spec.format = SDL_AUDIO_S16;
  spec.channels = 1;
  spec.freq = RATE;
  memset(&snd, 0, sizeof snd);
  snd.vol[0] = snd.vol[1] = snd.vol[2] = snd.vol[3] = 15;
  audio = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_cb, NULL);
  if (audio) {
    SDL_ResumeAudioStreamDevice(audio);
  } else {
    fprintf(stderr, "poolrad: no audio (%s)\n", SDL_GetError());
  }
}

void platform_speaker_set(u16 divisor, u8 port61_low2)
{
  extern void sound_trace_speaker(u16, u8);
  sound_trace_speaker(divisor, port61_low2);
  if (!audio_lock) return;
  SDL_LockMutex(audio_lock);
  snd.spk_div = divisor;
  snd.spk_on = (port61_low2 & 3) == 3;
  SDL_UnlockMutex(audio_lock);
}

void platform_speaker_off(void)
{
  extern void sound_trace_speaker(u16, u8);
  sound_trace_speaker(0, 0);
  if (!audio_lock) return;
  SDL_LockMutex(audio_lock);
  snd.spk_on = 0;
  SDL_UnlockMutex(audio_lock);
}

void platform_tandy_write(u8 v)
{
  extern void sound_trace_tandy(u8);
  sound_trace_tandy(v);
  if (!audio_lock) return;
  SDL_LockMutex(audio_lock);
  if (v & 0x80) {
    int reg = (v >> 5) & 3;
    snd.tandy_latch = (u8)(v & 0x7F);
    if (v & 0x10) {
      snd.vol[reg] = v & 15;
    } else if (reg == 3) {
      snd.noise = v & 7;
      syn.lfsr = 0x4000;
    } else {
      snd.tone[reg] = (u16)((snd.tone[reg] & 0x3F0) | (v & 15));
    }
  } else {
    int reg = (snd.tandy_latch >> 5) & 3;
    if (!(snd.tandy_latch & 0x10) && reg < 3) {
      snd.tone[reg] = (u16)((snd.tone[reg] & 15) | ((v & 0x3F) << 4));
    }
  }
  SDL_UnlockMutex(audio_lock);
}

/* ---- keyboard ----------------------------------------------------------------------------------------------------- */
#define KEYQ 64
static u16 keyq[KEYQ];
static unsigned key_head, key_tail;

/* BIOS scan codes by SDL scancode (USB HID usage); 0: no key */
static const u8 bios_scan[232] = {
    [4] = 0x1E, [5] = 0x30, [6] = 0x2E, [7] = 0x20, [8] = 0x12, [9] = 0x21, [10] = 0x22, [11] = 0x23, [12] = 0x17,
    [13] = 0x24, [14] = 0x25, [15] = 0x26, [16] = 0x32, [17] = 0x31, [18] = 0x18, [19] = 0x19, [20] = 0x10,
    [21] = 0x13, [22] = 0x1F, [23] = 0x14, [24] = 0x16, [25] = 0x2F, [26] = 0x11, [27] = 0x2D, [28] = 0x15,
    [29] = 0x2C, [30] = 0x02, [31] = 0x03, [32] = 0x04, [33] = 0x05, [34] = 0x06, [35] = 0x07, [36] = 0x08,
    [37] = 0x09, [38] = 0x0A, [39] = 0x0B, [40] = 0x1C, [41] = 0x01, [42] = 0x0E, [43] = 0x0F, [44] = 0x39,
    [45] = 0x0C, [46] = 0x0D, [47] = 0x1A, [48] = 0x1B, [49] = 0x2B, [51] = 0x27, [52] = 0x28, [53] = 0x29,
    [54] = 0x33, [55] = 0x34, [56] = 0x35, [58] = 0x3B, [59] = 0x3C, [60] = 0x3D, [61] = 0x3E, [62] = 0x3F,
    [63] = 0x40, [64] = 0x41, [65] = 0x42, [66] = 0x43, [67] = 0x44, [68] = 0x85, [69] = 0x86, [73] = 0x52,
    [74] = 0x47, [75] = 0x49, [76] = 0x53, [77] = 0x4F, [78] = 0x51, [79] = 0x4D, [80] = 0x4B, [81] = 0x50,
    [82] = 0x48, [84] = 0x35, [85] = 0x37, [86] = 0x4A, [87] = 0x4E, [88] = 0x1C, [89] = 0x4F, [90] = 0x50,
    [91] = 0x51, [92] = 0x4B, [93] = 0x4C, [94] = 0x4D, [95] = 0x47, [96] = 0x48, [97] = 0x49, [98] = 0x52,
    [99] = 0x53,
};

static void key_push(u16 code)
{
  unsigned next = (key_head + 1) % KEYQ;
  if (next != key_tail) {
    keyq[key_head] = code;
    key_head = next;
  }
}

/* One SDL key press as the BIOS would report it, 0 when the key does not exist on a PC keyboard. */
static u16 bios_key(const SDL_KeyboardEvent *k)
{
  u8 scan;
  u16 ascii = 0;
  SDL_Keymod mod = k->mod;
  SDL_Keycode sym;
  if ((int)k->scancode >= 232) return 0;
  scan = bios_scan[k->scancode];
  if (!scan) return 0;
  /* extended keys have no ASCII */
  if ((k->scancode >= 58 && k->scancode <= 69) || (k->scancode >= 73 && k->scancode <= 82)) {
    return (u16)(scan << 8);
  }
  if (k->scancode >= 89 && k->scancode <= 99 && !(mod & SDL_KMOD_NUM)) {
    return (u16)(scan << 8);                                     /* keypad with NumLock off: navigation */
  }
  sym = SDL_GetKeyFromScancode(k->scancode, (SDL_Keymod)(mod & (SDL_KMOD_SHIFT | SDL_KMOD_CAPS)), false);
  if (sym < 128) ascii = (u16)sym;
  if (k->scancode == SDL_SCANCODE_RETURN || k->scancode == SDL_SCANCODE_KP_ENTER) ascii = 13;
  if (k->scancode == SDL_SCANCODE_ESCAPE) ascii = 27;
  if (k->scancode == SDL_SCANCODE_BACKSPACE) ascii = 8;
  if (k->scancode == SDL_SCANCODE_TAB) ascii = 9;
  if (k->scancode == SDL_SCANCODE_SPACE) ascii = 32;
  if ((mod & SDL_KMOD_CTRL) && ascii >= 'a' && ascii <= 'z') ascii = (u16)(ascii - 'a' + 1);
  else if ((mod & SDL_KMOD_CTRL) && ascii >= 'A' && ascii <= 'Z') ascii = (u16)(ascii - 'A' + 1);
  if ((mod & SDL_KMOD_ALT) && ascii >= 32) ascii = 0;            /* Alt+key: the scan code alone */
  if ((mod & SDL_KMOD_SHIFT) && k->scancode == SDL_SCANCODE_TAB) return 0x0F00;
  return (u16)((scan << 8) | ascii);
}

static void toggle_fullscreen(void)
{
  cfg.fullscreen = !cfg.fullscreen;
  SDL_SetWindowFullscreen(win, cfg.fullscreen != 0);
  video_pending = 1;
}

/* Alt/Cmd shortcuts: returns 1 when the key was one of ours. */
static int hotkey(const SDL_KeyboardEvent *k)
{
  int alt = (k->mod & (SDL_KMOD_ALT | SDL_KMOD_GUI)) != 0;
  if (k->scancode == SDL_SCANCODE_F11 || (alt && (k->scancode == SDL_SCANCODE_RETURN))) {
    toggle_fullscreen();
    return 1;
  }
  if (!alt) return 0;
  if (k->scancode >= SDL_SCANCODE_1 && k->scancode <= SDL_SCANCODE_6) {
    cfg.scale = (int)(k->scancode - SDL_SCANCODE_1) + 1;
    resize_window();
    apply_view();
    video_pending = 1;
    return 1;
  }
  switch (k->scancode) {
  case SDL_SCANCODE_A: cfg.aspect43 = !cfg.aspect43; apply_view(); resize_window(); video_pending = 1; return 1;
  case SDL_SCANCODE_F: cfg.smooth = !cfg.smooth; apply_view(); video_pending = 1; return 1;
  case SDL_SCANCODE_M: cfg.muted = !cfg.muted; return 1;
  case SDL_SCANCODE_MINUS: cfg.volume = cfg.volume > 5 ? cfg.volume - 10 : 0; return 1;
  case SDL_SCANCODE_EQUALS: cfg.volume = cfg.volume < 95 ? cfg.volume + 10 : 100; return 1;
  default: return 0;
  }
}

/* ---- time, the timer interrupt, polling ------------------------------------------------------------------------ */
static Uint64 start_ns;
static time_t start_wall;
static u16 timer_div;
static void (*timer_handler)(void);
static Uint64 timer_last_ns;
static double timer_carry;
static Uint64 pump_ns;
static unsigned spin;
static const char *shot_path;            /* --screenshot FILE MS: save the window to a BMP after MS ms and exit (tests) */
static Uint64 shot_ms;
static const char *inject_keys;          /* --inject L,A,...: key presses fed in at start-up, one every 700 ms (tests) */
static Uint64 inject_next;
static int show_intro;                   /* --intro: the title screens and the code wheel question */

static Uint64 now_ns(void)
{
  return SDL_GetTicksNS();
}

static void run_timer(void)
{
  Uint64 t;
  double due;
  int n;
  if (!timer_handler) return;
  t = now_ns();
  due = (double)(t - timer_last_ns) * 1e-9 * (1193182.0 / (timer_div ? timer_div : 65536)) + timer_carry;
  timer_last_ns = t;
  n = (int)due;
  timer_carry = due - n;
  if (n > 16) {                                                   /* the game was suspended: do not storm */
    n = 16;
    timer_carry = 0;
  }
  while (n-- > 0 && timer_handler) {
    timer_handler();
  }
}

/* Test input: names of keys pushed as if typed. */
static void inject(void)
{
  SDL_Event e;
  char name[16];
  const char *p = inject_keys;
  size_t n;
  SDL_Scancode sc = SDL_SCANCODE_UNKNOWN;
  if (!p || !*p || now_ns() < inject_next) return;
  n = strcspn(p, ",");
  snprintf(name, sizeof name, "%.*s", (int)(n < 15 ? n : 15), p);
  inject_keys = p[n] ? p + n + 1 : p + n;
  inject_next = now_ns() + 700000000u;
  if (strlen(name) == 1 && name[0] >= 'A' && name[0] <= 'Z') sc = (SDL_Scancode)(SDL_SCANCODE_A + (name[0] - 'A'));
  else if (strlen(name) == 1 && name[0] >= '1' && name[0] <= '9') sc = (SDL_Scancode)(SDL_SCANCODE_1 + (name[0] - '1'));
  else if (!strcmp(name, "ENTER")) sc = SDL_SCANCODE_RETURN;
  else if (!strcmp(name, "ESC")) sc = SDL_SCANCODE_ESCAPE;
  else if (!strcmp(name, "SPACE")) sc = SDL_SCANCODE_SPACE;
  else if (!strcmp(name, "UP")) sc = SDL_SCANCODE_UP;
  else if (!strcmp(name, "LEFT")) sc = SDL_SCANCODE_LEFT;
  else if (!strcmp(name, "RIGHT")) sc = SDL_SCANCODE_RIGHT;
  else if (!strcmp(name, "DOWN")) sc = SDL_SCANCODE_DOWN;
  if (sc == SDL_SCANCODE_UNKNOWN) return;
  SDL_zero(e);
  e.type = SDL_EVENT_KEY_DOWN;
  e.key.scancode = sc;
  e.key.key = SDL_GetKeyFromScancode(sc, SDL_KMOD_NONE, false);
  e.key.mod = SDL_KMOD_NONE;
  e.key.down = true;
  SDL_PushEvent(&e);
}

static void events(void)
{
  SDL_Event e;
  inject();
  while (SDL_PollEvent(&e)) {
    switch (e.type) {
    case SDL_EVENT_QUIT:
      platform_quit(0);
      break;
    case SDL_EVENT_KEY_DOWN:
      if (hotkey(&e.key)) break;
      {
        u16 code = bios_key(&e.key);
        if (code) key_push(code);
      }
      break;
    case SDL_EVENT_WINDOW_EXPOSED:
    case SDL_EVENT_WINDOW_RESIZED:
    case SDL_EVENT_WINDOW_RESTORED:
      video_pending = 1;
      break;
    default:
      break;
    }
  }
}

void platform_pump(void)
{
  Uint64 t = now_ns();
  run_timer();
  if (t - pump_ns < 1000000u) {
    return;                                                       /* at most once a millisecond */
  }
  pump_ns = t;
  events();
  if ((video_pending || ega.dirty != shown_dirty) && t - last_present_ns >= 16000000u) {
    present();
  }
  if (shot_path && (t - start_ns) / 1000000u >= shot_ms) {
    SDL_Surface *surf;
    present();
    surf = SDL_RenderReadPixels(ren, NULL);
    if (surf) {
      SDL_SaveBMP(surf, shot_path);
      SDL_DestroySurface(surf);
    }
    platform_quit(0);
  }
}

/* A game that polls in a tight loop gets a short sleep instead of a busy core. */
static void spin_check(void)
{
  platform_pump();
  if (++spin >= 40) {
    spin = 0;
    SDL_DelayNS(500000);
  }
}

u16 platform_key_peek(void)
{
  spin_check();
  return key_head == key_tail ? 0 : keyq[key_tail];
}

u16 platform_key_wait(void)
{
  for (;;) {
    u16 k;
    platform_pump();
    if (key_head != key_tail) {
      k = keyq[key_tail];
      key_tail = (key_tail + 1) % KEYQ;
      spin = 0;
      return k;
    }
    if (video_pending || ega.dirty != shown_dirty) present();
    SDL_DelayNS(2000000);
  }
}

void platform_delay_ms(u16 ms)
{
  Uint64 end = now_ns() + (Uint64)ms * 1000000u;
  while (now_ns() < end) {
    platform_pump();
    SDL_DelayNS(1000000);
  }
  spin = 0;
}

void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund)
{
  Uint64 t;
  time_t w;
  struct tm tmv;
  spin_check();
  t = now_ns() - start_ns;
  w = start_wall + (time_t)(t / 1000000000u);
#ifdef _WIN32
  localtime_s(&tmv, &w);
#else
  localtime_r(&w, &tmv);
#endif
  *hour = (u8)tmv.tm_hour;
  *min = (u8)tmv.tm_min;
  *sec = (u8)tmv.tm_sec;
  *hund = (u8)((t % 1000000000u) / 10000000u);
}

void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow)
{
  time_t w = time(NULL);
  struct tm tmv;
#ifdef _WIN32
  localtime_s(&tmv, &w);
#else
  localtime_r(&w, &tmv);
#endif
  *year = (u16)(tmv.tm_year + 1900);
  *month = (u8)(tmv.tm_mon + 1);
  *day = (u8)tmv.tm_mday;
  *dow = (u8)tmv.tm_wday;
}

u8 platform_pit_counter(void)
{
  return (u8)(SDL_GetPerformanceCounter() >> 3);
}

u8 platform_retrace_status(void)
{
  Uint64 us = (now_ns() / 1000u) % 16667u;
  int vr = us >= 15000u;
  spin_check();
  return (u8)((vr ? 8 : 0) | ((vr || ((us / 30u) & 1u)) ? 1 : 0));
}

void platform_timer_set(u16 divisor, void (*handler)(void))
{
  extern void sound_trace_pit0(u16);
  sound_trace_pit0(divisor);
  timer_div = divisor;
  timer_handler = handler;
  timer_last_ns = now_ns();
  timer_carry = 0;
}

void platform_timer_reset(void)
{
  extern void sound_trace_pit0(u16);
  sound_trace_pit0(0);
  timer_handler = NULL;
}

void platform_video_changed(void)
{
  video_pending = 1;
}

void platform_quit(int code)
{
  save_ini();
  if (audio) SDL_DestroyAudioStream(audio);
  if (tex) SDL_DestroyTexture(tex);
  if (ren) SDL_DestroyRenderer(ren);
  if (win) SDL_DestroyWindow(win);
  SDL_Quit();
  exit(code);
}

const char *platform_data_dir(void) { return data_dir; }
const char *platform_save_dir(void) { return save_dir; }

/* ---- start ------------------------------------------------------------------------------------------------------------ */
static int dir_has_game(const char *d)
{
  char p[1200];
  FILE *f;
  snprintf(p, sizeof p, "%s/GAME.OVR", d);
  f = fopen(p, "rb");
  if (!f) {
    snprintf(p, sizeof p, "%s/game.ovr", d);
    f = fopen(p, "rb");
  }
  if (f) fclose(f);
  return f != NULL;
}

static void make_dir(const char *p)
{
  char tmp[1200];
  char *q;
  snprintf(tmp, sizeof tmp, "%s", p);
  for (q = tmp + 1; *q; q++) {
    if (*q == '/' || *q == '\\') {
      char c = *q;
      *q = 0;
      SDL_CreateDirectory(tmp);
      *q = c;
    }
  }
  SDL_CreateDirectory(tmp);
}

/* POOL.CFG for this run: EGA video, the chosen sound, the game's own folders as DOS names. */
static void write_cfg(void)
{
  char p[1200];
  FILE *f;
  snprintf(p, sizeof p, "%s/POOL.CFG", save_dir);
  f = fopen(p, "wb");
  if (!f) return;
  fprintf(f, "E\r\n%c\r\nC:\\POOLRAD\\\r\nC:\\POOLRAD\\SAVE\\\r\nF\r\n", cfg.sound == 'T' ? 'T' : (cfg.sound == 'N' ? 'N' : 'P'));
  fclose(f);
}

int main(int argc, char **argv)
{
  int i;
  int want_full = -1;
  const char *pref;
  char *base;
  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--data") == 0 && i + 1 < argc) snprintf(data_dir, sizeof data_dir, "%s", argv[++i]);
    else if (strcmp(argv[i], "--save") == 0 && i + 1 < argc) snprintf(save_dir, sizeof save_dir, "%s", argv[++i]);
    else if (strcmp(argv[i], "--scale") == 0 && i + 1 < argc) cfg.scale = atoi(argv[++i]);
    else if (strcmp(argv[i], "--fullscreen") == 0) want_full = 1;
    else if (strcmp(argv[i], "--windowed") == 0) want_full = 0;
    else if (strcmp(argv[i], "--aspect") == 0 && i + 1 < argc) cfg.aspect43 = strcmp(argv[++i], "square") != 0;
    else if (strcmp(argv[i], "--filter") == 0 && i + 1 < argc) cfg.smooth = strcmp(argv[++i], "linear") == 0;
    else if (strcmp(argv[i], "--sound") == 0 && i + 1 < argc) {
      const char *s = argv[++i];
      cfg.sound = s[0] == 't' || s[0] == 'T' ? 'T' : (s[0] == 'o' || s[0] == 'n' || s[0] == 'O' || s[0] == 'N' ? 'N' : 'P');
    } else if (strcmp(argv[i], "--volume") == 0 && i + 1 < argc) cfg.volume = atoi(argv[++i]);
    else if (strcmp(argv[i], "--mute") == 0) cfg.muted = 1;
    else if (strcmp(argv[i], "--intro") == 0) show_intro = 1;
    else if (strcmp(argv[i], "--inject") == 0 && i + 1 < argc) inject_keys = argv[++i];
    else if (strcmp(argv[i], "--screenshot") == 0 && i + 2 < argc) {
      shot_path = argv[++i];
      shot_ms = (Uint64)atol(argv[++i]);
    }
    else {
      fprintf(stderr,
              "usage: poolrad [--data DIR] [--save DIR] [--scale N] [--fullscreen|--windowed] [--aspect 4:3|square]\n"
              "               [--filter nearest|linear] [--sound speaker|tandy|off] [--volume 0-100] [--mute] [--intro]\n");
      return 2;
    }
  }
  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
    fprintf(stderr, "poolrad: SDL: %s\n", SDL_GetError());
    return 1;
  }
  /* where the game is: --data, $POOLRAD_DATA, the working directory, or next to the program */
  if (!data_dir[0] && getenv("POOLRAD_DATA")) snprintf(data_dir, sizeof data_dir, "%s", getenv("POOLRAD_DATA"));
  base = SDL_GetCurrentDirectory();
  if (!data_dir[0] && dir_has_game(".")) snprintf(data_dir, sizeof data_dir, ".");
  if (!data_dir[0] && SDL_GetBasePath() && dir_has_game(SDL_GetBasePath())) snprintf(data_dir, sizeof data_dir, "%s", SDL_GetBasePath());
  if (!data_dir[0] && dir_has_game("poolrad")) snprintf(data_dir, sizeof data_dir, "poolrad");
  if (!data_dir[0] || !dir_has_game(data_dir)) {
    const char *msg = "Pool of Radiance's game files (GAME.OVR and the .DAX files) were not found.\n"
                      "Run poolrad with --data FOLDER, where FOLDER holds your copy of the game.";
    fprintf(stderr, "poolrad: %s\n", msg);
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Pool of Radiance", msg, NULL);
    SDL_free(base);
    return 1;
  }
  SDL_free(base);
  if (!save_dir[0]) {
    pref = SDL_GetPrefPath("poolrad", "poolrad");
    snprintf(save_dir, sizeof save_dir, "%s%s", pref ? pref : "./", "save");
  }
  make_dir(save_dir);
  snprintf(ini_path, sizeof ini_path, "%s/poolrad.ini", save_dir);
  load_ini();
  if (want_full >= 0) cfg.fullscreen = want_full;
  write_cfg();

  start_ns = SDL_GetTicksNS();
  start_wall = time(NULL);
  win = SDL_CreateWindow("Pool of Radiance", 320 * cfg.scale, (cfg.aspect43 ? 240 : 200) * cfg.scale,
                         SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if (!win) {
    fprintf(stderr, "poolrad: window: %s\n", SDL_GetError());
    return 1;
  }
  ren = SDL_CreateRenderer(win, NULL);
  if (!ren) {
    fprintf(stderr, "poolrad: renderer: %s\n", SDL_GetError());
    return 1;
  }
  SDL_SetRenderVSync(ren, 1);
  SDL_SetWindowFullscreen(win, cfg.fullscreen != 0);
  SDL_HideCursor();
  apply_view();
  audio_start();

  rtl_init();
  if (!show_intro) {
    static const char *const sting[1] = {"STING"};
    rtl_set_args(1, sting);               /* the game's own switch: no title screens, no code wheel question */
  }
  pool_init_units();
  pool_main();
  platform_quit(0);
  return 0;
}

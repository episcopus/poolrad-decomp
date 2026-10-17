/* sdl_host.c: the game you play: platform.h over SDL3 (window, keyboard, clock, audio) on macOS, Linux and
 * Windows.
 *
 *   poolrad [--data DIR] [--save DIR] [--scale N] [--fullscreen] [--aspect 4:3|square] [--filter nearest|linear]
 *           [--sound speaker|tandy|off] [--volume 0-100] [--mute] [--skip-intro]
 *
 * The game starts as the original did: title screens, music and the code wheel question. --skip-intro passes the
 * original's own switch STING, which goes straight to the main menu (and also arms the developers' keys).
 * Options given on the command line win over the choices remembered in poolrad.ini (and are remembered).
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
#include "psg.h"

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
/* The driver writes the devices from its 236.7 Hz timer interrupt, so a sound is a sequence of writes a few
 * milliseconds apart (pitch sweeps, envelopes, gate toggles). The writes are queued with the time they were made
 * (a timer tick's own time, see run_timer) and the audio thread replays them at that time, AUDIO_LATENCY behind
 * the clock, so every tick is heard; reading the device state once per audio buffer instead lost short sounds. */
#define RATE 44100
#define AUDIO_LATENCY_NS 40000000u     /* the sound plays this far behind the game: room for a buffer's writes */
#define AUDIO_RESYNC_NS 80000000u      /* further than this from that point (a stall, a slow device): jump */
#define SOUND_QUEUE 16384              /* writes waiting for the audio thread (about 5 s of a playing tune) */
static Uint64 now_ns(void);
static SDL_AudioStream *audio;
static SDL_Mutex *audio_lock;
static Psg psg;                        /* the devices as the audio thread has replayed them so far */

enum { EvSpeaker, EvSpeakerOff, EvTandy };
typedef struct SoundEvent {
  Uint64 t;                /* when the game made the write (SDL ticks, ns) */
  u16 a;                   /* speaker divisor, Tandy byte */
  u8 kind, b;              /* b: the speaker's port 61h low bits */
} SoundEvent;
static SoundEvent sq[SOUND_QUEUE];
static unsigned sq_head, sq_tail;      /* under audio_lock */
static Uint64 play_ns;                 /* the time of the next sample the audio thread makes; 0: not started */
static Uint64 tick_ns;                 /* while the timer handler runs: the tick's time; 0 otherwise */
static FILE *wav_out;                  /* --wav FILE: the rendered sound, for tests */
static u32 wav_samples;

static void apply_event(const SoundEvent *e)
{
  switch (e->kind) {
  case EvSpeaker: psg_speaker(&psg, e->a, e->b); break;
  case EvSpeakerOff: psg_speaker_off(&psg); break;
  default: psg_tandy(&psg, (u8)e->a); break;
  }
}

static void queue_event(u8 kind, u16 a, u8 b)
{
  SoundEvent e;
  if (!audio_lock) return;
  e.t = tick_ns ? tick_ns : now_ns();
  e.kind = kind;
  e.a = a;
  e.b = b;
  SDL_LockMutex(audio_lock);
  if ((sq_head + 1) % SOUND_QUEUE == sq_tail) {                  /* nobody is playing them: keep the state only */
    apply_event(&sq[sq_tail]);
    sq_tail = (sq_tail + 1) % SOUND_QUEUE;
  }
  sq[sq_head] = e;
  sq_head = (sq_head + 1) % SOUND_QUEUE;
  SDL_UnlockMutex(audio_lock);
}

/* n samples from play_ns on: each write is applied at the sample of its time. */
static void synth(s16 *out, int n)
{
  int i;
  float master = cfg.muted ? 0.0f : (float)cfg.volume / 100.0f * 0.35f;
  Uint64 want = now_ns() - AUDIO_LATENCY_NS;
  if (play_ns == 0 || play_ns + AUDIO_RESYNC_NS < want || play_ns > want + AUDIO_RESYNC_NS) {
    play_ns = want;
  }
  for (i = 0; i < n; i++) {
    Uint64 t = play_ns + (Uint64)i * 1000000000u / RATE;
    float v;
    while (sq_tail != sq_head && sq[sq_tail].t <= t) {
      apply_event(&sq[sq_tail]);
      sq_tail = (sq_tail + 1) % SOUND_QUEUE;
    }
    v = psg_sample(&psg, RATE) * master * 32767.0f;
    out[i] = (s16)(v > 32767.0f ? 32767.0f : (v < -32768.0f ? -32768.0f : v));
  }
  play_ns += (Uint64)n * 1000000000u / RATE;
  if (wav_out) {
    fwrite(out, 2, (size_t)n, wav_out);
    wav_samples += (u32)n;
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

static void wav_header(FILE *f, u32 samples)
{
  u32 bytes = samples * 2;
  u8 h[44] = {'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ', 16, 0, 0, 0, 1, 0, 1, 0,
              RATE & 255, (RATE >> 8) & 255, 0, 0, (RATE * 2) & 255, ((RATE * 2) >> 8) & 255, ((RATE * 2) >> 16) & 255, 0,
              2, 0, 16, 0, 'd', 'a', 't', 'a', 0, 0, 0, 0};
  u32 riff = bytes + 36;
  int k;
  for (k = 0; k < 4; k++) {
    h[4 + k] = (u8)(riff >> (8 * k));
    h[40 + k] = (u8)(bytes >> (8 * k));
  }
  fseek(f, 0, SEEK_SET);
  fwrite(h, 1, sizeof h, f);
}

static void audio_start(const char *wav_path)
{
  SDL_AudioSpec spec;
  audio_lock = SDL_CreateMutex();
  spec.format = SDL_AUDIO_S16;
  spec.channels = 1;
  spec.freq = RATE;
  psg_reset(&psg);
  if (wav_path) {
    wav_out = fopen(wav_path, "wb");
    if (wav_out) wav_header(wav_out, 0);
  }
  audio = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_cb, NULL);
  if (audio) {
    SDL_ResumeAudioStreamDevice(audio);
  } else {
    fprintf(stderr, "poolrad: no audio (%s)\n", SDL_GetError());
  }
}

static void audio_stop(void)
{
  if (audio) SDL_DestroyAudioStream(audio);
  audio = NULL;
  if (wav_out) {
    wav_header(wav_out, wav_samples);
    fclose(wav_out);
    wav_out = NULL;
  }
}

void platform_speaker_set(u16 divisor, u8 port61_low2)
{
  extern void sound_trace_speaker(u16, u8);
  sound_trace_speaker(divisor, port61_low2);
  queue_event(EvSpeaker, divisor, port61_low2);
}

void platform_speaker_off(void)
{
  extern void sound_trace_speaker(u16, u8);
  sound_trace_speaker(0, 0);
  queue_event(EvSpeakerOff, 0, 0);
}

void platform_tandy_write(u8 v)
{
  extern void sound_trace_tandy(u8);
  sound_trace_tandy(v);
  queue_event(EvTandy, v, 0);
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
static double timer_next_ns;             /* when the next timer interrupt is due */
static Uint64 pump_ns;
static unsigned spin;
static const char *shot_path;            /* --screenshot FILE MS: save the window to a BMP after MS ms and exit (tests) */
static Uint64 shot_ms;
static const char *inject_keys;          /* --inject L,A,~3000,...: key presses fed in at start-up, one every 700 ms;
                                            ~MS waits MS ms more (tests) */
static Uint64 inject_next;
static int show_intro = 1;               /* the title screens and the code wheel question; --skip-intro: none */

static Uint64 now_ns(void)
{
  return SDL_GetTicksNS();
}

static double timer_period_ns(void)
{
  return 1e9 * (timer_div ? timer_div : 65536) / 1193182.0;
}

/* Every interrupt that is due, each with its own time (tick_ns), so the sound it makes is placed where the PC
   would have made it even when the game polls late. */
static void run_timer(void)
{
  double t;
  int n = 0;
  if (!timer_handler) return;
  t = (double)now_ns();
  if (t - timer_next_ns > 16 * timer_period_ns()) {               /* the game was suspended: do not storm */
    timer_next_ns = t;
  }
  while (timer_handler && timer_next_ns <= t && n++ < 16) {
    tick_ns = (Uint64)timer_next_ns;
    timer_handler();
    tick_ns = 0;
    timer_next_ns += timer_period_ns();
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
  if (name[0] == '~') {
    inject_next = now_ns() + (Uint64)atol(name + 1) * 1000000u;
    return;
  }
  if (strlen(name) == 1 && name[0] >= 'A' && name[0] <= 'Z') sc = (SDL_Scancode)(SDL_SCANCODE_A + (name[0] - 'A'));
  else if (strlen(name) == 1 && name[0] >= '1' && name[0] <= '9') sc = (SDL_Scancode)(SDL_SCANCODE_1 + (name[0] - '1'));
  else if (!strcmp(name, "ENTER")) sc = SDL_SCANCODE_RETURN;
  else if (!strcmp(name, "ESC")) sc = SDL_SCANCODE_ESCAPE;
  else if (!strcmp(name, "SPACE")) sc = SDL_SCANCODE_SPACE;
  else if (!strcmp(name, "UP")) sc = SDL_SCANCODE_UP;
  else if (!strcmp(name, "LEFT")) sc = SDL_SCANCODE_LEFT;
  else if (!strcmp(name, "RIGHT")) sc = SDL_SCANCODE_RIGHT;
  else if (!strcmp(name, "DOWN")) sc = SDL_SCANCODE_DOWN;
  else if (!strcmp(name, "END")) sc = SDL_SCANCODE_END;
  else if (!strcmp(name, "HOME")) sc = SDL_SCANCODE_HOME;
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
    int w = 320, h = 200;
    ega_size(&w, &h);                                             /* the game's picture itself, not the window's */
    ega_render(pixels);
    surf = SDL_CreateSurfaceFrom(w, h, SDL_PIXELFORMAT_RGBA32, pixels, w * 4);
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
  timer_next_ns = (double)now_ns() + timer_period_ns();
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
  audio_stop();
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

static const char *wav_path;             /* --wav FILE: also write the sound to a WAV file (tests) */

/* The command line. Pass 0 takes only the folders (the save folder holds poolrad.ini); pass 1, after the ini is read,
   takes the rest, so an option given on the command line wins over the remembered choice. 0: usage error. */
static int parse_args(int argc, char **argv, int pass, int *want_full)
{
  int i;
  for (i = 1; i < argc; i++) {
    const char *a = argv[i];
    int has1 = i + 1 < argc;
    if (strcmp(a, "--data") == 0 && has1) {
      if (pass == 0) snprintf(data_dir, sizeof data_dir, "%s", argv[i + 1]);
      i++;
    } else if (strcmp(a, "--save") == 0 && has1) {
      if (pass == 0) snprintf(save_dir, sizeof save_dir, "%s", argv[i + 1]);
      i++;
    } else if (strcmp(a, "--scale") == 0 && has1) {
      if (pass == 1) cfg.scale = atoi(argv[i + 1]);
      i++;
    } else if (strcmp(a, "--fullscreen") == 0) {
      *want_full = 1;
    } else if (strcmp(a, "--windowed") == 0) {
      *want_full = 0;
    } else if (strcmp(a, "--aspect") == 0 && has1) {
      if (pass == 1) cfg.aspect43 = strcmp(argv[i + 1], "square") != 0;
      i++;
    } else if (strcmp(a, "--filter") == 0 && has1) {
      if (pass == 1) cfg.smooth = strcmp(argv[i + 1], "linear") == 0;
      i++;
    } else if (strcmp(a, "--sound") == 0 && has1) {
      const char *v = argv[++i];
      if (pass == 1) {
        cfg.sound = v[0] == 't' || v[0] == 'T' ? 'T' : (v[0] == 'o' || v[0] == 'n' || v[0] == 'O' || v[0] == 'N' ? 'N' : 'P');
      }
    } else if (strcmp(a, "--volume") == 0 && has1) {
      if (pass == 1) cfg.volume = atoi(argv[i + 1]);
      i++;
    } else if (strcmp(a, "--mute") == 0) {
      if (pass == 1) cfg.muted = 1;
    } else if (strcmp(a, "--intro") == 0) {
      show_intro = 1;
    } else if (strcmp(a, "--skip-intro") == 0) {
      show_intro = 0;
    } else if (strcmp(a, "--inject") == 0 && has1) {
      inject_keys = argv[++i];
    } else if (strcmp(a, "--wav") == 0 && has1) {
      wav_path = argv[++i];
    } else if (strcmp(a, "--screenshot") == 0 && i + 2 < argc) {
      shot_path = argv[++i];
      shot_ms = (Uint64)atol(argv[++i]);
    } else {
      fprintf(stderr,
              "usage: poolrad [--data DIR] [--save DIR] [--scale N] [--fullscreen|--windowed] [--aspect 4:3|square]\n"
              "               [--filter nearest|linear] [--sound speaker|tandy|off] [--volume 0-100] [--mute]\n"
              "               [--skip-intro]\n");
      return 0;
    }
  }
  if (cfg.scale < 1) cfg.scale = 1;
  if (cfg.scale > 8) cfg.scale = 8;
  if (cfg.volume < 0) cfg.volume = 0;
  if (cfg.volume > 100) cfg.volume = 100;
  return 1;
}

int main(int argc, char **argv)
{
  int want_full = -1;
  const char *pref;
  char *base;
  if (!parse_args(argc, argv, 0, &want_full)) return 2;
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
  parse_args(argc, argv, 1, &want_full);
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
  audio_start(wav_path);

  rtl_init();
  if (!show_intro) {
    static const char *const sting[1] = {"STING"};
    rtl_set_args(1, sting);               /* the game's own switch: no title screens, no code wheel question (it
                                             also arms the developers' keys: Ctrl-D debug mode, Ctrl-C quit, and
                                             the J cheat of the character menu) */
  }
  pool_init_units();
  pool_main();
  platform_quit(0);
  return 0;
}

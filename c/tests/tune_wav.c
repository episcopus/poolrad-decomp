/* tune_wav.c: plays every tune of the sound driver (c/driver/res03_driver.c) on the PC speaker and on the Tandy chip
 * and writes each one to a WAV file through the host's synthesiser (c/platform/psg.c), so the tunes can be heard
 * without the game.
 *
 *   tune_wav OUTDIR [MAXSECONDS]
 *
 * For each device (Tandy, then speaker) and each tune 1..20 it does what the game does with the driver running in
 * the background (SetSoundDriverIdle(0), PlaySound(1) to turn the output on, PlaySound(tune + 1)), fires the timer
 * interrupt at its rate (5041: 236.7 Hz) and renders the devices between ticks. A tune ends when both devices have
 * been silent for half a second, or after MAXSECONDS (default 20; a tune that loops plays until then). Writes
 * OUTDIR/tandy-NN.wav and OUTDIR/speaker-NN.wav (44.1 kHz, 16-bit mono) and prints each tune's length. The game
 * plays tunes 1 to 11 (PlaySound 2 to 12, the Sound* constants of DGROUP 2618h..262Ch); 12 to 20 are in the driver
 * but no routine plays them. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "game.h"
#include "platform.h"
#include "psg.h"

enum { Rate = 44100, Tunes = 20 };
#define TICK_HZ (1193182.0 / 5041.0)

static void (*timer_handler)(void);
static Psg psg;

u16 platform_key_peek(void) { return 0; }
u16 platform_key_wait(void) { return 0; }
void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund) { *hour = 0; *min = 0; *sec = 0; *hund = 0; }
void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow) { *year = 1991; *month = 1; *day = 1; *dow = 2; }
void platform_delay_ms(u16 ms) { (void)ms; }
u8 platform_pit_counter(void) { return 0; }
u8 platform_retrace_status(void) { return 0; }
void platform_timer_set(u16 divisor, void (*handler)(void)) { (void)divisor; timer_handler = handler; }
void platform_timer_reset(void) { timer_handler = NULL; }
void platform_speaker_set(u16 divisor, u8 port61_low2) { psg_speaker(&psg, divisor, port61_low2); }
void platform_speaker_off(void) { psg_speaker_off(&psg); }
void platform_tandy_write(u8 value) { psg_tandy(&psg, value); }
void platform_video_changed(void) {}
void platform_pump(void) {}
void platform_quit(int code) { exit(code); }
const char *platform_data_dir(void) { return "."; }
const char *platform_save_dir(void) { return "."; }

static int silent(void)
{
  return !psg.spk_on && psg.vol[0] == 15 && psg.vol[1] == 15 && psg.vol[2] == 15 && psg.vol[3] == 15;
}

static void put32(FILE *f, u32 v)
{
  fputc((int)(v & 255), f);
  fputc((int)((v >> 8) & 255), f);
  fputc((int)((v >> 16) & 255), f);
  fputc((int)((v >> 24) & 255), f);
}

static void put16(FILE *f, u16 v)
{
  fputc(v & 255, f);
  fputc(v >> 8, f);
}

static int write_wav(const char *path, const s16 *pcm, u32 n)
{
  FILE *f = fopen(path, "wb");
  u32 i;
  if (!f) return 0;
  fwrite("RIFF", 1, 4, f);
  put32(f, 36 + n * 2);
  fwrite("WAVEfmt ", 1, 8, f);
  put32(f, 16);
  put16(f, 1);
  put16(f, 1);
  put32(f, Rate);
  put32(f, Rate * 2);
  put16(f, 2);
  put16(f, 16);
  fwrite("data", 1, 4, f);
  put32(f, n * 2);
  for (i = 0; i < n; i++) put16(f, (u16)pcm[i]);
  fclose(f);
  return 1;
}

/* Play one tune; returns the number of samples written to pcm. */
static u32 play(int device, unsigned tune, s16 *pcm, u32 cap, unsigned *ticks)
{
  u32 n = 0, quiet = 0, last_sound = 0;
  double carry = 0;
  unsigned t = 0;
  psg_reset(&psg);
  SoundMode = (u8)device;
  SetSoundDriverIdle(0);
  PlaySound(1);
  PlaySound((u16)(tune + 1));
  while (n < cap) {
    int k, count;
    if (timer_handler) timer_handler();
    t++;
    carry += Rate / TICK_HZ;
    count = (int)carry;
    carry -= count;
    for (k = 0; k < count && n < cap; k++) {
      float v = psg_sample(&psg, Rate) * 0.6f * 32767.0f;
      pcm[n++] = (s16)(v > 32767.0f ? 32767.0f : (v < -32768.0f ? -32768.0f : v));
    }
    if (silent()) {
      quiet += (u32)count;
      if (quiet >= Rate / 2) break;
    } else {
      quiet = 0;
      last_sound = n;
      *ticks = t;
    }
  }
  PlaySound(0xFF);
  SetSoundDriverIdle(100);
  return last_sound + Rate / 10 < n ? last_sound + Rate / 10 : n;   /* keep a tenth of a second of the tail */
}

int main(int argc, char **argv)
{
  static const char *const names[2] = {"tandy", "speaker"};
  static const int devices[2] = {SoundTandy, SoundSpeaker};
  const char *dir;
  double maxs = 20;
  u32 cap;
  s16 *pcm;
  int d;
  unsigned tune;
  if (argc < 2) {
    fprintf(stderr, "usage: tune_wav OUTDIR [MAXSECONDS]\n");
    return 2;
  }
  dir = argv[1];
  if (argc > 2) maxs = atof(argv[2]);
  cap = (u32)(maxs * Rate);
  pcm = (s16 *)malloc(cap * sizeof *pcm);
  if (!pcm) return 1;
  SoundMode = SoundSpeaker;
  SilenceSound();
  SetSoundDriverIdle(100);
  for (d = 0; d < 2; d++) {
    for (tune = 1; tune <= Tunes; tune++) {
      char path[1024];
      unsigned ticks = 0;
      u32 n = play(devices[d], tune, pcm, cap, &ticks);
      snprintf(path, sizeof path, "%s/%s-%02u.wav", dir, names[d], tune);
      if (!write_wav(path, pcm, n)) {
        fprintf(stderr, "tune_wav: cannot write %s\n", path);
        return 1;
      }
      printf("%s tune %2u: %4u ticks, %.2f s%s%s\n", names[d], tune, ticks, ticks / TICK_HZ,
             ticks / TICK_HZ >= maxs - 0.6 ? " (still playing at the limit: it loops)" : "", tune > 11 ? " [not played by the game]" : "");
    }
  }
  free(pcm);
  return 0;
}

/* psg.c: the speaker and the Tandy chip as a synthesiser (psg.h). */
#include <math.h>

#include "psg.h"

void psg_reset(Psg *p)
{
  int i;
  p->spk_on = 0;
  p->spk_div = 0;
  p->tandy_latch = 0;
  for (i = 0; i < 3; i++) {
    p->tone[i] = 0;
    p->tone_phase[i] = 0;
  }
  for (i = 0; i < 4; i++) p->vol[i] = 15;
  p->noise = 0;
  p->spk_phase = 0;
  p->lfsr = 0x4000;
  p->noise_phase = 0;
  p->lp = 0;
}

void psg_speaker(Psg *p, u16 divisor, u8 port61_low2)
{
  p->spk_div = divisor;
  p->spk_on = (port61_low2 & 3) == 3;
}

void psg_speaker_off(Psg *p)
{
  p->spk_on = 0;
}

/* A latch byte 1cctdddd (cc channel, t 1 attenuation / 0 tone or noise control, dddd the low bits) or a data byte
   00dddddd with the high six bits of the latched tone. */
void psg_tandy(Psg *p, u8 v)
{
  int reg;
  if (v & 0x80) {
    reg = (v >> 5) & 3;
    p->tandy_latch = (u8)(v & 0x7F);
    if (v & 0x10) {
      p->vol[reg] = v & 15;
    } else if (reg == 3) {
      p->noise = v & 7;
      p->lfsr = 0x4000;
    } else {
      p->tone[reg] = (u16)((p->tone[reg] & 0x3F0) | (v & 15));
    }
  } else {
    reg = (p->tandy_latch >> 5) & 3;
    if (!(p->tandy_latch & 0x10) && reg < 3) {
      p->tone[reg] = (u16)((p->tone[reg] & 15) | ((v & 0x3F) << 4));
    }
  }
}

static float tandy_amp(int att)
{
  return att >= 15 ? 0.0f : (float)pow(10.0, -0.1 * att);       /* 2 dB per step */
}

static double tone_hz(u16 period)
{
  return 3579545.0 / (32.0 * (period ? period : 1024));
}

float psg_sample(Psg *p, int rate)
{
  int ch;
  float mix = 0;
  double spk_hz = p->spk_div ? 1193181.0 / p->spk_div : 0;
  if (p->spk_on && spk_hz > 0 && spk_hz < rate / 2) {
    p->spk_phase += spk_hz / rate;
    if (p->spk_phase >= 1.0) p->spk_phase -= 1.0;
    mix += p->spk_phase < 0.5 ? 0.5f : -0.5f;
  }
  for (ch = 0; ch < 3; ch++) {
    float a = tandy_amp(p->vol[ch]);
    double hz = tone_hz(p->tone[ch]);
    if (a > 0 && hz < rate / 2) {
      p->tone_phase[ch] += hz / rate;
      if (p->tone_phase[ch] >= 1.0) p->tone_phase[ch] -= 1.0;
      mix += (p->tone_phase[ch] < 0.5 ? 0.3f : -0.3f) * a;
    }
  }
  {
    float a = tandy_amp(p->vol[3]);
    if (a > 0) {
      static const int rates[3] = {512, 1024, 2048};
      int sel = p->noise & 3;
      double hz = sel < 3 ? 3579545.0 / rates[sel] : tone_hz(p->tone[2]);
      p->noise_phase += hz / rate;
      while (p->noise_phase >= 1.0) {
        int fb = (p->noise & 4) ? ((p->lfsr ^ (p->lfsr >> 1)) & 1) : (p->lfsr & 1);
        p->lfsr = (u16)((p->lfsr >> 1) | (fb << 14));
        p->noise_phase -= 1.0;
      }
      mix += ((p->lfsr & 1) ? 0.3f : -0.3f) * a;
    }
  }
  p->lp += (mix - p->lp) * 0.45f;                               /* a little smoothing against harsh aliasing */
  return p->lp;
}

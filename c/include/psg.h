/* psg.h: the two sound devices the driver writes, as a synthesiser: the PC speaker (PIT channel 2 behind the port 61h
 * gate bits) and the Tandy SN76496 (three square-wave tones and a noise channel, 2 dB attenuation steps). Shared by
 * the SDL host (c/platform/sdl_host.c) and the tune renderer (c/tests/tune_wav.c). */
#ifndef POOLRAD_PSG_H
#define POOLRAD_PSG_H

#include "pool.h"

typedef struct Psg {
  int spk_on;              /* speaker gate and data bits both set */
  u16 spk_div;             /* PIT channel 2 reload; it persists across a gate change */
  u8 tandy_latch;          /* last latched register */
  u16 tone[3];             /* tone periods (10 bits; 0 counts as 1024) */
  u8 vol[4];               /* attenuation 0 (loud) .. 15 (off) */
  u8 noise;                /* noise control */
  double spk_phase;
  double tone_phase[3];
  u16 lfsr;
  double noise_phase;
  float lp;
} Psg;

void psg_reset(Psg *p);
void psg_speaker(Psg *p, u16 divisor, u8 port61_low2);
void psg_speaker_off(Psg *p);
void psg_tandy(Psg *p, u8 v);
float psg_sample(Psg *p, int rate);   /* the next sample, about -1 .. 1 */

#endif

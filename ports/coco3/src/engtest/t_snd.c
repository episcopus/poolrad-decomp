/* t_snd.c: step 8.8. The sound driver on the CoCo: the GIME timer on its fast clock, the interrupt in the constant page, the pump, the
 * generated driver (src/snd/snd_driver.c) and the backend (src/snd/snd_core.c) in this program (one unit, the state block static).
 *
 * Checks (results 0 to 10 are 1 when the check passed), measures in results 8, 9 and 10 to 17 (the ticks with the tone held at divisor 100, 65535, 3000):
 *   r10  interrupts counted in 60 frames of silence (the rest clock, 4097 units): 875 expected, within 2 %
 *   r11  the same with the 1,193 Hz tone (divisor 1000: 2 * 1193 interrupts a second, k = 1, ISR_A): 2389
 *   r12  with the 298 Hz tone (divisor 4000, k = 2: ISR_B): 1192
 *   r14  the DAC register when the wave is high and when it is low (read back from the PIA): $C040 expected
 *   r15  driver ticks the pump ran in 120 frames of silence (the rest clock alone): 236.7 Hz, 474 expected, within 1 %
 *   r13  the same while tune 8 played
 *   r16  frames counted at the end (the 60 Hz interrupt ran through all of it)
 *   then every tune of the game, one second each (tunes 1 to 20, the host's sound_probe schedule), for the ear: with MB_DAC set the Lua
 *   script writes every DAC write to <out>.dac and tools/dac2wav.py makes the WAV.
 * The checkpoints (mb_hold-free: counted, MAME's .cp file has their emulated time) are 60 frames apart where a measure starts and ends. */
#include "eng.h"
#include "mailbox.h"

#define SND_STATIC 1
#include "../snd/snd.h"

#include "snd_expect.h"

static u16 ticks_run;
static u16 chk;                                         /* the checksum of the calls the driver makes to the speaker (probes/snd_ref.c digests) */
static u8 hooking;                                      /* check_driver: the calls go to the checksum, not to the hardware */
void test_set(u16 d, u8 g)
{
    if (hooking)
        chk = (u16)(chk * 33u + d * 7u + (((g & 3) == 3) ? 3u : 0u) + 1u);
    else
        snd_want_tone(d, g);
}
void test_off(void)
{
    if (hooking)
        chk = (u16)(chk * 33u + 6u + 1u);
    else
        snd_want_off();
}
#define DriverTick DriverTickReal
#define snd_want_tone test_set
#define snd_want_off test_off
#include "../snd/snd_driver.c"
#undef snd_want_tone
#undef snd_want_off
#undef DriverTick
static u8 mark_ticks;                                   /* the diagnostic at the end: a mark in the DAC at every tick (0x10), the pump's calls (0x18 in, 0x1C out) */
static u8 tick_real = 1;                                /* 0: the pump's ticks are only counted (the clock measures with a tone held) */
void DriverTick(void)
{
    ticks_run++;
    if (mark_ticks)
        *(u8 *)0xFF20 = 0x10;
    if (tick_real)
        DriverTickReal();
}
#include "../snd/snd_core.c"

u16 frame_count(void);

/* the pump runs as the game's clock and keyboard polls would run it */
static void run_frames(u16 n)
{
    u16 target = (u16)(frame_count() + n);
    while ((s16)(frame_count() - target) < 0) {
        if (snd_thresh && snd_n >= snd_thresh) {
            if (mark_ticks)
                *(u8 *)0xFF20 = 0x18;
            snd_run();
            if (mark_ticks)
                *(u8 *)0xFF20 = 0x1C;
        }
    }
}

/* ... and without it: snd_n is then the count of interrupts */
static u16 count_interrupts(u16 frames)
{
    u16 target = (u16)(frame_count() + frames), n0 = snd_n;
    while ((s16)(frame_count() - target) < 0)
        ;
    return (u16)(snd_n - n0);
}

static u16 within(u16 v, u16 want, u16 percent)
{
    u16 slack = (u16)((u32)want * percent / 100);
    return v + slack >= want && v <= want + slack;
}

/* the driver alone (no hardware) for 237 ticks of each tune: the calls it makes to the speaker, as a checksum, against the host's (r17, r18: the
   bit mask of the tunes that differ) */
static void check_driver(void)
{
    u8 k, t;
    u16 lo_mask = 0, hi_mask = 0;
    extern u16 frame_count(void);

    hooking = 1;
    for (k = 1; k <= 20; k++) {
        chk = 0;
        SetSoundOutput(1);
        SetSpeakerTune(k);
        for (t = 0; t < 237; t++)
            DriverTickReal();
        if (chk != snd_expect[k - 1]) {
            if (k <= 16) lo_mask |= (u16)(1u << (k - 1));
            else hi_mask |= (u16)(1u << (k - 17));
        }
        SetSpeakerTune(0);
        DriverTickReal();
    }
    for (k = 1; k <= 20; k++) {                         /* what a tick of the driver costs: 237 ticks of tunes 1, 13, 18 back to back (r26: frames) */
        if (k == 1 || k == 13 || k == 18) {
            u16 f0 = frame_count();
            SetSpeakerTune(k);
            for (t = 0; t < 237; t++)
                DriverTickReal();
            MB_RESULT(k == 1 ? 26 : k == 13 ? 28 : 29) = (u16)(frame_count() - f0);
            SetSpeakerTune(0);
            DriverTickReal();
        }
    }
    hooking = 0;
    MB_RESULT(31) = lo_mask;
    MB_RESULT(18) = hi_mask;
    mb_check(6, lo_mask == 0 && hi_mask == 0, 1);
}

/* the backend's arithmetic on the 6809: k and the length of an interrupt for the divisors at the edges of its cases, against the host's (r30: the first
   divisor that differs, r31: what the 6809 made of it, k * 4096 + step) */
static void check_backend(void)
{
    u8 i, bad = 0;

    snd_begin();
    for (i = 0; i < SND_NBACKEND; i++) {
        snd_speaker_set(snd_backend[i][0], 3);
        if (snd_state->cur_k != snd_backend[i][1] || snd_state->cur_step != snd_backend[i][2]) {
            if (!bad) {
                MB_RESULT(30) = snd_backend[i][0];
                MB_RESULT(29) = (u16)(snd_state->cur_k * 4096u + snd_state->cur_step);
                MB_RESULT(28) = (u16)(snd_backend[i][1] * 4096u + snd_backend[i][2]);
            }
            bad++;
        }
        snd_speaker_off();
    }
    snd_end();
    MB_RESULT(27) = bad;
    mb_check(7, bad == 0, 1);
}

int main(void)
{
    u16 k;
    u8 hi = 0, lo = 0, i;

    irq_start();
    snd_install();
    snd_init();
    check_driver();
    check_backend();
    snd_init();
    snd_begin();
    snd_thresh = 0;                                     /* (the pump stays out of the first three measures) */
    MB_CHECKPOINT = 1;
    MB_RESULT(10) = count_interrupts(60);               /* the rest clock */
    mb_check(0, within(MB_RESULT(10), 875, 2), 1);

    snd_speaker_set(1000, 3);
    snd_thresh = 0;
    MB_CHECKPOINT = 2;
    MB_RESULT(11) = count_interrupts(60);
    mb_check(1, within(MB_RESULT(11), 2389, 2), 1);
    for (i = 0; i < 200; i++) {                         /* the wave's two levels, as the PIA's output register shows them */
        u8 v = *(u8 *)0xFF20 & 0xFC;
        if (v > hi) hi = v;
        if (!lo || v < lo) lo = v;
    }
    MB_RESULT(14) = (u16)(((u16)hi << 8) | lo);
    mb_check(2, hi == 0xC0 && lo == 0x40, 1);

    snd_speaker_set(4000, 3);
    snd_thresh = 0;
    MB_CHECKPOINT = 3;
    MB_RESULT(12) = count_interrupts(60);
    mb_check(3, within(MB_RESULT(12), 1192, 2), 1);
    snd_speaker_off();
    snd_run();                                          /* (the threshold is the pump's again) */

    tick_real = 0;                                      /* the clock with a tone held: the interrupt at its fastest (the clamp, 300 units) and at its slowest */
    snd_speaker_set(100, 3);
    ticks_run = 0;
    MB_CHECKPOINT = 8;
    run_frames(120);
    MB_RESULT(8) = ticks_run;                           /* 474 expected; fewer: the main line is starved */
    mb_check(20, within(MB_RESULT(8), 474, 2), 1);
    snd_speaker_set(65535, 3);
    ticks_run = 0;
    run_frames(120);
    MB_RESULT(9) = ticks_run;
    mb_check(21, within(MB_RESULT(9), 474, 2), 1);
    snd_speaker_set(3000, 3);
    ticks_run = 0;
    run_frames(120);
    MB_RESULT(17) = ticks_run;
    mb_check(25, within(MB_RESULT(17), 474, 2), 1);
    snd_speaker_off();
    snd_run();
    tick_real = 1;

    ticks_run = 0;
    SetSoundOutput(1);
    MB_CHECKPOINT = 4;
    run_frames(120);
    MB_RESULT(15) = ticks_run;
    mb_check(4, within(MB_RESULT(15), 474, 1), 1);

    ticks_run = 0;
    SetSpeakerTune(8);
    MB_CHECKPOINT = 5;
    run_frames(120);
    MB_RESULT(13) = ticks_run;
    mb_check(5, within(MB_RESULT(13), 474, 1), 1);
    SetSpeakerTune(0);
    snd_end();

    snd_begin();
    SetSoundOutput(1);
    MB_CHECKPOINT = 6;
    for (i = 1; i <= 20; i++) {
        ticks_run = 0;
        MB_CHECKPOINT = (u8)(10 + i);                    /* (the harness stamps each one: tools/snd_compare.py finds the tunes' windows with them) */
        SetSpeakerTune(i);
        run_frames(60);
        if (i == 13 || i == 16 || i == 17 || i == 18)
            MB_RESULT(i + 6) = ticks_run;                /* (r19, r22, r23, r24: ticks run in the 60 frames: 237 when the pump keeps up) */
        SetSpeakerTune(0);
        run_frames(6);
    }
    snd_end();

    snd_begin();                                        /* the diagnostic: tune 18 again, with marks (tools/snd_compare.py --marks) */
    SetSoundOutput(1);
    mark_ticks = 1;
    MB_CHECKPOINT = 40;
    SetSpeakerTune(18);
    run_frames(30);
    SetSpeakerTune(0);
    mark_ticks = 0;
    snd_end();
    MB_CHECKPOINT = 31;
    k = frame_count();
    MB_RESULT(16) = k;
    mb_finish();
    return 0;
}

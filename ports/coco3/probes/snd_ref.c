/* snd_ref.c: the CoCo sound driver (src/snd/snd_driver.c, snd_core.c) on the host, the GIME timer and the interrupt replaced by a model
 * (step 8.8). It plays the PC speaker half of tests/sessions/golden/sound-driver's schedule (c/tests/sound_probe.c: every tune of the
 * game, a second each) and prints
 *
 *   S divisor on     the speaker events the way the oracle logs them (c/platform/null.c: a write of the divisor, a write of port 61h),
 *                    which tools/snd_check.py compares with the golden's speaker events of the same half;
 *   the DAC          with --dac FILE: every write of the DAC register, as `units value`, one line each (tools/dac2wav.py makes a WAV).
 *
 * The model: virtual time in GIME fast clock units (279.365 ns). The timer counts reload + 2 units from the write of the low byte; at each
 * expiry the interrupt of the vector the driver set ($FFF6: ISR_A toggles at every interrupt, ISR_B every snd_k-th) runs exactly as
 * src/engine/snd.asm does. The driver is clocked in one of two ways:
 *
 *   ideal    DriverTick is called 237 times per second of driver time, as the oracle's probe fires the handler (the backend's tone
 *            arithmetic is still the one under test: every divisor the driver sets goes through snd_speaker_set into the model's registers);
 *   pump     the real clock: the model's interrupts are counted and snd_run turns them into ticks, polled every --poll units.
 *
 *   snd_ref ideal|pump [--poll UNITS] [--dac FILE] [--events FILE] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SND_HOST 1
#include "../src/snd/snd.h"

/* ---- the model of the hardware ---- */
u8 *hw_mem;
u8 eng_init0;
#define ENGINE_VEC ((u16)(unsigned long)&firq_isr)
void firq_isr(void) {}                                  /* the engine's handler: only its address matters (snd_end puts it back) */
SndState *snd_state;
u16 snd_n, snd_thresh, snd_cn, snd_tn, snd_tc;
u8 snd_k, snd_kcnt, snd_dac, snd_flip, tins, snd_new_hi, snd_new_lo;

static unsigned long long now_u, next_irq;
static u16 last_reload;
static int timer_on;
static u8 last_out = 0x80;
static FILE *dacf, *tickf;
static unsigned long long interrupts, toggles;

static void dac_log(void)
{
    if (hw_mem[0xFF20] != last_out) {
        last_out = hw_mem[0xFF20];
        if (dacf)
            fprintf(dacf, "%llu %u\n", now_u, last_out);
    }
}

static void hw_sync(void)
{
    u16 reload = (u16)(((hw_mem[0xFF94] & 0xF) << 8) | hw_mem[0xFF95]);
    int on = (hw_mem[0xFF93] & 0x20) != 0;
    if (!on) {
        timer_on = 0;
    } else if (!timer_on || reload != last_reload) {
        timer_on = 1;
        last_reload = reload;
        next_irq = now_u + reload + 2;
    }
    dac_log();
}

static void fire(void)
{
    u16 vec = (u16)((hw_mem[0xFFF6] << 8) | hw_mem[0xFFF7]);
    interrupts++;
    snd_n++;
    if (vec == 0xFE00 || (vec == 0xFE3B && --snd_kcnt == 0)) {
        if (vec == 0xFE3B)
            snd_kcnt = snd_k;
        snd_dac ^= snd_flip;
        hw_mem[0xFF20] = snd_dac;
        if (snd_flip)
            toggles++;
        dac_log();
    }
    if (snd_new_hi) {                                   /* the commit: the interrupt loads the reload, the timer restarts from here */
        hw_mem[0xFF94] = snd_new_hi & 0x0F;
        hw_mem[0xFF95] = snd_new_lo;
        snd_new_hi = 0;
        snd_cn = snd_n;
        last_reload = (u16)(((hw_mem[0xFF94] & 0xF) << 8) | hw_mem[0xFF95]);
        next_irq = now_u + last_reload + 2;
    }
}

static void hw_advance(unsigned long long dt)
{
    unsigned long long target = now_u + dt;
    hw_sync();
    while (timer_on && next_irq <= target) {
        now_u = next_irq;
        next_irq += last_reload + 2;
        fire();                                          /* (a commit moves next_irq) */
        hw_sync();
    }
    now_u = target;
}

void snd_take_hw(void)
{
    snd_tn = snd_n;
    snd_tc = snd_cn;
    snd_n = 0;
    snd_cn = 0;
}

/* the model keeps the registers as the CPU wrote them: the driver writes 16 bit values big-endian (the 6809's order), so the model's
   memory is big-endian too, and HW16 in snd_core.c is told so here */

/* ---- the speaker events, as the oracle logs them ---- */
static FILE *evf;
static u16 spk_divisor;
static u8 spk_bits;
static unsigned long long nevents;

static void trace(u16 d, u8 on)
{
    nevents++;
    if (evf)
        fprintf(evf, "S %u %u\n", d, on);
}

static u16 tone_div;                                   /* the divisor of the tone the driver last set; 0 = silence */

void drv_want_tone(u16 divisor, u8 gate)
{
    extern void snd_want_tone(u16, u8);
    extern void chk_hook(u16, u8);
    chk_hook(divisor, (gate & 3) == 3);
    tone_div = (gate & 3) == 3 ? (divisor ? divisor : 0xFFFF) : 0;
    spk_divisor = divisor;
    trace(spk_divisor, spk_bits == 3);
    spk_bits = gate & 3;
    trace(spk_divisor, spk_bits == 3);
    snd_want_tone(divisor, gate);
}

void drv_want_off(void)
{
    extern void snd_want_off(void);
    extern void chk_hook(u16, u8);
    chk_hook(0, 2);
    spk_bits = 0;
    tone_div = 0;
    trace(spk_divisor, 0);
    snd_want_off();
}

void drv_end(void)
{
    extern void snd_end(void);
    tone_div = 0;
    spk_bits = 0;                                    /* StopSoundTimer: the host driver closes the speaker gate (platform_speaker_off) */
    trace(spk_divisor, 0);
    snd_end();
}

/* ---- the front end (c/game/res03.c: PlaySound, SilenceSound, SetSoundDriverIdle with SoundMode = SoundSpeaker) ---- */
static u16 SoundDriverIdle;

static void SilenceSound(void)
{
    StartSoundTimer();
    SetSpeakerTune(0);
    SetTandyTune(0);
    StopSoundTimer();
}

static void SetSoundDriverIdle(u16 idle)
{
    if (idle > 0) {
        if (SoundDriverIdle == 0)
            StopSoundTimer();
    } else {
        StartSoundTimer();
    }
    SoundDriverIdle = idle;
}

static void PlaySound(u16 s)
{
    if (SoundDriverIdle > 0)
        StartSoundTimer();
    switch (s) {
    case 0: SetTandyTune(0); SetSpeakerTune(0); SetSoundOutput(0); break;
    case 1: SetSoundOutput(1); break;
    case 0xFF: SetTandyTune(0); SetSpeakerTune(0); break;
    default: SetSpeakerTune((u16)(s - 1)); break;
    }
}

/* ---- the clock ---- */
static unsigned long poll_units = SND_TICK_UNITS;
static unsigned long long driver_ticks, pump_calls;
static int pump_mode;
static unsigned long busy_units;                       /* --busy: the CPU time one DriverTick takes, in GIME units */
void ref_tick(void)                                    /* the pump's call of DriverTick (snd_core.c is built with DriverTick = ref_tick) */
{
    extern void DriverTick(void);
    driver_ticks++;
    DriverTick();
    if (busy_units && pump_mode)
        hw_advance(busy_units);                        /* the driver takes time: interrupts arrive while it runs, and the tone it asked for is not set yet */
    if (!pump_mode)
        snd_apply();                                   /* (the pump applies, once for all the ticks it ran) */
}

static void wait_ticks(unsigned ticks)
{
    unsigned i;
    if (!snd_state->started) {                     /* the timer is stopped: time passes, nothing runs */
        hw_advance((unsigned long long)ticks * SND_TICK_UNITS);
        return;
    }
    if (!pump_mode) {
        for (i = 0; i < ticks; i++) {
            unsigned long long t0 = toggles;
            u16 d = tone_div;
            hw_advance(SND_TICK_UNITS);
            if (tickf)
                fprintf(tickf, "%u %llu\n", d, toggles - t0);   /* the tone that played through this tick, the toggles it made */
            ref_tick();
        }
        return;
    }
    {
        unsigned long long end = now_u + (unsigned long long)ticks * SND_TICK_UNITS;
        while (now_u < end) {
            unsigned long long dt = end - now_u < poll_units ? end - now_u : poll_units;
            hw_advance(dt);
            if (snd_thresh && snd_n >= snd_thresh) {
                pump_calls++;
                snd_run();                           /* (the driver's own time, --busy, moves now_u on) */
            }
        }
    }
}

/* "digests": for every tune, the driver alone (no hardware) for 237 ticks; a checksum of the calls it makes to the speaker. The CoCo's
   engine test t_snd does the same on the 6809 and compares (build/eng/snd_expect.h is this output). */
static u16 chk;
void chk_hook(u16 d, u8 on) { chk = (u16)(chk * 33u + d * 7u + on * 3u + 1u); }

/* the divisors the backend's arithmetic is checked on (the edges of its cases), and what it makes of them */
static const u16 probe_div[] = {0, 1, 39, 70, 133, 134, 163, 989, 1000, 2730, 2731, 4000, 5461, 8150, 8191, 8192, 43690, 43691, 65236, 65535};

static int digests(void)
{
    int k, t;
    unsigned i;
    snd_state = calloc(1, sizeof(SndState));
    snd_init();
    snd_begin();
    for (i = 0; i < sizeof probe_div / sizeof *probe_div; i++) {
        extern void snd_speaker_set(u16, u8);
        snd_speaker_set(probe_div[i], 3);
        printf("B %u %u %u\n", probe_div[i], snd_state->cur_k, snd_state->cur_step);
        snd_speaker_off();
    }
    snd_end();
    free(snd_state);
    snd_state = calloc(1, sizeof(SndState));
    snd_init();
    snd_state->started = 1;                             /* (the backend is not under test here: the calls to it are the checksum) */
    for (k = 1; k <= 20; k++) {
        chk = 0;
        SetSoundOutput(1);
        SetSpeakerTune((u16)k);
        for (t = 0; t < 237; t++) {
            DriverTick();
        }
        printf("%d %u\n", k, chk);
        SetSpeakerTune(0);
        DriverTick();
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "digests")) {
        hw_mem = calloc(65536, 1);
        return digests();
    }
    int i, k;
    const char *dacn = NULL, *evn = NULL;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "pump")) pump_mode = 1;
        else if (!strcmp(argv[i], "ideal")) pump_mode = 0;
        else if (!strcmp(argv[i], "--poll") && i + 1 < argc) poll_units = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--dac") && i + 1 < argc) dacn = argv[++i];
        else if (!strcmp(argv[i], "--busy") && i + 1 < argc) busy_units = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--events") && i + 1 < argc) evn = argv[++i];
        else if (!strcmp(argv[i], "--ticks") && i + 1 < argc) tickf = fopen(argv[++i], "w");
    }
    hw_mem = calloc(65536, 1);
    hw_mem[0xFFF6] = ENGINE_VEC >> 8; hw_mem[0xFFF7] = ENGINE_VEC & 255;      /* the engine's vector, put back by snd_end */
    hw_mem[0x0909] = 0;                                  /* FC_TASK */
    snd_state = calloc(1, sizeof(SndState));
    snd_init();
    if (dacn) dacf = fopen(dacn, "w");
    if (evn) evf = fopen(evn, "w");

    SilenceSound();
    SetSoundDriverIdle(100);
    SetSoundDriverIdle(0);
    PlaySound(1);
    for (k = 1; k <= 20; k++) {
        PlaySound((u16)(k + 1));
        wait_ticks(237);
        PlaySound(0xFF);
        wait_ticks(24);
    }
    PlaySound(0);
    SetSoundDriverIdle(100);
    wait_ticks(24);
    if (hw_mem[0xFFF6] != (ENGINE_VEC >> 8) || hw_mem[0xFFF7] != (ENGINE_VEC & 255)) { fprintf(stderr, "the FIRQ vector was not put back\n"); return 1; }
    fprintf(stderr, "%s: %llu speaker events, %llu interrupts, %llu toggles, %llu ticks (driver) %llu pump calls, %llu units of virtual time\n",
            pump_mode ? "pump" : "ideal", nevents, interrupts, toggles, driver_ticks, pump_calls, now_u);
    if (dacf) fclose(dacf);
    if (evf) fclose(evf);
    if (tickf) fclose(tickf);
    return 0;
}

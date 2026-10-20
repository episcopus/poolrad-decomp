/* snd_core.c: the backend of the CoCo 3 sound driver (step 8.8): the PC speaker's square wave on the 6 bit DAC, and the driver's clock.
 *
 * THE HARDWARE. One GIME timer (the FIRQ) does both jobs. The tone: the PIT channel 2 of the PC, divisor D, is a square wave of period
 * D / 1,193,182 s; the DAC toggles every half period. A half period is D / 2,386,364 s = 1.5 D units of the GIME's fast clock (279.365 ns,
 * TINS in $FF91), and the timer counts reload + 2 units, 12 bits: up to 4097 units (1.14 ms), so a half period that is longer (D above
 * 2731, below 437 Hz) takes k interrupts, the reload being the half period divided by k, and the interrupt toggles every k-th. The clock:
 * the interrupts are counted (snd_n) and the pump multiplies the count by the length of one: 15123 units (3 * 5041) are one tick of the
 * driver, the original's 236.7 Hz. A rest is the same timer without the toggle, at the longest interval.
 * The interrupt itself is in src/engine/snd.asm (~70 cycles); everything here runs in the main line. See docs/PHASE-8.8.md.
 *
 * Compiled by CMOC into the sound bank and the engine test t_snd, and by clang (SND_HOST) for probes/snd_ref.c, which replaces the
 * registers and the interrupt by a model. */
#include "snd.h"

#ifdef SND_HOST
extern u8 *hw_mem;                       /* the model of the 64 KB map */
extern void snd_take_hw(void);
#define HW8(a) (hw_mem[(u16)(a)])
#define GET16(a) ((u16)((hw_mem[(u16)(a)] << 8) | hw_mem[(u16)(a) + 1]))      /* the 6809's order */
#define PUT16(a, v) (hw_mem[(u16)(a)] = (u8)((v) >> 8), hw_mem[(u16)(a) + 1] = (u8)(v))
#define TAKE() snd_take_hw()
#define ENGINE_VEC ((u16)(unsigned long)&firq_isr)
#define SETVEC(v) (PUT16(VEC_FIRQ, v), PUT16(VEC_STUB, v))
#else
#ifndef SND_STATIC
u32 rtl_getmem_m(u16 size);
#endif
#define HW8(a) (*(u8 *)(a))
#define GET16(a) (*(u16 *)(a))
#define PUT16(a, v) (*(u16 *)(a) = (v))
#define TAKE() (((void (*)(void))SND_TAKE)())
#define ENGINE_VEC ((u16)&firq_isr)
#define SETVEC(v) (((void (*)(u16))SND_SETVEC)(v))
#endif

extern u8 eng_init0;                     /* boot.asm: the value last written to $FF90, a register that cannot be read */
void firq_isr(void);                     /* irq.asm: the engine's FIRQ handler (counts ticks) */

#define SND_ISR_A 0xFE00u /* the interrupt for k = 1, in the constant page (snd.asm copies it there at boot) */
#define SND_ISR_B 0xFE3Bu /* k > 1: counts down snd_kcnt */
#define SND_TAKE 0xFE81u /* void take(void): snd_n and snd_cn to snd_tn and snd_tc, cleared, with the FIRQ masked */
#define SND_SETVEC 0xFE9Fu /* void setvec(u16): the FIRQ vector, with the FIRQ masked */
#define VEC_FIRQ 0xFFF6u /* the FIRQ vector, and the operand of the JMP stub the constant page holds ($FEF4) */
#define VEC_STUB 0xFEF5u 
#define FC_TASK 0x0909 /* mailbox.inc: the MMU task the CPU is in; $FF91 cannot be read back */
#define GIME_INIT0 0xFF90u /* bit 4: the GIME's FIRQ sources (the timer) reach the CPU */
#define GIME_TASK 0xFF91u /* bit 0 the task, bit 5 TINS: the timer's clock (1 = 279 ns, 0 = 63.7 us) */
#define GIME_FIRQ 0xFF93u /* bit 5: the timer */
#define GIME_TIMER_HI 0xFF94u /* the reload's high nibble; the low byte ($FF95) starts the timer */
#define GIME_TIMER_LO 0xFF95u 
#define PIA0_CRA 0xFF01u /* bit 3: the sound multiplexer's select A (0 with select B: the DAC) */
#define PIA0_CRB 0xFF03u 
#define PIA1_DAC 0xFF20u /* bits 7 to 2: the 6 bit DAC */
#define PIA1_CRB 0xFF23u /* bit 3: sound enable */
#define DAC_REST 0x80 /* the DAC's middle: silence */
#define DAC_LO 0x40 /* the two levels of the tone: the middle plus and minus 16 of 64 steps */
#define DAC_FLIP 0x80 /* LO xor HI ($C0) */
#define MIN_UNITS 500 /* the shortest half period (3.6 kHz): the interrupt (~70 cycles) must leave the main line most of the CPU, the driver ticks run there; 9 of the 1822 tone ticks of the game's 20 tunes are higher and are clamped */

/* $FF91 with the task the CPU is in and the timer's clock */
static void write_task(void)
{
    HW8(GIME_TASK) = (u8)(HW8(FC_TASK) | tins);
}

/* The timer, restarted now: reload (12 bits), the low byte starts the count. The interval that was running is cut short. */
static void timer_write(u16 reload)
{
    HW8(GIME_FIRQ) = 0;
    snd_new_hi = 0;
    HW8(GIME_TIMER_HI) = (u8)(reload >> 8);
    HW8(GIME_TIMER_LO) = (u8)reload;
    HW8(GIME_FIRQ) = 0x20;
}

/* A new reload for the interrupt to load when the running interval ends: the tone changes without losing the time the interval had run (the
 * timer cannot be read, so a restart in the middle of an interval loses an unknown part of it). The pump has to know which of the interrupts it
 * counts ended intervals of the old length: the one that loaded the new reload (snd_cn says how many there had been by then) and those before. */
static void timer_next(SndState *s, u16 reload)
{
    if (!s->chg) {
        s->old_step = s->cur_step;
        s->chg = 1;
    }
    snd_new_lo = (u8)reload;
    snd_new_hi = (u8)(0x80 | (reload >> 8));          /* last: the commit */
}

void snd_init(void)
{
    SndState *s;
#if defined(SND_HOST)
    s = snd_state;
#elif defined(SND_STATIC)
    static SndState block;               /* the engine test: no heap */
    s = &block;
    snd_state = s;
#else
    s = (SndState *)(u16)rtl_getmem_m(sizeof(SndState));      /* the mapped heap, once, for the rest of the run */
    snd_state = s;
#endif
    memset(s, 0, sizeof(SndState));
    s->output_on = 1;                    /* the host driver's initial value */
}

/* StartSoundTimer: the multiplexer to the DAC, the timer on the fast clock at the longest interval (the clock for the rests), the FIRQ
 * on the counting interrupt. */
void snd_begin(void)
{
    SndState *s = snd_state;

    if (s->started) {
        return;
    }
    eng_init0 |= 0x10;                   /* the engine's graphics set the register again without it (gfx_init): the timer's FIRQ is asked for here */
    HW8(GIME_INIT0) = eng_init0;
    HW8(PIA0_CRA) = (u8)(HW8(PIA0_CRA) & 0xF7);
    HW8(PIA0_CRB) = (u8)(HW8(PIA0_CRB) & 0xF7);
    HW8(PIA1_CRB) = (u8)(HW8(PIA1_CRB) | 0x08);
    snd_flip = 0;
    snd_dac = DAC_REST;
    HW8(PIA1_DAC) = DAC_REST;
    tins = 0x20;
    write_task();
    snd_k = 1;
    snd_kcnt = 1;
    snd_n = 0;
    s->acc = 0;
    s->cur_k = 0;
    s->cur_step = SND_REST_UNITS;
    snd_thresh = 4;                      /* (15123 / 4097 = 3.7, the rest clock) */
    snd_new_hi = 0;
    snd_cn = 0;
    s->chg = 0;
    SETVEC(SND_ISR_A);
    timer_write(SND_REST_UNITS - 2);
    s->started = 1;
}

/* StopSoundTimer: the timer and the FIRQ off, the engine's vector back, the DAC at rest. */
void snd_end(void)
{
    SndState *s = snd_state;

    if (!s->started) {
        return;
    }
    HW8(GIME_FIRQ) = 0;
    snd_thresh = 0;
    SETVEC(ENGINE_VEC);                  /* the engine's own handler (irq.asm) */
    snd_flip = 0;
    snd_dac = DAC_REST;
    HW8(PIA1_DAC) = DAC_REST;
    HW8(PIA1_CRB) = (u8)(HW8(PIA1_CRB) & 0xF7);
    tins = 0;
    write_task();
    s->cur_k = 0;
    s->cur_step = 0;
    s->chg = 0;
    s->want = 0;
    s->started = 0;
}

/* The tone for PIT divisor D (D = 0 is 65536) if both gate bits are set, else silence. */
void snd_speaker_set(u16 divisor, u8 gate)
{
    SndState *s = snd_state;
    u16 q, u, reload;
    u8 k;

    if (!s->started) {
        return;
    }
    if ((gate & 3) != 3) {
        snd_speaker_off();
        return;
    }
    if (divisor == 0) {                  /* (the PIT counts 0 as 65536) */
        divisor = 65535;
    }
    /* The half period is 1.5 D GIME units; one interrupt is at most 4097 of them, so k interrupts make it, k a power of two (shifts: the 6809
     * takes 0.6 ms over a 16 bit division, and the pump does this every tick). An interrupt is then 2048 to 4096 units when k > 1. */
    if (divisor < 2732) {
        k = 1;
        q = divisor;
    } else if (divisor < 5464) {
        k = 2;
        q = divisor >> 1;
    } else if (divisor < 10928) {
        k = 4;
        q = divisor >> 2;
    } else if (divisor < 21856) {
        k = 8;
        q = divisor >> 3;
    } else if (divisor < 43712) {
        k = 16;
        q = divisor >> 4;
    } else {
        k = 32;
        q = divisor >> 5;
    }
    u = (u16)(q + (q >> 1));
    if (u < MIN_UNITS) {
        u = MIN_UNITS;
    }
    reload = (u16)(u - 2);
    if (s->cur_k == k && s->cur_step == (u16)(reload + 2)) {
        return;                          /* the same tone: the wave goes on */
    }
    if (s->cur_k == 0) {                 /* from silence: the wave starts at its low level */
        snd_dac = DAC_LO;
        HW8(PIA1_DAC) = DAC_LO;
        snd_flip = DAC_FLIP;
    }
    if (k > 1) {                         /* the interrupt that counts snd_k of them to a toggle */
        if (s->cur_k <= 1 || snd_kcnt > k) {
            snd_kcnt = k;
        }
        snd_k = k;
        if (s->cur_k <= 1) {
            SETVEC(SND_ISR_B);
        }
    } else if (s->cur_k > 1) {
        snd_k = 1;
        snd_kcnt = 1;
        SETVEC(SND_ISR_A);
    }
    timer_next(s, reload);
    s->cur_k = k;
    s->cur_step = (u16)(reload + 2);
}

void snd_speaker_off(void)
{
    SndState *s = snd_state;

    if (!s->started || s->cur_k == 0) {
        return;
    }
    snd_flip = 0;
    snd_dac = DAC_REST;
    HW8(PIA1_DAC) = DAC_REST;
    if (s->cur_k > 1) {
        snd_k = 1;
        snd_kcnt = 1;
        SETVEC(SND_ISR_A);
    }
    timer_next(s, SND_REST_UNITS - 2);
    s->cur_k = 0;
    s->cur_step = SND_REST_UNITS;
}

/* What the driver's tick asks of the speaker is kept; the pump sets it once, after all the ticks it ran: a tone changed twice between two looks at the
 * interrupt count could not be told apart in it. */
void snd_want_tone(u16 divisor, u8 gate)
{
    SndState *s = snd_state;

    s->want_div = divisor;
    s->want_gate = gate;
    s->want = 1;
}

void snd_want_off(void)
{
    snd_state->want = 2;
}

void snd_apply(void)
{
    SndState *s = snd_state;

    if (s->want == 1) {
        snd_speaker_set(s->want_div, s->want_gate);
    } else if (s->want == 2) {
        snd_speaker_off();
    }
    s->want = 0;
}

/* The interrupts counted since the last look are time. */
/* num / den (floored) for a quotient under 64: the 6809 takes 0.6 ms over the C division */
static u16 div_small(u16 num, u16 den)
{
    u16 q = 0, d;
    u8 b;

    if (den > 2047) {
        while (num >= den) {
            num -= den;
            q++;
        }
        return q;
    }
    d = (u16)(den << 5);
    for (b = 0; b < 6; b++) {
        q <<= 1;
        if (num >= d) {
            num -= d;
            q |= 1;
        }
        d >>= 1;
    }
    return q;
}

/* n * step in GIME units, without the 32 bit multiplication (600 cycles) when n is small, which it is */
static u32 units(u16 n, u16 step)
{
    if (n < 16) {
        return (u16)(n * step);
    }
    return (u32)n * step;
}

static void account(SndState *s)
{
    u16 n;

    TAKE();
    n = snd_tn;
    if (s->chg) {                        /* a new reload was left: the interrupts up to the one that loaded it ended intervals of the old length */
        if (snd_tc) {
            s->acc += units(snd_tc, s->old_step) + units((u16)(n - snd_tc), s->cur_step);
            s->chg = 0;
        } else {
            s->acc += units(n, s->old_step);
        }
    } else {
        s->acc += units(n, s->cur_step);
    }
}

/* The pump: every 15123 units are a tick of the driver. After a long computation (more than SND_MAX_CATCHUP ticks pending) the backlog is dropped, the
 * sound goes on from now. */
void snd_run(void)
{
    SndState *s = snd_state;
    u16 rem;
    u8 ticks = 0;

    if (!s->started) {
        return;
    }
    account(s);
    while (s->acc >= SND_TICK_UNITS) {
        s->acc -= SND_TICK_UNITS;
        if (++ticks > SND_MAX_CATCHUP) {
            s->acc = 0;
            break;
        }
        DriverTick();
    }
    if (s->want) {
        account(s);                      /* the interrupts that came while the driver ran: a commit that has happened is settled before the next request */
        snd_apply();
    }
    if (s->acc >= SND_TICK_UNITS) {      /* another tick is due already (the catch-up stopped, or the driver took long) */
        rem = 1;
    } else {
        rem = (u16)(SND_TICK_UNITS - s->acc);
    }
    snd_thresh = div_small((u16)(rem + s->cur_step - 1), s->cur_step);
}

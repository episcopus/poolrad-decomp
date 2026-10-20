/* snd.h: the CoCo 3 sound driver's interface (step 8.8): the state block, the hardware layer's variables and entries, the backend.
 *
 * The PC speaker's square wave is the CoCo's 6 bit DAC. One GIME timer interrupt (FIRQ) per half period of the tone toggles the DAC
 * (src/engine/snd.asm, the code at $FE00 in the constant page); the same interrupts are the clock of the driver: the pump counts the
 * interrupts since it last looked, multiplies by the length of one, and runs DriverTick once for every 236.7 Hz tick that has passed.
 * snd_driver.c (the tunes' interpreter, generated) and snd_core.c (the backend) are one bank in the game, and one program with the engine in
 * the test t_snd; probes/snd_ref.c builds them with clang, the interrupt replaced by a loop, and compares the sequence of tones with the
 * oracle's. */
#ifndef SND_H
#define SND_H

#if defined(_CMOC_VERSION_) && defined(ENG_H)
#include <cmoc.h>
typedef long s32;                        /* (eng.h has the others) */
#elif defined(_CMOC_VERSION_)
#include <cmoc.h>
typedef unsigned char u8;
typedef signed char s8;
typedef unsigned int u16;
typedef int s16;
typedef unsigned long u32;
typedef long s32;
#else
#include <stdint.h>
#include <stddef.h>
#include <string.h>
typedef uint8_t u8;
typedef int8_t s8;
typedef uint16_t u16;
typedef int16_t s16;
typedef uint32_t u32;
typedef int32_t s32;
#endif

typedef u16 Voice;                       /* a voice record: VoiceWords words */

enum {
    SND_VOICES = 8 * 24 + 128            /* 8 records of 24 words, and the slack a stray field offset of a stream reaches (the host's VoiceMem, one device) */
};

/* the driver's variables and the backend's, one block in the mapped heap (the bank has no variables) */
typedef struct SndState {
    Voice voices[SND_VOICES];            /* 640 bytes */
    u8 in_service;                       /* the host driver's variables (res03_driver.c) */
    u8 voices_left;
    u16 current_tune;
    Voice *current_voice;
    Voice *voice_base;
    const u16 *note_table;
    u16 return_ptr;
    u8 voice_tune[4];
    u8 output_on;
    Voice *loudest_voice;
    /* the backend */
    u32 acc;                             /* hardware units counted towards the next tick */
    u16 cur_step;                        /* reload + 2 of the tone playing, in GIME units; 0 = the timer is not running */
    u16 old_step;                        /* the interval the timer was running when a new reload was left for the interrupt (while chg) */
    u16 want_div;                        /* what the last tick of the driver asked for: want 1 = a tone of this divisor and gate bits, 2 = none, 0 = nothing yet */
    u8 want_gate;
    u8 want;
    u8 chg;                              /* a new reload has been left, and the pump has not yet seen the interrupt that loaded it */
    u8 cur_k;                            /* interrupts per toggle of the tone playing; 0 = silence */
    u8 started;                          /* between snd_begin and snd_end */
} SndState;

/* snd_state is the pointer to the block (asm: in the shared data, so that no bank holds it); the game sets it up with snd_init */
extern SndState *snd_state;

/* every entry of the driver allocates the block on its first call (the game; the tests set snd_state before) */
#define SND_ENSURE() do { if (snd_state == 0) snd_init(); } while (0)

/* The hardware layer (src/engine/snd.asm): the variables the interrupt reads and writes, in the shared data. */
extern u16 snd_n;                        /* interrupts counted since the pump last took them */
extern u16 snd_thresh;                   /* the pump runs when snd_n has reached this (0: the sound is off) */
extern u8 snd_k, snd_kcnt;               /* interrupts per toggle; the countdown */
extern u8 snd_dac, snd_flip;             /* the DAC's value now, and the xor that toggles it (0 = silence) */
extern u8 snd_new_hi, snd_new_lo;        /* a new reload for the interrupt to load at its next expiry (so that no interval is cut short): bit 7 of snd_new_hi says it is there */
extern u16 snd_cn;                       /* snd_n at the moment the interrupt loaded a new reload (0: it did not since the pump looked) */
extern u16 snd_tn, snd_tc;               /* take's answer: snd_n and snd_cn as they were */
extern u8 tins;                          /* $20 while the GIME timer runs on the fast clock (279 ns), else 0: every write of $FF91 is OR'ed with it */

/* The driver (snd_driver.c). The five routines of unit RES03 the game calls, and the tick. */
void SetSoundOutput(u16 enabled);
void SetSpeakerTune(u16 tune);
void SetTandyTune(u16 tune);
void StartSoundTimer(void);
void StopSoundTimer(void);
void DriverTick(void);

/* The backend (snd_core.c). */
void snd_init(void);                     /* allocate and clear the state block (the game; the tests set snd_state themselves) */
void snd_want_tone(u16 divisor, u8 gate);     /* what the driver asks of the speaker: PIT channel 2's divisor and the gate bits of port 61h (a tone when both are set) */
void snd_want_off(void);                 /* ... no tone */
void snd_apply(void);                    /* put the last request in the hardware (the pump does, once for all the ticks it ran) */
void snd_speaker_set(u16 divisor, u8 gate);   /* the hardware: a tone now (the tests) */
void snd_speaker_off(void);              /* no tone; the clock goes on */
void snd_begin(void);                    /* start the timer: the clock runs, the DAC is on */
void snd_end(void);                      /* stop it */
void snd_run(void);                      /* the pump: run DriverTick for every tick the timer has counted (a bank entry; the core checks snd_n first) */

/* the hardware, shared with the engine and the tests */
#define SND_TICK_UNITS 15123UL           /* 3 * 5041: one tick of the driver (236.7 Hz) in GIME fast clock units (279.365 ns) */
#define SND_REST_UNITS 4097              /* the longest interval the 12 bit reload gives (reload 4095): the clock while nothing sounds */
#define SND_MAX_CATCHUP 24               /* ticks run at one pump at most (100 ms): after a long computation the sound goes on from here */

#endif

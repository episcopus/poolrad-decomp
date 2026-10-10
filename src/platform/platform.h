/* platform.h: the only boundary between the engine and the outside world (SPEC 7.5).
 *
 * Status: hooks, waits (input, time, entropy, timer, sound) and the video
 * present call, approved by the human on 2026-10-10 after `make timing-scan`
 * (whitepaper 5.14, appendix C); P3 adds video present only, files and heap
 * records arrive with the first lifted unit that needs them (P4).
 *
 * HOOKS. Every function below reads the outside world, so it is a hook: a live or oracle run records its
 * result, a replay returns the recorded result unchanged, and the engine stays deterministic.
 * Two kinds:
 *
 *   poll   returns at once, with the state of the world now   (peek, ticks, time, entropy)
 *   wait   returns when a condition holds                     (key_wait, tick_wait, delay_ms)
 *
 * RULES FOR ENGINE CODE
 *   1. Never spin on a poll waiting for the world to change. In a replay and in a hybrid run (C inside
 *      the oracle) no time passes while C runs, so such a loop does not end. Use the wait that names the
 *      condition. The original spins (Crt init on the BIOS tick, menu loops on KeyPressed); the lift
 *      replaces the spin by the wait, which is the one deliberate structural difference.
 *   2. A wait costs nothing in a replay: it returns the recorded result at once. Time is charged by the
 *      replay system from the original's recording (SPEC 8.4, tools/oracle/timing.py), never spent here.
 *   3. Polling in a loop that has a bound of its own is fine (draining the keyboard buffer: the loop ends
 *      when platform_key_peek() returns 0).
 *
 * EVIDENCE (original routines, whitepaper 5.14; addresses are load-relative / overlay offsets)
 *   Crt.KeyPressed 0A40:02FD, Crt.ReadKey 0A40:030F, keyboard flush and Ctrl-C 0A40:0143,
 *   Crt.Delay 0A40:029C (+ calibration 0A40:002E), Crt.Sound 0A40:02C9, Crt.NoSound 0A40:02F6,
 *   Dos.GetDate 0A32:006C, Dos.GetTime 0A32:00A2 (also what Randomize reads), sound unit start 08AE:137C,
 *   stop 08AE:13B1, timer handler 08AE:13EA, voice step 08AE:1477, PIT counter as entropy ovl14:0B48 and
 *   ovl22:0B89.
 */
#ifndef POOLRAD_PLATFORM_H
#define POOLRAD_PLATFORM_H

#include "types.h"

/* ---- Input ------------------------------------------------------------------------------------ */

/* poll: INT 16h AH=1. The next key as a BIOS key code (scan code in the high byte, ASCII in the low
 * byte), left in the queue; 0 when the queue is empty. */
u16 platform_key_peek(void);

/* wait: INT 16h AH=0. Blocks until a key is available, removes it and returns its BIOS key code. */
u16 platform_key_wait(void);

/* ---- Time ------------------------------------------------------------------------------------- */

/* poll: the BIOS tick count (0040:006C, INT 1Ah AH=0): 18.2065 ticks per second since midnight, kept
 * by the platform whatever the game does with the timer interrupt (see platform_timer_set). */
u32 platform_ticks(void);

/* wait: blocks until platform_ticks() differs from `last`; returns the new value. Replaces the spin
 * "repeat until the tick count changed" of the original (Crt init, 0A40:002E). */
u32 platform_tick_wait(u32 last);

/* wait: blocks for about `ms` milliseconds (Crt.Delay). The original is a busy loop calibrated at start
 * up; the lift has no calibration and no DS:84FC (whitepaper 5.14). */
void platform_delay_ms(u16 ms);

/* poll: INT 21h AH=2Ch. Local time of day; hund is hundredths of a second. */
void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund);

/* poll: INT 21h AH=2Ah. dow is 0 for Sunday. */
void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow);

/* ---- Entropy ---------------------------------------------------------------------------------- */

/* poll: IN AL,40h, the low byte of the PIT channel 0 counter, which two overlay routines use as a
 * random source (not Random: that is rtl_random). A hook like every other: replays return the
 * recorded byte. */
u8 platform_entropy(void);

/* ---- Timer interrupt -------------------------------------------------------------------------- */

typedef void (*platform_tick_fn)(void);

/* Reprogram PIT channel 0 and install a handler called once per timer period, 1193182 / divisor times
 * per second (divisor 0 means 65536: the BIOS rate). The sound unit uses divisor 5041 (13h B1h): 13
 * times the BIOS rate, 236.7 Hz. The handler is called with interrupts as a handler would be: it must
 * return quickly and must not call a wait. The original handler chains to the BIOS tick every 13th
 * call; the platform keeps the BIOS tick count itself, so the C handler does not chain. */
void platform_timer_set(u16 divisor, platform_tick_fn handler);

/* Back to the BIOS rate (divisor 65536) with no handler (08AE:13B1). */
void platform_timer_reset(void);

/* ---- Sound ------------------------------------------------------------------------------------ */

/* PC speaker: PIT channel 2 reload value and the two low bits of port 61h (bit 0 gates the PIT, bit 1
 * connects the speaker). Crt.Sound computes divisor = 1193181 / hz and sets gate = 3; the voice
 * stepper (08AE:1477) writes both directly. */
void platform_speaker_set(u16 divisor, u8 port61_low2);

/* Speaker off: clears the two low bits of port 61h (Crt.NoSound, 08AE:13B1). */
void platform_speaker_off(void);

/* Tandy 3-voice sound chip (SN76489), one byte written to port C0h. */
void platform_tandy_write(u8 value);

/* ---- Video ------------------------------------------------------------------------------------ */

/* The engine draws into a 320x200 indexed framebuffer with a 16-entry EGA
 * palette and presents it here (SPEC 7.5; EGA mode 0Dh first, whitepaper 5.9
 * is still open). The host scales and presents it (SDL3); the oracle harness
 * compares m.ega.planes_digest() instead. Files and the heap record design
 * arrive with the first lifted unit that needs them (P4). */
void platform_present_frame(const u8 *fb_320x200, const u8 palette[16][3]);

#endif /* POOLRAD_PLATFORM_H */

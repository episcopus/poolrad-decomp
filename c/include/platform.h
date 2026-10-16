/* platform.h: the only boundary between the game and the machine it runs on (SPEC 7.5).
 *
 * The original reads the outside world in a few places: the keyboard (INT 16h), the clock (INT 21h AH=2Ch/2Ah, the
 * BIOS tick), the PIT and the vertical retrace, and it drives the timer interrupt, the PC speaker and the Tandy
 * sound chip. Every one of those reads and writes is a function here. Two implementations exist:
 *
 *   platform/sdl_host.c   a window, the keyboard, a real clock, audio (the game you play)
 *   platform/replay.c     headless; answers each read from a recording of the original and checks the screen
 *                         against the original's at the recorded checkpoints (the game you test)
 *
 * RULES FOR ENGINE CODE. A poll returns at once with the state of the world now; a wait returns when a condition
 * holds. The original spins on polls (the game clock, KeyPressed); the host makes a spin cheap by yielding
 * inside the poll, and the replay answers it from the recording. Engine code never sleeps on its own.
 */
#ifndef POOL_PLATFORM_H
#define POOL_PLATFORM_H

#include "pool.h"

/* Input. BIOS key codes: the scan code in the high byte, the ASCII code (0 for extended keys) in the low byte. */
u16 platform_key_peek(void);               /* the next key left in the queue, 0 when there is none */
u16 platform_key_wait(void);               /* blocks, removes and returns the next key */

/* Time. */
void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund);
void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow);
void platform_delay_ms(u16 ms);
u8 platform_pit_counter(void);             /* IN AL,40h: the low byte of the PIT channel 0 count (used as entropy) */
u8 platform_retrace_status(void);          /* IN AL,3DAh: bit 3 vertical retrace, bit 0 display disabled */

/* The timer interrupt. `divisor` reloads PIT channel 0 (0 means 65536, the BIOS rate); `handler` is called once
 * per timer period from the thread that runs the game. */
void platform_timer_set(u16 divisor, void (*handler)(void));
void platform_timer_reset(void);

/* Sound. */
void platform_speaker_set(u16 divisor, u8 port61_low2);   /* PIT channel 2 reload value, gate and speaker bits */
void platform_speaker_off(void);
void platform_tandy_write(u8 value);                      /* SN76489 byte written to port C0h */

/* The sound driver reports each write it makes to PIT channel 0 (5041 on start, 65535 on stop) for the sound
 * comparison (c/rtl/soundtrace.c, tools/c/sound_check.py). */
void sound_trace_pit0(u16 reload);

/* Video: the EGA memory changed; the host may present when it likes. */
void platform_video_changed(void);

/* Called from the polling hooks: a chance for the host to pump events, run timers and present. */
void platform_pump(void);

/* The game ends (Halt, or the player quits). Never returns. */
void platform_quit(int code);

/* Where the game's files are (the directory that DOS calls \POOLRAD) and where it writes (saved games). */
const char *platform_data_dir(void);
const char *platform_save_dir(void);

#endif

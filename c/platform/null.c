/* null.c: the platform for headless tests that need no recording (c/tests/sound_probe.c). Every platform.h function
 * does nothing, except the sound ones, which keep what the sound comparison needs:
 *
 *   timer     the handler platform_timer_set was given is kept, and the test fires it by hand (null_timer_active,
 *             null_timer_fire), so virtual time is whatever the test says it is.
 *   speaker   the port-level events the oracle logs (tools/oracle/machine.py): writing the high byte of the PIT
 *             channel 2 divisor logs (divisor, speaker bits as they were), writing port 61h logs (divisor, new
 *             bits), where "on" means both gate bits set. The divisor persists across a platform_speaker_off.
 *   tandy     every byte is logged.
 * They go to c/rtl/soundtrace.c, the same list as the driver's PIT channel 0 events.
 *
 * Not for the replay: c/platform/replay.c plays recordings and keeps its own sound hooks. */
#include "platform.h"

extern void sound_trace_speaker(u16 divisor, u8 gate);
extern void sound_trace_tandy(u8 v);

static void (*timer_handler)(void);
static u16 speaker_divisor;   /* PIT channel 2 reload as last written */
static u8 speaker_bits;       /* port 61h bits 0 and 1 as last written */

int null_timer_active(void) { return timer_handler != NULL; }

void null_timer_fire(void)
{
  if (timer_handler) {
    timer_handler();
  }
}

u16 platform_key_peek(void) { return 0; }
u16 platform_key_wait(void) { return 0; }
void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund) { *hour = 0; *min = 0; *sec = 0; *hund = 0; }
void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow) { *year = 1991; *month = 1; *day = 1; *dow = 2; }
void platform_delay_ms(u16 ms) { (void)ms; }
u8 platform_pit_counter(void) { return 0; }
u8 platform_retrace_status(void) { return 0; }

void platform_timer_set(u16 divisor, void (*handler)(void))
{
  (void)divisor;
  timer_handler = handler;
}

void platform_timer_reset(void) { timer_handler = NULL; }

void platform_speaker_set(u16 divisor, u8 port61_low2)
{
  speaker_divisor = divisor;
  sound_trace_speaker(speaker_divisor, (u8)(speaker_bits == 3));
  speaker_bits = (u8)(port61_low2 & 3);
  sound_trace_speaker(speaker_divisor, (u8)(speaker_bits == 3));
}

void platform_speaker_off(void)
{
  speaker_bits = 0;
  sound_trace_speaker(speaker_divisor, 0);
}

void platform_tandy_write(u8 value) { sound_trace_tandy(value); }
void platform_video_changed(void) {}
void platform_pump(void) {}
void platform_quit(int code) { (void)code; for (;;) { } }
const char *platform_data_dir(void) { return "."; }
const char *platform_save_dir(void) { return "."; }

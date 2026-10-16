/* sound_probe.c: plays every tune of the sound driver (c/driver/res03_driver.c) on a null platform and prints the
 * hardware trace, for tools/c/sound_check.py to compare with the oracle's (tests/sessions/golden/sound-driver).
 * It does what tools/oracle/soundprobe.py does to the original:
 *
 *   the game's start: SilenceSound, then SetSoundDriverIdle(100)    (res08's initialisation, StartGame)
 *   for device 1 (PC speaker), then 0 (Tandy chip):
 *     SetSoundDriverIdle(0); PlaySound(1)
 *     for tune k = 1..20: PlaySound(k + 1), one second, PlaySound(0FFh), a tenth of a second
 *     PlaySound(0); SetSoundDriverIdle(100); a tenth of a second
 *
 * VIRTUAL TIME. The oracle ran 1,000,000 instructions per second and raised 237 timer interrupts in a second of
 * driver time and 24 in a tenth (counted at the handler's entry, the same for every tune and both devices); no
 * interrupt falls inside a call. A wait with the timer stopped raised none. The probe fires the handler those
 * numbers of times. The oracle stamps each event with the clock of the instruction chunk it ran in, so events of
 * one timer tick, and of the calls that follow it, share a time, and its trace orders events of equal time by kind
 * (P, S, T). The probe therefore prints, after the events (sound_trace_dump), a line `--` and then pairs `index
 * vtime`: from event number index on, events belong to virtual time vtime. The time advances once per timer tick,
 * once per wait with the timer stopped, and once at each of the two start-up steps and each device's first call.
 * Output on stdout. */
#include <stdio.h>

#include "game.h"
#include "platform.h"

extern int null_timer_active(void);
extern void null_timer_fire(void);
extern void sound_trace_dump(FILE *f);
extern unsigned sound_trace_count(void);

enum {
  Tunes = 20,
  TicksPerSecond = 237,       /* timer interrupts the oracle raised in 1,000,000 instructions at divisor 5041 */
  TicksPerTenth = 24,         /* ... in 100,000 */
  MaxMarks = 100000
};

static unsigned mark_index[MaxMarks];
static unsigned mark_time[MaxMarks];
static unsigned marks;
static unsigned vtime;

static void advance(void)
{
  vtime++;
  mark_index[marks] = sound_trace_count();
  mark_time[marks] = vtime;
  marks++;
}

/* Let `ticks` timer interrupts pass: each is a new virtual time. With the timer stopped time passes once. */
static void wait_ticks(unsigned ticks)
{
  unsigned i;
  if (!null_timer_active()) {
    advance();
    return;
  }
  for (i = 0; i < ticks; i++) {
    advance();
    null_timer_fire();
  }
}

int main(void)
{
  int device;
  unsigned tune;
  unsigned i;

  SoundMode = SoundSpeaker;
  advance();
  SilenceSound();
  advance();
  SetSoundDriverIdle(100);

  for (device = 1; device >= 0; device--) {
    SoundMode = (u8)device;
    advance();
    SetSoundDriverIdle(0);
    PlaySound(1);
    for (tune = 1; tune <= Tunes; tune++) {
      PlaySound((u16)(tune + 1));
      wait_ticks(TicksPerSecond);
      PlaySound(0xFF);
      wait_ticks(TicksPerTenth);
    }
    PlaySound(0);
    SetSoundDriverIdle(100);
    wait_ticks(TicksPerTenth);
  }

  sound_trace_dump(stdout);
  printf("--\n");
  for (i = 0; i < marks; i++) {
    printf("%u %u\n", mark_index[i], mark_time[i]);
  }
  return 0;
}

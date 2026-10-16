/* soundtrace.c: what the game sent to the speaker and the Tandy chip, as a list, for the sound comparison
 * (tools/oracle/sound.py writes the same events for the original). */
#include <stdio.h>
#include <stdlib.h>

#include "platform.h"

#define MAX_EVENTS 1000000

typedef struct Ev {
  char kind;
  u16 a;
  u8 b;
} Ev;

static Ev *events;
static unsigned count;

static void add(char kind, u16 a, u8 b)
{
  static Ev store[1];
  (void)store;
  if (!events) {
    events = (Ev *)malloc(sizeof(Ev) * MAX_EVENTS);
  }
  if (events && count < MAX_EVENTS) {
    events[count].kind = kind;
    events[count].a = a;
    events[count].b = b;
    count++;
  }
}

void sound_trace_speaker(u16 divisor, u8 gate)
{
  add('S', divisor, gate);
}

void sound_trace_tandy(u8 v)
{
  add('T', v, 0);
}

void sound_trace_pit0(u16 reload)
{
  add('P', reload, 0);
}

void sound_trace_dump(FILE *f)
{
  unsigned i;
  for (i = 0; i < count; i++) {
    fprintf(f, "%c %u %u\n", events[i].kind, events[i].a, events[i].b);
  }
}

unsigned sound_trace_count(void)
{
  return count;
}

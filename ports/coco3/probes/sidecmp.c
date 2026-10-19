/* sidecmp.c: `Record->Side == OpposingSide(Who)` as CollectEnemiesInRange writes it (a signed byte against the byte a routine returns), and
 * the copy of a 3 byte record within one table with rtl_Move's contract (memmove forward). Step 8.7b: the CoCo's AI found no enemy where the
 * original's found one.
 * r0 equal sides found (Who side 1, records of side 0), count of 3 records | std = 3
 * r1 the same with Who side 0 (records side 1)                              | std = 3
 * r2 records of the Who's own side must not count                           | std = 0
 */
#include "mailbox.h"
typedef unsigned char u8;
typedef signed char s8;
typedef short s16;
typedef struct Ch { s8 Side; u8 pad[3]; } Ch;
Ch chars[4];
Ch *rec[4];

u8 OpposingSide(Ch *Who)
{
  u8 Result = 0;
  if ((s16)Who->Side == 0) {
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

u8 Count(Ch *Who)
{
  u8 Found = 0;
  u8 Index;
  for (Index = 1; Index <= 3; Index++) {
    if (rec[Index]->Side == OpposingSide(Who)) {
      Found++;
    }
  }
  return Found;
}

int main(void)
{
    u8 i;
    scr_clear();
    scr_puts(0, 0, "PROBE SIDECMP");
    for (i = 0; i < 4; i++) rec[i] = &chars[i];
    chars[0].Side = 1;
    chars[1].Side = 0; chars[2].Side = 0; chars[3].Side = 0;
    mb_check(0, Count(&chars[0]), 3);
    chars[0].Side = 0;
    chars[1].Side = 1; chars[2].Side = 1; chars[3].Side = 1;
    mb_check(1, Count(&chars[0]), 3);
    chars[1].Side = 0; chars[2].Side = 0; chars[3].Side = 0;
    mb_check(2, Count(&chars[0]), 0);
    mb_finish();
    return 0;
}

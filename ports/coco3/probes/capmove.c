/* capmove.c: res12's CapMovementByLoad as the translation writes it (a case over an Integer through a 32 bit temporary, ranges as constants), run by
 * CMOC on the loads a kobold, a fighter and an overloaded man carry (step 8.7b: after a fight a combatant's movement is 6 half moves on the CoCo where the
 * original has 12).
 * r0..r5  the movement after the cap for (carried, allowance, movement) = (46,-350,12) (46,-150,12) (600,100,12) (700,0,12) (900,0,12) (1200,0,12)
 * std = 12 12 12 9 6 3
 */
#include "mailbox.h"
typedef unsigned char u8;
typedef unsigned short u16;
typedef short s16;
typedef long s32;
enum { MediumLoadMove = 9, HeavyLoadMove = 6, OverloadMove = 3 };

u8 Cap(u16 CarriedWeight, s16 Allowance, u8 Movement)
{
  s16 Weight = 0;
  u8 NewMovement = 0;
  s32 t1;
  Weight = (s32)CarriedWeight - Allowance;
  if (Weight < 0) {
    Weight = 0;
  }
  t1 = Weight;
  if ((t1 >= 0 && t1 <= 512)) {
    NewMovement = Movement;
  } else if ((t1 >= 513 && t1 <= 768)) {
    NewMovement = MediumLoadMove;
  } else if ((t1 >= 769 && t1 <= 1024)) {
    NewMovement = HeavyLoadMove;
  } else {
    NewMovement = OverloadMove;
  }
  if (NewMovement < Movement) {
    Movement = NewMovement;
  }
  return Movement;
}

int main(void)
{
    scr_clear();
    scr_puts(0, 0, "PROBE CAPMOVE");
    mb_check(0, Cap(46, -350, 12), 12);
    mb_check(1, Cap(46, -150, 12), 12);
    mb_check(2, Cap(600, 100, 12), 12);
    mb_check(3, Cap(700, 0, 12), 9);
    mb_check(4, Cap(900, 0, 12), 6);
    mb_check(5, Cap(1200, 0, 12), 3);
    mb_finish();
    return 0;
}

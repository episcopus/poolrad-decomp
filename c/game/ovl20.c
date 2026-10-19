#include "game.h"

/* ovl20:0000. Spends elapsed game time on the party's timed affects. AdvanceGameClock calls it with the Amount
     and Index just added to the game clock. Those units are scaled down to the smallest digit (each higher
     digit multiplied by ClockRadix), then spent in passes of at most MaxAffectStep. Outside camp every
     member is marked due (FillChar of TimedAffectFlagsFrom0, the same 72 bytes as TimedAffectFlags from index 1; a port
     should use TimedAffectFlags). In camp it returns at once when no TimedAffectFlags entry is set. A
     marked member's flag is cleared, then each affect loses the pass or is removed through RemoveAffect
     when its duration does not outlast the pass. Duration 0 is permanent and is left. The flag is set
     again while a timed affect remains. Reads ViewMode, GameVars2 word VarPartySize, ClockRadix and the party
     list PartyListHead; changes TimedAffectFlags, TimedAffectFlagsFrom0 and the affect lists. QUIRK ovl20:0118:
     NextAffect is loaded from
     the list head before the empty-list test, so a nil list reads through nil and the value is discarded. */
void AdvanceAffectDurations(u8 Amount, s8 Index)
{
  POOL_TRACE("AdvanceAffectDurations");
  s8 UnitIndex = 0;
  u8 PartyIndex = 0;
  u8 AffectTimeStep = 0;
  u16 ScaledAmount = 0;
  PCharacter Who = 0;
  u8 AffectAtTail = 0;
  u8 HasTimedAffect = 0;
  PAffect TailAffect = 0;
  PAffect PreviousAffect = 0;
  PAffect NextAffect = 0;
  PAffect TargetAffect = 0;
  if (ViewMode != ViewModeCamp) {
    rtl_FillChar((void *)&TimedAffectFlagsFrom0, TimedAffectFlagCount, TimedAffectDue);
  } else {
    HasTimedAffect = 0;
    PartyIndex = FirstPartyIndex;
    do {
      if (TimedAffectFlags[PartyIndex] != 0) {
        HasTimedAffect = 1;
      }
      PartyIndex++;
    } while (!(((HasTimedAffect != 0)) || ((PartyIndex > (*FPD(TGameVars (*), GameVars2))[830]))));
    if (HasTimedAffect == 0) {
      return;
    }
  }
  ScaledAmount = Amount;
  UnitIndex = Index;
  /* Pred, not Dec or minus: ShortInt Pred is mov/dec/mov, and Pred as an index is dec then cwde
     (tools/re/tp_idioms/ovl20/PRB20_A.PAS). */
  while (UnitIndex > 1) {
    ScaledAmount = ScaledAmount * ClockRadix[(s8)(UnitIndex - 1)];
    UnitIndex = (s8)(UnitIndex - 1);
  }
  while (ScaledAmount > 0) {
    if (ScaledAmount > MaxAffectStep) {
      AffectTimeStep = MaxAffectStep;
    } else {
      AffectTimeStep = ScaledAmount;
    }
    PartyIndex = FirstPartyIndex;
    Who = PartyListHead;
    while (Who != 0) {
      if (TimedAffectFlags[PartyIndex] != 0) {
        TimedAffectFlags[PartyIndex] = 0;
        TargetAffect = (*FPD(TCharacter (*), Who)).Affects;
        TailAffect = (*FPD(TCharacter (*), Who)).Affects;
        PreviousAffect = (*FPD(TCharacter (*), Who)).Affects;
        NextAffect = (*FPD(TAffect (*), PreviousAffect)).Next;
        if ((*FPD(TCharacter (*), Who)).Affects != 0) {
          while ((*FPD(TAffect (*), TailAffect)).Next != 0) {
            TailAffect = (*FPD(TAffect (*), TailAffect)).Next;
          }
        }
        AffectAtTail = 0;
        while (((TargetAffect != 0)) && ((AffectAtTail == 0))) {
          if (TargetAffect == TailAffect) {
            AffectAtTail = 1;
          }
          if ((*FPD(TAffect (*), TargetAffect)).Duration == 0) {
            TargetAffect = (*FPD(TAffect (*), TargetAffect)).Next;
          } else if (AffectTimeStep < (*FPD(TAffect (*), TargetAffect)).Duration) {
            (*FPD(TAffect (*), TargetAffect)).Duration -= AffectTimeStep;
            TimedAffectFlags[PartyIndex] = 1;
            TargetAffect = (*FPD(TAffect (*), TargetAffect)).Next;
          } else {
            NextAffect = (*FPD(TAffect (*), TargetAffect)).Next;
            RemoveAffect(Who, (*FPD(TAffect (*), TargetAffect)).Id, TargetAffect);
            if (PreviousAffect == (*FPD(TCharacter (*), Who)).Affects) {
              TargetAffect = (*FPD(TCharacter (*), Who)).Affects;
            } else {
              TargetAffect = NextAffect;
            }
          }
          PreviousAffect = (*FPD(TCharacter (*), Who)).Affects;
          while ((((PreviousAffect != 0)) && ((PreviousAffect != TargetAffect))) && (((*FPD(TAffect (*), PreviousAffect)).Next != TargetAffect))) {
            PreviousAffect = (*FPD(TAffect (*), PreviousAffect)).Next;
          }
        }
        while (TargetAffect != 0) {
          if ((*FPD(TAffect (*), TargetAffect)).Duration > 0) {
            TimedAffectFlags[PartyIndex] = 1;
          }
          TargetAffect = (*FPD(TAffect (*), TargetAffect)).Next;
        }
      }
      PartyIndex++;
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    if (ScaledAmount > MaxAffectStep) {
      ScaledAmount -= MaxAffectStep;
    } else {
      ScaledAmount = 0;
    }
  }
}

/* ovl20:02F2: retf 4: a var pointer to the rest clock (4 bytes of parameters); 6 bytes of locals.
     Carries the clock up its digits: digit I at or above its radix (ClockRadix[I], DS:363A) gives one
     unit to digit I+1 and loses the radix, for digits 0..5. The top digit has no next digit: at or above
     its radix it ages every character on the party list by one year (TCharacter.Age, +$30) and the radix
     is kept [I]. QUIRK ovl20:037B: the top digit is never reduced, so once Clock[TopClockDigit] is at or
     above its radix every later carry call ages the party again (whether the game can reach that is not
     proven). */
void CarryRestClock(TRestClock (*Clock))
{
  POOL_TRACE("CarryRestClock");
  s8 Digit = 0;
  PCharacter Who = 0;
  {
    if (0 <= TopClockDigit) {
      Digit = 0;
      for (;;) {
          if ((*Clock)[Digit] >= ClockRadix[Digit]) {
            if (Digit != TopClockDigit) {
              (*Clock)[(s8)(Digit + 1)]++;
              (*Clock)[Digit] = (*Clock)[Digit] - ClockRadix[Digit];
            } else {
              Who = PartyListHead;
              while (Who != 0) {
                (*FPD(TCharacter (*), Who)).Age++;
                Who = (*FPD(TCharacter (*), Who)).Next;
              }
            }
          }
        if (Digit == TopClockDigit) break;
        Digit++;
      }
    }
  }
}

/* ovl20:03A3: retf 0: no parameters, no locals. Settles the rest time after a change (ovl20:0721 and
     ovl20:047A call it): carries the clock, then turns the months (RestTime[MonthsDigit]) into days at
     ClockRadix[DaysDigit], 30 days a month, and keeps the days (RestTime[DaysDigit]) at MaxRestDays or
     less. */
void NormalizeRestTime(void)
{
  POOL_TRACE("NormalizeRestTime");
  CarryRestClock(&RestTime);
  if (RestTime[5] > 0) {
    RestTime[4] += (u16)(ClockRadix[4] * RestTime[5]);
    RestTime[5] = 0;
    if (RestTime[4] > MaxRestDays) {
      RestTime[4] = MaxRestDays;
    }
  }
}

/* ovl20:03D5: retf 4: Amount and Index (4 bytes of parameters); 18 bytes of locals. Advances the game clock by
     Amount units of digit Index: copies the seven game-clock words into a local clock, adds one unit per step
     and carries it (CarryRestClock), writes the clock back, then spends the elapsed time on timed affects
     (AdvanceAffectDurations with the same arguments). GameClockWord is the first of the seven words: the VM
     words at 49C6h..49CCh, that is GameVars^[198..204] (whitepaper 5.22.1). This is the unit's main entry for
     other units: EndCombatRound (ovl08:0880) advances it one unit of digit 1 at the end of a combat round,
     MoveParty, CheckMapCell and HandleWildernessKeys (ovl14) advance it during movement, and RunRestPeriod
     five minutes (Index 1) per rest step. Reads and writes VarsAt4900 and, through CarryRestClock, ClockRadix;
     side effects through AdvanceAffectDurations. */
void AdvanceGameClock(u8 Amount, s8 Index)
{
  POOL_TRACE("AdvanceGameClock");
  TRestClock Clock = {0};
  s8 Digit = 0;
  u8 Step = 0;
  {
    if (0 <= 6) {
      Digit = 0;
      for (;;) {
          Clock[Digit] = (*FPD(TVmWords4900 (*), VarsAt4900))[(s16)(GameClockWord + Digit) - 18688];
        if (Digit == 6) break;
        Digit++;
      }
    }
  }
  {
    u8 limit = Amount;
    if (1 <= limit) {
      Step = 1;
      for (;;) {
          Clock[Index]++;
          CarryRestClock(&Clock);
        if (Step == limit) break;
        Step++;
      }
    }
  }
  {
    if (0 <= 6) {
      Digit = 0;
      for (;;) {
          (*FPD(TVmWords4900 (*), VarsAt4900))[(s16)(GameClockWord + Digit) - 18688] = Clock[Digit];
        if (Digit == 6) break;
        Digit++;
      }
    }
  }
  AdvanceAffectDurations(Amount, Index);
}

/* ovl20:047A: retf 4: Amount and Index (4 bytes of parameters); 4 bytes of locals. Takes Amount off the
     rest clock digit Index (the Dec key of the Rest menu, ovl20:0721, and the rest's countdown, RunRestPeriod).
     Nothing happens when the minutes, tens, hours and days (RestTime[MinutesDigit..DaysDigit]) are all zero.
     Otherwise, while Amount is more than the digit, the next higher digit that is not zero lends one unit to
     the digits below it (each gets its radix, ClockRadix); when no such digit below the months is left, the
     clock is cleared and Amount becomes 0. The digit then loses Amount and the clock is normalized
     (NormalizeRestTime). */
void SpendRestTime(u8 Amount, s8 Index)
{
  POOL_TRACE("SpendRestTime");
  s8 Lender = 0;
  s8 Digit = 0;
  if (((((RestTime[4] != 0)) || ((RestTime[3] != 0))) || ((RestTime[2] != 0))) || ((RestTime[1] != 0))) {
    while (Amount > RestTime[Index]) {
      Lender = (s8)(Index + 1);
      while (((RestTime[Lender] == 0)) && ((Lender < MonthsDigit))) {
        Lender = (s8)(Lender + 1);
      }
      if (Lender == MonthsDigit) {
        rtl_FillChar((void *)&RestTime, 14, 0);
        Amount = 0;
      } else {
        {
          s8 limit = (s8)(Index + 1);
          s8 first = Lender;
          if (first >= limit) {
            Digit = first;
            for (;;) {
                RestTime[Digit]--;
                RestTime[(s8)(Digit - 1)] += ClockRadix[(s8)(Digit - 1)];
              if (Digit == limit) break;
              Digit--;
            }
          }
        }
      }
    }
    RestTime[Index] -= Amount;
    NormalizeRestTime();
  }
}

/* ovl20:0565: retf 2: Number (2 bytes of parameters) and the String40 result, which the caller pushes
     before Number; 298 bytes of locals (S and the compiler's string temporary). The result is Number as
     two characters: ByteToText gives its text, a '0' goes in front below 10, the first two are kept. */
u8 *TwoDigitText(u8 *Result_out, u8 Number)
{
  POOL_TRACE("TwoDigitText");
  u8 *Result = Result_out;
  String40_RES06 Digits = {0};
  u8 ts1[256];
  rtl_str_assign(Digits, 40, ByteToText(ts1, Number));
  if (Number < 10) {
    rtl_str_assign(Digits, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\001\060"), Digits}));
  }
  rtl_str_assign(Result, 40, rtl_str_copy(ts1, Digits, 1, 2));
  return Result;
}

/* ovl20:05F0: retf 2: Selected (2 bytes of parameters); 272 bytes of locals. Draws the rest time on row 17:
     "Rest Time:" and then days and hours as two digits with a colon between them, and the minutes (the tens
     and the minutes of RestTime, MinutesPerTensDigit * RestTime[TensOfMinutesDigit] +
     RestTime[MinutesDigit]). The field Selected is drawn in RestSelectedColor, the others in RestTextColor.
     Selected is a RestTime digit (TensOfMinutesDigit, HoursDigit or DaysDigit) or 0; Colors[0] is never
     drawn, so Selected 0 (every caller but the menu) highlights nothing. */
void ShowRestTime(s8 Selected)
{
  POOL_TRACE("ShowRestTime");
  s8 Digit = 0;
  u16 Colors[7] = {0};
  u8 Col = 0;
  u8 ts1[256];
  {
    if (0 <= 6) {
      Digit = 0;
      for (;;) {
          Colors[Digit] = RestTextColor;
        if (Digit == 6) break;
        Digit++;
      }
    }
  }
  Colors[Selected] = RestSelectedColor;
  DrawTextAt(RestLabelColumn, RestRow, RestTextColor, S("\012Rest Time:"));
  Col = RestFirstColumn;
  {
    if (DaysDigit >= HoursDigit) {
      Digit = DaysDigit;
      for (;;) {
          DrawTextAt((s16)(Col + 1), RestRow, Colors[Digit], TwoDigitText(ts1, RestTime[Digit]));
          /* Col + 1 + 1 + 1 is the original's expression for the colon column, one past the two digits */
          DrawTextAt((s16)(((Col + 1) + 1) + 1), RestRow, RestTextColor, S("\001:"));
          Col += 3;
        if (Digit == HoursDigit) break;
        Digit--;
      }
    }
  }
  DrawTextAt((s16)(Col + 1), RestRow, Colors[2], TwoDigitText(ts1, (u16)((MinutesPerTensDigit * RestTime[2]) + RestTime[1])));
}

/* ovl20:0721: retf 0, 46 bytes of locals. The rest menu: "Rest daYs Hours Mins Inc Dec Exit" under the
     rest time line, until the player picks Rest (result 1) or Exit or Escape (result 0). Selected is the
     RestTime digit of the field being changed (TensOfMinutesDigit for the minutes, HoursDigit, DaysDigit),
     drawn highlighted by ShowRestTime. Y, H and M choose the days, hours and minutes field; the arrow keys
     move between the fields (wrapping); Inc and Dec, or the up and down arrows, change the field (five
     minutes at a time on the minutes field, through SpendRestTime for a decrease) and NormalizeRestTime
     carries the clock. Enter is Rest. The arrows and any unknown extended key set KeyIgnore 'X', which no
     case arm handles, so nothing happens. The R arm sets the result and falls through to the until test,
     which ends the loop (07D5 jumps to 083D, not to the epilogue). */
u8 RestTimeMenu(void)
{
  POOL_TRACE("RestTimeMenu");
  u8 Result = 0;
  u8 ExtendedKey = 0;
  u8 Key = 0;
  s8 Selected = 0;
  Result = 0;
  Selected = TensOfMinutesDigit;
  do {
    ShowRestTime(Selected);
    Key = ReadPromptChoice(S("\000"), S("'Rest   daYs Hours Mins   Inc Dec   Exit"), RestTitleColor, RestWordColor, RestHotColor, 1, 0, &ExtendedKey);
    if (ExtendedKey != 0) {
      switch ((u8)Key) {
      case 'H':
      {
        Key = 'I';
        break;
      }
      case 'P':
      {
        Key = 'D';
        break;
      }
      case 'K':
      {
        Selected++;
        if (Selected > DaysDigit) {
          Selected = TensOfMinutesDigit;
        }
        Key = KeyIgnore;
        break;
      }
      case 'M':
      {
        Selected--;
        if (Selected < TensOfMinutesDigit) {
          Selected = DaysDigit;
        }
        Key = KeyIgnore;
        break;
      }
      default:
      {
        Key = KeyIgnore;
      }
      }
    }
    if (Key == KeyEnter_OVL20) {
      Key = KeyRest;
    }
    switch ((u8)Key) {
    case 'R':
    {
      Result = 1;
      break;
    }
    case 'Y':
    {
      Selected = DaysDigit;
      break;
    }
    case 'H':
    {
      Selected = HoursDigit;
      break;
    }
    case 'M':
    {
      Selected = TensOfMinutesDigit;
      break;
    }
    case 'I':
    {
      if (Selected == TensOfMinutesDigit) {
        RestTime[1] += RestMinuteStep;
      } else {
        RestTime[Selected]++;
      }
      NormalizeRestTime();
      break;
    }
    case 'D':
    {
      if (Selected == TensOfMinutesDigit) {
        SpendRestTime(RestMinuteStep, MinutesDigit);
      } else {
        SpendRestTime(1, Selected);
      }
      NormalizeRestTime();
      break;
    }
    }
  } while (!(Key == KeyEscape_OVL20 || Key == KeyExit || Key == KeyRest));
  return Result;
}

/* ovl20:0871: the whole-party heal of the rest. RestHealCounter counts five-minute rest steps; at
     RestHealCheckInterval ($120, 288 steps, 24 hours) every party member is healed one hit point
     (HealCharacter with RestHealAmount and flag 0, so a member with affect $32 is skipped) and the message
     "The Whole Party Is Healed" is shown. The roster is redrawn only when someone actually healed. It then
     delays, clears the message and resets RestHealCounter. Reads the party list; changes RestHealCounter and
     character health; side effects are the screen and delay. */
void CheckRestHealing(void)
{
  POOL_TRACE("CheckRestHealing");
  u8 Healed = 0;
  PCharacter Who = 0;
  RestHealCounter++;
  if (RestHealCounter >= RestHealCheckInterval) {
    Healed = 0;
    Who = PartyListHead;
    while (Who != 0) {
      /* RestHealAmount hit points; flag 0, so HealCharacter skips a member with affect $32 (ovl24:175D) */
      if (HealCharacter(Who, RestHealAmount, 0)) {
        Healed = 1;
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    ShowRestTime(0);
    /* the original draws this message in colour 10 (RestTextColor), not the interruption message's
       RestMessageColor 15; the healing itself is what the message claims */
    DrawTextAt(RestMessageColumn, RestMessageRow, RestTextColor, S("\031The Whole Party Is Healed"));
    if (Healed) {
      DrawPartyRoster(SelectedCharacter);
    }
    DelayByGameSpeed();
    ClearCharacterMessage();
    RestHealCounter = 0;
  }
}

/* ovl20:0925: scans Who's 21 spell slots. When Handled is 0, the first spell with bit 7 set is completed:
     the bit is cleared, the rest-time line is redrawn, and ShowSpellMessage receives Who, "has memorized" and the
     spell byte; Handled becomes 1. Once one is handled, the function returns the level of the next pending
     spell, or 0 when none remains. Reads SpellTable and changes Who^.Spells and Handled; also draws text. */
u8 ProcessMemorizedSpell(PCharacter Who, u8 (*Handled))
{
  POOL_TRACE("ProcessMemorizedSpell");
  u8 Result = 0;
  u8 SpellLevel = 0;
  u8 SpellIndex = 0;
  SpellLevel = 0;
  SpellIndex = 0;
  while (((SpellIndex <= LastCharacterSpellSlot)) && ((SpellLevel == 0))) {
    if ((*FPD(TCharacter (*), Who)).Spells[SpellIndex] > SpellNumberMask) {
      if ((*Handled) != 0) {
        SpellLevel = SpellTable[((*FPD(TCharacter (*), Who)).Spells[SpellIndex] & SpellNumberMask)].Level;
      } else {
        (*FPD(TCharacter (*), Who)).Spells[SpellIndex] -= PendingSpellFlag;
        ShowRestTime(0);
        ShowSpellMessage(Who, S("\015has memorized"), (*FPD(TCharacter (*), Who)).Spells[SpellIndex]);
        (*Handled) = 1;
      }
    }
    SpellIndex++;
  }
  Result = SpellLevel;
  return Result;
}

/* ovl20:09E7: for Who, scans carried scrolls and their three spell bytes for pending scribing (bit 7 set).
     When Handled is 0, it marks the first pending spell known, calls ConsumeScrollSpell to consume it, redraws the
     rest-time line and reports "has scribed" through ShowSpellMessage; Handled becomes 1. When already handled, it
     returns the level of the next pending scroll spell, or 0. Reads Who^.Items and SpellTable; changes
     Who^.KnownSpells, the scroll and Handled; also changes the screen. */
u8 ProcessPendingScribedSpell(PCharacter Who, u8 (*Handled))
{
  POOL_TRACE("ProcessPendingScribedSpell");
  u8 Result = 0;
  u8 SpellIndex = 0;
  u8 SpellNumber = 0;
  u8 SpellLevel = 0;
  PItem Item = 0;
  SpellLevel = 0;
  Item = (*FPD(TCharacter (*), Who)).Items;
  while (((Item != 0)) && ((SpellLevel == 0))) {
    SpellIndex = 1;
    if (IsScroll(Item)) {
      while (((SpellIndex <= LastScrollSpellSlot)) && ((SpellLevel == 0))) {
        if ((*FPD(TMenuLine (*), Item)).Affects[SpellIndex - 1] > PendingSpellFlag) {
          if ((*Handled) != 0) {
            SpellLevel = SpellTable[((*FPD(TMenuLine (*), Item)).Affects[SpellIndex - 1] & SpellNumberMask)].Level;
          } else {
            SpellNumber = ((*FPD(TMenuLine (*), Item)).Affects[SpellIndex - 1] & SpellNumberMask);
            (*FPD(TCharacter (*), Who)).KnownSpells[SpellNumber - 1] = 1;
            ConsumeScrollSpell(Who, Item, SpellNumber);
            ShowRestTime(0);
            ShowSpellMessage(Who, S("\013has scribed"), SpellNumber);
            (*Handled) = 1;
          }
        }
        SpellIndex++;
      }
    }
    Item = (*FPD(TMenuLine (*), Item)).Next;
  }
  Result = SpellLevel;
  return Result;
}

/* ovl20:0B0A: visits each party member and decrements that member's RestStudyCountdowns rest counter. When the counter
     reaches zero and RestHours is zero, it completes a pending scribed spell first, then a memorized spell,
     and sets the counter to three times the next pending spell's level. Reads the party list and RestHours;
     changes RestStudyCountdowns, spell state and the screen through the study helpers. */
void AdvanceRestStudies(void)
{
  POOL_TRACE("AdvanceRestStudies");
  u8 PartyIndex = 0;
  u8 SpellLevel = 0;
  PCharacter Who = 0;
  u8 Handled = 0;
  u8 UnusedFrameByte = 0;
  PartyIndex = FirstPartyIndex;
  Who = PartyListHead;
  while (Who != 0) {
    RestStudyCountdowns[PartyIndex]--;
    if (RestStudyCountdowns[PartyIndex] == 0) {
      if ((*FPD(TCharacter (*), Who)).RestHours == 0) {
        Handled = 0;
        SpellLevel = ProcessPendingScribedSpell(Who, &Handled);
        if (SpellLevel == 0) {
          SpellLevel = ProcessMemorizedSpell(Who, &Handled);
        }
        RestStudyCountdowns[PartyIndex] = SpellLevel * RestStepsPerSpellLevel;
      }
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
    PartyIndex++;
  }
}

/* ovl20:0BB2: counts twelve calls as one rest hour. At that point, it decreases each party member's
     RestHours when positive; on reaching zero, it reads the next pending scribed or memorized spell level
     and sets that member's RestStudyCountdowns entry to three times the level. State is a shared byte
     counter updated by reference. Reads the party list; changes State, RestHours, spell-related counts and
     RestStudyCountdowns. */
void AdvanceRestHour(u8 (*State))
{
  POOL_TRACE("AdvanceRestHour");
  u8 PartyIndex = 0;
  u8 SpellLevel = 0;
  PCharacter Who = 0;
  u8 Handled = 0;
  u8 UnusedFrameByte = 0;
  (*State)++;
  if ((*State) >= RestStepsPerHour) {
    (*State) = 0;
    PartyIndex = FirstPartyIndex;
    Who = PartyListHead;
    while (Who != 0) {
      if ((*FPD(TCharacter (*), Who)).RestHours > 0) {
        (*FPD(TCharacter (*), Who)).RestHours--;
        if ((*FPD(TCharacter (*), Who)).RestHours == 0) {
          Handled = 1;
          SpellLevel = ProcessPendingScribedSpell(Who, &Handled);
          if (SpellLevel == 0) {
            SpellLevel = ProcessMemorizedSpell(Who, &Handled);
          }
          RestStudyCountdowns[PartyIndex] = SpellLevel * RestStepsPerSpellLevel;
        }
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
      PartyIndex++;
    }
  }
}

/* ovl20:0C9A: rest countdown and interruptions. RestParty (ovl15:077A) calls this with no parameters and
     uses the byte result to decide whether the camp ends. It reads RestTime, the party list, the GameVars2 game
     words and RestInterruptCounter, and changes RestStudyCountdowns, TimedAffectFlagsFrom0 and RestWindowActive. Each
     five-minute step spends rest time, advances the game clock, runs the rest's healing and study, and may
     trigger a random interruption: while GameVars2 word VarRestInterruptSteps is nonzero it counts the rest
     steps in RestInterruptCounter; at that threshold the counter resets and a 1d100 RollDice no greater than
     GameVars2 word VarRestInterruptChance interrupts. It draws the rest line and messages, asks whether to stop
     when a key is pending, and clears its window on exit. Result 1 means interrupted. */
u8 RunRestPeriod(void)
{
  POOL_TRACE("RunRestPeriod");
  u8 Result = 0;
  PCharacter Who = 0;
  u8 FrameGap[5] = {0};
  u8 PartyIndex = 0;
  u8 RestCycleCounter = 0;
  u8 DisplayCounter = 0;
  u8 EndRest = 0;
  u8 Unused = 0;
  Result = 0;
  Unused = 0;
  PartyIndex = FirstPartyIndex;
  Who = PartyListHead;
  while (Who != 0) {
    RestStudyCountdowns[PartyIndex] = 0;
    PartyIndex++;
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  rtl_FillChar((void *)&TimedAffectFlagsFrom0, TimedAffectFlagCount, TimedAffectDue);
  RestCycleCounter = 0;
  DisplayCounter = 0;
  ClearRect(RestWindowLeft, RestWindowTop, RestWindowRight, RestWindowBottom);
  ShowRestTime(0);
  RestWindowActive = 1;
  EndRest = (RestTimeMenu() == 0);
  while (((EndRest == 0)) && ((((((RestTime[4] > 0)) || ((RestTime[3] > 0))) || ((RestTime[2] > 0))) || ((RestTime[1] > 0))))) {
    if (rtl_KeyPressed()) {
      ShowRestTime(0);
      if (AskYesNo(S("\016Stop Resting\077 "), RestTitleColor, RestWordColor, RestHotColor) == 'Y') {
        EndRest = 1;
      } else {
        ClearPromptLine();
      }
    }
    if (EndRest == 0) {
      SpendRestTime(RestMinuteStep, MinutesDigit);
      DisplayCounter++;
      if (DisplayCounter >= RestDisplayInterval) {
        ShowRestTime(0);
        DisplayCounter = 0;
      }
      AdvanceGameClock(RestMinuteStep, MinutesDigit);
      CheckRestHealing();
      AdvanceRestStudies();
      AdvanceRestHour(&RestCycleCounter);
      if ((*FPD(TGameVars (*), GameVars2))[722] > 0) {
        RestInterruptCounter++;
        if (RestInterruptCounter >= (*FPD(TGameVars (*), GameVars2))[722]) {
          RestInterruptCounter = 0;
          if (RollDice(RestInterruptDice, RestInterruptSides) <= (*FPD(TGameVars (*), GameVars2))[723]) {
            ClearCharacterMessage();
            ShowRestTime(0);
            DrawTextAt(RestMessageColumn, RestMessageRow, RestMessageColor, S(" The Party is rudely interrupted!"));
            EndRest = 1;
            Result = 1;
            DelayByGameSpeed();
          }
        }
      }
    }
  }
  ClearRect(RestWindowLeft, RestWindowTop, RestWindowRight, RestWindowBottom);
  RestWindowActive = 0;
  return Result;
}

/* Initialisation part of unit OVL20. */
void init_OVL20(void)
{
  POOL_TRACE("init");
}

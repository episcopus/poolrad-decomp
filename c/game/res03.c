#include "game.h"

/* 08AE:0000. The time of day in hundredths of a second since midnight (Dos.GetTime).
     QUIRK 08AE:0033: Minute * 6000 and Second * 100 are Word products, so the minutes term
     wraps above 10 minutes; only the hours term is a Longint product. */
s32 TimeInHundredths(void)
{
  POOL_TRACE("TimeInHundredths");
  s32 Result = 0;
  u16 Hour = 0;
  u16 Minute = 0;
  u16 Second = 0;
  u16 Sec100 = 0;
  rtl_GetTime(&Hour, &Minute, &Second, &Sec100);
  Result = (((Hour * HundredthsPerHour) + (Minute * HundredthsPerMinute)) + (Second * HundredthsPerSecond)) + Sec100;
  return Result;
}

/* 08AE:006C. Busy-waits Hundredths hundredths of a second on TimeInHundredths. When the clock
     falls back by more than Hundredths (midnight, or the minutes wrap of TimeInHundredths) the wait
     ends at once. */
void WaitHundredths(u16 Hundredths)
{
  POOL_TRACE("WaitHundredths");
  s32 Target = 0;
  s32 Now = 0;
  Target = TimeInHundredths() + Hundredths;
  do {
    Now = TimeInHundredths();
    if (Target - Now > Hundredths) {
      Now = Target + 1;
    }
  } while (!(Now >= Target));
}

/* 08AE:00DC. Plays a sound or tune. Sound SoundStop sets both devices to NoTune and the output
     off, SoundOutputOn turns the output on, SoundQuiet sets both devices to NoTune; any other n
     starts tune n - 1 on the device of SoundMode (SetSpeakerTune or SetTandyTune). Nothing when
     SoundMode is SoundSilent. While SoundDriverIdle is nonzero the timer driver runs only around
     this call: started first, then after BriefSoundTime both devices are silenced and it stops. */
void PlaySound(u16 Sound_)
{
  POOL_TRACE("PlaySound");
  if (SoundMode == SoundSilent) {
    return;
  }
  if (SoundDriverIdle > 0) {
    StartSoundTimer();
  }
  switch (Sound_) {
  case SoundStop:
  {
    SetTandyTune(NoTune);
    SetSpeakerTune(NoTune);
    SetSoundOutput(0);
    break;
  }
  case SoundOutputOn:
  {
    SetSoundOutput(1);
    break;
  }
  case SoundQuiet:
  {
    SetTandyTune(NoTune);
    SetSpeakerTune(NoTune);
    break;
  }
  default:
  {
    switch (SoundMode) {
    case SoundSpeaker:
    {
      SetSpeakerTune((u16)(Sound_ - 1));
      break;
    }
    case SoundTandy:
    {
      SetTandyTune((u16)(Sound_ - 1));
      break;
    }
    }
  }
  }
  if (SoundDriverIdle > 0) {
    WaitHundredths(BriefSoundTime);
    SetTandyTune(NoTune);
    SetSpeakerTune(NoTune);
    StopSoundTimer();
  }
}

/* 08AE:017B. Saves SoundMode in SoundModeBeforePause, then, unless SoundMode is SoundSilent,
     runs the timer driver once to set both devices to NoTune and stops it again. Called by
     res08's initialisation and by ReadGameKey when Ctrl-S resumes the sound. */
void SilenceSound(void)
{
  POOL_TRACE("SilenceSound");
  SoundModeBeforePause = SoundMode;
  if (SoundMode == SoundSilent) {
    return;
  }
  StartSoundTimer();
  SetSpeakerTune(NoTune);
  SetTandyTune(NoTune);
  StopSoundTimer();
}

/* 08AE:01A5. Idle 0 starts the timer driver for good (tunes play in the background); a nonzero
     Idle stops it unless it was already idle, and PlaySound then runs it only around each sound.
     Stores Idle in SoundDriverIdle. Nothing when SoundMode is SoundSilent. Callers pass 100
     (StartGame), 0 and 10 (RemoveCombatant). */
void SetSoundDriverIdle(u16 Idle)
{
  POOL_TRACE("SetSoundDriverIdle");
  if (SoundMode == SoundSilent) {
    return;
  }
  if (Idle > 0) {
    if (SoundDriverIdle == 0) {
      StopSoundTimer();
    }
  } else {
    StartSoundTimer();
  }
  SoundDriverIdle = Idle;
}

/* Initialisation part of unit RES03. */
void init_RES03(void)
{
  POOL_TRACE("init");
}

#include "game.h"

/* 0899:0000. Ends the program. Copies SoundModeBeforePause into SoundMode and calls
     PlaySound(SoundStopAll), the same call as the Ctrl-S pause path, not SilenceSound (the resume
     call at 0899:00A1). What that call does to the sound is not shown here; the sound unit's
     proven stop is 08AE:13B1 (whitepaper 5.14). Then INT 10h function VideoSetMode with
     SavedVideoMode in AL. No writer of SavedVideoMode is in this unit, so where that byte was
     saved is not shown. Then Halt. */
void QuitGame(void)
{
  POOL_TRACE("QuitGame");
  SoundMode = SoundModeBeforePause;
  PlaySound(SoundStopAll);
  Regs.AH = VideoSetMode;
  Regs.AL = SavedVideoMode;
  rtl_Intr(VideoBios, &Regs);
  rtl_Halt(0);
}

/* 0899:0059. The ReadKey of the game: waits for a key and returns a Char. Ctrl-S, when SoundMode
     is not SoundPaused, saves SoundMode in SoundModeBeforePause, calls PlaySound(SoundStopAll) and
     sets SoundMode to SoundPaused. A later Ctrl-S resumes only when SoundMode is already
     SoundPaused and SoundModeBeforePause is ResumeIfSaved0 or ResumeIfSaved1: it copies the saved
     mode back and calls SilenceSound. Any other second Ctrl-S does nothing. When ParamStr(1) is
     STING, Ctrl-D switches DebugMode and Ctrl-C quits. Those tests, and the Ctrl-S test, use the
     first key. Then, unless that key is KeyExtended, every key still waiting is read into Key
     (0899:00E4), so the function returns the last key in the buffer. The 258-byte frame is
     ParamStr's string temporary. */
u8 ReadGameKey(void)
{
  POOL_TRACE("ReadGameKey");
  u8 Result = 0;
  u8 Key = 0;
  u8 ts1[256];
  Key = rtl_ReadKey();
  if (Key == KeyCtrlS) {
    if (SoundMode != SoundPaused) {
      SoundModeBeforePause = SoundMode;
      PlaySound(SoundStopAll);
      SoundMode = SoundPaused;
    } else if (SoundModeBeforePause == ResumeIfSaved0 || SoundModeBeforePause == ResumeIfSaved1) {
      SoundMode = SoundModeBeforePause;
      SilenceSound();
    }
  }
  if (rtl_str_cmp(rtl_paramstr(ts1, 1), S("\005STING")) == 0) {
    if (Key == KeyCtrlD) {
      DebugMode = !DebugMode;
    }
    if (Key == KeyCtrlC) {
      QuitGame();
    }
  }
  if (Key != KeyExtended) {
    while (rtl_KeyPressed()) {
      Key = rtl_ReadKey();
    }
  }
  Result = Key;
  return Result;
}

/* 0899:0104. Meant to throw away every key typed ahead (called before prompts such as the code
     wheel's), but it returns at once. QUIRK 0899:010A: the Exit comes first, so the loop never runs. */
void FlushKeyboard(void)
{
  POOL_TRACE("FlushKeyboard");
  u8 Key = 0;
  return;
  while (rtl_KeyPressed()) {
    Key = ReadGameKey();
  }
}

/* 0899:0122. If a key is waiting, reads it through ReadGameKey and throws the result away, so
     Ctrl-S and the STING keys still run. ReadGameKey's own drain can still consume keys past
     that one. */
void DiscardWaitingKey(void)
{
  POOL_TRACE("DiscardWaitingKey");
  u8 Key = 0;
  if (rtl_KeyPressed()) {
    Key = ReadGameKey();
  }
}

/* Initialisation part of unit RES04. */
void init_RES04(void)
{
  POOL_TRACE("init");
  /* 0899:013C. Empty initialisation: push bp, mov bp, sp, pop bp, retf, then 15 zero bytes of
     paragraph padding. */
}

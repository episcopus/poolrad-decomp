#include "game.h"

/* ovl02:00FD. The code wheel check. Up to MaxAttempts times it picks a wheel record at random,
     clears the question window (DrawWindow), writes the instructions (DrawTextAt), draws the
     record runes as font characters (DrawGlyph: the two runes to match and the third, plus the
     fourth only when the record has one), shows the path pattern as five spaces and the record path
     (DrawTextAt), flushes the keyboard and asks for the code word (ReadInputLine, the line reader
     of res06). A matching answer (the record CodeWord) leaves the routine at once; a wrong one shows
     the failure message (FlashMessageLine), and the third wrong answer ends the program through
     QuitGame. Reads: CodeWheelRecords (the wheel records), Random. Globals: none besides those. Side effect:
     the screen; on the third failure the program halts. */
void CheckCodeWheel(void)
{
  POOL_TRACE("CheckCodeWheel");
  u8 Answer[41] = {0};
  u8 Question = 0;
  u8 Attempt = 0;
  u8 ts1[256];
  {
    if (1 <= MaxAttempts) {
      Attempt = 1;
      for (;;) {
          Question = rtl_Random(WheelEntryCount);
          DrawWindow(1, 1, 0x26, 0x16, 0, 0, S("\000"));
          DrawTextAt(1, 1, LightGreen_OVL02, S("%USE THE TRANSLATION WHEEL TO DECIPHER"));
          DrawTextAt(1, 2, LightGreen_OVL02, S("\016THE CODE WORD."));
          DrawTextAt(1, 5, LightGreen_OVL02, S("#MATCH THE ESPRUAR RUNE (OUTER RING)"));
          DrawGlyph(8, 6, 0xC, 1, (s16)(CodeWheelRecords[Question].OuterRune + RuneCharBase), 0);
          DrawGlyph(9, 6, 0xC, 1, (s16)(CodeWheelRecords[Question].InnerRune + RuneCharBase), 0);
          DrawTextAt(1, 8, LightGreen_OVL02, S("!WITH THE DETHEK RUNE (INNER RING)"));
          DrawGlyph(8, 9, 0xC, 1, (s16)(CodeWheelRecords[Question].ThirdRune + RuneCharBase), 0);
          if (CodeWheelRecords[Question].FourthRune != NoFourthRune) {
            DrawGlyph(9, 9, 0xC, 1, (s16)(CodeWheelRecords[Question].FourthRune + RuneCharBase), 0);
          }
          DrawTextAt(1, 0xB, LightGreen_OVL02, S("&AND READ THE CODE WORD UNDER THE PATH:"));
          DrawTextAt(1, 0xD, LightRed_OVL02, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\005     "), CodeWheelRecords[Question].Path}));
          DrawTextAt(1, 0xE, LightGreen_OVL02, S("$READ FROM THE INSIDE TO THE OUTSIDE."));
          FlushKeyboard();
          rtl_str_assign(Answer, 40, ReadInputLine(ts1, S("\025INPUT THE CODE WORD: "), 13, 6));
          if (rtl_str_cmp(Answer, CodeWheelRecords[Question].CodeWord) == 0) {
            return;
          }
          FlashMessageLine(S("\030Sorry, that's incorrect."), Yellow_OVL02);
        if (Attempt == MaxAttempts) break;
        Attempt++;
      }
    }
  }
  QuitGame();
}

/* Initialisation part of unit OVL02. */
void init_OVL02(void)
{
  POOL_TRACE("init");
  /* Initialisation (ovl02:0359): empty (55 89 E5 5D CB). */
}

#include "game.h"

/* ovl25:0000. Returns line Index of the menu line list List, counting from 0, or nil when the list is
     shorter. Called by ChooseFromList and its nested routines and by ovl16 (packet). */
PMenuLine GetMenuLine(s16 Index, PMenuLine List)
{
  PMenuLine Result = 0;
  PMenuLine Line = 0;
  s16 I = 0;
  I = 0;
  Line = List;
  while (((Line != 0)) && ((I != Index))) {
    Line = (*FPD(TMenuLine (*), Line)).Next;
    I++;
  }
  if (I == Index) {
    Result = Line;
  } else {
    Result = 0;
  }
  return Result;
}

/* ovl25:0067. Returns the number of lines of the menu line list List (0 for nil). Called by
     ChooseFromList. */
s16 CountMenuLines(PMenuLine List)
{
  s16 Result = 0;
  PMenuLine Line = 0;
  s16 N = 0;
  N = 0;
  Line = List;
  while (Line != 0) {
    N++;
    Line = (*FPD(TMenuLine (*), Line)).Next;
  }
  Result = N;
  return Result;
}

typedef struct Frame_ReadPromptChoice {
  String40_RES06 Title;
  String40_RES06 Prompt;
  u8 TitleColor;
  u8 WordColor;
  u8 HotColor;
  u8 ExtKeys;
  u8 Animate;
  u8 (*ExtKey);
  u8 Result;
  s32 Start;
  s32 Unused30;
  s32 Unused80;
  u8 Key;
  u8 J;
  u8 I;
  u8 Done;
  u8 PromptLen;
  u8 WordsCol;
  ReadPromptChoice_TWordSpan Words[20];
  u8 WordCount;
  u8 AcceptsEnter;
} Frame_ReadPromptChoice;

/* ovl25:00CB (nested). Splits Text (the prompt) into Words: every capital letter or digit after
       the first word's start begins a new word whose previous one ends two characters earlier (one
       separator assumed); the last word ends at the end of the text. Sets WordCount. */
static void ReadPromptChoice_SplitPromptWords(struct Frame_ReadPromptChoice *up, const u8 *Text_in)
{
  const u8 *Text = Text_in;
  u8 Count = 0;
  u8 I = 0;
  u8 Len = 0;
  u8 Spare = 0;
  u8 t1;
  rtl_FillChar((void *)&up->Words, 40, 0);
  Count = 1;
  Len = Text[0];
  t1 = Len;
  I = 1;
  if (I <= t1) for (;;) {
    if ((Text[I] >= '0' && Text[I] <= '9') || (Text[I] >= 'A' && Text[I] <= 'Z')) {
      if (up->Words[Count - 1].Start == 0) {
        up->Words[Count - 1].Start = I;
      } else {
        up->Words[Count - 1].Stop = I - 2;
        Count++;
        up->Words[Count - 1].Start = I;
      }
    }
    if (I == t1) break;
    I++;
  }
  up->Words[Count - 1].Stop = Len;
  up->WordCount = Count;
}

/* ovl25:01DA (nested). Draws the prompt's words on row 24 from column WordsCol, one character at a
       time through DrawGlyph: the characters of word Chosen (when HotColor is nonzero) and every
       capital or digit in HotColor, the rest in WordColor; then blanks the row to column 39. */
static void ReadPromptChoice_DrawPromptWords(struct Frame_ReadPromptChoice *up, u8 Chosen)
{
  u8 I = 0;
  u8 t1;
  if (up->PromptLen > 0) {
    t1 = up->PromptLen;
    I = 1;
    if (I <= t1) for (;;) {
      if ((((up->Words[Chosen - 1].Start <= I)) && ((up->Words[Chosen - 1].Stop >= I))) && ((up->HotColor != 0))) {
        DrawGlyph((s16)((up->WordsCol + I) - 1), BottomRow, up->HotColor, 1, up->Prompt[I], 1);
      } else if ((up->Prompt[I] >= '0' && up->Prompt[I] <= '9') || (up->Prompt[I] >= 'A' && up->Prompt[I] <= 'Z')) {
        DrawGlyph((s16)((up->WordsCol + I) - 1), BottomRow, up->HotColor, 1, up->Prompt[I], 1);
      } else {
        DrawGlyph((s16)((up->WordsCol + I) - 1), BottomRow, up->WordColor, 1, up->Prompt[I], 1);
      }
      if (I == t1) break;
      I++;
    }
    if ((s16)(up->WordsCol + up->PromptLen) < LastTextCol) {
      DrawGlyph((s16)(up->WordsCol + up->PromptLen), BottomRow, 0, (s16)(((LastTextCol - up->PromptLen) - up->WordsCol) + 1), Space, 1);
    }
  }
}

/* ovl25:03BD. The prompt line: shows Title in TitleColor at the left of text row 24 and the words of
     Prompt after it, then waits for the player's choice and returns the key. A word is a run starting
     with a capital letter or digit; capitals are drawn in HotColor, other letters in WordColor, and the
     word PromptWordChoice (kept between calls, reset to 1 when out of range) is highlighted in
     HotColor. ',' and '.' step the highlight (wrapping), a capital or digit that starts a word picks
     that word and returns its letter, Space returns ' ', Enter returns #13 when either colour is
     nonzero, Escape returns #0. With ExtKeys nonzero an extended key returns its scan code letter and
     the keypad digits return the scan letter of their key (KeypadScanLetters), both with ExtKey set to
     1; otherwise extended keys are read and ignored. While waiting it animates PictureAnimation when
     Animate (passed to DrawSprite as Direct) or game variable VarAnimateNow is nonzero, and returns
     PromptTimeoutKey when PromptTimeout is above 0 and that many hundredths of a second have passed.
     On return it clears VarAnimateNow and copies ExtKey into LastPromptExtKey. Called by ChooseFromList and AskYesNo and
     by many units (the Temple, the shops, ovl14's area keys).
     QUIRK ovl25:043D: two more clock values (Start plus 30 and plus 80) are computed and never read.
     QUIRK ovl25:0662: a hotkey that is a capital inside a word, not its first letter, searches the
     word spans past their end (the loop has no bound).
     QUIRK ovl25:0530: the timeout counts from the last animation frame, not from the start. */
u8 ReadPromptChoice(const u8 *Title_in, const u8 *Prompt_in, u8 TitleColor, u8 WordColor, u8 HotColor, u8 ExtKeys, u8 Animate, u8 (*ExtKey))
{
  Frame_ReadPromptChoice fr;
  memset(&fr, 0, sizeof fr);
  rtl_str_assign(fr.Title, 40, Title_in);
  rtl_str_assign(fr.Prompt, 40, Prompt_in);
  fr.TitleColor = TitleColor;
  fr.WordColor = WordColor;
  fr.HotColor = HotColor;
  fr.ExtKeys = ExtKeys;
  fr.Animate = Animate;
  fr.ExtKey = ExtKey;
  u8 t1;
  LastPromptExtKey = 0;
  fr.AcceptsEnter = (((fr.WordColor != 0)) || ((fr.HotColor != 0)));
  ReadPromptChoice_SplitPromptWords(&fr, fr.Prompt);
  if (PromptWordChoice > fr.WordCount) {
    PromptWordChoice = 1;
  }
  fr.PromptLen = fr.Prompt[0];
  fr.Key = KeyNone;
  (*fr.ExtKey) = 0;
  fr.Done = 0;
  fr.Start = GameClock();
  fr.Unused30 = GameClock() + 30;
  fr.Unused80 = fr.Unused30 + 50;
  if (fr.Title[0] != 0) {
    DrawTextAt(PromptLeftCol, BottomRow, fr.TitleColor, fr.Title);
  }
  fr.WordsCol = fr.Title[0] + PromptLeftCol;
  ReadPromptChoice_DrawPromptWords(&fr, PromptWordChoice);
  do {
    if ((((((*FPD(TGameVars (*), GameVars))[511] != 0)) || ((fr.Animate != 0)))) && ((PictureAnimation.Current > 0))) {
      DrawSprite(PictureCol, PictureRow, fr.Animate, PictureAnimation.Frames[PictureAnimation.Current - 1].Sprite);
      if (((GameClock() - fr.Start >= PictureAnimation.Frames[PictureAnimation.Current - 1].Delay_ * TicksPerDelay)) || (((*FPD(TGameVars (*), GameVars))[511] != 0))) {
        PictureAnimation.Current++;
        if (PictureAnimation.Current > PictureAnimation.Count) {
          PictureAnimation.Current = 1;
        }
        fr.Start = GameClock();
      }
    }
    if (((PromptTimeout > 0)) && ((GameClock() - fr.Start >= PromptTimeout))) {
      fr.Key = PromptTimeoutKey;
      fr.Done = 1;
    } else if (rtl_KeyPressed()) {
      fr.Key = ReadGameKey();
      if (fr.Key == KeyNone) {
        fr.Key = ReadGameKey();
        if (fr.ExtKeys != 0) {
          (*fr.ExtKey) = 1;
          fr.Done = 1;
        }
      } else {
        switch ((u8)fr.Key) {
        case 0x1B:
        {
          fr.Done = 1;
          fr.Key = KeyNone;
          break;
        }
        case 0x0D:
        {
          if (fr.AcceptsEnter) {
            fr.Key = KeyEnter;
            fr.Done = 1;
          }
          break;
        }
        case ',':
        {
          if (PromptWordChoice == 1) {
            PromptWordChoice = fr.WordCount;
          } else {
            PromptWordChoice--;
          }
          ReadPromptChoice_DrawPromptWords(&fr, PromptWordChoice);
          break;
        }
        case '.':
        {
          if (PromptWordChoice == fr.WordCount) {
            PromptWordChoice = 1;
          } else {
            PromptWordChoice++;
          }
          ReadPromptChoice_DrawPromptWords(&fr, PromptWordChoice);
          break;
        }
        default:
        {
          fr.Key = rtl_upcase(fr.Key);
          if (fr.Key == ' ' || (fr.Key >= '0' && fr.Key <= '9') || (fr.Key >= 'A' && fr.Key <= 'Z')) {
            if (fr.Key == ' ') {
              fr.Done = 1;
            } else {
              t1 = fr.PromptLen;
              fr.I = 1;
              if (fr.I <= t1) for (;;) {
                if (fr.Prompt[fr.I] == fr.Key) {
                  fr.Done = 1;
                  fr.J = 1;
                  while (fr.Words[fr.J - 1].Start != fr.I) {
                    fr.J++;
                  }
                  PromptWordChoice = fr.J;
                  ReadPromptChoice_DrawPromptWords(&fr, PromptWordChoice);
                }
                if (fr.I == t1) break;
                fr.I++;
              }
            }
          }
          if (fr.ExtKeys != 0) {
            if ((fr.Key >= '1' && fr.Key <= '9') || fr.Key == KeypadBackslash) {
              if (fr.Key == KeypadBackslash) {
                fr.Key = KeypadBackslashKey;
              } else {
                fr.Key = KeypadScanLetters[(s16)(fr.Key - 49)];
              }
              (*fr.ExtKey) = 1;
              fr.Done = 1;
            }
          }
        }
        }
      }
    }
  } while (!(fr.Done));
  (*FPD(TGameVars (*), GameVars))[511] = 0;
  fr.Result = fr.Key;
  LastPromptExtKey = (*fr.ExtKey);
  return fr.Result;
}

/* ovl25:06FB. Blanks the prompt line: ClearTextCells over the 40 columns of text row 24. Called by
     the loader (ovl07, ovl11), the area keys and many other units before they draw a new prompt. */
void ClearPromptLine(void)
{
  ClearTextCells(0, BottomRow, 0, TextCols);
}

typedef struct Frame_ChooseFromList {
  String40_RES06 Title;
  String40_RES06 Prompt;
  u8 HeadingColor;
  u8 LineColor;
  u8 HighlightColor;
  s8 Left;
  s8 Top;
  s8 Right;
  s8 Bottom;
  PMenuLine List;
  u8 WithExit;
  u8 (*Redraw);
  s16 (*Choice);
  PMenuLine (*Selected);
  u8 Result;
  u8 Width;
  s16 LineCount;
  u8 ExtKey;
  s16 Height;
  u8 Key;
  String40_RES06 Words;
  u8 HasNext;
  u8 HasPrev;
  PMenuLine Line;
  s16 HeadingCount;
  s16 Total;
} Frame_ChooseFromList;

/* ovl25:0711 (nested). Returns the last heading line among the first Count lines of List; when
       there is none, List itself if its first line is a heading, else nil. Its only caller, DrawListPage,
       stores the result and never reads it. */
static PMenuLine ChooseFromList_LastHeadingBefore(struct Frame_ChooseFromList *up, s16 Count, PMenuLine List)
{
  PMenuLine Result = 0;
  PMenuLine Line = 0;
  PMenuLine Found = 0;
  s16 I = 0;
  I = 0;
  Line = List;
  Found = 0;
  while (((Line != 0)) && ((I < Count))) {
    if ((*FPD(TMenuLine (*), Line)).Flag29 != 0) {
      Found = Line;
    }
    Line = (*FPD(TMenuLine (*), Line)).Next;
    I++;
  }
  if (((Found == 0)) && (((*FPD(TMenuLine (*), List)).Flag29 != 0))) {
    Result = List;
  } else {
    Result = Found;
  }
  return Result;
}

/* ovl25:07A4 (nested). Clears the window and draws the lines from line TopLine on, one per row
       from Top to Bottom, headings in HeadingColor and the others in LineColor, each padded with
       blanks to the window width.
       QUIRK ovl25:07F9: the heading found by LastHeadingBefore is never used. */
static void ChooseFromList_DrawListPage(struct Frame_ChooseFromList *up, s16 TopLine)
{
  PMenuLine Line = 0;
  PMenuLine Heading = 0;
  s8 Row = 0;
  ClearWindow(up->Left, up->Top, up->Right, up->Bottom);
  Line = GetMenuLine(TopLine, up->List);
  Heading = ChooseFromList_LastHeadingBefore(up, TopLine, up->List);
  Row = up->Top;
  while (((Line != 0)) && ((Row <= up->Bottom))) {
    if ((*FPD(TMenuLine (*), Line)).Flag29 != 0) {
      DrawTextAt(up->Left, Row, up->HeadingColor, (*FPD(TMenuLine (*), Line)).Text);
    } else {
      DrawTextAt(up->Left, Row, up->LineColor, (*FPD(TMenuLine (*), Line)).Text);
    }
    if ((*FPD(TMenuLine (*), Line)).Text[0] < up->Width) {
      DrawGlyph((s16)(up->Left + (*FPD(TMenuLine (*), Line)).Text[0]), Row, 0, (s16)(up->Width - (*FPD(TMenuLine (*), Line)).Text[0]), Space, 1);
    }
    Line = (*FPD(TMenuLine (*), Line)).Next;
    Row++;
  }
}

/* ovl25:08D7 (nested). Returns the position of the first non-blank character of Text (the length
       when all but the last are blanks). */
static u8 ChooseFromList_FirstNonBlank(struct Frame_ChooseFromList *up, const u8 *Text_in)
{
  const u8 *Text = Text_in;
  u8 Result = 0;
  u8 I = 0;
  u8 Len = 0;
  I = 1;
  Len = Text[0];
  while (((I < Len)) && ((Text[I] == ' '))) {
    I++;
  }
  Result = I;
  return Result;
}

/* ovl25:0923 (nested). Returns the position of the last non-blank character of Text (1 when all
       are blanks). */
static u8 ChooseFromList_LastNonBlank(struct Frame_ChooseFromList *up, const u8 *Text_in)
{
  const u8 *Text = Text_in;
  u8 Result = 0;
  u8 I = 0;
  I = Text[0];
  while (((I > 1)) && ((Text[I] == ' '))) {
    I--;
  }
  Result = I;
  return Result;
}

/* ovl25:0969 (nested). Redraws the text of line LineNo, without its leading and trailing blanks,
       in HighlightColor at its row of the page (Top plus LineNo minus ListMenuTop). */
static void ChooseFromList_HighlightListLine(struct Frame_ChooseFromList *up, s16 LineNo)
{
  PMenuLine Line = 0;
  u8 First = 0;
  u8 Len = 0;
  u8 t1[256];
  Line = GetMenuLine(LineNo, up->List);
  First = ChooseFromList_FirstNonBlank(up, (*FPD(TMenuLine (*), Line)).Text);
  Len = (ChooseFromList_LastNonBlank(up, (*FPD(TMenuLine (*), Line)).Text) - First) + 1;
  DrawTextAt((s16)((up->Left + First) - 1), (s16)(up->Top + ((s16)(LineNo - ListMenuTop))), up->HighlightColor, rtl_str_copy(t1, (*FPD(TMenuLine (*), Line)).Text, First, Len));
}

/* ovl25:0A08 (nested). Redraws the trimmed text of line LineNo in its own colour (HeadingColor for
       a heading, LineColor otherwise): the highlight is taken off. */
static void ChooseFromList_UnhighlightListLine(struct Frame_ChooseFromList *up, s16 LineNo)
{
  PMenuLine Line = 0;
  u8 First = 0;
  u8 Len = 0;
  u8 t1[256];
  u8 t2[256];
  Line = GetMenuLine(LineNo, up->List);
  First = ChooseFromList_FirstNonBlank(up, (*FPD(TMenuLine (*), Line)).Text);
  Len = (ChooseFromList_LastNonBlank(up, (*FPD(TMenuLine (*), Line)).Text) - First) + 1;
  if ((*FPD(TMenuLine (*), Line)).Flag29 != 0) {
    DrawTextAt((s16)((up->Left + First) - 1), (s16)(up->Top + ((s16)(LineNo - ListMenuTop))), up->HeadingColor, rtl_str_copy(t1, (*FPD(TMenuLine (*), Line)).Text, First, Len));
  } else {
    DrawTextAt((s16)((up->Left + First) - 1), (s16)(up->Top + ((s16)(LineNo - ListMenuTop))), up->LineColor, rtl_str_copy(t2, (*FPD(TMenuLine (*), Line)).Text, First, Len));
  }
}

/* ovl25:0B03 (nested). While line Choice is a heading (at most Height times), moves Choice one
       line down (Down) or up, wrapping inside the page shown and the list. */
static void ChooseFromList_SkipHeadingLines(struct Frame_ChooseFromList *up, u8 Down)
{
  s16 N = 0;
  N = 0;
  if (Down) {
    while (((N < up->Height)) && (((*FPD(TMenuLine (*), GetMenuLine((*up->Choice), up->List))).Flag29 != 0))) {
      N++;
      (*up->Choice)++;
      if ((s16)((ListMenuTop + up->Height) - 1) < (*up->Choice)) {
        (*up->Choice) = ListMenuTop;
      }
      if ((s16)(up->LineCount - 1) < (*up->Choice)) {
        (*up->Choice) = ListMenuTop;
      }
    }
  } else {
    while (((N < up->Height)) && (((*FPD(TMenuLine (*), GetMenuLine((*up->Choice), up->List))).Flag29 != 0))) {
      N++;
      (*up->Choice)--;
      if ((*up->Choice) < ListMenuTop) {
        (*up->Choice) = (ListMenuTop + up->Height) - 1;
      }
      if ((s16)(up->LineCount - 1) < (*up->Choice)) {
        (*up->Choice) = up->LineCount - 1;
      }
    }
  }
}

/* ovl25:0C33 (nested). Turns the page down (Down) or up: moves ListMenuTop by Height (not past the
       last page or the first line), keeps the highlight at the same row of the page, skips headings
       and redraws the page. */
static void ChooseFromList_ScrollListPage(struct Frame_ChooseFromList *up, u8 Down)
{
  s16 RowOnPage = 0;
  RowOnPage = (*up->Choice) - ListMenuTop;
  if (Down) {
    ListMenuTop += up->Height;
    if ((s16)(up->LineCount - up->Height) < ListMenuTop) {
      ListMenuTop = up->LineCount - up->Height;
    }
  } else {
    ListMenuTop -= up->Height;
    if (ListMenuTop < 0) {
      ListMenuTop = 0;
    }
  }
  (*up->Choice) = ListMenuTop + RowOnPage;
  ChooseFromList_SkipHeadingLines(up, Down);
  ChooseFromList_DrawListPage(up, ListMenuTop);
}

/* ovl25:0CC5 (nested). Moves the highlight one line down (Down, the End key) or up (Home), wrapping
       inside the page shown, then skips headings in the same direction. */
static void ChooseFromList_MoveListCursor(struct Frame_ChooseFromList *up, u8 Down)
{
  PMenuLine Spare[2] = {0};
  if (Down) {
    (*up->Choice)++;
    if ((s16)((ListMenuTop + up->Height) - 1) < (*up->Choice)) {
      (*up->Choice) = ListMenuTop;
    }
    if ((s16)(up->LineCount - 1) < (*up->Choice)) {
      (*up->Choice) = ListMenuTop;
    }
  } else {
    (*up->Choice)--;
    if ((*up->Choice) < ListMenuTop) {
      (*up->Choice) = (ListMenuTop + up->Height) - 1;
    }
    if ((s16)(up->LineCount - 1) < (*up->Choice)) {
      (*up->Choice) = up->LineCount - 1;
    }
  }
  ChooseFromList_SkipHeadingLines(up, Down);
}

/* ovl25:0D9A. The list menu: shows the lines of List in the window Left..Right, Top..Bottom (lines
     with Flag29 set are headings: drawn in HeadingColor and skipped by the highlight, the others in
     LineColor), highlights line Choice (0-based) in HighlightColor and asks through ReadPromptChoice
     with Title and Prompt plus " Next", " Prev" (when there are more lines below or above the page)
     and " Exit" (when WithExit is nonzero). Home and End move the highlight, PgUp/PgDn and the P and N
     words turn the page; any other key returns that key with Choice and Selected set to the
     highlighted line; Escape, E and #0 return #0 with Selected nil. The page is redrawn on entry only
     when Redraw is nonzero or ListMenuTop (the first shown line, kept between calls) had to be
     reset; Redraw is cleared. A nil List returns #0 at once with Choice 0 and Selected nil. Called by
     the Temple (HealMenu), the shops (ChooseShopItem) and ovl05, ovl07, ovl15, ovl16, ovl19, ovl21.
     QUIRK ovl25:0E5F: the lines are counted twice (CountMenuLines into LineCount, then a loop into
     Total) and the two counts are used for different checks. */
u8 ChooseFromList(const u8 *Title_in, const u8 *Prompt_in, u8 HeadingColor, u8 LineColor, u8 HighlightColor, s8 Left, s8 Top, s8 Right, s8 Bottom, PMenuLine List, u8 WithExit, u8 (*Redraw), s16 (*Choice), PMenuLine (*Selected))
{
  Frame_ChooseFromList fr;
  memset(&fr, 0, sizeof fr);
  rtl_str_assign(fr.Title, 40, Title_in);
  rtl_str_assign(fr.Prompt, 40, Prompt_in);
  fr.HeadingColor = HeadingColor;
  fr.LineColor = LineColor;
  fr.HighlightColor = HighlightColor;
  fr.Left = Left;
  fr.Top = Top;
  fr.Right = Right;
  fr.Bottom = Bottom;
  fr.List = List;
  fr.WithExit = WithExit;
  fr.Redraw = Redraw;
  fr.Choice = Choice;
  fr.Selected = Selected;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  if (fr.List == 0) {
    (*fr.Choice) = 0;
    (*fr.Selected) = 0;
    fr.Result = KeyNone;
    return fr.Result;
  }
  PromptWordChoice = 1;
  fr.Width = (fr.Right - fr.Left) + 1;
  fr.LineCount = CountMenuLines(fr.List);
  fr.Height = (fr.Bottom - fr.Top) + 1;
  fr.Line = fr.List;
  fr.HeadingCount = 0;
  while (((fr.Line != 0)) && (((*FPD(TMenuLine (*), fr.Line)).Flag29 != 0))) {
    fr.Line = (*FPD(TMenuLine (*), fr.Line)).Next;
    fr.HeadingCount++;
  }
  fr.Line = fr.List;
  fr.Total = 0;
  while (fr.Line != 0) {
    fr.Line = (*FPD(TMenuLine (*), fr.Line)).Next;
    fr.Total++;
  }
  if (ListMenuTop > (*fr.Choice)) {
    ListMenuTop = (*fr.Choice);
    (*fr.Redraw) = 1;
  }
  if (ListMenuTop > fr.Total) {
    ListMenuTop = 0;
    (*fr.Redraw) = 1;
  }
  (*fr.Choice)++;
  ChooseFromList_MoveListCursor(&fr, 0);
  if ((*fr.Redraw) != 0) {
    ChooseFromList_DrawListPage(&fr, ListMenuTop);
  }
  (*fr.Redraw) = 0;
  do {
    ChooseFromList_HighlightListLine(&fr, (*fr.Choice));
    rtl_str_assign(fr.Words, 40, fr.Prompt);
    fr.HasNext = 0;
    fr.HasPrev = 0;
    if ((s16)(fr.LineCount - fr.Height) > ListMenuTop) {
      rtl_str_assign(fr.Words, 40, rtl_str_cat(t1, 2, (const u8 *const[]){fr.Words, S("\005 Next")}));
      fr.HasNext = 1;
    }
    if (ListMenuTop > fr.HeadingCount) {
      rtl_str_assign(fr.Words, 40, rtl_str_cat(t2, 2, (const u8 *const[]){fr.Words, S("\005 Prev")}));
      fr.HasPrev = 1;
    }
    if (fr.WithExit != 0) {
      rtl_str_assign(fr.Words, 40, rtl_str_cat(t3, 2, (const u8 *const[]){fr.Words, S("\005 Exit")}));
    }
    fr.Key = ReadPromptChoice(fr.Title, fr.Words, fr.HeadingColor, fr.LineColor, fr.HighlightColor, 1, 0, &fr.ExtKey);
    ChooseFromList_UnhighlightListLine(&fr, (*fr.Choice));
    if (fr.ExtKey != 0) {
      switch ((u8)fr.Key) {
      case 'G':
      {
        ChooseFromList_MoveListCursor(&fr, 0);
        break;
      }
      case 'O':
      {
        ChooseFromList_MoveListCursor(&fr, 1);
        break;
      }
      case 'I':
      {
        if (fr.HasPrev != 0) {
          ChooseFromList_ScrollListPage(&fr, 0);
        }
        break;
      }
      case 'Q':
      {
        if (fr.HasNext != 0) {
          ChooseFromList_ScrollListPage(&fr, 1);
        }
        break;
      }
      }
    } else {
      switch ((u8)fr.Key) {
      case 'P':
      {
        ChooseFromList_ScrollListPage(&fr, 0);
        break;
      }
      case 'N':
      {
        ChooseFromList_ScrollListPage(&fr, 1);
        break;
      }
      case 0x1B:
      case 'E':
      case 0x00:
      {
        (*fr.Selected) = 0;
        fr.Result = KeyNone;
        return fr.Result;
        break;
      }
      default:
      {
        (*fr.Selected) = GetMenuLine((*fr.Choice), fr.List);
        fr.Result = fr.Key;
        return fr.Result;
      }
      }
    }
  } while (!(0));
  return fr.Result;
}

/* ovl25:10D1. Asks Prompt with the words "Yes No" (the highlight starts on No) through
     ReadPromptChoice until the key is Y or N and returns it; Escape asks again. Called by the Temple
     (AskCastAnyway, ChargeForCure) and ovl08, ovl13, ovl15, ovl16. */
u8 AskYesNo(const u8 *Prompt_in, u8 TitleColor, u8 WordColor, u8 HotColor)
{
  const u8 *Prompt = Prompt_in;
  u8 Result = 0;
  u8 ExtKey = 0;
  u8 Key = 0;
  PromptWordChoice = 2;
  do {
    Key = ReadPromptChoice(Prompt, S("\006Yes No"), TitleColor, WordColor, HotColor, 0, 0, &ExtKey);
  } while (!(Key == KeyYes || Key == KeyNo));
  Result = Key;
  return Result;
}

/* ovl25:1140. Builds a list of Count blank menu lines (at least one) in List: each is a 46-byte
     block from the heap with an empty Text, Flag29 0 and Next linking to the following one. Called by
     the Temple (HealMenu), ovl03 and ovl16. */
void NewMenuList(s16 Count, PMenuLine (*List))
{
  PMenuLine Line = 0;
  s16 I = 0;
  s16 t1;
  (*List) = rtl_getmem(MenuLineBytes);
  (*FPD(TMenuLine (*), (*List))).Next = 0;
  (*FPD(TMenuLine (*), (*List))).Flag29 = 0;
  rtl_str_assign((*FPD(TMenuLine (*), (*List))).Text, 40, S("\000"));
  Line = (*List);
  t1 = Count;
  I = 2;
  if (I <= t1) for (;;) {
    (*FPD(TMenuLine (*), Line)).Next = rtl_getmem(MenuLineBytes);
    Line = (*FPD(TMenuLine (*), Line)).Next;
    (*FPD(TMenuLine (*), Line)).Next = 0;
    (*FPD(TMenuLine (*), Line)).Flag29 = 0;
    rtl_str_assign((*FPD(TMenuLine (*), Line)).Text, 40, S("\000"));
    if (I == t1) break;
    I++;
  }
}

/* ovl25:11F3. Frees every 46-byte line of the list List built by NewMenuList.
     QUIRK ovl25:11F3: List itself is left pointing at the freed first line. */
void FreeMenuList(PMenuLine (*List))
{
  PMenuLine Line = 0;
  PMenuLine Done = 0;
  Line = (*List);
  while (Line != 0) {
    Done = Line;
    Line = (*FPD(TMenuLine (*), Line)).Next;
    rtl_freemem(Done, MenuLineBytes);
  }
}

/* Initialisation part of unit OVL25. */
void init_OVL25(void)
{
}

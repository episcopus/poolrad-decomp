#include "game.h"

/* 0709:0000. Sets the EGA Graphics Controller registers for the picture fill: GC 0..5 to 0
     (set/reset, enable set/reset, colour compare, data rotate, read map select, mode), GC 7 to
     $0F (colour don't care) and GC 8 to $FF (bit mask), then the Sequencer Map Mask (SC 2) to
     MapMaskAll. Port I/O only; no parameters. */
void SetEgaFillRegisters(void)
{
  POOL_TRACE("SetEgaFillRegisters");
  rtl_outp(GcIndex, 0);
  rtl_outp(GcData, 0);
  rtl_outp(GcIndex, 1);
  rtl_outp(GcData, 0);
  rtl_outp(GcIndex, 2);
  rtl_outp(GcData, 0);
  rtl_outp(GcIndex, 3);
  rtl_outp(GcData, 0);
  rtl_outp(GcIndex, 4);
  rtl_outp(GcData, 0);
  rtl_outp(GcIndex, GcMode);
  rtl_outp(GcData, 0);
  rtl_outp(GcIndex, 7);
  rtl_outp(GcData, 0xF);
  rtl_outp(GcIndex, GcBitMask);
  rtl_outp(GcData, 0xFF);
  rtl_outp(SeqIndex, SeqMapMask);
  rtl_outp(SeqData, MapMaskAll);
}

/* 0709:0071. Selects display page Page through the video BIOS: writes AH=5 (INT 10h set active
     display page) and AL=Page into Regs, calls Intr($10), then stores the page's segment
     (Page shl 9 + $A000; one $200-paragraph page) in ActivePageSegment. Called by res08_init. */
void SetActivePage(u8 Page)
{
  POOL_TRACE("SetActivePage");
  Regs.AH = 5;
  Regs.AL = Page;
  rtl_Intr(0x10, &Regs);
  ActivePageSegment = (Page << 9) + 0xA000;
}

/* 0709:00A0. Stores the segment of display page Page (Page shl 9 + $A000) in FillPageSegment: the page
     the rectangle fill writes through. Called by FillPlaneRect and res08_init. */
void SetPageSegment(u8 Page)
{
  POOL_TRACE("SetPageSegment");
  FillPageSegment = (Page << 9) + 0xA000;
}

/* 0709:00B7. Fills a rectangle on one display page: byte columns LeftCol..RightCol and cell rows
     TopRow..BotRow (8 scanlines each), on page Page with the byte Value. It saves the current page
     FillTextPage, points SetPageSegment(Page) at the fill page, sets the EGA registers
     (SetEgaFillRegisters, then the GC mode register to write mode 2), fills scanline by scanline
     with FillChar(Mem[FillPageSegment:DestOff], RightCol - LeftCol + 1, Value) stepping DestOff by 40, then
     restores the GC mode to 0, FillTextPage and its page segment. The Word/LongInt casts keep
     the TopRow * 40 * 8 offset math unsigned. Called by ClearFullScreen, ClearRect and
     ClearWindow. */
void FillPlaneRect(s8 LeftCol, s8 TopRow, s8 RightCol, s8 BotRow, u8 Page, u8 Value)
{
  POOL_TRACE("FillPlaneRect");
  u8 SavedPage = 0;
  u16 DestOff = 0;
  u16 ScanLast = 0;
  u16 Scan = 0;
  SavedPage = FillTextPage;
  DestOff = (((u16)TopRow * 40) * 8) + (s32)LeftCol;
  ScanLast = (((s16)((BotRow - TopRow) + 1)) * 8) - 1;
  SetPageSegment(Page);
  SetEgaFillRegisters();
  rtl_outp(GcIndex, GcMode);
  rtl_outp(GcData, WriteMode2);
  {
    u16 limit = ScanLast;
    if (0 <= limit) {
      Scan = 0;
      for (;;) {
          rtl_FillChar(rtl_mem_ptr(FillPageSegment, DestOff), (s16)((RightCol - LeftCol) + 1), Value);
          DestOff += 0x28;
        if (Scan == limit) break;
        Scan++;
      }
    }
  }
  rtl_outp(GcIndex, GcMode);
  rtl_outp(GcData, 0);
  FillTextPage = SavedPage;
  SetPageSegment(FillTextPage);
}

/* 0709:017C. Loads the game's 1-bit font: DAX block 201 ($C9) of 8X8D1.DAX (177 glyphs
     of 8 bytes each) into the GameFont heap block, then frees the DAX buffer. Called once by
     StartGame after it allocates GameFont. Exits at once when the block is missing (size 0).
     Side effects: the heap and the disk through LoadDaxBlock. */
void LoadGameFont(void)
{
  POOL_TRACE("LoadGameFont");
  u16 BlockSize = 0;
  farptr Block = 0;
  LoadDaxBlock(S("\0058X8d1"), S("\004.dax"), LoadGameFont_FontBlockId, &BlockSize, &Block);
  if (BlockSize == 0) {
    return;
  }
  rtl_Move((void *)&(*FPD(u8 *, Block)), (void *)&(*FPD(TBlock588 (*), GameFont)), BlockSize);
  rtl_freemem(Block, BlockSize);
}

/* 0709:01DF. Draws Count copies of the GameFont glyph Glyph from cell Col rightwards on
     text row Row in Color, one per outer iteration (Col advances). TextSet nonzero cooks Glyph
     through UpCase into the 64-glyph text set (mod 64), else the raw byte indexes the font.
     By VideoAdapter: 0 writes the 8 font rows as byte-swapped 16-bit pixel rows to the two
     text-scanline banks (even scanlines to $B800, odd to $BA00, 4 scanlines per text row);
     1 writes the 8 font bytes to the two EGA display pages (ActivePageSegment/FillPageSegment) through the
     Sequencer Map Mask (masks from EgaPlaneMasks, colour gating); 2 builds two colour nibbles
     per font-bit pair and writes them to all four graphics banks (2 rows per text row, 4 bytes
     per column). Exits at once for out-of-range cells, a nil GameFont, or Count 0. Glyph stays
     Byte in the signature because ovl02 passes Integer expressions and the constant 1 for TextSet
     (a Char or Boolean parameter would not accept those); the Ord(Chr()) bridges compile to
     nothing (proven by tpc probes). QUIRK 0709:021A: with TextSet 0 a Glyph above 176 reads past
     the 177-glyph font block (range checks are off). Side effect: video memory.
     Called by CheckCodeWheel, ovl03, ovl25, ClearTextCells, DrawTextAt and DrawTextRun. */
void DrawGlyph(u8 Col, u8 Row, u8 Color, u8 Count, u8 Glyph, u8 TextSet)
{
  POOL_TRACE("DrawGlyph");
  u8 I = 0;
  u8 Index = 0;
  u16 DestOff = 0;
  u16 FontRow = 0;
  u16 ColBase = 0;
  u16 Acc = 0;
  u8 Pix = 0;
  u8 Bit = 0;
  u8 Mask = 0;
  u8 Bank = 0;
  u8 Line = 0;
  u8 Unused = 0;
  if ((((Col > LastCol)) || ((Row > LastRow))) || ((GameFont == 0))) {
    return;
  }
  if (TextSet != 0) {
    Index = (rtl_upcase((u8)Glyph) % DrawGlyph_CookedGlyphMod);
  } else {
    Index = Glyph;
  }
  {
    u8 limit = Count;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          switch (VideoAdapter) {
          case AdapterCga:
          {
            Color = TextColorMap4[Color];
            DestOff = Row * 4;
            FontRow = 0;
            {
              {
                Line = 0;
                for (;;) {
                    Acc = 0;
                    Mask = DrawGlyph_TopBit;
                    {
                      {
                        Bit = 0;
                        for (;;) {
                            if (((*FPD(TFont (*), GameFont))[Index][FontRow] & Mask) > 0) {
                              Acc = (Acc | ((GlyphPixelMasks[Bit] & GlyphColorPatterns[Color])));
                            }
                            Mask = (s16)((u16)Mask >> 1);
                          if (Bit == 7) break;
                          Bit++;
                        }
                      }
                    }
                    WordPlane0[DestOff][Col] = rtl_swap(Acc);
                    FontRow++;
                    Acc = 0;
                    Mask = DrawGlyph_TopBit;
                    {
                      {
                        Bit = 0;
                        for (;;) {
                            if (((*FPD(TFont (*), GameFont))[Index][FontRow] & Mask) > 0) {
                              Acc = (Acc | ((GlyphPixelMasks[Bit] & GlyphColorPatterns[Color])));
                            }
                            Mask = (s16)((u16)Mask >> 1);
                          if (Bit == 7) break;
                          Bit++;
                        }
                      }
                    }
                    WordPlane1[DestOff][Col] = rtl_swap(Acc);
                    FontRow++;
                    DestOff++;
                  if (Line == 3) break;
                  Line++;
                }
              }
            }
            break;
          }
          case AdapterEga:
          {
            DestOff = ((Row * 8) * DrawGlyph_GraphStride) + Col;
            rtl_outp(SeqIndex, SeqMapMask);
            {
              {
                Line = 0;
                for (;;) {
                    {
                      {
                        Bit = 0;
                        for (;;) {
                            rtl_outp(SeqData, EgaPlaneMasks[(s16)(3 - Bit)]);
                            if (((EgaPlaneMasks[(s16)(3 - Bit)] & Color)) > 0) {
                              rtl_poke8(ActivePageSegment, DestOff, (*FPD(TFont (*), GameFont))[Index][Line]);
                              rtl_poke8(FillPageSegment, DestOff, (*FPD(TFont (*), GameFont))[Index][Line]);
                            } else {
                              rtl_poke8(ActivePageSegment, DestOff, 0);
                              rtl_poke8(FillPageSegment, DestOff, 0);
                            }
                          if (Bit == 3) break;
                          Bit++;
                        }
                      }
                    }
                    DestOff += DrawGlyph_GraphStride;
                  if (Line == 7) break;
                  Line++;
                }
              }
            }
            rtl_outp(SeqData, DrawGlyph_MapMaskRestore);
            break;
          }
          case AdapterTandy:
          {
            /* QUIRK 0709:047B: the names of DestOff and FontRow are the other way round in this
               mode: DestOff holds the font row and FontRow the graph row of the destination (the
               slots are fixed by the original frame). */
            DestOff = 0;
            FontRow = Row * 2;
            ColBase = Col * 4;
            {
              {
                Line = 0;
                for (;;) {
                    {
                      {
                        Bank = 0;
                        for (;;) {
                            Mask = DrawGlyph_TopBit;
                            {
                              {
                                Bit = 0;
                                for (;;) {
                                    if (((*FPD(TFont (*), GameFont))[Index][DestOff] & Mask) > 0) {
                                      Pix = Color << 4;
                                    } else {
                                      Pix = 0;
                                    }
                                    Mask = (s16)((u16)Mask >> 1);
                                    if (((*FPD(TFont (*), GameFont))[Index][DestOff] & Mask) > 0) {
                                      Pix = (Pix | Color);
                                    }
                                    Mask = (s16)((u16)Mask >> 1);
                                    switch (Bank) {
                                    case 0:
                                    {
                                      GraphPlane0[FontRow][(u16)(Bit + ColBase)] = Pix;
                                      break;
                                    }
                                    case 1:
                                    {
                                      GraphPlane1[FontRow][(u16)(Bit + ColBase)] = Pix;
                                      break;
                                    }
                                    case 2:
                                    {
                                      GraphPlane2[FontRow][(u16)(Bit + ColBase)] = Pix;
                                      break;
                                    }
                                    case 3:
                                    {
                                      GraphPlane3[FontRow][(u16)(Bit + ColBase)] = Pix;
                                      break;
                                    }
                                    }
                                  if (Bit == 3) break;
                                  Bit++;
                                }
                              }
                            }
                            DestOff++;
                          if (Bank == 3) break;
                          Bank++;
                        }
                      }
                    }
                    FontRow++;
                  if (Line == 1) break;
                  Line++;
                }
              }
            }
            break;
          }
          }
          Col++;
        if (I == limit) break;
        I++;
      }
    }
  }
}

/* 0709:05EB. Draws Count space glyphs (GlyphSpace) in Color from cell Col of text row Row, that
     is, clears Count cells of a row to the background; nothing when the cell is off the 40 by 25
     screen. QUIRK 0709:05EE, 05FA: the Byte parameters are also compared below 0, which is never
     true; the compiler keeps the compares. Called by
     ReadAmount, ClearPromptLine, ReadInputLine, ShowMessageLine (row 24, 40 cells) and FlashMessageLine. */
void ClearTextCells(u8 Col, u8 Row, u8 Color, u8 Count)
{
  POOL_TRACE("ClearTextCells");
  if (((((Col < 0)) || ((Col > LastCol))) || ((Row < 0))) || ((Row > LastRow))) {
    return;
  }
  DrawGlyph(Col, Row, Color, Count, GlyphSpace, 1);
}

/* 0709:0626. Draws Text in Color from cell Col of text row Row, one DrawGlyph per character
     (cooked through UpCase into the 64-glyph text set), advancing Col; nothing when Col is past
     column 39. QUIRK 0709:0647: Row is also tested against LastCol (39), not LastRow (24);
     DrawGlyph then skips rows past 24, and characters past column 39. Called
     by ShowMessageLine (row 24), ShowCredits, CheckCodeWheel, StartGame and many menus. */
void DrawTextAt(u8 Col, u8 Row, u8 Color, const u8 *Text_in)
{
  POOL_TRACE("DrawTextAt");
  const u8 *Text = Text_in;
  u8 Len = 0;
  u8 I = 0;
  if (((Col > LastCol)) || ((Row > LastCol))) {
    return;
  }
  Len = Text[0];
  {
    u8 limit = Len;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          DrawGlyph(Col, Row, Color, 1, Text[I], 1);
          Col++;
        if (I == limit) break;
        I++;
      }
    }
  }
}

typedef struct Frame_ShowPagedText {
  u8 Left;
  u8 Top;
  u8 Right;
  u8 Bottom;
  u8 Color;
  u8 ClearFirst;
  u8 Text[256];
  u8 Len;
  u8 Width;
  u8 WordStart;
  u8 WordEnd;
  u8 Unused;
} Frame_ShowPagedText;

/* 0709:06A7. Draws Text[WordStart..WordEnd] glyph by glyph through DrawGlyph at (GlyphCol,
       GlyphRow) in Color, waiting the Crt delay after each glyph when DelayPerGlyph is set,
       advancing WordStart and GlyphCol. Nested in ShowPagedText. */
static void ShowPagedText_DrawTextRun(struct Frame_ShowPagedText *up)
{
  while (up->WordStart <= up->WordEnd) {
    DrawGlyph(GlyphCol, GlyphRow, up->Color, 1, up->Text[up->WordStart], 1);
    if (DelayPerGlyph != 0) {
      rtl_Delay((s16)(GameSpeed * 10));
    }
    up->WordStart++;
    GlyphCol++;
  }
}

/* 0709:0714. Skips blank Text chars while WordStart stays below Len. Nested in ShowPagedText. */
static void ShowPagedText_SkipSpaces(struct Frame_ShowPagedText *up)
{
  while (((up->WordStart < up->Len)) && ((up->Text[up->WordStart] == ' '))) {
    up->WordStart++;
  }
}

/* 0709:0768. Shows Text with word wrap in the Left..Right by Top..Bottom rectangle, paging
     with 'Press any key to continue' when the GlyphRow cursor passes Bottom. The Text value
     parameter (which the compiler materializes to a hidden stack copy on entry, the StrLCopy
     at 076F) is scanned word by word: leading BreakChars are skipped, the word run stops
     at a blank or a BreakChar, trailing BreakChars (Text[WordEnd + 1], 0709:08C9) are absorbed,
     and the word is drawn when (WordEnd - WordStart) + GlyphCol still fits in Right, else a new
     line starts. Out-of-range coordinates exit at once, as does empty text. A nonzero ClearFirst
     clears the rectangle first. The GlyphCol/GlyphRow cursor is kept inside the rectangle, reset
     to (Left, Top) when it leaves. Color passes through to the glyph drawer. Width is computed
     but never read. QUIRK 0709:0795: Bottom is tested against LastCol (39), not LastRow (24).
     QUIRK 0709:0919: the (WordEnd - WordStart) + GlyphCol = Right and Text[WordEnd] = ' ' test is
     dead: the enclosing test already took (WordEnd - WordStart) + GlyphCol > Right. Side effects:
     video memory, the keyboard on paging. Called by the menu, shop, temple, credit and script
     screens.
     06A7 draws the Text[WordStart..WordEnd] run glyph by glyph at advancing GlyphCol with the Crt
     delay; 0714 skips blank Text chars while WordStart stays below Len. Both are nested (they
     reach the parent frame through the frame link, push bp; push cs; call) and get L2 with their
     parent. */
void ShowPagedText(u8 Left, u8 Top, u8 Right, u8 Bottom, u8 Color, u8 ClearFirst, const u8 *Text_in)
{
  POOL_TRACE("ShowPagedText");
  Frame_ShowPagedText fr;
  memset(&fr, 0, sizeof fr);
  fr.Left = Left;
  fr.Top = Top;
  fr.Right = Right;
  fr.Bottom = Bottom;
  fr.Color = Color;
  fr.ClearFirst = ClearFirst;
  rtl_str_assign(fr.Text, 255, Text_in);
  if (((((fr.Left > LastCol)) || ((fr.Top > LastRow))) || ((fr.Right > LastCol))) || ((fr.Bottom > LastCol))) {
    return;
  }
  if (((((GlyphCol < fr.Left)) || ((GlyphCol > fr.Right))) || ((GlyphRow < fr.Top))) || ((GlyphRow > fr.Bottom))) {
    GlyphCol = fr.Left;
    GlyphRow = fr.Top;
  }
  if (fr.ClearFirst != 0) {
    ClearRect(fr.Left, fr.Top, fr.Right, fr.Bottom);
    GlyphCol = fr.Left;
    GlyphRow = fr.Top;
  }
  fr.WordStart = 1;
  fr.Len = fr.Text[0];
  if (fr.Len == 0) {
    return;
  }
  fr.Width = (fr.Right - fr.Left) + 1;
  do {
    fr.WordEnd = fr.WordStart;
    while (((fr.WordEnd < fr.Len)) && (rtl_set_in_at(BreakChars, 4, 4, fr.Text[fr.WordEnd]))) {
      fr.WordEnd++;
    }
    while ((((fr.WordEnd < fr.Len)) && !(rtl_set_in_at(BreakChars, 4, 4, fr.Text[fr.WordEnd]))) && ((fr.Text[fr.WordEnd] != ' '))) {
      fr.WordEnd++;
    }
    if (fr.Text[fr.WordEnd] != ' ') {
      while ((((s16)(fr.WordEnd + 1) < fr.Len)) && (rtl_set_in_at(BreakChars, 4, 4, fr.Text[(s16)(fr.WordEnd + 1)]))) {
        fr.WordEnd++;
      }
    }
    if ((s16)(((s16)(fr.WordEnd - fr.WordStart)) + GlyphCol) > fr.Right) {
      if ((((s16)(((s16)(fr.WordEnd - fr.WordStart)) + GlyphCol) == fr.Right)) && ((fr.Text[fr.WordEnd] == ' '))) {
        fr.WordEnd--;
        ShowPagedText_DrawTextRun(&fr);
      }
      GlyphCol = fr.Left;
      GlyphRow++;
      ShowPagedText_SkipSpaces(&fr);
      if (GlyphRow > fr.Bottom) {
        if (fr.WordStart < fr.Len) {
          GlyphCol = fr.Left;
          GlyphRow = fr.Top;
          ShowMessageLine(ShowPagedText_MoreKeyColor, S("\031Press any key to continue"));
          FlushKeyboard();
          ClearRect(fr.Left, fr.Top, fr.Right, fr.Bottom);
          ShowPagedText_DrawTextRun(&fr);
        }
      }
    } else {
      ShowPagedText_DrawTextRun(&fr);
    }
  } while (!(fr.WordStart > fr.Len));
  if (GlyphCol > fr.Right) {
    GlyphCol = fr.Left;
    GlyphRow++;
  }
}

/* 0709:09E3. The line reader: shows Prompt in Color on the bottom row (BottomRow) and lets the
     player type up to MaxLen characters after it, echoed in white (EchoColor 15): ' '..'z' are
     added, Backspace removes the last one; Enter or Esc ends. Returns the line in upper case (Esc
     returns what was typed too). The row is cleared at the end. CheckCodeWheel asks for the code
     word with it (prompt 'INPUT THE CODE WORD: '). */
u8 *ReadInputLine(u8 *Result_out, const u8 *Prompt_in, u8 Color, u8 MaxLen)
{
  POOL_TRACE("ReadInputLine");
  const u8 *Prompt = Prompt_in;
  u8 *Result = Result_out;
  u8 Col = 0;
  u8 Line[256] = {0};
  u8 Key = 0;
  s32 t1;
  u8 ts1[256];
  u8 ts2[256];
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Prompt);
  Col = Prompt[0];
  rtl_str_assign(Line, 255, S("\000"));
  do {
    Key = ReadGameKey();
    t1 = (u8)Key;
    if ((t1 >= 32 && t1 <= 122)) {
      if (Line[0] < MaxLen) {
        rtl_str_assign(Line, 255, rtl_str_cat(ts2, 2, (const u8 *const[]){Line, rtl_str_char(ts1, Key)}));
        Col++;
        DrawTextAt(Col, BottomRow, ReadInputLine_EchoColor, rtl_str_char(ts1, Key));
      }
    } else if (t1 == 8) {
      if (Line[0] > 0) {
        rtl_str_assign(Line, 255, rtl_str_copy(ts1, Line, 1, (s16)(Line[0] - 1)));
        ClearTextCells(Col, BottomRow, 0, 1);
        Col--;
      }
    }
  } while (!(((Key == ReadInputLine_KeyEnter)) || ((Key == ReadInputLine_KeyEsc))));
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  {
    u8 limit = Line[0];
    if (1 <= limit) {
      Col = 1;
      for (;;) {
          Line[Col] = rtl_upcase(Line[Col]);
        if (Col == limit) break;
        Col++;
      }
    }
  }
  rtl_str_assign(Result, 40, Line);
  return Result;
}

/* 0709:0B66. Asks for a number on the bottom line: reads up to 6 characters with
     ReadInputLine (Prompt in Color) until Val accepts them as a number from 0 to 65536, and
     returns it as a Word. QUIRK 0709:0BBF: 65536 itself is accepted and returns 0. Called by
     ReadNumberCommand. */
u16 ReadNumber(const u8 *Prompt_in, u8 Color)
{
  POOL_TRACE("ReadNumber");
  const u8 *Prompt = Prompt_in;
  u16 Result = 0;
  s32 Value = 0;
  String40_RES06 Answer = {0};
  s16 Code = 0;
  u8 ts1[256];
  do {
    rtl_str_assign(Answer, 40, ReadInputLine(ts1, Prompt, Color, ReadNumber_MaxDigits));
    rtl_str_val(Answer, &Value, 4, 1, &Code);
    if (((Code == 0)) && ((((Value > 65536)) || ((Value < 0))))) {
      Code = 1;
    }
  } while (!(Code == 0));
  Result = Value;
  return Result;
}

/* 0709:0BF5. Shows Text in Color on the bottom row (BottomRow): clears the row's ScreenCols
     cells (ClearTextCells), writes the text (DrawTextAt) and waits for a key; the key is read
     through ReadGameKey and discarded (the local Key is assigned and never read, QUIRK 0709:0C36).
     Returns nothing. Called from the paging prompt, the menus and the credit and temple screens
     (twelve call sites). */
void ShowMessageLine(u8 Color, const u8 *Text_in)
{
  POOL_TRACE("ShowMessageLine");
  const u8 *Text = Text_in;
  u8 Key = 0;
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Text);
  Key = ReadGameKey();
}

/* 0709:0C3F. The game clock in hundredths of a second: reads the DOS time (GetTime) and returns
     Hour * 360000 + Minute * 6000 + Second * 100 + Sec100. Hour * 360000 is a LongInt multiply;
     Minute * 6000 is a Word multiply, so a minute from 11 up (11 * 6000 = 66000) wraps by 65536 per
     overflowed minute and the clock falls back within the hour (QUIRK 0709:0C75); Second * 100 can
     never overflow (at most 5900), so 0709:0C85 is harmless. Callers compare deadlines with
     GameClock >= Limit, so a wrap can miss a deadline set just before it or pass one at once.
     Called by WaitKeyOrTimeout, ShowTitleScreen, AnimateFinalPicture and ReadPromptChoice. */
s32 GameClock(void)
{
  POOL_TRACE("GameClock");
  s32 Result = 0;
  u16 Hour = 0;
  u16 Minute = 0;
  u16 Second = 0;
  u16 Sec100 = 0;
  rtl_GetTime(&Hour, &Minute, &Second, &Sec100);
  Result = (((Hour * 360000) + (Minute * 6000)) + (Second * 100)) + Sec100;
  return Result;
}

/* 0709:0CAB. Clears the whole screen to 0 by video adapter (the VideoAdapter global):
     0 fills the two text-scanline banks ($BA00 then $B800), 1 draws the full 40 by 25 cell screen
     through FillPlaneRect on display pages 0 and 1, 2 fills the four graphics banks
     ($B800/$BA00/$BC00/$BE00). Called by ovl19. */
void ClearFullScreen(void)
{
  POOL_TRACE("ClearFullScreen");
  switch (VideoAdapter) {
  case AdapterCga:
  {
    rtl_FillChar((void *)&TextPlane1, ClearFullScreen_BankBytes, 0);
    rtl_FillChar((void *)&TextPlane0, ClearFullScreen_BankBytes, 0);
    break;
  }
  case AdapterEga:
  {
    FillPlaneRect(0, 0, LastCol, LastRow, 0, 0);
    FillPlaneRect(0, 0, LastCol, LastRow, 1, 0);
    break;
  }
  case AdapterTandy:
  {
    rtl_FillChar((void *)&GraphPlane0, ClearFullScreen_BankBytes, 0);
    rtl_FillChar((void *)&GraphPlane1, ClearFullScreen_BankBytes, 0);
    rtl_FillChar((void *)&GraphPlane2, ClearFullScreen_BankBytes, 0);
    rtl_FillChar((void *)&GraphPlane3, ClearFullScreen_BankBytes, 0);
    break;
  }
  }
}

/* 0709:0D68. Shows Text in Color on the bottom line (row 24) for a moment: clears the row
     (ClearTextCells), writes the text (DrawTextAt), waits DelayByGameSpeed and clears the row again;
     no key is waited for, unlike ShowMessageLine. CheckCodeWheel shows a wrong code word with it,
     ovl14 'Not Here' and the river's stench, in colour 14. */
void FlashMessageLine(const u8 *Text_in, u8 Color)
{
  POOL_TRACE("FlashMessageLine");
  const u8 *Text = Text_in;
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Text);
  DelayByGameSpeed();
  ClearTextCells(0, BottomRow, 0, ScreenCols);
}

/* 0709:0DBE. A delay of GameSpeed * 225 milliseconds (Crt.Delay): 225 milliseconds per GameSpeed
     step. No parameters. Called while
     drawing many screens (ovl03, ovl10, ovl12, ovl13, ovl18, ovl19, ovl20). */
void DelayByGameSpeed(void)
{
  POOL_TRACE("DelayByGameSpeed");
  rtl_Delay((s16)(GameSpeed * 225));
}

/* 0709:0DD3. Clears the Left..Right by Top..Bottom rectangle to 0 by video adapter (the
     VideoAdapter global), the Byte-coordinate twin of ClearWindow: 0 fills the text-scanline
     rows Top*4..Bottom*4+3 on both text banks, 1 draws the rectangle through FillPlaneRect on
     display pages 0 and 1, 2 fills the graphics rows Top*2..Bottom*2+1 on all four graphics
     banks. Called by the menu screens (HealMenu, VisitTemple, ShopMain), ShowEndingNarrative
     and others. Side effect: video memory. */
void ClearRect(s8 Left, s8 Top, s8 Right, s8 Bottom)
{
  POOL_TRACE("ClearRect");
  s16 TopCode = 0;
  s16 BottomCode = 0;
  s16 LeftCode = 0;
  s16 Width = 0;
  u16 Row = 0;
  switch (VideoAdapter) {
  case AdapterCga:
  {
    TopCode = Top * ClearRect_ScanlinesPerTextRow;
    BottomCode = (Bottom * ClearRect_ScanlinesPerTextRow) + ClearRect_LastTextScanline;
    Width = ((s16)((Right - Left) + 1)) * ClearRect_BytesPerTextColumn;
    {
      u16 limit = BottomCode;
      u16 first = TopCode;
      if (first <= limit) {
        Row = first;
        for (;;) {
            rtl_FillChar((void *)&TextPlane0[Row][(s16)(Left * ClearRect_BytesPerTextColumn)], Width, 0);
            rtl_FillChar((void *)&TextPlane1[Row][(s16)(Left * ClearRect_BytesPerTextColumn)], Width, 0);
          if (Row == limit) break;
          Row++;
        }
      }
    }
    break;
  }
  case AdapterEga:
  {
    FillPlaneRect(Left, Top, Right, Bottom, 0, 0);
    FillPlaneRect(Left, Top, Right, Bottom, 1, 0);
    break;
  }
  case AdapterTandy:
  {
    TopCode = Top * ClearRect_GraphRowsPerTextRow;
    BottomCode = (Bottom * ClearRect_GraphRowsPerTextRow) + ClearRect_LastGraphRow;
    LeftCode = Left * ClearRect_BytesPerGraphColumn;
    Width = ((s16)((Right - Left) + 1)) * ClearRect_BytesPerGraphColumn;
    {
      u16 limit = BottomCode;
      u16 first = TopCode;
      if (first <= limit) {
        Row = first;
        for (;;) {
            rtl_FillChar((void *)&GraphPlane0[Row][LeftCode], Width, 0);
            rtl_FillChar((void *)&GraphPlane1[Row][LeftCode], Width, 0);
            rtl_FillChar((void *)&GraphPlane2[Row][LeftCode], Width, 0);
            rtl_FillChar((void *)&GraphPlane3[Row][LeftCode], Width, 0);
          if (Row == limit) break;
          Row++;
        }
      }
    }
    break;
  }
  }
}

/* Initialisation part of unit RES06. */
void init_RES06(void)
{
  POOL_TRACE("init");
}

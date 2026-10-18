#include "game.h"

/* 03F1:0000. Draws the frame around a window: the four corner tiles
     (TileBase + TileCorner), the top and bottom edges (TileBase + TileHorizontal) and the
     left and right edges (TileBase + TileVertical), with TileBase from FrameSet. The frame
     extends one cell past the window on every side (Dec/Inc first), so the coordinates are
     ShortInt and can reach -1. Drawn through Put8x8Symbol; side effect: the screen. Called by
     DrawWindow. */
void DrawWindowFrame(s8 LeftCol, s8 TopRow, s8 RightCol, s8 BottomRow_, u8 FrameSet)
{
  POOL_TRACE("DrawWindowFrame");
  s8 Edge = 0;
  u16 TileBase = 0;
  LeftCol--;
  TopRow--;
  RightCol++;
  BottomRow_++;
  TileBase = (FrameSet * TilesPerFrameSet) + FirstFrameTile;
  Put8x8Symbol(LeftCol, TopRow, (u16)(TileBase + TileCorner), 0, 0);
  Put8x8Symbol(RightCol, TopRow, (u16)(TileBase + TileCorner), 0, 0);
  Put8x8Symbol(LeftCol, BottomRow_, (u16)(TileBase + TileCorner), 0, 0);
  Put8x8Symbol(RightCol, BottomRow_, (u16)(TileBase + TileCorner), 0, 0);
  {
    s8 limit = (s16)(RightCol - 1);
    s8 first = (s16)(LeftCol + 1);
    if (first <= limit) {
      Edge = first;
      for (;;) {
          Put8x8Symbol(Edge, TopRow, (u16)(TileBase + TileHorizontal), 0, 0);
          Put8x8Symbol(Edge, BottomRow_, (u16)(TileBase + TileHorizontal), 0, 0);
        if (Edge == limit) break;
        Edge++;
      }
    }
  }
  {
    s8 limit = (s16)(BottomRow_ - 1);
    s8 first = (s16)(TopRow + 1);
    if (first <= limit) {
      Edge = first;
      for (;;) {
          Put8x8Symbol(LeftCol, Edge, (u16)(TileBase + TileVertical), 0, 0);
          Put8x8Symbol(RightCol, Edge, (u16)(TileBase + TileVertical), 0, 0);
        if (Edge == limit) break;
        Edge++;
      }
    }
  }
}

/* 03F1:0137. Clears the window rectangle LeftCol..RightCol by TopRow..BottomRow to 0, by
     video adapter (the VideoAdapter global): 0 fills two text-scanline planes (VideoText0/1),
     1 draws through FillPlaneRect twice, 2 fills four graphics planes (VideoGrf0..3).
     The coordinates are ShortInt (sign-extended to Integer); Row stays Word (the for-loop
     exit test is unsigned). Side effect: video memory. Called by DrawWindow. */
void ClearWindow(s8 LeftCol, s8 TopRow, s8 RightCol, s8 BottomRow_)
{
  POOL_TRACE("ClearWindow");
  s16 TopCode = 0;
  s16 BottomCode = 0;
  s16 LeftCode = 0;
  s16 Width = 0;
  u16 Row = 0;
  switch (VideoAdapter) {
  case AdapterCga:
  {
    TopCode = TopRow * ScanlinesPerTextRow;
    BottomCode = (BottomRow_ * ScanlinesPerTextRow) + LastTextScanline;
    Width = ((s16)((RightCol - LeftCol) + 1)) * BytesPerTextColumn;
    {
      u16 limit = BottomCode;
      u16 first = TopCode;
      if (first <= limit) {
        Row = first;
        for (;;) {
            rtl_FillChar((void *)&VideoText0[Row][(s16)(LeftCol * BytesPerTextColumn)], Width, 0);
            rtl_FillChar((void *)&VideoText1[Row][(s16)(LeftCol * BytesPerTextColumn)], Width, 0);
          if (Row == limit) break;
          Row++;
        }
      }
    }
    break;
  }
  case AdapterEga:
  {
    FillPlaneRect(LeftCol, TopRow, RightCol, BottomRow_, 0, 0);
    FillPlaneRect(LeftCol, TopRow, RightCol, BottomRow_, 1, 0);
    break;
  }
  case AdapterTandy:
  {
    TopCode = TopRow * GraphRowsPerTextRow;
    BottomCode = (BottomRow_ * GraphRowsPerTextRow) + LastGraphRow;
    LeftCode = LeftCol * BytesPerGraphColumn;
    Width = ((s16)((RightCol - LeftCol) + 1)) * BytesPerGraphColumn;
    {
      u16 limit = BottomCode;
      u16 first = TopCode;
      if (first <= limit) {
        Row = first;
        for (;;) {
            rtl_FillChar((void *)&VideoGrf0[Row][LeftCode], Width, 0);
            rtl_FillChar((void *)&VideoGrf1[Row][LeftCode], Width, 0);
            rtl_FillChar((void *)&VideoGrf2[Row][LeftCode], Width, 0);
            rtl_FillChar((void *)&VideoGrf3[Row][LeftCode], Width, 0);
          if (Row == limit) break;
          Row++;
        }
      }
    }
    break;
  }
  }
}

/* 03F1:02E8. Draws a titled window for dialogs and screens: clears it (ClearWindow), draws
     its frame (DrawWindowFrame) and centres Text on TopRow in colour TextColor
     (DrawTextAt, skipped when Text is empty). LeftCol/TopRow/RightCol/BottomRow are the
     window's text columns and rows; FrameSet selects the frame tiles. Text is a String40
     value parameter: the compiler copies it to a hidden stack temporary on entry (the
     StrLCopy at 02EE, limit $28), and Length and the 0626 call read that temporary
     ([bp-$29]). Side effect: the screen. Called from ovl01/02/03/04/05/06 and res12. */
void DrawWindow(s8 LeftCol, s8 TopRow, s8 RightCol, s8 BottomRow_, u8 FrameSet, u8 TextColor_, const u8 *Text_in)
{
  POOL_TRACE("DrawWindow");
  const u8 *Text = Text_in;
  ClearWindow(LeftCol, TopRow, RightCol, BottomRow_);
  DrawWindowFrame(LeftCol, TopRow, RightCol, BottomRow_, FrameSet);
  if (Text[0] != 0) {
    DrawTextAt((((s16)((LeftCol + RightCol) - Text[0])) / 2), TopRow, TextColor_, Text);
  }
}

/* Initialisation part of unit RES09. */
void init_RES09(void)
{
  POOL_TRACE("init");
}

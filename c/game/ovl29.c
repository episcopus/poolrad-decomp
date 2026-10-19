#include "game.h"

/* ovl29:0000. Draws the overhead wall map in the view instead of the 3D walls (DrawWallView calls it
     while WallMapMode is nonzero): an 11x11 window of the 16x16 area map, placed so that the party cell
     (Col, Row) is centred where the map allows (the window's left column and top row are clamped to
     0..5), one 8x8 symbol per cell: WallSymbols plus 1, 2, 4 and 8 for a wall on the north, east,
     south and west side (WallIdAt nonzero). Then the party arrow, PartyArrow + Dir div 2 (Dir 0, 2,
     4, 6), goes on the party's cell, and StepDisplay shows the result. The map's symbols go through
     Put8x8Symbol with Direct 1, Attr 0. QUIRK ovl29:0003: the frame holds 256 more bytes that no code
     uses (Unused). The map placed a second routine at ovl29:0143; it is this routine's tail. */
void DrawWallMap(s8 Col, s8 Row, u8 Dir)
{
  POOL_TRACE("DrawWallMap");
  s8 PartyCol = 0;
  s8 PartyRow = 0;
  s8 ViewCol = 0;
  s8 ViewRow = 0;
  s8 LeftCol = 0;
  s8 TopRow = 0;
  s8 MapCol = 0;
  s8 MapRow = 0;
  u16 Symbol = 0;
  u8 Unused[256] = {0};
  LeftCol = Col - MapWindowHalf;
  if (LeftCol < 0) {
    LeftCol = 0;
  }
  if (LeftCol > MapWindowHalf) {
    LeftCol = MapWindowHalf;
  }
  PartyCol = Col - LeftCol;
  TopRow = Row - MapWindowHalf;
  if (TopRow < 0) {
    TopRow = 0;
  }
  if (TopRow > MapWindowHalf) {
    TopRow = MapWindowHalf;
  }
  PartyRow = Row - TopRow;
  {
    if (0 <= ViewLast) {
      ViewRow = 0;
      for (;;) {
          MapRow = ViewRow + TopRow;
          {
            if (0 <= ViewLast) {
              ViewCol = 0;
              for (;;) {
                  MapCol = ViewCol + LeftCol;
                  Symbol = WallSymbols;
                  if (WallIdAt(MapCol, MapRow, DirNorth) > 0) {
                    Symbol += WallBitNorth;
                  }
                  if (WallIdAt(MapCol, MapRow, DirEast) > 0) {
                    Symbol += WallBitEast;
                  }
                  if (WallIdAt(MapCol, MapRow, DirSouth) > 0) {
                    Symbol += WallBitSouth;
                  }
                  if (WallIdAt(MapCol, MapRow, DirWest) > 0) {
                    Symbol += WallBitWest;
                  }
                  Put8x8Symbol((s16)((ViewCol + ViewLeft_OVL29) - 1), (s16)((ViewRow + ViewLeft_OVL29) - 1), Symbol, DrawDirect, MapSymbolAttr);
                if (ViewCol == ViewLast) break;
                ViewCol++;
              }
            }
          }
        if (ViewRow == ViewLast) break;
        ViewRow++;
      }
    }
  }
  Put8x8Symbol((s16)((PartyCol + ViewLeft_OVL29) - 1), (s16)((PartyRow + ViewLeft_OVL29) - 1), (s16)((s16)((u16)Dir >> 1) + PartyArrow), DrawDirect, MapSymbolAttr);
  StepDisplay();
}

/* ovl29:0155. Stores the four wall view descriptors Wall1..Wall4 into WallDescriptor1..WallDescriptor4 (descriptor 1..4;
     whitepaper 5.2). Called by ovl26 ShowAreaView with the wall view ids. */
void SetWallDescriptors(u8 Wall1, u8 Wall2, u8 Wall3, u8 Wall4)
{
  POOL_TRACE("SetWallDescriptors");
  WallDescriptor1 = Wall1;
  WallDescriptor2 = Wall2;
  WallDescriptor3 = Wall3;
  WallDescriptor4 = Wall4;
}

/* ovl29:0174. Draws the four wall view descriptors WallDescriptor1..WallDescriptor4 through FillPictureRect (A=2,
     B and D the descriptor's screen position/size, C=$B, E the descriptor, F=@FillRectPalette's 8-byte
     structure, G=DrawBuf). Called by DrawWallView. */
void DrawWallDescriptors(void)
{
  POOL_TRACE("DrawWallDescriptors");
  FillPictureRect(2, 0x10, 0xB, 0x2B, WallDescriptor1, rtl_far(&FillRectPalette), DrawBuf);
  FillPictureRect(2, 0x3B, 0xB, 1, WallDescriptor2, rtl_far(&FillRectPalette), DrawBuf);
  FillPictureRect(2, 0x3C, 0xB, 2, WallDescriptor3, rtl_far(&FillRectPalette), DrawBuf);
  FillPictureRect(2, 0x3E, 0xB, 0x2A, WallDescriptor4, rtl_far(&FillRectPalette), DrawBuf);
}

/* ovl29:0211. Draws piece Piece (0..9) of wall Wall (a wall id 1..15) in the 3D view: the piece's
     Width x Height tiles (WallPieceWidth, WallPieceHeight), taken in order from the wall's tile list WallTiles^[Wall]
     starting at WallPieceFirstTile[Piece], go row by row to the view cells from (Col, Row) on. Cells outside the
     11x11 view (0..ViewLast) and tile number 0 are skipped; each drawn tile is an 8x8 symbol at
     screen column Col + ViewLeft - 1 (Put8x8Symbol with Direct 1, the 3D view path). Called by
     DrawWallView with the piece positions WallPieceCol/WallPieceRow, shifted per distance and side. */
void DrawWallPiece(s8 Col, s8 Row, u8 Wall, u8 Piece)
{
  POOL_TRACE("DrawWallPiece");
  s16 LastCol_ = 0;
  s16 LastRow_ = 0;
  s16 TileCol = 0;
  s16 TileRow = 0;
  u8 Tile = 0;
  Tile = WallPieceFirstTile[Piece];
  LastCol_ = (WallPieceWidth[Piece] + Col) - 1;
  LastRow_ = (WallPieceHeight[Piece] + Row) - 1;
  {
    s16 limit = LastRow_;
    s16 first = Row;
    if (first <= limit) {
      TileRow = first;
      for (;;) {
          {
            s16 limit = LastCol_;
            s16 first = Col;
            if (first <= limit) {
              TileCol = first;
              for (;;) {
                  if (((((TileRow >= 0)) && ((TileRow <= ViewLast))) && ((TileCol >= 0))) && ((TileCol <= ViewLast))) {
                    if ((*FPD(TWallTiles (*), WallTiles))[Wall - 1][Tile] > 0) {
                      Put8x8Symbol((s16)((TileCol + ViewLeft_OVL29) - 1), (s16)((TileRow + ViewLeft_OVL29) - 1), (*FPD(TWallTiles (*), WallTiles))[Wall - 1][Tile], DrawDirect, WallTileAttr);
                    }
                  }
                  Tile++;
                if (TileCol == limit) break;
                TileCol++;
              }
            }
          }
        if (TileRow == limit) break;
        TileRow++;
      }
    }
  }
}

/* ovl29:031F. True when both Col and Row are in 0..$F (a map cell inside the 16x16 block). Signed
     ShortInt parameters; the four compares are in the order Col <= $F, Col >= 0, Row <= $F, Row >= 0. Called
     by DoorKindAt, WallIdAt, EventByteAt and DrawWallView. */
u8 CellInRange(s8 Col, s8 Row)
{
  POOL_TRACE("CellInRange");
  u8 Result = 0;
  if (((((Col > 0xF)) || ((Col < 0))) || ((Row > 0xF))) || ((Row < 0))) {
    Result = 0;
  } else {
    Result = 1;
  }
  return Result;
}

/* ovl29:0350. The passage kind of the side Dir of map cell (Col, Row): DoorOpen (1) when that side
     has no wall (WallIdAt 0), else the door bit pair of the door plane GeoCells^.Cells (bits 0-1
     north, 2-3 east, 4-5 south, 6-7 west). The ovl14 movement code takes 0 as a solid wall, 1 as
     open and 2 or 3 as two kinds of locked door (DoWildernessMenu offers Bash, Pick and Knock).
     A cell outside the 16x16 map answers 0 while WallViewMode is 0 or $A; otherwise the coordinates wrap
     to the opposite edge (Col > 15 becomes 0, Col < 0 becomes 15, the same for Row). */
u8 DoorKindAt(s8 Col, s8 Row, u8 Dir)
{
  POOL_TRACE("DoorKindAt");
  u8 Result = 0;
  u8 Kind = 0;
  if (!CellInRange(Col, Row) && ((((WallViewMode == 0)) || ((WallViewMode == 0xA))))) {
    Result = 0;
  } else {
    if (Col > MapLast) {
      Col = 0;
    }
    if (Col < 0) {
      Col = MapLast;
    }
    if (Row > MapLast) {
      Row = 0;
    }
    if (Row < 0) {
      Row = MapLast;
    }
    Kind = DoorOpen;
    if (WallIdAt(Col, Row, Dir) > 0) {
      switch (Dir) {
      case DirWest:
      {
        Kind = (s16)((u16)(((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xC0)) >> 6);
        break;
      }
      case DirSouth:
      {
        Kind = (s16)((u16)(((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0x30)) >> 4);
        break;
      }
      case DirEast:
      {
        Kind = (s16)((u16)(((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xC)) >> 2);
        break;
      }
      case DirNorth:
      {
        Kind = ((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0x3);
        break;
      }
      }
    }
    Result = Kind;
  }
  return Result;
}

/* ovl29:047B. The wall id (0..15, 0 = no wall) on the side Dir of map cell (Col, Row): the high
     nibble of WallsNE for north, its low nibble for east, the high nibble of WallsSW for south and
     its low nibble for west (whitepaper 4.2.1). Off-map cells answer 0 while WallViewMode is 0 or $A and
     wrap otherwise, as in DoorKindAt. QUIRK ovl29:047B: a Dir other than 0, 2, 4, 6 leaves the
     result unassigned. */
u8 WallIdAt(s8 Col, s8 Row, u8 Dir)
{
  POOL_TRACE("WallIdAt");
  u8 Result = 0;
  if (!CellInRange(Col, Row) && ((((WallViewMode == 0)) || ((WallViewMode == 0xA))))) {
    Result = 0;
  } else {
    if (Col > MapLast) {
      Col = 0;
    }
    if (Col < 0) {
      Col = MapLast;
    }
    if (Row > MapLast) {
      Row = 0;
    }
    if (Row < 0) {
      Row = MapLast;
    }
    switch (Dir) {
    case DirNorth:
    {
      Result = (s16)((u16)(((*FPD(TGeoCellBlock (*), GeoCells)).WallsNE[Row][Col] & 0xF0)) >> 4);
      break;
    }
    case DirEast:
    {
      Result = ((*FPD(TGeoCellBlock (*), GeoCells)).WallsNE[Row][Col] & 0xF);
      break;
    }
    case DirSouth:
    {
      Result = (s16)((u16)(((*FPD(TGeoCellBlock (*), GeoCells)).WallsSW[Row][Col] & 0xF0)) >> 4);
      break;
    }
    case DirWest:
    {
      Result = ((*FPD(TGeoCellBlock (*), GeoCells)).WallsSW[Row][Col] & 0xF);
      break;
    }
    }
  }
  return Result;
}

/* ovl29:057A. The event byte of map cell (Col, Row) from the event plane GeoCells^.Events (bit 7 =
     interior cell, whitepaper 4.2.1); ShowAreaView asks for the party cell and tests bit 7, MoveParty
     keeps it in PartyCellEventByte. Off-map cells answer 0 while WallViewMode is 0 or $A and wrap otherwise, as in
     DoorKindAt. */
u8 EventByteAt(s8 Col, s8 Row)
{
  POOL_TRACE("EventByteAt");
  u8 Result = 0;
  if (!CellInRange(Col, Row) && ((((WallViewMode == 0)) || ((WallViewMode == 0xA))))) {
    Result = 0;
  } else {
    if (Col > MapLast) {
      Col = 0;
    }
    if (Col < 0) {
      Col = MapLast;
    }
    if (Row > MapLast) {
      Row = 0;
    }
    if (Row < 0) {
      Row = MapLast;
    }
    Result = (*FPD(TGeoCellBlock (*), GeoCells)).Events[Row][Col];
  }
  return Result;
}

/* ovl29:05F3. Steps the picture display (FlushPictureChanges, the same call ovl34 uses after a
     direct blit). No parameters. Called by DrawWallMap and DrawWallView. */
void StepDisplay(void)
{
  POOL_TRACE("StepDisplay");
  FlushPictureChanges();
}

/* ovl29:05FD. Draws the 3D view for the party at map cell (Col0, Row0) facing Dir (0, 2, 4, 6):
     while WallMapMode is set it draws the overhead wall map (DrawWallMap) instead. Otherwise it draws
     the view's frame (DrawWallDescriptors), then the walls from the farthest row of cells (ViewDepth
     ahead) to the party's own row, so nearer walls cover farther ones, and shows the result
     (StepDisplay). Each wall goes through DrawWallPiece at its piece position WallPieceCol/Row[n]
     moved by Shift tiles per cell to the side: far row, up to four cells each side, front walls
     (piece 0, FarCellStep tiles per cell) and the edge piece 9 where a front wall ends, then the side walls of
     the nearest three cells each side (pieces 1, 2); middle row, three cells from two to the left and
     from two to the right, front (3) and side walls (4, 5), MidCellStep tiles per cell; near row, two cells
     each side, front (6) and side walls (7, 8), NearCellStep tiles per cell. Wall ids come from WallIdAt with
     the facing direction for front walls and the left (Dir + 6) or right (Dir + 2) direction for
     side walls; the step tables DirStepX/DirStepY move one cell. Called by ShowAreaView and the
     movement loop (A key). QUIRK ovl29:05FD: two locals (Unused1, Unused2) are never used. */
void DrawWallView(s8 Col0, s8 Row0, u8 Dir)
{
  POOL_TRACE("DrawWallView");
  u8 DirLeft = 0;
  u8 DirRight = 0;
  u8 DirBack = 0;
  s16 BaseCol = 0;
  s16 BaseRow = 0;
  s16 StepCol = 0;
  s16 StepRow = 0;
  s16 Col = 0;
  s16 Row = 0;
  u8 Count = 0;
  s16 Shift = 0;
  u8 Depth = 0;
  u8 FrontWall = 0;
  u8 SideWall_ = 0;
  u8 Unused1 = 0;
  u8 EdgeWall = 0;
  u8 Unused2 = 0;
  if (WallMapMode != 0) {
    DrawWallMap(Col0, Row0, Dir);
  } else {
    DrawWallDescriptors();
    DirLeft = (((s16)(Dir + 6)) % 8);
    DirBack = (((s16)(Dir + 4)) % 8);
    DirRight = (((s16)(Dir + 2)) % 8);
    BaseCol = Col0;
    BaseRow = Row0;
    StepCol = DirStepX[Dir];
    StepRow = DirStepY[Dir];
    Depth = ViewDepth;
    BaseCol += (s16)(Depth * StepCol);
    BaseRow += (s16)(Depth * StepRow);
    do {
      switch (Depth) {
      case 2:
      {
        Col = BaseCol;
        Row = BaseRow;
        Count = 0;
        Shift = 0;
        EdgeWall = 0;
        while (Count < 4) {
          FrontWall = WallIdAt(Col, Row, Dir);
          if (!CellInRange(Col, Row)) {
            if (WallIdAt(Col, Row, DirRight) == 0) {
              EdgeWall = 0;
            }
          }
          if (FrontWall != 0) {
            if (EdgeWall > 0) {
              DrawWallPiece((s16)((WallPieceCol[9] + Shift) + 1), WallPieceRow[9], EdgeWall, PieceFarEdge);
            }
            EdgeWall = FrontWall;
            DrawWallPiece((s16)(WallPieceCol[0] + Shift), WallPieceRow[0], FrontWall, PieceFarFront);
          } else {
            if (EdgeWall > 0) {
              if (WallIdAt((s16)(Col - DirStepX[DirLeft]), (s16)(Row - DirStepY[DirLeft]), DirLeft) != 0) {
                DrawWallPiece((s16)((WallPieceCol[9] + Shift) + 1), WallPieceRow[9], EdgeWall, PieceFarEdge);
              }
            }
            EdgeWall = 0;
          }
          Count++;
          Shift -= FarCellStep;
          Col = Col + DirStepX[DirLeft];
          Row = Row + DirStepY[DirLeft];
        }
        Col = BaseCol;
        Row = BaseRow;
        Count = 0;
        Shift = 0;
        EdgeWall = 0;
        while (Count < 4) {
          FrontWall = WallIdAt(Col, Row, Dir);
          if (!CellInRange(Col, Row)) {
            if (WallIdAt(Col, Row, DirLeft) == 0) {
              EdgeWall = 0;
            }
          }
          if (FrontWall != 0) {
            if (EdgeWall > 0) {
              DrawWallPiece((s16)((WallPieceCol[9] + Shift) - 1), WallPieceRow[9], EdgeWall, PieceFarEdge);
            }
            EdgeWall = FrontWall;
            DrawWallPiece((s16)(WallPieceCol[0] + Shift), WallPieceRow[0], FrontWall, PieceFarFront);
          } else {
            if (EdgeWall > 0) {
              if (WallIdAt((s16)(Col - DirStepX[DirRight]), (s16)(Row - DirStepY[DirRight]), DirRight) != 0) {
                DrawWallPiece((s16)((WallPieceCol[9] + Shift) - 1), WallPieceRow[9], EdgeWall, PieceFarEdge);
              }
            }
            EdgeWall = 0;
          }
          Count++;
          Shift += FarCellStep;
          Col = Col + DirStepX[DirRight];
          Row = Row + DirStepY[DirRight];
        }
        Col = BaseCol;
        Row = BaseRow;
        Count = 0;
        Shift = 0;
        while (Count < 3) {
          SideWall_ = WallIdAt(Col, Row, DirLeft);
          if (SideWall_ != 0) {
            if (Count == 0) {
              DrawWallPiece((s16)(WallPieceCol[1] + Shift), WallPieceRow[1], SideWall_, PieceFarLeft);
            } else {
              DrawWallPiece((s16)((WallPieceCol[1] + Shift) - 1), WallPieceRow[1], SideWall_, PieceFarLeft);
            }
          }
          Count++;
          Shift -= FarCellStep;
          Col = Col + DirStepX[DirLeft];
          Row = Row + DirStepY[DirLeft];
        }
        Col = BaseCol;
        Row = BaseRow;
        Count = 0;
        Shift = 0;
        while (Count < 3) {
          SideWall_ = WallIdAt(Col, Row, DirRight);
          if (SideWall_ != 0) {
            if (Count == 0) {
              DrawWallPiece((s16)(WallPieceCol[2] + Shift), WallPieceRow[2], SideWall_, PieceFarRight);
            } else {
              DrawWallPiece((s16)((WallPieceCol[2] + Shift) + 1), WallPieceRow[2], SideWall_, PieceFarRight);
            }
          }
          Count++;
          Shift += FarCellStep;
          Col = Col + DirStepX[DirRight];
          Row = Row + DirStepY[DirRight];
        }
        break;
      }
      case 1:
      {
        Col = BaseCol + DirStepX[DirLeft];
        Col = Col + DirStepX[DirLeft];
        Row = BaseRow + DirStepY[DirLeft];
        Row = Row + DirStepY[DirLeft];
        Count = 0;
        Shift = (-6);
        while (Count < 3) {
          FrontWall = WallIdAt(Col, Row, Dir);
          if (FrontWall != 0) {
            DrawWallPiece((s16)(WallPieceCol[3] + Shift), WallPieceRow[3], FrontWall, PieceMidFront);
          }
          SideWall_ = WallIdAt(Col, Row, DirLeft);
          if (SideWall_ != 0) {
            DrawWallPiece((s16)(WallPieceCol[4] + Shift), WallPieceRow[4], SideWall_, PieceMidLeft);
          }
          Count++;
          Shift += MidCellStep;
          Col = Col + DirStepX[DirRight];
          Row = Row + DirStepY[DirRight];
        }
        Col = BaseCol + DirStepX[DirRight];
        Col = Col + DirStepX[DirRight];
        Row = BaseRow + DirStepY[DirRight];
        Row = Row + DirStepY[DirRight];
        Count = 0;
        Shift = 6;
        while (Count < 3) {
          FrontWall = WallIdAt(Col, Row, Dir);
          if (FrontWall != 0) {
            DrawWallPiece((s16)(WallPieceCol[3] + Shift), WallPieceRow[3], FrontWall, PieceMidFront);
          }
          SideWall_ = WallIdAt(Col, Row, DirRight);
          if (SideWall_ != 0) {
            DrawWallPiece((s16)(WallPieceCol[5] + Shift), WallPieceRow[5], SideWall_, PieceMidRight);
          }
          Count++;
          Shift -= MidCellStep;
          Col = Col + DirStepX[DirLeft];
          Row = Row + DirStepY[DirLeft];
        }
        break;
      }
      case 0:
      {
        Col = BaseCol + DirStepX[DirLeft];
        Row = BaseRow + DirStepY[DirLeft];
        Count = 0;
        Shift = (-7);
        while (Count < 2) {
          FrontWall = WallIdAt(Col, Row, Dir);
          if (FrontWall != 0) {
            DrawWallPiece((s16)(WallPieceCol[6] + Shift), WallPieceRow[6], FrontWall, PieceNearFront);
          }
          SideWall_ = WallIdAt(Col, Row, DirLeft);
          if (SideWall_ != 0) {
            DrawWallPiece((s16)(WallPieceCol[7] + Shift), WallPieceRow[7], SideWall_, PieceNearLeft);
          }
          Count++;
          Shift += NearCellStep;
          Col = Col + DirStepX[DirRight];
          Row = Row + DirStepY[DirRight];
        }
        Col = BaseCol + DirStepX[DirRight];
        Row = BaseRow + DirStepY[DirRight];
        Count = 0;
        Shift = NearCellStep;
        while (Count < 2) {
          FrontWall = WallIdAt(Col, Row, Dir);
          if (FrontWall != 0) {
            DrawWallPiece((s16)(WallPieceCol[6] + Shift), WallPieceRow[6], FrontWall, PieceNearFront);
          }
          SideWall_ = WallIdAt(Col, Row, DirRight);
          if (SideWall_ != 0) {
            DrawWallPiece((s16)(WallPieceCol[8] + Shift), WallPieceRow[8], SideWall_, PieceNearRight);
          }
          Count++;
          Shift -= NearCellStep;
          Col = Col + DirStepX[DirLeft];
          Row = Row + DirStepY[DirLeft];
        }
        break;
      }
      }
      BaseCol = BaseCol + DirStepX[DirBack];
      BaseRow = BaseRow + DirStepY[DirBack];
      Depth--;
    } while (!(Depth == 0xFF));
    StepDisplay();
  }
}

/* ovl29:0E08. Loads the WALLDEF<TileSet>.DAX block BlockId (one to three wallsets of $30C
     bytes, whitepaper 4.2.4) into the wall tiles from wallset slot First (1..3) on; any other First
     does nothing. A missing block or one that does not fit in the slots left is fatal (Unable to
     load wallset in LoadWallSet. on Output, a key, QuitGame). For each wallset slot filled it marks
     the slot's WallSetSlotPairs pair $FFFF, adds Delta (SymbolBase[First] - SymbolBase[1], the slot's
     8x8 bank base) to every tile number at or above WallSymbolFloor, and loads the slot's 8x8 tiles with
     Load8x8Bank: block BlockId for a single wallset, BlockId * 10 + n for the n-th of several
     (block 0 counting as 10 there). Finally WallSetSlotPairs[First] records (BlockId, First).
     The size check does not ask for a multiple of $30C: a partial last wallset is copied whole
     (reading past the block) and counted, and only the slot test of ovl29:0F5B (1..3) keeps its
     tiles in range. QUIRK ovl29:101A: BlockId 0 becomes 10 inside the loop and back to 0 after it. */
void LoadWallSet(u8 BlockId, u8 First)
{
  POOL_TRACE("LoadWallSet");
  u16 Size = 0;
  farptr Block = 0;
  u16 Offset = 0;
  u16 Delta = 0;
  u8 Wall = 0;
  u16 WallSet = 0;
  u16 Tile = 0;
  u8 Count = 0;
  u8 Num[2] = {0};
  u8 Key = 0;
  u8 ts1[9];
  if (((First < 1)) || ((First > LastWallSlot))) {
    return;
  }
  rtl_str_int(Num, 1, TileSet, 0);
  LoadDaxBlock(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\007WALLDEF"), Num}), S("\004.dax"), BlockId, &Size, &Block);
  if (((Size == 0)) || (((u16)((Size / WallSetSize) + First) > 4))) {
    RestoreVideoMode();
    rtl_write_str(&Output, S("&Unable to load wallset in LoadWallSet."), 0), rtl_write_ln(&Output);
    Key = ReadGameKey();
    RestoreVideoMode();
    QuitGame();
  }
  Delta = SymbolBase[First] - SymbolBase[1];
  Offset = 0;
  WallSet = 1;
  do {
    rtl_Move((void *)&(*(TByteArray_RES07 (*))&(*FPD(u8 *, Block)))[Offset], (void *)&(*FPD(TWallSets (*), WallSets))[(u16)((First + WallSet) - 1) - 1], WallSetSize);
    Offset += WallSetSize;
    WallSet++;
  } while (!(Offset >= Size));
  rtl_freemem(Block, Size);
  Count = WallSet - 1;
  {
    u16 limit = Count;
    if (1 <= limit) {
      WallSet = 1;
      for (;;) {
          if (((u16)((First + WallSet) - 1) >= 1 && (u16)((First + WallSet) - 1) <= LastWallSlot)) {
            WallSetSlotPairs[(u16)((First + WallSet) - 1)].A = 0xFFFF;
            WallSetSlotPairs[(u16)((First + WallSet) - 1)].B = 0xFFFF;
            {
              if (1 <= WallsPerSet) {
                Wall = 1;
                for (;;) {
                    {
                      if (0 <= LastWallTile) {
                        Tile = 0;
                        for (;;) {
                            if ((*FPD(TWallSets (*), WallSets))[(u16)((First + WallSet) - 1) - 1][Wall - 1][Tile] >= WallSymbolFloor) {
                              (*FPD(TWallSets (*), WallSets))[(u16)((First + WallSet) - 1) - 1][Wall - 1][Tile] += Delta;
                            }
                          if (Tile == LastWallTile) break;
                          Tile++;
                        }
                      }
                    }
                  if (Wall == WallsPerSet) break;
                  Wall++;
                }
              }
            }
            if (Count > 1) {
              if (BlockId == 0) {
                BlockId = 10;
              }
              Load8x8Bank((BlockId * 10) + WallSet, (u16)((First + WallSet) - 1));
            } else {
              Load8x8Bank(BlockId, (u16)((First + WallSet) - 1));
            }
          }
        if (WallSet == limit) break;
        WallSet++;
      }
    }
  }
  if (BlockId == 10) {
    BlockId = 0;
  }
  WallSetSlotPairs[First].A = BlockId;
  WallSetSlotPairs[First].B = First;
}

/* ovl29:10C7. Loads the 3D area map: block BlockId of GEO<TileSet>.DAX, which must be exactly
     $402 bytes (else Unable to load geo in Load3DMap. on Output, a key, QuitGame). It skips the
     size word, copies the four 256-byte planes into GeoCells^ (WallsNE, WallsSW, Events, Cells;
     whitepaper 4.2.1), frees the block and records BlockId in GameVars^[VarGeoBlock]. */
void Load3DMap(u8 BlockId)
{
  POOL_TRACE("Load3DMap");
  u16 Size = 0;
  farptr Block = 0;
  u16 Offset = 0;
  u8 Num[2] = {0};
  u8 Key = 0;
  u8 ts1[5];
  rtl_str_int(Num, 1, TileSet, 0);
  LoadDaxBlock(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\003GEO"), Num}), S("\004.dax"), BlockId, &Size, &Block);
  if (((Size == 0)) || ((Size != GeoBlockSize))) {
    RestoreVideoMode();
    rtl_write_str(&Output, S(" Unable to load geo in Load3DMap."), 0), rtl_write_ln(&Output);
    Key = ReadGameKey();
    RestoreVideoMode();
    QuitGame();
  }
  Offset = 2;
  rtl_Move((void *)&(*(TByteArray_RES07 (*))&(*FPD(u8 *, Block)))[Offset], (void *)&(*FPD(TGeoCellBlock (*), GeoCells)).WallsNE, GeoPlaneSize);
  Offset += GeoPlaneSize;
  rtl_Move((void *)&(*(TByteArray_RES07 (*))&(*FPD(u8 *, Block)))[Offset], (void *)&(*FPD(TGeoCellBlock (*), GeoCells)).WallsSW, GeoPlaneSize);
  Offset += GeoPlaneSize;
  rtl_Move((void *)&(*(TByteArray_RES07 (*))&(*FPD(u8 *, Block)))[Offset], (void *)&(*FPD(TGeoCellBlock (*), GeoCells)).Events, GeoPlaneSize);
  Offset += GeoPlaneSize;
  rtl_Move((void *)&(*(TByteArray_RES07 (*))&(*FPD(u8 *, Block)))[Offset], (void *)&(*FPD(TGeoCellBlock (*), GeoCells)).Cells, GeoPlaneSize);
  rtl_freemem(Block, Size);
  (*FPD(TGameVars (*), GameVars))[197] = BlockId;
}

/* Initialisation part of unit OVL29. */
void init_OVL29(void)
{
  POOL_TRACE("init");
  /* Initialisation (ovl29:1206): empty (55 89 E5 5D CB). */
}

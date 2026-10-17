#include "game.h"

/* ovl31:0000. Cell Index (0..3) of footprint kind Kind: its offset (DX, DY) from the combatant's
     cell, from Footprints. True when that cell exists (DX >= 0); kind 0 has no cells. Kind 1 is one
     cell, 2 is two cells one above the other, 3 two side by side, 4 a 2x2 square (DS:2844 bytes).
     Called by every routine here that walks a footprint and by ovl30's ScanTargets. */
u8 FootprintCell(u8 Kind, u8 Index, s8 (*DX), s8 (*DY))
{
  POOL_TRACE("FootprintCell");
  u8 Result = 0;
  Result = 0;
  if (Kind == 0) {
    return Result;
  }
  (*DX) = Footprints[Kind][Index].DX;
  (*DY) = Footprints[Kind][Index].DY;
  if ((*DX) >= 0) {
    Result = 1;
  }
  return Result;
}

/* ovl31:0068. Recomputes every combatant's place in the view, CombatantViewCol/Row[I] = its map
     cell minus the view origin. Called by ScrollViewTo after the view moved. */
void UpdateViewPositions(void)
{
  POOL_TRACE("UpdateViewPositions");
  u8 I = 0;
  {
    u8 limit = CombatantTable[0].Kind;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          CombatantViewCol[I - 1] = CombatantTable[I].X - (*FPD(TCombatMap (*), CombatMap)).ViewX;
          CombatantViewRow[I - 1] = CombatantTable[I].Y - (*FPD(TCombatMap (*), CombatMap)).ViewY;
        if (I == limit) break;
        I++;
      }
    }
  }
}

/* ovl31:00E3. when VideoAdapter is 1 it calls SetPaletteRegister(0, 8) and then
     SetPaletteRegister(8, 0); RestorePaletteColors0And8 makes the calls (0, 0) and (8, 8). Called by EditCharacterIcon,
     ovl19 and
     DrawCombatScreen. */
void SwapPaletteColors0And8(void)
{
  POOL_TRACE("SwapPaletteColors0And8");
  switch (VideoAdapter) {
  case AdapterEga:
  {
    SetPaletteRegister(0, 8);
    SetPaletteRegister(8, 0);
    break;
  }
  }
}

/* ovl31:0105. when VideoAdapter is 1 it calls SetPaletteRegister(0, 0) and then
     SetPaletteRegister(8, 8), the counterpart of SwapPaletteColors0And8. Called by ovl08, ovl16 and ViewSelectedCharacter. */
void RestorePaletteColors0And8(void)
{
  POOL_TRACE("RestorePaletteColors0And8");
  switch (VideoAdapter) {
  case AdapterEga:
  {
    SetPaletteRegister(0, 0);
    SetPaletteRegister(8, 8);
    break;
  }
  }
}

/* ovl31:0127. Draws the cursor on map cell (CellX, CellY): every cell of the cursor's footprint
     (CombatMap^.CursorKind) that is in view gets its ground picture again and, when
     CombatMap^.ShowCursor is set, the cursor icon; then the combatant standing on (CellX, CellY), if it is in
     view, is drawn over it. Called by MoveCombatCursor. */
void DrawCursorAt(s8 CellX, s8 CellY)
{
  POOL_TRACE("DrawCursorAt");
  s8 ViewCol = 0;
  s8 ViewRow = 0;
  s8 DX = 0;
  s8 DY = 0;
  u8 J = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  ViewCol = CellX - (*FPD(TCombatMap (*), CombatMap)).ViewX;
  ViewRow = CellY - (*FPD(TCombatMap (*), CombatMap)).ViewY;
  {
    if (0 <= FootprintCells) {
      J = 0;
      for (;;) {
          if (FootprintCell((*FPD(TCombatMap (*), CombatMap)).CursorKind, J, &DX, &DY)) {
            if (IsInView((s16)(ViewCol + DX), (s16)(ViewRow + DY))) {
              DrawCellPicture((s16)(((s16)(ViewCol + DX)) * CellStep_OVL31), (s16)(((s16)(ViewRow + DY)) * CellStep_OVL31), CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[(s16)(CellY + DY)][(s16)(CellX + DX)]].Picture, 0);
              if ((*FPD(TCombatMap (*), CombatMap)).ShowCursor != 0) {
                DrawIcon((s16)(ViewCol + DX), (s16)(ViewRow + DY), 0, 0, CursorIcon);
              }
            }
          }
        if (J == FootprintCells) break;
        J++;
      }
    }
  }
  GetMapCell(CellX, CellY, &Occupant, &Tile);
  if (Occupant > 0) {
    if (IsCombatantInView(CombatantRecord[Occupant - 1], 0)) {
      DrawIcon(CombatantViewCol[Occupant - 1], CombatantViewRow[Occupant - 1], (*FPD(TCombatant (*), (*FPD(TCharacter (*), CombatantRecord[Occupant - 1])).Combat)).IconSet, 0, (*FPD(TCharacter (*), CombatantRecord[Occupant - 1])).CombatIcon);
    }
  }
}

/* ovl31:02D5. Repaints map cell (CellX, CellY) without the cursor: the ground under it (RedrawGround) and
     the combatant standing there, if it is in view. Called by MoveCombatCursor for the cell the cursor
     leaves, and by ovl08, ovl13. */
void RedrawMapCell(s8 CellX, s8 CellY)
{
  POOL_TRACE("RedrawMapCell");
  s8 ViewCol = 0;
  s8 ViewRow = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  ViewCol = CellX - (*FPD(TCombatMap (*), CombatMap)).ViewX;
  ViewRow = CellY - (*FPD(TCombatMap (*), CombatMap)).ViewY;
  RedrawGround(ViewCol, ViewRow, 0);
  GetMapCell(CellX, CellY, &Occupant, &Tile);
  if (Occupant > 0) {
    if (IsCombatantInView(CombatantRecord[Occupant - 1], 0)) {
      DrawIcon(CombatantViewCol[Occupant - 1], CombatantViewRow[Occupant - 1], (*FPD(TCombatant (*), (*FPD(TCharacter (*), CombatantRecord[Occupant - 1])).Combat)).IconSet, 0, (*FPD(TCharacter (*), CombatantRecord[Occupant - 1])).CombatIcon);
    }
  }
}

/* ovl31:03A0. Rebuilds CellOccupant from CombatantTable: clears it, writes each active combatant's
     index into the cells of its footprint, and refreshes its view position. Called after a combatant
     is placed or removed (PlaceCombatant, RemoveCombatant) and by ovl10, ovl13, ovl24. */
void RebuildOccupancy(void)
{
  POOL_TRACE("RebuildOccupancy");
  u8 I = 0;
  u8 J = 0;
  s8 DX = 0;
  s8 DY = 0;
  rtl_FillChar((void *)&CellOccupant, 1250, 0);
  {
    u8 limit = CombatantTable[0].Kind;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if (CombatantTable[I].Kind > 0) {
            {
              if (0 <= FootprintCells) {
                J = 0;
                for (;;) {
                    if (FootprintCell(CombatantTable[I].Kind, J, &DX, &DY)) {
                      CellOccupant[(s16)(CombatantTable[I].Y + DY)][(s16)(CombatantTable[I].X + DX)] = I;
                    }
                  if (J == FootprintCells) break;
                  J++;
                }
              }
            }
            CombatantViewCol[I - 1] = CombatantTable[I].X - (*FPD(TCombatMap (*), CombatMap)).ViewX;
            CombatantViewRow[I - 1] = CombatantTable[I].Y - (*FPD(TCombatMap (*), CombatMap)).ViewY;
          }
        if (I == limit) break;
        I++;
      }
    }
  }
}

/* ovl31:04BE. The tile id (CombatMap^.Cells) and the combatant (CellOccupant, 0 for none) of map
     cell (CellX, CellY); both are 0 for a cell off the 50x25 map. Called here and by ovl13, ovl22. */
void GetMapCell(s8 CellX, s8 CellY, u8 (*Occupant), u8 (*Tile))
{
  POOL_TRACE("GetMapCell");
  if (((((CellX >= 0)) && ((CellX <= MapLastCol))) && ((CellY >= 0))) && ((CellY <= MapLastRow))) {
    (*Tile) = (*FPD(TCombatMap (*), CombatMap)).Cells[CellY][CellX];
    (*Occupant) = CellOccupant[CellY][CellX];
  } else {
    (*Occupant) = 0;
    (*Tile) = 0;
  }
}

/* ovl31:052B. Repaints the ground: with Occupant 0 it looks up the combatant on view cell (Col, Row)
     first. When there is one, the ground pictures of all its footprint cells that are in view are
     drawn (the combatant itself is erased); otherwise only view cell (Col, Row), when it is in view.
     Called by RedrawMapCell, SetCombatantIcon, RemoveCombatant and ovl08, ovl13, ovl24. */
void RedrawGround(s8 Col, s8 Row, u8 Occupant)
{
  POOL_TRACE("RedrawGround");
  s8 MapCol = 0;
  s8 MapRow = 0;
  s8 DX = 0;
  s8 DY = 0;
  u8 J = 0;
  u8 Tile = 0;
  u8 Kind = 0;
  if (Occupant == 0) {
    MapCol = Col + (*FPD(TCombatMap (*), CombatMap)).ViewX;
    MapRow = Row + (*FPD(TCombatMap (*), CombatMap)).ViewY;
    GetMapCell(MapCol, MapRow, &Occupant, &Tile);
  }
  if (Occupant > 0) {
    Col = CombatantViewCol[Occupant - 1];
    Row = CombatantViewRow[Occupant - 1];
    MapCol = Col + (*FPD(TCombatMap (*), CombatMap)).ViewX;
    MapRow = Row + (*FPD(TCombatMap (*), CombatMap)).ViewY;
    Kind = CombatantTable[Occupant].Kind;
    {
      if (0 <= FootprintCells) {
        J = 0;
        for (;;) {
            if (FootprintCell(Kind, J, &DX, &DY)) {
              if (IsInView((s16)(Col + DX), (s16)(Row + DY))) {
                DrawCellPicture((s16)(((s16)(Col + DX)) * CellStep_OVL31), (s16)(((s16)(Row + DY)) * CellStep_OVL31), CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[(s16)(MapRow + DY)][(s16)(MapCol + DX)]].Picture, 0);
              }
            }
          if (J == FootprintCells) break;
          J++;
        }
      }
    }
  } else if (IsInView(Col, Row)) {
    DrawCellPicture((s16)(Col * CellStep_OVL31), (s16)(Row * CellStep_OVL31), CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[MapRow][MapCol]].Picture, 0);
  }
}

/* ovl31:06E9. True when view cell (Col, Row) is inside the 7x7 window (0..ViewLast both ways).
     Called here and by ovl13, WalkCombatLine, WalkCombatLine. */
u8 IsInView(s8 Col, s8 Row)
{
  POOL_TRACE("IsInView");
  u8 Result = 0;
  if (((((Col < 0)) || ((Col > ViewLast_OVL31))) || ((Row < 0))) || ((Row > ViewLast_OVL31))) {
    Result = 0;
  } else {
    Result = 1;
  }
  return Result;
}

/* ovl31:071A. True when combatant Who can be seen: with AllCells set every cell of its footprint
     must be in view, otherwise one is enough. False for a combatant whose Kind is 0 (not on the map).
     QUIRK ovl31:071D: the frame holds two bytes no code uses (Spare). */
u8 IsCombatantInView(PCharacter Who, u8 AllCells)
{
  POOL_TRACE("IsCombatantInView");
  u8 Result = 0;
  u8 J = 0;
  u8 Index = 0;
  s8 DX = 0;
  s8 DY = 0;
  u8 Spare[2] = {0};
  Result = 1;
  Index = CombatantIndex(Who);
  if (CombatantTable[Index].Kind == 0) {
    Result = 0;
    return Result;
  }
  {
    if (0 <= FootprintCells) {
      J = 0;
      for (;;) {
          if (FootprintCell(CombatantTable[Index].Kind, J, &DX, &DY)) {
            if (!IsInView((s16)(CombatantViewCol[Index - 1] + DX), (s16)(CombatantViewRow[Index - 1] + DY))) {
              Result = 0;
              if (AllCells != 0) {
                return Result;
              }
            } else {
              Result = 1;
              if (AllCells == 0) {
                return Result;
              }
            }
          }
        if (J == FootprintCells) break;
        J++;
      }
    }
  }
  return Result;
}

/* ovl31:07D4. Scrolls the view so that map cell (CellX, CellY) lies within Margin cells of the window's
     centre: returns False and does nothing when it already does. Otherwise the centre moves one cell at
     a time towards (CellX, CellY), never past columns 3..46 and rows 3..21, the new origin is stored in
     CombatMap^, all 49 cell pictures are drawn and the combatants' view positions are updated
     (UpdateViewPositions); returns True. Margin NoReach ($FF) counts as 0 and always redraws.
     Called by MoveCombatCursor. */
u8 ScrollViewTo(s8 CellX, s8 CellY, u8 Margin)
{
  POOL_TRACE("ScrollViewTo");
  u8 Result = 0;
  u8 Reach = 0;
  u8 PicCol = 0;
  u8 PicRow = 0;
  u8 I = 0;
  u8 J = 0;
  s8 MapCol = 0;
  s8 MapRow = 0;
  s8 MinX = 0;
  s8 MaxX = 0;
  s8 MinY = 0;
  s8 MaxY = 0;
  Result = 0;
  MapCol = (*FPD(TCombatMap (*), CombatMap)).ViewX + ViewCentre;
  MapRow = (*FPD(TCombatMap (*), CombatMap)).ViewY + ViewCentre;
  Reach = Margin;
  if (Margin == NoReach) {
    Reach = 0;
  }
  MinX = MapCol - Reach;
  MaxX = MapCol + Reach;
  MinY = MapRow - Reach;
  MaxY = MapRow + Reach;
  if ((((((Margin != NoReach)) && ((CellX >= MinX))) && ((CellX <= MaxX))) && ((CellY >= MinY))) && ((CellY <= MaxY))) {
    return Result;
  }
  if (CellX < MinX) {
    while (((CellX < MapCol)) && ((MapCol > ViewCentre))) {
      MapCol--;
    }
  } else if (CellX > MaxX) {
    while (((CellX > MapCol)) && ((MapCol < MaxCentreCol))) {
      MapCol++;
    }
  }
  if (CellY < MinY) {
    while (((CellY < MapRow)) && ((MapRow > ViewCentre))) {
      MapRow--;
    }
  } else if (CellY > MaxY) {
    while (((CellY > MapRow)) && ((MapRow < MaxCentreRow))) {
      MapRow++;
    }
  }
  (*FPD(TCombatMap (*), CombatMap)).ViewX = MapCol - ViewCentre;
  (*FPD(TCombatMap (*), CombatMap)).ViewY = MapRow - ViewCentre;
  PicRow = 0;
  MapRow = (*FPD(TCombatMap (*), CombatMap)).ViewY;
  {
    if (0 <= ViewLast_OVL31) {
      J = 0;
      for (;;) {
          PicCol = 0;
          MapCol = (*FPD(TCombatMap (*), CombatMap)).ViewX;
          {
            if (0 <= ViewLast_OVL31) {
              I = 0;
              for (;;) {
                  DrawCellPicture(PicCol, PicRow, CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[MapRow][MapCol]].Picture, 1);
                  PicCol += CellStep_OVL31;
                  MapCol++;
                if (I == ViewLast_OVL31) break;
                I++;
              }
            }
          }
          PicRow += CellStep_OVL31;
          MapRow++;
        if (J == ViewLast_OVL31) break;
        J++;
      }
    }
  }
  UpdateViewPositions();
  Result = 1;
  return Result;
}

/* ovl31:0996. Moves the cursor from map cell (CellX, CellY) one step in direction Dir (DirStepX/DirStepY;
     DirNone stays): scrolls the view when the new cell is more than Margin cells from the centre
     (ScrollViewTo) and then redraws every combatant in view whose record has Flag10D set, repaints the
     old cell (RedrawMapCell), clamps the new cell to the map when it is out of view, draws the cursor
     there (DrawCursorAt) and shows the frame (FlushPictureChanges). Called by the combat code (ovl08, ovl09,
     ovl13, ovl22) and here. */
void MoveCombatCursor(s8 CellX, s8 CellY, u8 Margin, u8 Dir)
{
  POOL_TRACE("MoveCombatCursor");
  PCharacter Who = 0;
  u8 I = 0;
  s8 NewX = 0;
  s8 NewY = 0;
  NewX = CellX + DirStepX[Dir];
  NewY = CellY + DirStepY[Dir];
  if (ScrollViewTo(NewX, NewY, Margin)) {
    {
      u8 limit = CombatantTable[0].Kind;
      if (1 <= limit) {
        I = 1;
        for (;;) {
            Who = CombatantRecord[I - 1];
            if ((((*FPD(TCharacter (*), Who)).Flag10D != 0)) && ((CombatantTable[I].Kind > 0))) {
              if (IsCombatantInView(Who, 0)) {
                DrawIcon(CombatantViewCol[I - 1], CombatantViewRow[I - 1], (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet, 0, (*FPD(TCharacter (*), Who)).CombatIcon);
              }
            }
          if (I == limit) break;
          I++;
        }
      }
    }
  }
  RedrawMapCell(CellX, CellY);
  if (!IsInView((s16)(NewX - (*FPD(TCombatMap (*), CombatMap)).ViewX), (s16)(NewY - (*FPD(TCombatMap (*), CombatMap)).ViewY))) {
    if (NewX > MapLastCol) {
      NewX = MapLastCol;
    }
    if (NewX < 0) {
      NewX = 0;
    }
    if (NewY > MapLastRow) {
      NewY = MapLastRow;
    }
    if (NewY < 0) {
      NewY = 0;
    }
  }
  DrawCursorAt(NewX, NewY);
  FlushPictureChanges();
}

/* ovl31:0AF8. Turns combatant Who to the icon set IconSet: brings it into view first when part of
     it is outside (MoveCombatCursor on its cell), erases it (RedrawGround) when the icon set changes
     by more than the low two bits or Mirror or NoDraw is set, stores IconSet in Who^.Combat^ and,
     unless NoDraw, draws it with Mirror and shows the frame. Called by ovl08, ovl09, ovl13, ovl22. */
void SetCombatantIcon(PCharacter Who, u8 IconSet, u8 Mirror, u8 NoDraw)
{
  POOL_TRACE("SetCombatantIcon");
  u8 Index = 0;
  Index = CombatantIndex(Who);
  if (!IsCombatantInView(Who, 1)) {
    MoveCombatCursor(CombatantX(Who), CombatantY(Who), CentreMargin, DirNone);
  }
  if ((((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet / 4) != (IconSet / 4))) || ((Mirror != 0))) || ((NoDraw != 0))) {
    RedrawGround(0, 0, Index);
  }
  if (IconSet != (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet = IconSet;
  }
  if (NoDraw == 0) {
    if (IsCombatantInView(Who, 1)) {
      DrawIcon(CombatantViewCol[Index - 1], CombatantViewRow[Index - 1], IconSet, Mirror, (*FPD(TCharacter (*), Who)).CombatIcon);
      FlushPictureChanges();
    }
  }
}

/* ovl31:0BE7. The map column of combatant Who (CombatantTable). Called widely by the combat units. */
s8 CombatantX(PCharacter Who)
{
  POOL_TRACE("CombatantX");
  s8 Result = 0;
  Result = CombatantTable[CombatantIndex(Who)].X;
  return Result;
}

/* ovl31:0C0F. The map row of combatant Who (CombatantTable). Called widely by the combat units. */
s8 CombatantY(PCharacter Who)
{
  POOL_TRACE("CombatantY");
  s8 Result = 0;
  Result = CombatantTable[CombatantIndex(Who)].Y;
  return Result;
}

/* ovl31:0C37. The footprint kind of combatant Who (CombatantTable; 0 when it is not on the map).
     Called by ovl13, ovl24, res12. */
u8 CombatantKind(PCharacter Who)
{
  POOL_TRACE("CombatantKind");
  u8 Result = 0;
  Result = CombatantTable[CombatantIndex(Who)].Kind;
  return Result;
}

/* ovl31:0C5F. The combatant number of character record Who: the I (1..count) with
     CombatantRecord[I] = Who, or 0 when it is not among them. QUIRK ovl31:0C71: with a count of 0
     the loop still looks at entry 1 and then runs on until I wraps round to 0. */
u8 CombatantIndex(PCharacter Who)
{
  POOL_TRACE("CombatantIndex");
  u8 Result = 0;
  u8 Found = 0;
  u8 I = 0;
  Found = 0;
  Result = 0;
  I = 0;
  do {
    I++;
    if (CombatantRecord[I - 1] == Who) {
      Found = 1;
    }
  } while (!(Found || ((I == CombatantTable[0].Kind))));
  if (Found) {
    Result = I;
  }
  return Result;
}

/* ovl31:0CB9. Looks at the cells combatant Who's footprint would cover after one step in direction
     Dir (DirNone: where it stands): Occupant is another combatant on one of them (0 for none; the
     last one found), Tile the tile that decides the step: 0 when any cell is off the map or tile 0,
     else CloudTile when any cell has it, else the cell tile with the largest CombatTiles cost (from
     cost 1 up; FirstProbeTile when no cell exists). Called by PlaceCombatant and ovl08, ovl10, ovl24. */
void ProbeStep(PCharacter Who, u8 Dir, u8 (*Occupant), u8 (*Tile))
{
  POOL_TRACE("ProbeStep");
  u8 J = 0;
  u8 Index = 0;
  u8 CellWho = 0;
  u8 CellTile = 0;
  u8 BestCost = 0;
  s8 NewX = 0;
  s8 NewY = 0;
  s8 CellX = 0;
  s8 CellY = 0;
  s8 DX = 0;
  s8 DY = 0;
  (*Occupant) = 0;
  (*Tile) = FirstProbeTile;
  BestCost = 1;
  Index = CombatantIndex(Who);
  CellX = CombatantTable[Index].X;
  CellY = CombatantTable[Index].Y;
  {
    if (0 <= FootprintCells) {
      J = 0;
      for (;;) {
          if (FootprintCell(CombatantTable[Index].Kind, J, &DX, &DY)) {
            NewX = (CellX + DX) + DirStepX[Dir];
            NewY = (CellY + DY) + DirStepY[Dir];
            GetMapCell(NewX, NewY, &CellWho, &CellTile);
            if (CellWho == Index) {
              CellWho = 0;
            }
            if (CellWho > 0) {
              (*Occupant) = CellWho;
            }
            if (((CellTile == 0)) || (((*Tile) == 0))) {
              (*Tile) = 0;
            } else if (((CellTile == CloudTile)) || (((*Tile) == CloudTile))) {
              (*Tile) = CloudTile;
            } else if (CombatTiles[CellTile].Cost >= BestCost) {
              BestCost = CombatTiles[CellTile].Cost;
              (*Tile) = CellTile;
            }
          }
        if (J == FootprintCells) break;
        J++;
      }
    }
  }
}

/* ovl31:0E11. Takes combatant Who off the combat map (it dies or leaves). Outside view mode 5 it only
     makes the PlaySound(SoundCombatantDies) call and waits (DelayByGameSpeed). In combat it does nothing when Who
     already has a body record; otherwise it brings Who into view, erases it, draws DyingPicture on
     each of its cells, and unless Who^.Combat^.NoBody is set adds a body record (BodyTable: who, cell,
     the tile under it) and puts BodyTile on its cell (a CloudTile cell stays). Then the res03 call and
     the wait, the ground is redrawn, its Kind is cleared, CellOccupant rebuilt, the view redrawn round
     its centre and four bytes of its combat record cleared. SetSoundDriverIdle brackets the whole.
     QUIRK ovl31:0E41: the search for an existing body record tests BodyTable[SharedLoopIndex] (the sprite list
     loop counter of FreeSpriteList) every time, not BodyTable[I]; I only counts to 9.
     QUIRK ovl31:0E69: the early exit skips the closing SetSoundDriverIdle(10).
     QUIRK ovl31:0E14: the frame holds two bytes no code uses (Spare). */
void RemoveCombatant(PCharacter Who)
{
  POOL_TRACE("RemoveCombatant");
  u8 Index = 0;
  u8 I = 0;
  s8 DX = 0;
  s8 DY = 0;
  s8 CellX = 0;
  s8 CellY = 0;
  u8 Spare[2] = {0};
  SetSoundDriverIdle(BeforeRemoval);
  if (ViewMode != ViewModeCombat) {
    PlaySound(SoundCombatantDies);
    DelayByGameSpeed();
  } else {
    I = 1;
    while (((I < 9)) && ((BodyTable[SharedLoopIndex - 1].Who != Who))) {
      I++;
    }
    if (I < 9) {
      return;
    }
    Index = CombatantIndex(Who);
    CellX = CombatantX(Who);
    CellY = CombatantY(Who);
    if (!IsCombatantInView(Who, 1)) {
      MoveCombatCursor(CellX, CellY, CentreMargin, DirNone);
    }
    RedrawGround(0, 0, Index);
    {
      if (0 <= FootprintCells) {
        I = 0;
        for (;;) {
            if (FootprintCell(CombatantTable[Index].Kind, I, &DX, &DY)) {
              DrawPictureItemClipped((s16)(((s16)(CombatantViewCol[Index - 1] + DX)) * CellStep_OVL31), (s16)(((s16)(CombatantViewRow[Index - 1] + DY)) * CellStep_OVL31), 0, DyingFlags, DyingPicture, DrawBuf);
            }
          if (I == FootprintCells) break;
          I++;
        }
      }
    }
    FlushPictureChanges();
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == 0) {
      BodyCount++;
      BodyTable[BodyCount - 1].Tile = (*FPD(TCombatMap (*), CombatMap)).Cells[CellY][CellX];
      if ((*FPD(TCombatMap (*), CombatMap)).Cells[CellY][CellX] != CloudTile) {
        (*FPD(TCombatMap (*), CombatMap)).Cells[CellY][CellX] = BodyTile;
      }
      BodyTable[BodyCount - 1].Who = Who;
      BodyTable[BodyCount - 1].X = CellX;
      BodyTable[BodyCount - 1].Y = CellY;
    }
    PlaySound(SoundCombatantDies);
    DelayByGameSpeed();
    RedrawGround(0, 0, Index);
    CombatantTable[CombatantIndex(Who)].Kind = 0;
    RebuildOccupancy();
    MoveCombatCursor((s16)((*FPD(TCombatMap (*), CombatMap)).ViewX + ViewCentre), (s16)((*FPD(TCombatMap (*), CombatMap)).ViewY + ViewCentre), CentreMargin, DirNone);
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative = 0;
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell = 0;
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).B7 = 0;
  }
  SetSoundDriverIdle(AfterRemoval);
}

/* ovl31:10A7. Puts combatant Who on map cell (CellX, CellY) with the footprint kind of its record
     (CombatSize and KindMask) and returns True, or clears its Kind again and returns False when
     ProbeStep finds another combatant there, tile 0 or a CostBlocked tile. With Restore set and no
     NoBody flag it takes back its body records (the tile under the body, unless BodyTile, becomes the
     one restored; the records are cleared) and, when no other body lies on (CellX, CellY), puts that tile on
     the cell. CellOccupant is rebuilt on success. Outside view mode 5 it only returns True.
     Called by ovl08, ovl22, ovl24. */
u8 PlaceCombatant(PCharacter Who, u8 CellX, u8 CellY, u8 Restore)
{
  POOL_TRACE("PlaceCombatant");
  u8 Result = 0;
  u8 Index = 0;
  u8 I = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  u8 BodyThere = 0;
  if (ViewMode == ViewModeCombat) {
    Result = 0;
    Index = CombatantIndex(Who);
    CombatantTable[Index].Kind = ((*FPD(TCharacter (*), Who)).CombatSize & KindMask);
    CombatantTable[Index].X = CellX;
    CombatantTable[Index].Y = CellY;
    ProbeStep(Who, DirNone, &Occupant, &Tile);
    if ((((Occupant != 0)) || ((Tile == 0))) || ((CombatTiles[Tile].Cost == CostBlocked))) {
      CombatantTable[Index].Kind = 0;
    } else {
      Result = 1;
      if (Restore != 0) {
        if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == 0) {
          {
            u8 limit = BodyCount;
            if (1 <= limit) {
              I = 1;
              for (;;) {
                  if (BodyTable[I - 1].Who == Who) {
                    if (BodyTable[I - 1].Tile != BodyTile) {
                      Tile = BodyTable[I - 1].Tile;
                    }
                    rtl_FillChar((void *)&BodyTable[I - 1], 7, 0);
                  }
                if (I == limit) break;
                I++;
              }
            }
          }
          BodyThere = 0;
          {
            u8 limit = BodyCount;
            if (1 <= limit) {
              I = 1;
              for (;;) {
                  if ((((BodyTable[I - 1].Who != 0)) && ((BodyTable[I - 1].X == CellX))) && ((BodyTable[I - 1].Y == CellY))) {
                    BodyThere = 1;
                  }
                if (I == limit) break;
                I++;
              }
            }
          }
          if (!BodyThere) {
            (*FPD(TCombatMap (*), CombatMap)).Cells[CellY][CellX] = Tile;
          }
        }
      }
      RebuildOccupancy();
    }
  } else {
    Result = 1;
  }
  return Result;
}

/* ovl31:1298. Shows the cursor on combatant Who: the cursor takes Who's footprint kind and is drawn
     (ShowCursor) on Who's cell through MoveCombatCursor (Margin, no step); then the cursor is reset to
     kind 1 and hidden for later moves. Called by ovl08, ovl12, ovl13, ovl24. */
void ShowCursorOn(PCharacter Who, u8 Margin, u8 ShowCursor)
{
  POOL_TRACE("ShowCursorOn");
  (*FPD(TCombatMap (*), CombatMap)).ShowCursor = ShowCursor;
  (*FPD(TCombatMap (*), CombatMap)).CursorKind = CombatantTable[CombatantIndex(Who)].Kind;
  MoveCombatCursor(CombatantX(Who), CombatantY(Who), Margin, DirNone);
  (*FPD(TCombatMap (*), CombatMap)).ShowCursor = 0;
  (*FPD(TCombatMap (*), CombatMap)).CursorKind = 1;
}

/* Initialisation part of unit OVL31. */
void init_OVL31(void)
{
  POOL_TRACE("init");
}

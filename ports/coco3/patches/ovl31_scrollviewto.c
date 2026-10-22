u8 ScrollViewTo(s8 CellX, s8 CellY, u8 Margin)
{
  POOL_TRACE("ScrollViewTo");
  u8 Result = 0;
  u8 Reach = 0;
  u8 n = 0;
  u8 Codes_[49];
  u8 I = 0;
  u8 J = 0;
  s8 MapCol = 0;
  s8 MapRow = 0;
  s8 MinX = 0;
  s8 MaxX = 0;
  s8 MinY = 0;
  s8 MaxY = 0;
  Result = 0;
  MapCol = (s16)(*FPM(TCombatMap *, CombatMap)).ViewX + ViewCentre;
  MapRow = (s16)(*FPM(TCombatMap *, CombatMap)).ViewY + ViewCentre;
  Reach = Margin;
  if ((s16)Margin == NoReach) {
    Reach = 0;
  }
  MinX = (s16)MapCol - Reach;
  MaxX = (s16)MapCol + Reach;
  MinY = (s16)MapRow - Reach;
  MaxY = (s16)MapRow + Reach;
  if (((((((s16)Margin != NoReach)) && ((CellX >= MinX))) && ((CellX <= MaxX))) && ((CellY >= MinY))) && ((CellY <= MaxY))) {
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
  (*FPM(TCombatMap *, CombatMap)).ViewX = (s16)MapCol - ViewCentre;
  (*FPM(TCombatMap *, CombatMap)).ViewY = (s16)MapRow - ViewCentre;
  n = 0;                                   /* (step 8.9g: the picture codes of the 49 cells are gathered and drawn by one engine call, DrawCellGrid; it was 49 far calls of DrawCellPicture) */
  MapRow = (*FPM(TCombatMap *, CombatMap)).ViewY;
  for (J = 0; J <= ViewLast_OVL31; J++) {
    MapCol = (*FPM(TCombatMap *, CombatMap)).ViewX;
    for (I = 0; I <= ViewLast_OVL31; I++) {
      Codes_[n++] = CombatTiles[(*FPM(TCombatMap *, CombatMap)).Cells[MapRow][MapCol]].Picture;
      MapCol++;
    }
    MapRow++;
  }
  DrawCellGrid(Codes_, (u16)SqrPaciBank1, (u16)SqrPaciBank2);
  UpdateViewPositions();
  Result = 1;
  return Result;
}

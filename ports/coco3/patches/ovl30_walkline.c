u8 WalkLine(s8 X1, s8 Y1, s8 *Ex, s8 *Ey, u16 *StepCount, PMapRows Map)
{
  POOL_TRACE("WalkLine");
  TLineState Line;
  TLineState Bound;
  struct PA_TMapRow_25 *mp = FPM(struct PA_TMapRow_25 *, Map);
  const TTileEntry *wt;
  u8 Flag = 0;
  u8 Open;
  u16 Limit = 0;
  Limit = (u16)((u16)(*StepCount) * 2) + 1;
  Line.X1 = X1;
  Line.Y1 = Y1;
  Line.X2 = (*Ex);
  Line.Y2 = (*Ey);
  SetupLineP(&Line);
  wt = WalkTileTable;                    /* the table of the tiles' heights, in a data window: nothing else takes a window in the loop */
  Bound.X1 = 0;
  Bound.Y1 = wt[mp->a[Y1].Cells[X1]].BoundY;
  if (Line.DX > Line.DY) {
    Bound.X2 = Line.DX;
  } else {
    Bound.X2 = Line.DY;
  }
  Bound.Y2 = wt[mp->a[Y1].Cells[X1]].BoundY;
  SetupLineP(&Bound);
  Open = ((s16)mp->a[0].Head[6] == 0);   /* (does not change in the loop) */
  do {
    if ((Open && ((s16)wt[mp->a[Line.Y].Cells[Line.X]].BlockY > Bound.Y)) || (Line.First > Limit)) {
      (*Ex) = Line.X;
      (*Ey) = Line.Y;
      (*StepCount) = Line.First;
      return 0;
    }
    StepLineP(&Bound);
    Flag = !StepLineP(&Line);
  } while (!(Flag));
  (*StepCount) = Line.First;
  return 1;
}

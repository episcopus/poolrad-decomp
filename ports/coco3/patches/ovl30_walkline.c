u8 WalkLine(s8 X1, s8 Y1, s8 *Ex, s8 *Ey, u16 *StepCount, PMapRows Map)
{
  POOL_TRACE("WalkLine");
  /* step 8.9e: on 16 bit locals. Big-battle round (2026-11-14, from the DOS port's walk-line-regs): the Bound line runs from (0, B) to (N, B), B the start
     tile's BoundY, so its Y step SY is 0 and Bound.Y is B for the whole walk: it is not stepped. The walked line is SetupLine's and StepLine's arithmetic,
     one loop for each major axis; the cell is a pointer moved by 1 a column and by 50 (sizeof(TMapRow)) a row, the address mp->a[Y].Cells[X] gives; the end
     is reached after exactly the larger of DX and DY steps (the major coordinate moves once a step), which is where StepLine stops. Line, Bound and the
     Pattern byte were the routine's own. */
  struct PA_TMapRow_25 *mp = FPM(struct PA_TMapRow_25 *, Map);
  const TTileEntry *wt;
  const u8 *cell;
  s16 X, Y, DX, DY, D1, D2, D3, N, MinStep;
  s8 SX, SY;
  u8 First = 0;
  u8 B;
  u8 Open;
  u16 Limit;
  Limit = (u16)((u16)(*StepCount) * 2) + 1;
  X = X1;
  Y = Y1;
  DX = (s16)((s16)(*Ex) - X);
  DY = (s16)((s16)(*Ey) - Y);
  SX = DX < 0 ? -1 : DX > 0 ? 1 : 0;
  SY = DY < 0 ? -1 : DY > 0 ? 1 : 0;
  if (DX < 0)
    DX = -DX;
  if (DY < 0)
    DY = -DY;
  wt = WalkTileTable;                    /* the table of the tiles' heights, in a data window: nothing else takes a window in the loop */
  cell = &mp->a[Y1].Cells[X1];
  B = wt[*cell].BoundY;
  Open = ((s16)mp->a[0].Head[6] == 0);   /* (does not change in the loop) */
  if (DX > DY) {
    D1 = (s16)(DY * 2) - DX;
    D2 = (s16)(DY - DX) * 2;
    D3 = DY * 2;
    N = DX;
    MinStep = SY < 0 ? -50 : SY > 0 ? 50 : 0;
    for (;;) {
      if ((Open && wt[*cell].BlockY > B) || (u16)First > Limit)
        break;
      if (N == 0) {
        (*StepCount) = First;
        return 1;
      }
      N--;
      if (D1 >= 0) {
        Y += SY;
        cell += MinStep;
        D1 += D2;
        First += 3;
      } else {
        D1 += D3;
        First += 2;
      }
      X += SX;
      cell += (s16)SX;
    }
  } else {
    D1 = (s16)(DX * 2) - DY;
    D2 = (s16)(DX - DY) * 2;
    D3 = DX * 2;
    N = DY;
    MinStep = SY < 0 ? -50 : SY > 0 ? 50 : 0;    /* (the major step here) */
    for (;;) {
      if ((Open && wt[*cell].BlockY > B) || (u16)First > Limit)
        break;
      if (N == 0) {
        (*StepCount) = First;
        return 1;
      }
      N--;
      if (D1 >= 0) {
        X += SX;
        cell += (s16)SX;
        D1 += D2;
        First += 3;
      } else {
        D1 += D3;
        First += 2;
      }
      Y += SY;
      cell += MinStep;
    }
  }
  (*Ex) = X;
  (*Ey) = Y;
  (*StepCount) = First;
  return 0;
}

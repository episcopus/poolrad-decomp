/* ovl30 SetupLine on a pointer (step 8.9e, combat): the same arithmetic on 16 bit values (the translation took the absolute values as 32 bit and called SignOf). The routine the
   other units call takes the pointer as the game holds it. */
static void SetupLineP(TLineState *w1)
{
  s16 dx, dy;
  dx = (s16)((s16)w1->X2 - w1->X1);
  dy = (s16)((s16)w1->Y2 - w1->Y1);
  w1->First = 0;
  w1->DX = dx < 0 ? (s16)-dx : dx;
  w1->DY = dy < 0 ? (s16)-dy : dy;
  w1->SX = dx < 0 ? -1 : dx > 0 ? 1 : 0;
  w1->SY = dy < 0 ? -1 : dy > 0 ? 1 : 0;
  w1->X = w1->X1;
  w1->Y = w1->Y1;
  if (w1->DX > w1->DY) {
    w1->D1 = (s16)((s16)w1->DY * 2) - w1->DX;
    w1->D2 = (s16)((s16)((s16)w1->DY - w1->DX)) * 2;
    w1->D3 = (s16)w1->DY * 2;
  } else {
    w1->D1 = (s16)((s16)w1->DX * 2) - w1->DY;
    w1->D2 = (s16)((s16)((s16)w1->DX - w1->DY)) * 2;
    w1->D3 = (s16)w1->DX * 2;
  }
}

void SetupLine(PLineState Line)
{
  POOL_TRACE("SetupLine");
  SetupLineP(FPM(TLineState *, Line));
}

/* ovl30 StepLine on a pointer (step 8.9e, combat). */
static u8 StepLineP(TLineState *w1)
{
  s8 StepX = 0;
  s8 StepY = 0;
  u8 Result = 0;
  if (w1->DX > w1->DY) {
    if (w1->X != w1->X2) {
      StepX = w1->SX;
      if (w1->D1 >= 0) {
        StepY = w1->SY;
        w1->Y += w1->SY;
        w1->D1 += w1->D2;
        w1->First += 3;
      } else {
        w1->D1 += w1->D3;
        w1->First += 2;
      }
      w1->X += w1->SX;
      Result = 1;
    }
  } else {
    if (w1->Y != w1->Y2) {
      StepY = w1->SY;
      if (w1->D1 >= 0) {
        StepX = w1->SX;
        w1->X += w1->SX;
        w1->D1 += w1->D2;
        w1->First += 3;
      } else {
        w1->D1 += w1->D3;
        w1->First += 2;
      }
      w1->Y += w1->SY;
      Result = 1;
    }
  }
  w1->Pattern = LinePatternTable[(s16)((s16)StepY + 1)][(s16)((s16)StepX + 1)];
  return Result;
}

u8 StepLine(PLineState Line)
{
  POOL_TRACE("StepLine");
  return StepLineP(FPM(TLineState *, Line));
}

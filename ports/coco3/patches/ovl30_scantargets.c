void ScanTargets(s8 FromX, s8 FromY, u16 MaxSteps, u8 Dir, u8 Base, farptr Map)
{
  POOL_TRACE("ScanTargets");
  u16 I = 0;
  u8 L2 = 0;
  u8 J = 0;
  u8 K = 0;
  u8 BestJ = 0;
  u8 BestK = 0;
  u8 Found = 0;
  s8 Ex = 0;
  s8 Ey = 0;
  s8 CandX[4];
  s8 CandY[4];
  s8 TargX[4];
  s8 TargY[4];
  s8 FootX[5][4];
  s8 FootY[5][4];
  u8 Kind;
  u8 Count;
  s8 TX, TY, EX, EY;
  s16 DxA, DyA;
  u16 StepCount = 0;
  u16 Best = 0;
  u16 N;
  /* step 8.9e (combat): the footprints (a table in a data window, read through a far call of FootprintCell for every cell of every combatant) are copied once;
     a pair of cells that WalkLine cannot reach within MaxSteps is not walked: a line of N steps (N = the larger of the two distances) ends with First = 2N or more
     and WalkLine fails when First is above 2 * MaxSteps + 1, so N > MaxSteps cannot succeed; and once a pair has been found, a pair with 2N >= Best cannot be
     better (StepCount >= 2N, and only a smaller one replaces Best). InDirArc, which has no effects, is asked last. The result and the table are the original's. */
  for (K = 1; K < 5; K++)
    for (J = 0; J < 4; J++) {
      FootX[K][J] = Footprints[K][J].DX;
      FootY[K][J] = Footprints[K][J].DY;
    }
  for (J = 0; J < 4; J++) {
    if (Base != 0 && FootX[Base][J] >= 0) {
      CandX[J] = (s16)FromX + FootX[Base][J];
      CandY[J] = (s16)FromY + FootY[Base][J];
    } else {
      CandX[J] = (-1);
      CandY[J] = 0;
    }
  }
  SortEntries[0].Val_ = 0;
  Count = CombatantTable[0].Kind;
  for (I = 1; I <= Count; I++) {
    Kind = CombatantTable[I].Kind;
    if (Kind > 0) {
      TX = CombatantTable[I].X;
      TY = CombatantTable[I].Y;
      Found = 0;
      Best = 0xFF;
      for (K = 0; K < 4; K++) {
        if (Kind != 0 && FootX[Kind][K] >= 0) {
          TargX[K] = (s16)TX + FootX[Kind][K];
          TargY[K] = (s16)TY + FootY[Kind][K];
        } else {
          TargX[K] = (-1);
          TargY[K] = 0;
        }
      }
      for (K = 0; K < 4; K++) {
        if (TargX[K] >= 0) {
          for (J = 0; J < 4; J++) {
            if (CandX[J] >= 0) {
              DxA = (s16)TargX[K] - CandX[J];
              DyA = (s16)TargY[K] - CandY[J];
              if (DxA < 0)
                DxA = -DxA;
              if (DyA < 0)
                DyA = -DyA;
              N = (u16)(DxA > DyA ? DxA : DyA);
              if (N > MaxSteps || (Found && Best <= (u16)(N * 2)))
                continue;
              if (InDirArc(CandX[J], CandY[J], TargX[K], TargY[K], Dir)) {
                Ex = TargX[K];
                Ey = TargY[K];
                StepCount = MaxSteps;
                if (WalkLine(CandX[J], CandY[J], &Ex, &Ey, &StepCount, Map)) {
                  Found = 1;
                  if (StepCount < Best) {
                    Best = StepCount;
                    BestJ = J;
                    BestK = K;
                  }
                }
              }
            }
          }
        }
      }
      if (Found) {
        SortEntries[0].Val_++;
        SortEntries[SortEntries[0].Val_].Head = (u8)I;
        SortEntries[SortEntries[0].Val_].Key = Best;
        L2 = 0;
        if ((s16)Dir < 8) {
          L2 = Dir;
        } else {
          while (!InDirArc(CandX[BestJ], CandY[BestJ], TargX[BestK], TargY[BestK], L2)) {
            L2++;
          }
        }
        SortEntries[SortEntries[0].Val_].Val_ = L2;
      }
    }
  }
  SortTable();
}

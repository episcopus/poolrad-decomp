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
  u16 Need;
  u16 Limit;
  u8 Omni;
  s8 DirDX, DirDY;
  u8 Ok;
  u8 NC, NT;
  u8 NK[5];
  s8 KDX[5][4];
  s8 KDY[5][4];
  const TMapEntry *ct;                    /* CombatantTable in its data window: taken again after a call that may map another page (WalkLine, InDirArc) */
  /* step 8.9e (combat): the footprints (a table in a data window, read through a far call of FootprintCell for every cell of every combatant) are copied once;
     a pair of cells that WalkLine cannot reach within MaxSteps is not walked: a line of N steps (N = the larger of the two distances) ends with First = 2N or more
     and WalkLine fails when First is above 2 * MaxSteps + 1, so N > MaxSteps cannot succeed; and once a pair has been found, a pair with 2N >= Best cannot be
     better (StepCount >= 2N, and only a smaller one replaces Best). InDirArc, which has no effects, is asked last. The result and the table are the original's.
     Big-battle round (2026-11-14, from the DOS port's scan-targets): WalkLine's First ends at exactly 2 max + min of the two distances and never decreases
     (checked for every displacement on the map), so a pair with 2 max + min above 2 * MaxSteps + 1 cannot succeed and one with 2 max + min >= Best cannot
     be better; with Dir 8 or $FF (every caller passes $FF) InDirArc is "both cells on the map", tested once per cell; and a hit's direction (the first
     L2 from 0 with InDirArc True) comes from the displacement (checked against InDirArc for all 1,562,500 pairs of map cells). */
  for (K = 1; K < 5; K++)
    for (J = 0; J < 4; J++) {
      FootX[K][J] = Footprints[K][J].DX;
      FootY[K][J] = Footprints[K][J].DY;
    }
  Omni = (Dir == 8 || Dir == 0xFF);
  Limit = (u16)((u16)MaxSteps * 2) + 1;   /* WalkLine's, the same u16 arithmetic */
  /* the cells that exist, in the original's order: the base's (J) once, each footprint kind's (K) once; a combatant of one cell is one pair */
  NC = 0;
  for (J = 0; J < 4; J++) {
    if (Base != 0 && FootX[Base][J] >= 0) {
      TX = (s16)FromX + FootX[Base][J];
      TY = (s16)FromY + FootY[Base][J];
      if (TX < 0)
        continue;                         /* (the original's "CandX >= 0") */
      if (Omni && (TX > 49 || TY < 0 || TY > 24))
        continue;                         /* off the map: InDirArc is False for it with Dir 8 */
      CandX[NC] = TX;
      CandY[NC] = TY;
      NC++;
    }
  }
  for (Kind = 1; Kind < 5; Kind++) {
    NK[Kind] = 0;
    for (K = 0; K < 4; K++)
      if (FootX[Kind][K] >= 0) {
        KDX[Kind][NK[Kind]] = FootX[Kind][K];
        KDY[Kind][NK[Kind]] = FootY[Kind][K];
        NK[Kind]++;
      }
  }
  SortEntries[0].Val_ = 0;
  ct = CombatantTable;
  Count = ct[0].Kind;
  for (I = 1; I <= Count; I++) {
    Kind = ct[I].Kind;
    if (Kind > 0 && NC > 0) {
      TX = ct[I].X;
      TY = ct[I].Y;
      Found = 0;
      Best = 0xFF;
      if (Kind < 5) {
        NT = NK[Kind];
        for (K = 0; K < NT; K++) {
          TargX[K] = (s16)TX + KDX[Kind][K];
          TargY[K] = (s16)TY + KDY[Kind][K];
        }
      } else {                            /* (no such kind in the game: the cells as FootprintCell reads them, past the table) */
        NT = 0;
        for (K = 0; K < 4; K++)
          if (FootprintCell(Kind, K, &Ex, &Ey)) {
            TargX[NT] = (s16)TX + Ex;
            TargY[NT] = (s16)TY + Ey;
            NT++;
          }
        ct = CombatantTable;
      }
      for (K = 0; K < NT; K++) {
        if (TargX[K] >= 0) {
          if (Omni && (TargX[K] > 49 || TargY[K] < 0 || TargY[K] > 24))
            continue;                     /* off the map: InDirArc is False with Dir 8 */
          for (J = 0; J < NC; J++) {
            DxA = (s16)TargX[K] - CandX[J];
            DyA = (s16)TargY[K] - CandY[J];
            if (DxA < 0)
              DxA = -DxA;
            if (DyA < 0)
              DyA = -DyA;
            if (DxA > DyA)
              Need = (u16)((u16)DxA * 2 + (u16)DyA);
            else
              Need = (u16)((u16)DyA * 2 + (u16)DxA);
            if (Need > Limit || (Found && Best <= Need))
              continue;
            if (!Omni) {
              Ok = InDirArc(CandX[J], CandY[J], TargX[K], TargY[K], Dir);
              ct = CombatantTable;
              if (!Ok)
                continue;
            }
            Ex = TargX[K];
            Ey = TargY[K];
            StepCount = MaxSteps;
            Ok = WalkLine(CandX[J], CandY[J], &Ex, &Ey, &StepCount, Map);
            ct = CombatantTable;
            if (Ok) {
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
      if (Found) {
        SortEntries[0].Val_++;
        SortEntries[SortEntries[0].Val_].Head = (u8)I;
        SortEntries[SortEntries[0].Val_].Key = Best;
        L2 = 0;
        if ((s16)Dir < 8) {
          L2 = Dir;
        } else if (Omni) {
          /* north of the candidate (DY < 0, A = -DY): 1 when DX >= A, 0 when DX > -A, 7 when DX = -A, else 6; on its row: 6 west, 0 on it, 2 east;
             south: 2 when DX > DY, 3 when DX >= 1, 4 when DX > -DY, else 5 */
          DirDX = (s8)(TargX[BestK] - CandX[BestJ]);
          DirDY = (s8)(TargY[BestK] - CandY[BestJ]);
          if (DirDY < 0) {
            if (DirDX >= -DirDY)
              L2 = 1;
            else if (DirDX > DirDY)
              L2 = 0;
            else if (DirDX == DirDY)
              L2 = 7;
            else
              L2 = 6;
          } else if (DirDY == 0) {
            L2 = DirDX < 0 ? 6 : DirDX == 0 ? 0 : 2;
          } else {
            if (DirDX > DirDY)
              L2 = 2;
            else if (DirDX >= 1)
              L2 = 3;
            else if (DirDX > -DirDY)
              L2 = 4;
            else
              L2 = 5;
          }
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

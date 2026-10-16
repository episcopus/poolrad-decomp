#include "game.h"

/* ovl30:0000. Returns the sign of N: -1 when N is negative, 1 when N is positive and 0 when N is
     zero. Called by MonsterBreath, SetupLine and WalkCombatLine. */
s16 SignOf(s16 N)
{
  s16 Result = 0;
  if (N < 0) {
    Result = (-1);
  } else if (N > 0) {
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* ovl30:002E. Sorts the table DS:6718 in place (element 0 holds the count in Val): for every pair
     I < J it swaps the two 3-byte records when Key[J] < Key[I], or when the keys are equal and Val[J]
     < Val[I] and Val[J] mod 2 <= Val[I] mod 2. Called by ScanTargets. */
void SortTable(void)
{
  u8 I = 0;
  u8 J = 0;
  u8 ValJ = 0;
  u8 ValI = 0;
  TSortRec Swap_ = {0};
  u8 t1;
  u8 t2;
  if (SortEntries[0].Val_ <= 1) {
    return;
  }
  t1 = (s16)(SortEntries[0].Val_ - 1);
  I = 1;
  if (I <= t1) for (;;) {
    t2 = SortEntries[0].Val_;
    J = (s16)(I + 1);
    if (J <= t2) for (;;) {
      ValI = SortEntries[I].Val_;
      ValJ = SortEntries[J].Val_;
      if (((SortEntries[J].Key < SortEntries[I].Key)) || (((((SortEntries[J].Key == SortEntries[I].Key)) && ((ValJ < ValI))) && ((((ValJ % 2)) <= ((ValI % 2))))))) {
        Swap_ = SortEntries[I];
        SortEntries[I] = SortEntries[J];
        SortEntries[J] = Swap_;
      }
      if (J == t2) break;
      J++;
    }
    if (I == t1) break;
    I++;
  }
}

/* ovl30:01A0. Sets up the line drawing state Line from its two endpoints: it clears the stepped
     flag, computes DX = |X2 - X1| and DY = |Y2 - Y1|, the x and y step directions through SignOf, the
     current position (X1, Y1) and the three Bresenham steps (the larger of DX and DY drives them).
     Called by CastLineBeam, WalkLine and WalkCombatLine. */
void SetupLine(PLineState Line)
{
  {
    TLineState *w1 = &(*FPD(TLineState (*), Line));
      w1->First = 0;
      w1->DX = rtl_abs((s16)(w1->X2 - w1->X1));
      w1->DY = rtl_abs((s16)(w1->Y2 - w1->Y1));
      w1->SX = SignOf((s16)(w1->X2 - w1->X1));
      w1->SY = SignOf((s16)(w1->Y2 - w1->Y1));
      w1->X = w1->X1;
      w1->Y = w1->Y1;
      if (w1->DX > w1->DY) {
        w1->D1 = (w1->DY * 2) - w1->DX;
        w1->D2 = ((s16)(w1->DY - w1->DX)) * 2;
        w1->D3 = w1->DY * 2;
      } else {
        w1->D1 = (w1->DX * 2) - w1->DY;
        w1->D2 = ((s16)(w1->DX - w1->DY)) * 2;
        w1->D3 = w1->DX * 2;
      }
  }
}

/* ovl30:02CC. Steps a Bresenham line: with Line^ it returns whether it moved. When DX > DY it
     walks X towards X2 (and, while D1 >= 0, Y towards Y2 by SY), else it walks Y towards Y2 (and,
     while D1 >= 0, X towards X2 by SX); the smaller axis moves on the sign of D1 and First advances
     by 2 or 3, and the direction taken picks the Pattern byte from the 3x3 table LinePatternTable at
     3*(StepY+1) + (StepX+1). Pattern is written on every call, even when the line is already at its
     end point and the routine returns False (StepX and StepY stay 0, giving LinePatternTable[1, 1]).
     Called by CastLineBeam, WalkLine and WalkCombatLine. */
u8 StepLine(PLineState Line)
{
  u8 Result = 0;
  s8 StepX = 0;
  s8 StepY = 0;
  StepX = 0;
  StepY = 0;
  Result = 0;
  {
    TLineState *w1 = &(*FPD(TLineState (*), Line));
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
      w1->Pattern = LinePatternTable[(s16)(StepY + 1)][(s16)(StepX + 1)];
  }
  return Result;
}

/* ovl30:0422. Walks a Bresenham line from (X1, Y1) towards (Ex, Ey) over the Map rows and
     reports the steps in StepCount: it sets up Line from the endpoints and a horizontal Bound
     line from the start tile's table height, then steps Bound and Line together, stopping with
     False at a blocking tile (the tile gate) or past Limit steps, else with True. Ex, Ey and
     StepCount carry the end point and the steps used. Called by AiTurn, GazeCharmsTarget,
     RunAimCursor and ScanTargets. */
u8 WalkLine(s8 X1, s8 Y1, s8 (*Ex), s8 (*Ey), u16 (*StepCount), PMapRows Map)
{
  u8 Result = 0;
  TLineState (*Line) = (TLineState (*))rtl_stack_alloc(26);
  TLineState (*Bound) = (TLineState (*))rtl_stack_alloc(26);
  u8 Flag = 0;
  u8 StepDone = 0;
  u16 Limit = 0;
  u16 stack_mark = rtl_stack_mark();
  Limit = ((*StepCount) * 2) + 1;
  (*Line).X1 = X1;
  (*Line).Y1 = Y1;
  (*Line).X2 = (*Ex);
  (*Line).Y2 = (*Ey);
  SetupLine(rtl_far(&(*Line)));
  (*Bound).X1 = 0;
  (*Bound).Y1 = WalkTileTable[(*FPD(TMapRows (*), Map))[Y1].Cells[X1]].BoundY;
  if ((*Line).DX > (*Line).DY) {
    (*Bound).X2 = (*Line).DX;
  } else {
    (*Bound).X2 = (*Line).DY;
  }
  (*Bound).Y2 = WalkTileTable[(*FPD(TMapRows (*), Map))[Y1].Cells[X1]].BoundY;
  SetupLine(rtl_far(&(*Bound)));
  Flag = 0;
  do {
    if ((((((*FPD(TMapRows (*), Map))[0].Head[6] == 0)) && ((WalkTileTable[(*FPD(TMapRows (*), Map))[(*Line).Y].Cells[(*Line).X]].BlockY > (*Bound).Y)))) || (((*Line).First > Limit))) {
      (*Ex) = (*Line).X;
      (*Ey) = (*Line).Y;
      (*StepCount) = (*Line).First;
      Result = 0;
      goto L_exit;
    }
    StepDone = StepLine(rtl_far(&(*Bound)));
    Flag = !StepLine(rtl_far(&(*Line)));
  } while (!(Flag));
  (*StepCount) = (*Line).First;
  Result = 1;
L_exit:
  rtl_stack_release(stack_mark);
  return Result;
}

/* ovl30:057B. Tests whether the point (ToX, ToY) lies in the 90-degree arc facing compass
     direction Dir from (FromX, FromY): 0 is north then clockwise to 7 (north-west), 8 (and the
     $FF default) is omni and always true. Points outside X 0..49 or Y 0..24 fail; a point equal
     to the from point or to the base point passes. Otherwise the base point steps once towards
     Dir (DirStepX, DirStepY) and the case body checks the two half-planes of that direction's wedge
     (each shared with the neighbouring direction). Returns True when the point is in the arc.
     Called by BearingTo, CastChosenSpell (which loops Dir upward to aim at a point) and ScanTargets. */
u8 InDirArc(s8 FromX, s8 FromY, s8 ToX, s8 ToY, u8 Dir)
{
  u8 Result = 0;
  s8 BaseX = 0;
  s8 BaseY = 0;
  if (((((((((FromX < 0)) || ((FromX > 49))) || ((FromY < 0))) || ((FromY > 24))) || ((ToX < 0))) || ((ToX > 49))) || ((ToY < 0))) || ((ToY > 24))) {
    Result = 0;
  } else {
    if (Dir == 0xFF) {
      Dir = 8;
    }
    BaseX = FromX + DirStepX[Dir];
    BaseY = FromY + DirStepY[Dir];
    if (((((FromX == ToX)) && ((FromY == ToY)))) || ((((BaseX == ToX)) && ((BaseY == ToY))))) {
      Result = 1;
    } else {
      switch (Dir) {
      case 0:
      {
        Result = (((((ToX >= BaseX)) && ((ToY <= (s16)((BaseX - ToX) + BaseY))))) || ((((ToX <= BaseX)) && ((ToY <= (s16)((ToX - BaseX) + BaseY))))));
        break;
      }
      case 1:
      {
        Result = (((((ToX >= BaseX)) && ((ToY <= (s16)((BaseX - ToX) + BaseY))))) || ((((ToX >= (s16)((BaseX + BaseY) - ToY))) && ((ToY <= BaseY)))));
        break;
      }
      case 2:
      {
        Result = (((((ToX >= (s16)((BaseX + BaseY) - ToY))) && ((ToY <= BaseY)))) || ((((ToX >= (s16)((BaseX + ToY) - BaseY))) && ((ToY >= BaseY)))));
        break;
      }
      case 3:
      {
        Result = (((((ToX >= (s16)((BaseX + ToY) - BaseY))) && ((ToY >= BaseY)))) || ((((ToX >= BaseX)) && ((ToY >= (s16)((ToX - BaseX) + BaseY))))));
        break;
      }
      case 4:
      {
        Result = (((((ToX >= BaseX)) && ((ToY >= (s16)((ToX - BaseX) + BaseY))))) || ((((ToX <= BaseX)) && ((ToY >= (s16)((BaseX - ToX) + BaseY))))));
        break;
      }
      case 5:
      {
        Result = (((((ToX <= BaseX)) && ((ToY >= (s16)((BaseX - ToX) + BaseY))))) || ((((ToX <= (s16)((BaseX + BaseY) - ToY))) && ((ToY >= BaseY)))));
        break;
      }
      case 6:
      {
        Result = (((((ToX <= (s16)((BaseX + BaseY) - ToY))) && ((ToY >= BaseY)))) || ((((ToX <= (s16)((BaseX + ToY) - BaseY))) && ((ToY <= BaseY)))));
        break;
      }
      case 7:
      {
        Result = (((((ToX <= (s16)((BaseX + ToY) - BaseY))) && ((ToY <= BaseY)))) || ((((ToX <= BaseX)) && ((ToY <= (s16)((ToX - BaseX) + BaseY))))));
        break;
      }
      case 8:
      {
        Result = 1;
        break;
      }
      }
    }
  }
  return Result;
}

/* ovl30:0909. Scans the DS:5F27 map entity table for records reachable from (FromX, FromY) and
     appends one sort record per hit, then sorts the table. MaxSteps budgets the line walk, Dir is
     the arc to try, Base is the FootprintCell neighbour base for the search point and Map is passed to
     WalkLine. For each active record it tries the four neighbours of the base point against the
     four neighbours of the record (FootprintCell fills the offsets, invalid neighbours get -1), keeps
     the pairs in Dir's arc (InDirArc) that the line walk (WalkLine) crosses in the fewest steps,
     and stores the record index, the step count and the working direction (the requested Dir, or
     the first working one when Dir is 8). Called from combat and item aiming (CastFireball) and from
     ovl09, ovl13, ovl24 and res12. */
void ScanTargets(s8 FromX, s8 FromY, u16 MaxSteps, u8 Dir, u8 Base, farptr Map)
{
  u8 I = 0;
  u8 L2 = 0;
  u8 J = 0;
  u8 K = 0;
  u8 BestJ = 0;
  u8 BestK = 0;
  u8 Found = 0;
  s8 Ex = 0;
  s8 Ey = 0;
  s8 LocX = 0;
  s8 LocY = 0;
  s8 CandX[4] = {0};
  s8 CandY[4] = {0};
  s8 TargX[4] = {0};
  s8 TargY[4] = {0};
  u16 StepCount = 0;
  u16 Best = 0;
  u8 t1;
  J = 0;
  if (J <= 3) for (;;) {
    if (FootprintCell(Base, J, &LocX, &LocY)) {
      CandX[J] = FromX + LocX;
      CandY[J] = FromY + LocY;
    } else {
      CandX[J] = (-1);
    }
    if (J == 3) break;
    J++;
  }
  SortEntries[0].Val_ = 0;
  t1 = CombatantTable[0].Kind;
  I = 1;
  if (I <= t1) for (;;) {
    if (CombatantTable[I].Kind > 0) {
      Found = 0;
      Best = 0xFF;
      K = 0;
      if (K <= 3) for (;;) {
        if (FootprintCell(CombatantTable[I].Kind, K, &LocX, &LocY)) {
          TargX[K] = CombatantTable[I].X + LocX;
          TargY[K] = CombatantTable[I].Y + LocY;
        } else {
          TargX[K] = (-1);
        }
        if (K == 3) break;
        K++;
      }
      K = 0;
      if (K <= 3) for (;;) {
        if (TargX[K] >= 0) {
          J = 0;
          if (J <= 3) for (;;) {
            if (CandX[J] >= 0) {
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
            if (J == 3) break;
            J++;
          }
        }
        if (K == 3) break;
        K++;
      }
      if (Found) {
        SortEntries[0].Val_++;
        SortEntries[SortEntries[0].Val_].Head = I;
        SortEntries[SortEntries[0].Val_].Key = Best;
        L2 = 0;
        if (Dir < 8) {
          L2 = Dir;
        } else {
          while (!InDirArc(CandX[BestJ], CandY[BestJ], TargX[BestK], TargY[BestK], L2)) {
            L2++;
          }
        }
        SortEntries[SortEntries[0].Val_].Val_ = L2;
      }
    }
    if (I == t1) break;
    I++;
  }
  SortTable();
}

/* Initialisation part of unit OVL30. */
void init_OVL30(void)
{
}

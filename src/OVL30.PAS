unit OVL30;
{ ovl30: the line drawing unit (whitepaper 5.18). SignOf returns the sign of a value, SortTable
  sorts a 3-byte record table in place, SetupLine fills a Bresenham line state, StepLine advances
  it one step, WalkLine walks a line over the map rows with tile gating, InDirArc tests whether
  a point lies in a compass direction's arc and ScanTargets collects the reachable map entities
  sorted by distance. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, OVL31;
function SignOf(N: Integer): Integer;
procedure SortTable;
procedure SetupLine(Line: PLineState);
function StepLine(Line: PLineState): Boolean;
function WalkLine(X1, Y1: ShortInt; var Ex, Ey: ShortInt; var StepCount: Word;
  Map: PMapRows): Boolean;
function InDirArc(FromX, FromY, ToX, ToY: ShortInt; Dir: Byte): Boolean;
procedure ScanTargets(FromX, FromY: ShortInt; MaxSteps: Word; Dir, Base: Byte; Map: Pointer);
implementation

{ ovl30:0000. Returns the sign of N: -1 when N is negative, 1 when N is positive and 0 when N is
  zero. Called by ovl22_e63, SetupLine and res12_fn_1CE0. }
function SignOf(N: Integer): Integer;
begin
  if N < 0 then
    SignOf := -1
  else if N > 0 then
    SignOf := 1
  else
    SignOf := 0;
end;
{ ovl30:002E. Sorts the table DS:6718 in place (element 0 holds the count in Val): for every pair
  I < J it swaps the two 3-byte records when Key[J] < Key[I], or when the keys are equal and Val[J]
  < Val[I] and Val[J] mod 2 <= Val[I] mod 2. Called by ScanTargets. }
procedure SortTable;
var
  I: Byte;                        { the outer index, 1 to Count - 1 }
  J: Byte;                        { the inner index, I + 1 to Count }
  ValJ: Byte;                     { Val of record J }
  ValI: Byte;                     { Val of record I }
  Swap: TSortRec;                 { the swap buffer }
begin
  if ds6718[0].Val <= 1 then
    Exit;
  for I := 1 to ds6718[0].Val - 1 do
  begin
    for J := I + 1 to ds6718[0].Val do
    begin
      ValI := ds6718[I].Val;
      ValJ := ds6718[J].Val;
      if (ds6718[J].Key < ds6718[I].Key) or
         ((ds6718[J].Key = ds6718[I].Key) and (ValJ < ValI) and ((ValJ mod 2) <= (ValI mod 2))) then
      begin
        Swap := ds6718[I];
        ds6718[I] := ds6718[J];
        ds6718[J] := Swap;
      end;
    end;
  end;
end;
{ ovl30:01A0. Sets up the line drawing state Line from its two endpoints: it clears the stepped
  flag, computes DX = |X2 - X1| and DY = |Y2 - Y1|, the x and y step directions through SignOf, the
  current position (X1, Y1) and the three Bresenham steps (the larger of DX and DY drives them).
  Called by ovl22_fn_295B, WalkLine and res12_fn_1A29. }
procedure SetupLine(Line: PLineState);
begin
  with Line^ do
  begin
    First := 0;
    DX := Abs(X2 - X1);
    DY := Abs(Y2 - Y1);
    SX := SignOf(X2 - X1);
    SY := SignOf(Y2 - Y1);
    X := X1;
    Y := Y1;
    if DX > DY then
    begin
      D1 := DY * 2 - DX;
      D2 := (DY - DX) * 2;
      D3 := DY * 2;
    end
    else
    begin
      D1 := DX * 2 - DY;
      D2 := (DX - DY) * 2;
      D3 := DX * 2;
    end;
  end;
end;
{ ovl30:02CC. Steps a Bresenham line: with Line^ it returns whether it moved. When DX > DY it
  walks X towards X2 (and, while D1 >= 0, Y towards Y2 by SY), else it walks Y towards Y2 (and,
  while D1 >= 0, X towards X2 by SX); the smaller axis moves on the sign of D1 and First advances
  by 2 or 3, and the direction taken picks the Pattern byte from the 3x3 table ds25C0 at
  3*(StepY+1) + (StepX+1). Called by ovl22_fn_295B, WalkLine and res12_fn_1A29. }
function StepLine(Line: PLineState): Boolean;
var
  StepX, StepY: ShortInt;         { the x and y direction of this step, -1, 0 or 1 }
begin
  StepX := 0;
  StepY := 0;
  StepLine := False;
  with Line^ do
  begin
    if DX > DY then
    begin
      if X <> X2 then
      begin
        StepX := SX;
        if D1 >= 0 then
        begin
          StepY := SY;
          Inc(Y, SY);
          Inc(D1, D2);
          Inc(First, 3);
        end
        else
        begin
          Inc(D1, D3);
          Inc(First, 2);
        end;
        Inc(X, SX);
        StepLine := True;
      end;
    end
    else
    begin
      if Y <> Y2 then
      begin
        StepY := SY;
        if D1 >= 0 then
        begin
          StepX := SX;
          Inc(X, SX);
          Inc(D1, D2);
          Inc(First, 3);
        end
        else
        begin
          Inc(D1, D3);
          Inc(First, 2);
        end;
        Inc(Y, SY);
        StepLine := True;
      end;
    end;
    Pattern := ds25C0[StepY + 1, StepX + 1];
  end;
end;
{ ovl30:0422. Walks a Bresenham line from (X1, Y1) towards (Ex, Ey) over the Map rows and
  reports the steps in StepCount: it sets up Line from the endpoints and a horizontal Bound
  line from the start tile's table height, then steps Bound and Line together, stopping with
  False at a blocking tile (the tile gate) or past Limit steps, else with True. Ex, Ey and
  StepCount carry the end point and the steps used. Called by ovl09_fn_0B96, ovl12_e70,
  ovl13_fn_2DFA and ScanTargets. }
function WalkLine(X1, Y1: ShortInt; var Ex, Ey: ShortInt; var StepCount: Word;
  Map: PMapRows): Boolean;
var
  Line, Bound: TLineState;        { the walked line and the horizontal tile bound }
  Flag: Boolean;                  { True once the line stepped }
  StepDone: Boolean;              { the Bound step result, never read (QUIRK ovl30:0544) }
  Limit: Word;                    { 2 * StepCount + 1: the First cutoff }
begin
  Limit := StepCount * 2 + 1;
  Line.X1 := X1;
  Line.Y1 := Y1;
  Line.X2 := Ex;
  Line.Y2 := Ey;
  SetupLine(@Line);
  Bound.X1 := 0;
  Bound.Y1 := ds2745[Map^[Y1].Cells[X1]].BoundY;
  if Line.DX > Line.DY then
    Bound.X2 := Line.DX
  else
    Bound.X2 := Line.DY;
  Bound.Y2 := ds2745[Map^[Y1].Cells[X1]].BoundY;
  SetupLine(@Bound);
  Flag := False;
  repeat
    if ((Map^[0].Head[6] = 0) and
        (ds2745[Map^[Line.Y].Cells[Line.X]].BlockY > Bound.Y)) or
       (Line.First > Limit) then
    begin
      Ex := Line.X;
      Ey := Line.Y;
      StepCount := Line.First;
      WalkLine := False;
      Exit;
    end;
    StepDone := StepLine(@Bound);
    Flag := not StepLine(@Line);
  until Flag;
  StepCount := Line.First;
  WalkLine := True;
end;
{ ovl30:057B. Tests whether the point (ToX, ToY) lies in the 90-degree arc facing compass
  direction Dir from (FromX, FromY): 0 is north then clockwise to 7 (north-west), 8 (and the
  $FF default) is omni and always true. Points outside X 0..49 or Y 0..24 fail; a point equal
  to the from point or to the base point passes. Otherwise the base point steps once towards
  Dir (ds2736, ds273F) and the case body checks the two half-planes of that direction's wedge
  (each shared with the neighbouring direction). Returns True when the point is in the arc.
  Called by ovl13_e18, ovl22_e5 (which loops Dir upward to aim at a point) and ScanTargets. }
function InDirArc(FromX, FromY, ToX, ToY: ShortInt; Dir: Byte): Boolean;
var
  BaseX, BaseY: ShortInt;         { the from point stepped once towards Dir }
begin
  if (FromX < 0) or (FromX > 49) or (FromY < 0) or (FromY > 24) or
     (ToX < 0) or (ToX > 49) or (ToY < 0) or (ToY > 24) then
    InDirArc := False
  else begin
    if Dir = $FF then
      Dir := 8;
    BaseX := FromX + ds2736[Dir];
    BaseY := FromY + ds273F[Dir];
    if ((FromX = ToX) and (FromY = ToY)) or ((BaseX = ToX) and (BaseY = ToY)) then
      InDirArc := True
    else case Dir of
      0: InDirArc := ((ToX >= BaseX) and (ToY <= BaseX - ToX + BaseY)) or
                      ((ToX <= BaseX) and (ToY <= ToX - BaseX + BaseY));
      1: InDirArc := ((ToX >= BaseX) and (ToY <= BaseX - ToX + BaseY)) or
                      ((ToX >= BaseX + BaseY - ToY) and (ToY <= BaseY));
      2: InDirArc := ((ToX >= BaseX + BaseY - ToY) and (ToY <= BaseY)) or
                      ((ToX >= BaseX + ToY - BaseY) and (ToY >= BaseY));
      3: InDirArc := ((ToX >= BaseX + ToY - BaseY) and (ToY >= BaseY)) or
                      ((ToX >= BaseX) and (ToY >= ToX - BaseX + BaseY));
      4: InDirArc := ((ToX >= BaseX) and (ToY >= ToX - BaseX + BaseY)) or
                      ((ToX <= BaseX) and (ToY >= BaseX - ToX + BaseY));
      5: InDirArc := ((ToX <= BaseX) and (ToY >= BaseX - ToX + BaseY)) or
                      ((ToX <= BaseX + BaseY - ToY) and (ToY >= BaseY));
      6: InDirArc := ((ToX <= BaseX + BaseY - ToY) and (ToY >= BaseY)) or
                      ((ToX <= BaseX + ToY - BaseY) and (ToY <= BaseY));
      7: InDirArc := ((ToX <= BaseX + ToY - BaseY) and (ToY <= BaseY)) or
                      ((ToX <= BaseX) and (ToY <= ToX - BaseX + BaseY));
      8: InDirArc := True;
    end;
  end;
end;
{ ovl30:0909. Scans the DS:5F27 map entity table for records reachable from (FromX, FromY) and
  appends one sort record per hit, then sorts the table. MaxSteps budgets the line walk, Dir is
  the arc to try, Base is the ovl31_e1 neighbour base for the search point and Map is passed to
  WalkLine. For each active record it tries the four neighbours of the base point against the
  four neighbours of the record (ovl31_e1 fills the offsets, invalid neighbours get -1), keeps
  the pairs in Dir's arc (InDirArc) that the line walk (WalkLine) crosses in the fewest steps,
  and stores the record index, the step count and the working direction (the requested Dir, or
  the first working one when Dir is 8). Called from combat and item aiming (ovl22_e5) and from
  ovl09, ovl13, ovl24 and res12. }
procedure ScanTargets(FromX, FromY: ShortInt; MaxSteps: Word; Dir, Base: Byte; Map: Pointer);
var
  I: Byte;                            { the table index, 1 to the entry-0 count }
  L2: Byte;                           { the retry direction stored in Val }
  J: Byte;                            { the base neighbour index, 0 to 3 }
  K: Byte;                            { the record neighbour index, 0 to 3 }
  BestJ: Byte;                        { the neighbour index of the best hit }
  BestK: Byte;                        { the record index of the best hit }
  Found: Boolean;                     { a walked line hit this record }
  Ex, Ey: ShortInt;                   { the walk endpoint WalkLine updates }
  LocX, LocY: ShortInt;               { the ovl31_e1 neighbour offsets }
  CandX, CandY: array[0..3] of ShortInt;  { the base neighbours (X is -1 when invalid) }
  TargX, TargY: array[0..3] of ShortInt;  { the record neighbours (X is -1 when invalid) }
  StepCount: Word;                    { the walk steps WalkLine reports }
  Best: Word;                         { the fewest steps so far }
begin
  for J := 0 to 3 do
    if ovl31_e1(Base, J, LocX, LocY) then
    begin
      CandX[J] := FromX + LocX;
      CandY[J] := FromY + LocY;
    end
    else
      CandX[J] := -1;
  ds6718[0].Val := 0;
  for I := 1 to ds5F27[0].Kind do
    if ds5F27[I].Kind > 0 then
    begin
      Found := False;
      Best := $FF;
      for K := 0 to 3 do
        if ovl31_e1(ds5F27[I].Kind, K, LocX, LocY) then
        begin
          TargX[K] := ds5F27[I].X + LocX;
          TargY[K] := ds5F27[I].Y + LocY;
        end
        else
          TargX[K] := -1;
      for K := 0 to 3 do
        if TargX[K] >= 0 then
          for J := 0 to 3 do
            if CandX[J] >= 0 then
              if InDirArc(CandX[J], CandY[J], TargX[K], TargY[K], Dir) then
              begin
                Ex := TargX[K];
                Ey := TargY[K];
                StepCount := MaxSteps;
                if WalkLine(CandX[J], CandY[J], Ex, Ey, StepCount, Map) then
                begin
                  Found := True;
                  if StepCount < Best then
                  begin
                    Best := StepCount;
                    BestJ := J;
                    BestK := K;
                  end;
                end;
              end;
      if Found then
      begin
        Inc(ds6718[0].Val);
        ds6718[ds6718[0].Val].Head := I;
        ds6718[ds6718[0].Val].Key := Best;
        L2 := 0;
        if Dir < 8 then
          L2 := Dir
        else
          while not InDirArc(CandX[BestJ], CandY[BestJ], TargX[BestK], TargY[BestK], L2) do
            Inc(L2);
        ds6718[ds6718[0].Val].Val := L2;
      end;
    end;
  SortTable;
end;

begin
end.

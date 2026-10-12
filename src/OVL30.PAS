unit OVL30;
{ ovl30: the line drawing unit (whitepaper 5.18). SignOf returns the sign of a value, SortTable
  sorts a 3-byte record table in place, SetupLine fills a Bresenham line state and StepLine advances
  it one step; the remaining routines are not decompiled yet. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
function SignOf(N: Integer): Integer;
procedure SortTable;
procedure SetupLine(Line: PLineState);
function StepLine(Line: PLineState): Boolean;
procedure ovl30_e5;
procedure ovl30_e4;
procedure ovl30_e6;
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
  < Val[I] and Val[J] mod 2 <= Val[I] mod 2. Called by ovl30_e6. }
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
  Called by ovl22_fn_295B, ovl30_e5 and res12_fn_1A29. }
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
  3*(StepY+1) + (StepX+1). Called by ovl22_fn_295B, ovl30_e5 and res12_fn_1A29. }
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
{ ovl30:0422. BLOCKED (dec-5, 2026-10-12): the line walk, 345 bytes, retf 20, frame 58. The
  prologue matches to ovl30:0473 (Limit := 2*Count^+1; Line from the endpoints; SetupLine(@Line);
  Bound from (0, ds2745[tile, 0]) to (Max(DX, DY), tile); SetupLine(@Bound)) and the loop shape is
  clear (step Bound then Line, QUIRK ovl30:0544 dead StepDone, stop on the ds2745[tile, 1] gate or
  First > Limit), but the ds2745 index codegen does not reproduce: the original adds Map + StartY*50
  + StartX with two separate adds to DI and folds +7 into [di+7], which a flat byte subscript does
  not. See the note in re/symbols.toml. }
{@stub} procedure ovl30_e5; begin end;
{ ovl30:057B: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl30_e4; begin end;
{ ovl30:0909: retf 14: 14 bytes of parameters; 32 bytes of locals }
{@stub} procedure ovl30_e6; begin end;

begin
end.

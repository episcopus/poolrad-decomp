unit OVL30;
{ ovl30: a resident-screen support unit (whitepaper 5.x). SignOf returns the sign of a value and
  SortTable sorts a 3-byte record table in place; the remaining routines are not decompiled yet. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
function SignOf(N: Integer): Integer;
procedure SortTable;
procedure SetupLine(Line: PLineState);
procedure ovl30_e3;
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
{ ovl30:02CC: retf 4: 4 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl30_e3; begin end;
{ ovl30:0422: retf 20: 20 bytes of parameters; 58 bytes of locals }
{@stub} procedure ovl30_e5; begin end;
{ ovl30:057B: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl30_e4; begin end;
{ ovl30:0909: retf 14: 14 bytes of parameters; 32 bytes of locals }
{@stub} procedure ovl30_e6; begin end;

begin
end.

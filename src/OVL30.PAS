unit OVL30;
{ ovl30: overlay unit, 3038 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
function SignOf(N: Integer): Integer;
procedure SortTable;
procedure ovl30_e2;
procedure ovl30_e3;
procedure ovl30_e5;
procedure ovl30_e4;
procedure ovl30_e6;
implementation

{ ovl30:0000. Returns the sign of N: -1 when N is negative, 1 when N is positive and 0 when N is
  zero. Called by ovl22_e63, ovl30_e2 and res12_fn_1CE0. }
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
  B: Byte;                        { Val of record J }
  A: Byte;                        { Val of record I }
  Temp: TSortRec;                 { the swap buffer }
begin
  if ds6718[0].Val <= 1 then
    Exit;
  for I := 1 to ds6718[0].Val - 1 do
  begin
    for J := I + 1 to ds6718[0].Val do
    begin
      A := ds6718[I].Val;
      B := ds6718[J].Val;
      if (ds6718[J].Key < ds6718[I].Key) or
         ((ds6718[J].Key = ds6718[I].Key) and (B < A) and ((B mod 2) <= (A mod 2))) then
      begin
        Temp := ds6718[I];
        ds6718[I] := ds6718[J];
        ds6718[J] := Temp;
      end;
    end;
  end;
end;
{ ovl30:01A0: retf 4: 4 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl30_e2; begin end;
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

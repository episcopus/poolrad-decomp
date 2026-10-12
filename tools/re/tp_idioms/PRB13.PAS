{ Probe for the loader's loop and call shapes (playbook 30). }
{$F+,S-,R-,I-}
program Prb13;

var
  Cnt: Byte;
  Arr: array[0..199] of Word;
  Slot: array[0..3] of record A, B: Word end;
  Rec: array[0..2] of record Kind: Byte; Addr: Pointer end;
  Buf: array[0..15] of Byte;
  BP: Pointer;

procedure P8(A, B: Byte); far;
begin
  A := B;
end;

procedure PW(A: Byte; B: Word); far;
begin
  A := B;
end;

procedure Take(var X: Pointer; A: Byte); far;
begin
  X := nil;
end;

begin
  for Cnt := 0 to $C7 do
  begin
    if Odd(Cnt) then
      Arr[Cnt] := $BA00 + (Cnt div 2) * 5
    else
      Arr[Cnt] := $B800 + (Cnt div 2) * 5;
    Arr[Cnt] := Cnt * $28;
    case Cnt mod 4 of
      0: Arr[Cnt] := (Cnt div 4) * $A + $B800;
      1: Arr[Cnt] := (Cnt div 4) * $A + $BA00;
      2: Arr[Cnt] := (Cnt div 4) * $A + $BC00;
      3: Arr[Cnt] := (Cnt div 4) * $A + $BE00;
    end;
  end;
  for Cnt := 1 to 2 do
  begin
    Rec[Cnt].Kind := $FF;
    Rec[Cnt].Addr := nil;
  end;
  for Cnt := 2 to 3 do
  begin
    Slot[Cnt].A := $FFFF;
    Slot[Cnt].B := $FFFF;
  end;
  P8(1, 2);
  P8(Cnt, Cnt + 13);
  PW(Cnt, Cnt + 13);
  Take(BP, 3);
  Randomize;
end.

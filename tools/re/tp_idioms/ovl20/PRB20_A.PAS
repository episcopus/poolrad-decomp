{ Probe for ovl20:0000. Which decrement and index form, Word zeroing, and frame
  padding match the original's shapes. }
{$A-,O+,F+,S-,R-,G-,I-}
program Prb20Affect;
type
  TClock = array[0..6] of Word;
var
  ClockRadix: TClock;
  ScaledAmount: Word;
  UnitIndex: ShortInt;
  Step: Byte;

procedure DecShort;
begin
  Dec(UnitIndex);
end;

procedure SubShort;
begin
  UnitIndex := UnitIndex - 1;
end;

procedure PredShort;
begin
  UnitIndex := Pred(UnitIndex);
end;

procedure IndexMinus;
begin
  ScaledAmount := ScaledAmount * ClockRadix[UnitIndex - 1];
end;

procedure IndexPred;
begin
  ScaledAmount := ScaledAmount * ClockRadix[Pred(UnitIndex)];
end;

procedure WordZero;
begin
  ScaledAmount := 0;
end;

procedure WordDecConst;
begin
  Dec(ScaledAmount, 10);
end;

procedure WordSubConst;
begin
  ScaledAmount := ScaledAmount - 10;
end;

procedure WhileGt;
begin
  while ScaledAmount > 0 do
    ScaledAmount := 0;
end;

procedure WhileNe;
begin
  while ScaledAmount <> 0 do
    ScaledAmount := 0;
end;

procedure CapAssign;
begin
  if ScaledAmount > 10 then
    Step := 10
  else
    Step := ScaledAmount;
end;

procedure Frame27;
var
  A: ShortInt;
  B: Byte;
  C: Byte;
  D: Word;
  E: Pointer;
  F: Byte;
  G: Byte;
  H: Pointer;
  I: Pointer;
  J: Pointer;
  K: Pointer;
begin
  A := 1;
  B := A;
end;

procedure Frame28;
var
  A: ShortInt;
  B: Byte;
  C: Byte;
  D: Word;
  E: Pointer;
  F: Byte;
  G: Byte;
  H: Pointer;
  I: Pointer;
  J: Pointer;
  K: Pointer;
  L: Byte;
begin
  A := 1;
  B := A;
  L := 0;
end;

begin
  DecShort;
  SubShort;
  PredShort;
  IndexMinus;
  IndexPred;
  WordZero;
  WordDecConst;
  WordSubConst;
  WhileGt;
  WhileNe;
  CapAssign;
  Frame27;
  Frame28;
end.

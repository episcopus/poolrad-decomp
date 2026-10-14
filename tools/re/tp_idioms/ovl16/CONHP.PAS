{ Probe for ovl16:3F31 (playbook 30, batch 16). The original frame is 8 bytes: result bp-1, Sum bp-2,
  counter bp-3, a spare byte bp-4, and a hidden `with Who^` pointer at bp-8 (offset) / bp-6
  (segment); its array index is sign-extended (`mov al,[bp-3]; cbw`). This finds the declaration
  combination that reproduces both. }
{$A-,O+,F+,S-,R-,G-,I-}
program ConHpProbe;
type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad0: array[0..$13] of Byte;
    Constitution: Byte;                     { +$14 }
    Pad15: array[$15..$2E] of Byte;
    ClassMask: ShortInt;                    { +$2F }
    Pad30: array[$30..$95] of Byte;
    ClassLevels: array[0..7] of ShortInt;   { +$96 }
  end;
var
  ds408E: array[0..$12] of ShortInt;
  G: PCharacter;
  R: ShortInt;

function VarA(Who: PCharacter): ShortInt;      { ShortInt counter + spare }
var
  Sum: ShortInt;
  I: ShortInt;
  Spare: Byte;
begin
  Sum := 0;
  with Who^ do
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
        Inc(Sum, ds408E[Constitution]);
  VarA := Sum;
end;

function VarB(Who: PCharacter): ShortInt;      { Byte counter, ShortInt(I) index + spare }
var
  Sum: ShortInt;
  I: Byte;
  Spare: Byte;
begin
  Sum := 0;
  with Who^ do
    for I := 0 to 7 do
      if ClassLevels[ShortInt(I)] > 0 then
        Inc(Sum, ds408E[Constitution]);
  VarB := Sum;
end;

function VarC(Who: PCharacter): ShortInt;      { Byte counter + ShortInt spare }
var
  Sum: ShortInt;
  I: Byte;
  Spare: ShortInt;
begin
  Sum := 0;
  with Who^ do
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
        Inc(Sum, ds408E[Constitution]);
  VarC := Sum;
end;

begin
  R := VarA(G);
  R := VarB(G);
  R := VarC(G);
end.

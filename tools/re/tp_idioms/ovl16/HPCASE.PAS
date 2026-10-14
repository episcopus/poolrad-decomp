{ Probe for ovl16:3FB3 (playbook 30, batch 16). The original tests class indices 4 and 7 with
  `mov al,[bp-5]; cmp al,4; jne ..; inc; jmp ..; cmp al,7; jne ..; inc` (the selector loaded once),
  not two direct memory compares. This finds the construct (if/else chain vs case) that emits that. }
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
  G: PCharacter;
  R: Byte;

function Adj(Who: PCharacter): ShortInt;
begin
  Adj := 0;
end;

function IfElse(Who: PCharacter): Byte;
var
  Count: Byte;
  Adjustment: ShortInt;
  Total: Byte;
  I: ShortInt;
begin
  with Who^ do
  begin
    Count := 0;
    Total := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Total, ClassLevels[I]);
        Inc(Count);
        if I = 4 then
          Inc(Total)
        else if I = 7 then
          Inc(Total);
      end;
  end;
  Adjustment := Adj(Who);
  if Adjustment < 0 then
  begin
    if Total > Abs(Adjustment) + Count then
      Total := (Total + Adjustment) div Count
    else
      Total := 1;
  end
  else
    Total := (Total + Adjustment) div Count;
  IfElse := Total;
end;

function CaseSel(Who: PCharacter): Byte;
var
  Count: Byte;
  Adjustment: ShortInt;
  Total: Byte;
  I: ShortInt;
begin
  with Who^ do
  begin
    Count := 0;
    Total := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Total, ClassLevels[I]);
        Inc(Count);
        case I of
          4: Inc(Total);
          7: Inc(Total);
        end;
      end;
  end;
  Adjustment := Adj(Who);
  if Adjustment < 0 then
  begin
    if Total > Abs(Adjustment) + Count then
      Total := (Total + Adjustment) div Count
    else
      Total := 1;
  end
  else
    Total := (Total + Adjustment) div Count;
  CaseSel := Total;
end;

begin
  R := IfElse(G);
  R := CaseSel(G);
end.

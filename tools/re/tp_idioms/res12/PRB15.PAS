{ Probe for res12:0BB8 (playbook 30).
  Question: which form gives `cmp al,0; jb` / `cmp al,8; ja` (unsigned range) with a cwde
  (signed) array index. Candidates: a set test `X in [0..8]` on a ShortInt, or a case with a
  cast selector. Original 00BA:0C89..0CA7. }
{$F+,S-,R-,I-}
program Res12Probe15;

type
  PItem = ^Byte;
  TChar = record
    SlotItems: array[0..12] of PItem;
  end;
  PChar = ^TChar;

var
  K: ShortInt;
  C: PChar;

procedure InSetShortInt(Who: PChar; Item: PItem); far;
var
  X: ShortInt;
begin
  X := K;
  if X in [0..8] then
    Who^.SlotItems[X] := Item
  else if X = 9 then
    Who^.SlotItems[9] := Item;
end;

procedure CaseShortCast(Who: PChar; Item: PItem); far;
var
  X: ShortInt;
begin
  X := K;
  case Byte(X) of
    0..8: Who^.SlotItems[X] := Item;
    9: Who^.SlotItems[9] := Item;
  end;
end;

begin
  InSetShortInt(C, nil);
  CaseShortCast(C, nil);
end.

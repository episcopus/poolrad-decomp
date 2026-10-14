{ Probe for res12:0BB8 (playbook 30).
  Question: which selector type and form make the case over the item kind compile to
  `cmp al,0; jb` / `cmp al,8; ja` (unsigned) while SlotItems[ItemKind] indexes with cwde
  (signed). The original is 00BA:0C89..0CA7. }
{$F+,S-,R-,I-}
program Res12Probe14;

type
  PItem = ^Byte;
  TChar = record
    SlotItems: array[0..12] of PItem;
  end;
  PChar = ^TChar;

var
  K: ShortInt;
  B: Byte;
  C: PChar;

procedure WithShortInt(Who: PChar; Item: PItem); far;
var
  X: ShortInt;
begin
  X := K;
  case X of
    0..8: Who^.SlotItems[X] := Item;
    9: Who^.SlotItems[9] := Item;
  end;
end;

procedure WithByte(Who: PChar; Item: PItem); far;
var
  X: Byte;
begin
  X := B;
  case X of
    0..8: Who^.SlotItems[X] := Item;
    9: Who^.SlotItems[9] := Item;
  end;
end;

begin
  WithShortInt(C, nil);
  WithByte(C, nil);
end.

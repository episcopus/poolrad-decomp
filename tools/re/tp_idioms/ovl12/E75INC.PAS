program Scratch75;
{$A-,O+,F+,S-,R-,G-,I-}
type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$13] of Byte;
    Constitution: Byte;
  end;
  PAffect = ^TAffect;
  TAffect = record
    Next: Pointer;
    Id: Byte;
    Data: Byte;
    Flag: Byte;
  end;
const
  SaveKindPoison = 0;
var
  SaveRoll: Byte;
  SaveKind: Byte;

procedure E75(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Bonus: Byte;
begin
  if SaveKind = SaveKindPoison then
  begin
    case Who^.Constitution of
      4..6: Bonus := 1;
      7..10: Bonus := 2;
      11..13: Bonus := 3;
      14..17: Bonus := 4;
      18..20: Bonus := 5;
    end;
    Inc(SaveRoll, Bonus);
  end;
end;

begin
  E75(nil, nil, 0);
end.

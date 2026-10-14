{ Probe for res12:2E03 (playbook 30).
  Question: the original 00BA:2E03 tests SlotItems[0] <> nil and then RaceRow[ItemType][$C] > 1
  as one short-circuit `and`, with the RaceRow row scaled by `mov cl,4; shl di,cl`. Why is our
  compiled true path 6 bytes short of the original? This probe reproduces the record shapes and
  the RaceRow global at the same DS offset (absolute $5582). }
{$A-,F+,S-,R-,G-,I-}
program Res12Probe32;

type
  TRaceRow = array[0..15] of Byte;
  PItem = ^TMenuLine;
  TMenuLine = record
    Pad: array[0..$2D] of Byte;
    ItemType: Byte;               { +$2E }
  end;
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$CB] of Byte;
    SlotItems: array[0..12] of PItem;  { +$CC }
  end;

var
  RaceRow: array[0..128] of TRaceRow absolute $0000:$5582;

function HasMeleeWeapon(Who: Pointer): Boolean; far;
begin
  HasMeleeWeapon := (PCharacter(Who)^.SlotItems[0] <> nil) and
                    (RaceRow[PCharacter(Who)^.SlotItems[0]^.ItemType][$C] > 1);
end;

begin
  if HasMeleeWeapon(nil) then RaceRow[0][0] := 0;
end.

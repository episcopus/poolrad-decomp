program PRB20_DEC;
{$A-,O+,F+,S-,R-,G-,I-}
type
  TCharacter = record
    Spells: array[0..20] of Byte;
  end;
  PCharacter = ^TCharacter;
var
  Who: PCharacter;
  SpellIndex: Byte;
begin
  Dec(Who^.Spells[SpellIndex], $80);
end.

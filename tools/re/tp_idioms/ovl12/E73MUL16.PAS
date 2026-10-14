program Scratch73b;
{$A-,O+,F+,S-,R-,G-,I-}
const
  RotDataLow = $0F;
var
  W: Word;
  B: Byte;
  X: Word;
  Y: Byte;

function RollDice(Count, Sides: Byte): Byte;
begin
  RollDice := 1;
end;

begin
  W := RollDice(1, 6) shl 4;
  B := RollDice(1, 6) shl 4;
  B := (RollDice(1, 6) shl 4) + RotDataLow;
  X := (RollDice(1, 6) shl 4) + RotDataLow;
  Y := (RollDice(1, 6) shl 4) + RotDataLow;
  W := Word(RollDice(1, 6)) shl 4;
  W := RollDice(1, 6) * 16;
  B := RollDice(1, 6) * 16 + RotDataLow;
end.

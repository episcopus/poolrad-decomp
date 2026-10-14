{ Probe: how TP 6.0 indexes a global 1-based far-pointer array by a Byte variable
  (ovl22:08C3 reads SpellTargets[I] with I*4 + 0x6C91). }
{$A-,F+,S-,R-,G-,I-}
program PtrArr;

type
  PCharacter = ^Byte;

var
  One: array[1..10] of PCharacter;
  Zero: array[0..10] of PCharacter;
  I: Byte;
  P: PCharacter;

begin
  P := One[I];
  P := Zero[I];
  if One[I] <> nil then P := One[I];
end.

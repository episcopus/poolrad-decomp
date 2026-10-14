{ Probe for ovl16:209F (playbook 30, batch 12). Does a 2D array with a shifted second-dimension
  lower bound fold the shift into the base (`[di+base+2]`) like the original ovl16 StrMax lookup? }
{$A-,O+,F+,S-,R-,G-,I-}
program AbsProbe;
var
  Race, B9E: ShortInt;
  V: Byte;

var
  StrMin: array[0..15, 0..15] of Byte;
  StrMax: array[0..15, -2..13] of Byte absolute StrMin;

begin
  V := StrMin[Race, B9E];
  V := StrMax[Race, B9E];
end.

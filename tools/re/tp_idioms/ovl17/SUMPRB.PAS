{ Probe for ovl17_e9 (playbook 30).
  Question: the original stores ShowMonsterPics * 2 + ShowPortraits at ovl17:1EF6 as
  `mov al,[ShowPortraits]; xor ah,ah; mov dx,ax; mov al,[ShowMonsterPics]; xor ah,ah; shl ax,1;
  add ax,dx`. Which source form of the sum loads ShowPortraits first? }
{$A-,O+,F+,S-,R-,G-,I-}
program SumProbe;

var
  A, B: Byte;
  X: Word;

begin
  X := A + B * 2;
  X := B * 2 + A;
  X := A + 2 * B;
end.

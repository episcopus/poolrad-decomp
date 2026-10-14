program SHR4;
{ Probe (ovl12_e113 work): V1 = Who^.B shr 4 is mov cx, 4; shr ax, cl. V2 = Who^.B div 16 is mov cl, 4; shr ax, cl
  (the form of the original). Disassemble with make tpc SRC=... DISASM=1 on the procedures (their addresses are in the map). }
{$A-,O+,F+,S-,R-,G-,I-}
type
  PR = ^TR;
  TR = record
    A: array[0..$3C] of Byte;
    B: Byte;
  end;
var
  Rec: PR;
procedure V1(Who: PR; Mode: Byte);
var
  D: Byte;
begin
  D := Who^.B shr 4;
  if D = Mode then Mode := 0;
end;
procedure V2(Who: PR; Mode: Byte);
var
  D: Byte;
begin
  D := Who^.B div 16;
  if D = Mode then Mode := 0;
end;
begin
  New(Rec);
  V1(Rec, 0);
  V2(Rec, 0);
end.

program BYTEADD;
{ Probe for ovl03:12C6 (ComputePartyValueCommand). The sum of five products divided by 10 is added
  to a Byte. Checksum := Checksum + (...) div 10 widens the byte to a word after the div: mov dx,ax;
  mov al,[Checksum]; xor ah,ah; add ax,dx; mov [Checksum],al (12 bytes). Inc(Checksum, ...) adds
  AL to the byte in place: add byte ptr [Checksum],al (3 bytes), the form the original uses.
  Run: make tpc SRC=tools/re/tp_idioms/ovl03/BYTEADD.PAS DISASM=1 }
var
  Checksum: Byte;
  HitPoints, HitAdjust, ClassLevel5, ClassLevel0, ResistValue: Byte;

procedure WideAdd;
begin
  Checksum := Checksum + (HitPoints + 5 * ResistValue + 5 * HitAdjust + 8 * ClassLevel5 + 4 * ClassLevel0) div 10;
end;

procedure InPlaceAdd;
begin
  Inc(Checksum, (HitPoints + 5 * ResistValue + 5 * HitAdjust + 8 * ClassLevel5 + 4 * ClassLevel0) div 10);
end;

begin
  WideAdd;
  InPlaceAdd;
end.

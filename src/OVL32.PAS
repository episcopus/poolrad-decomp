unit OVL32;
{ PicLoad: overlay unit, 1605 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure Load24x24Set;
procedure ovl32_e2;
procedure ovl32_e3;
procedure ovl32_e4;
procedure ovl32_e5(A, B: ShortInt; C, D, E: Byte);
implementation

{ ovl32:0022: retf 8: 8 bytes of parameters; 264 bytes of locals }
{@stub} procedure Load24x24Set; begin end;
{ ovl32:00F1: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl32_e2; begin end;
{ ovl32:014E: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl32_e3; begin end;
{ ovl32:01C8: retf 8: 8 bytes of parameters; 1028 bytes of locals }
{@stub} procedure ovl32_e4; begin end;
{ ovl32:04FC: retf 10: 10 bytes of parameters; 8 bytes of locals.
  Draws an icon: A and B name the cell (times 3 pixels each when they reach the display call
  res07_fn_0D71), C the picture set (its table is ds5E5A, checked against 3), D and E the mirror
  half and the picture index. DrawPartyMarker passes the marker cell, ds6AAF and MarkerFrame mod 2 and
  div 2 + 9. }
{@stub} procedure ovl32_e5(A, B: ShortInt; C, D, E: Byte); begin end;

begin
end.

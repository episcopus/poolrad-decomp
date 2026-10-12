unit OVL32;
{ PicLoad: overlay unit, 1605 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure Load24x24Set;
procedure ovl32_e2(PicCol, PicRow: Shortint; PicCode, Unused: Byte);
procedure ovl32_e3;
procedure ovl32_e4;
procedure ovl32_e5;
implementation

{ ovl32:0022: retf 8: 8 bytes of parameters; 264 bytes of locals }
{@stub} procedure Load24x24Set; begin end;
{ ovl32:00F1: retf 8: 8 bytes of parameters; 0 bytes of locals }
{ Draws the picture of code PicCode (bit 7 is a flag the blitter sees, the low 7 bits pick the
  picture) at cell position (PicCol, PicRow) of the 3D view window; Unused is never read by the
  callee (1 from DrawAreaView, 0 from ovl31). Signature from the pushes of the callers and the code of the callee. }
{@stub} procedure ovl32_e2(PicCol, PicRow: Shortint; PicCode, Unused: Byte); begin end;
{ ovl32:014E: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl32_e3; begin end;
{ ovl32:01C8: retf 8: 8 bytes of parameters; 1028 bytes of locals }
{@stub} procedure ovl32_e4; begin end;
{ ovl32:04FC: retf 10: 10 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl32_e5; begin end;

begin
end.

unit OVL27;
{ ovl27: overlay unit, 648 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure ovl27_e1(MapLeft, MapTop: Integer);
procedure ovl27_e2;
implementation

{ ovl27:0000: retf 4: 4 bytes of parameters; 8 bytes of locals.
  Draws the 5x5 map window: 25 cells of the 44-column map grid (ds3648) at 3 pixels per cell,
  each cell through ovl32_e2 (the tile id comes from the grid minus 1, or from the 9 exit records
  ds0C36[1..9] when one matches the cell). MapLeft and MapTop are the left column and the top
  row of the window, which ShowAreaView clamps to 0..39 and 0..31. }
{@stub} procedure ovl27_e1(MapLeft, MapTop: Integer); begin end;
{ ovl27:0207: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl27_e2; begin end;

begin
end.

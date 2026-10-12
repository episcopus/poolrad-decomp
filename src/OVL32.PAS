unit OVL32;
{ PicLoad: picture sets and the block blit (whitepaper 4.2.3). DrawCellPicture draws one picture
  code at a cell of the view; Load24x24Set loads the CHEAD, CBODY, COMSPR and ICON sets. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure Load24x24Set;
procedure DrawCellPicture(PicCol, PicRow: Shortint; PicCode, Unused: Byte);
procedure ovl32_e3;
procedure ovl32_e4;
procedure ovl32_e5(A, B: ShortInt; C, D, E: Byte);
implementation
uses POOLVARS, RES07;

const
  PicIndexMask = $7F;         { bit 7 of the picture code selects the source pointer }
  NoBlitFlags = 0;            { the flags byte this routine passes to the blitter }

{ ovl32:0022: retf 8: 8 bytes of parameters; 264 bytes of locals }
{@stub} procedure Load24x24Set; begin end;

{ ovl32:00F1. Draws the picture PicCode at cell (PicCol, PicRow). When PicCode is above
  PicIndexMask, bit 7 is cleared and the source is ds5E56; otherwise the source is ds5E52
  and the code is passed whole. Both paths pass NoBlitFlags and the destination ds4A20 to
  res07_fn_08D4. Unused is never read (DrawAreaView passes 1, ovl31 passes 0). }
procedure DrawCellPicture(PicCol, PicRow: Shortint; PicCode, Unused: Byte);
begin
  if PicCode > PicIndexMask then
    res07_fn_08D4(PicCol, PicRow, PicCode and PicIndexMask, NoBlitFlags, ds5E56, ds4A20)
  else
    res07_fn_08D4(PicCol, PicRow, PicCode, NoBlitFlags, ds5E52, ds4A20);
end;
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

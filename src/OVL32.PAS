unit OVL32;
{ PicLoad: picture sets and the block blit (whitepaper 4.2.3). DrawCellPicture draws one picture
  code at a cell of the view; Load24x24Set loads the CHEAD, CBODY, COMSPR and ICON sets. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure Load24x24Set;
procedure DrawCellPicture(PicCol, PicRow: Shortint; PicCode, Unused: Byte);
procedure FreePictureSlot(Slot: Byte);
procedure ovl32_e4;
procedure DrawIcon(CellCol, CellRow: Shortint; IconSet, Mirror, PicIndex: Byte);
implementation
uses POOLVARS, RES07;

const
  PicIndexMask = $7F;         { bit 7 of the picture code selects the source pointer }
  NoBlitFlags = 0;            { the flags byte this routine passes to the blitter }
  IconSetCopyLimit = 3;       { icon sets above this are copied by res07_fn_15C7 }
  OneItem = 1;                { item count stored in the allocated picture }
  AllocatePixels = 1;         { bit 0 of AllocFlags asks res07_fn_248E for a pixel buffer }
  NoPicIndex = 0;             { picture index this routine passes to res07_fn_0D71 }
  BlitFlagBit = 1;            { res07_fn_0D71 tests bit 0 of the flags byte }
  CellStep = 3;               { the cell column and row are multiplied by 3 for the blit }
  QuarterAdapter = 1;         { VideoAdapter 1: the pixel copy is a quarter of the byte size }

type
  PMemPic = ^TMemPic;
  { In-memory picture. Height and width are the words at +0 and +2. ByteSize, the pixel
    pointer and the copied tail sit at +$11, +$13 and +$17; the 13 bytes between width and
    ByteSize are not read here. }
  TMemPic = record
    Height, WidthCols: Word;
    BeforeSize: array[0..12] of Byte;
    ByteSize: Word;
    Pixels: ^Byte;
    Tail: Byte;
  end;

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
{ ovl32:014E. Frees both pictures of one slot in ds5E5A, when the pointer is not nil,
  through res07_fn_2595 (FreeMem, then the pointer is set nil). Slot selects the
  record, stride 8. QUIRK ovl32:0151: UnusedWord is allocated and never read or written. }
procedure FreePictureSlot(Slot: Byte);
var
  UnusedWord: Word;
begin
  if ds5E5A[Slot].FirstPic <> nil then res07_fn_2595(ds5E5A[Slot].FirstPic);
  if ds5E5A[Slot].SecondPic <> nil then res07_fn_2595(ds5E5A[Slot].SecondPic);
end;
{ ovl32:01C8: retf 8: 8 bytes of parameters; 1028 bytes of locals }
{@stub} procedure ovl32_e4; begin end;
{ ovl32:04FC. Draws the picture PicIndex, mirror half Mirror, from the table at ds5E5A.
  Nothing happens when that pointer is nil. Otherwise a picture of the same height and
  width is allocated, the bytes are copied (res07_fn_15C7 when IconSet is above
  IconSetCopyLimit, otherwise Move of the tail and the pixels), and res07_fn_0D71 draws
  it at the cell times CellStep. The copy is then freed. DrawPartyMarker passes the
  marker cell, the icon set ds6AAF, and the walk frame split into half and picture. }
procedure DrawIcon(CellCol, CellRow: Shortint; IconSet, Mirror, PicIndex: Byte);
var
  Dest: Pointer;
begin
  if ds5E5A[PicIndex].Pics[Mirror] <> nil then
  begin
    with PMemPic(ds5E5A[PicIndex].Pics[Mirror])^ do
    begin
      res07_fn_248E(Height, WidthCols, OneItem, AllocatePixels, Dest);
      if IconSet > IconSetCopyLimit then
        res07_fn_15C7(ds5E5A[PicIndex].Pics[Mirror], Dest)
      else
      begin
        Move(Tail, PMemPic(Dest)^.Tail, ByteSize);
        if VideoAdapter = QuarterAdapter then
          Move(Pixels^, PMemPic(Dest)^.Pixels^, ByteSize shr 1 shr 1)
        else
          Move(Pixels^, PMemPic(Dest)^.Pixels^, ByteSize);
      end;
    end;
    res07_fn_0D71(CellCol * CellStep, CellRow * CellStep, NoPicIndex, BlitFlagBit, Dest, ds4A20);
    res07_fn_2595(Dest);
  end;
end;

begin
end.

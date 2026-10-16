unit OVL32;
{ PicLoad: picture sets and the block blit (whitepaper 4.2.3). DrawCellPicture draws one picture
  code at a cell of the view; Load24x24Set copies a loaded set into the bank at SqrPaciBank1;
  LoadPictureSlot loads a picture and its mirrored half into a slot of the table PictureSlots,
  FreePictureSlot frees them, and DrawIcon draws a copy of one. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure Load24x24Set(SetName: string; Index, Unused: Byte);
procedure DrawCellPicture(PicCol, PicRow: Shortint; PicCode, Unused: Byte);
procedure FreePictureSlot(Slot: Byte);
procedure LoadPictureSlot(SetName: string; Block, Slot: Byte);
procedure DrawIcon(CellCol, CellRow: Shortint; IconSet, Mirror, PicIndex: Byte);
implementation
uses POOLVARS, RES04, RES07;

const
  PicIndexMask = $7F;         { bit 7 of the picture code selects the source pointer }
  NoBlitFlags = 0;            { the flags byte this routine passes to the blitter }
  IconSetCopyLimit = 3;       { icon sets above this are copied by MirrorPicture }
  OneItem = 1;                { item count stored in the allocated picture }
  AllocatePixels = 1;         { bit 0 of AllocFlags asks AllocatePicture for a pixel buffer }
  NoPicIndex = 0;             { picture index this routine passes to DrawPictureItemClipped }
  BlitFlagBit = 1;            { DrawPictureItemClipped tests bit 0 of the flags byte }
  CellStep = 3;               { the cell column and row are multiplied by 3 for the blit }
  AltPictures = $40;          { a CHEAD/CBODY name ending in T selects the pictures from $40 on }
  MirrorPictures = $80;       { the mirrored half of picture N is picture N + $80 }

type
  PMemPic = ^TMemPic;
  { In-memory picture. Height and width are the words at +0 and +2, the item count is the
    byte at +8, and ByteSize, the pixel pointer and the copied tail sit at +$11, +$13 and +$17.
    Tail is indexed by a byte times ByteSize; the array bound is only there so the index compiles. }
  TMemPic = record
    Height, WidthCols: Word;
    BeforeCount: array[0..3] of Byte;
    ItemCount: Byte;
    AfterCount: array[0..7] of Byte;
    ByteSize: Word;
    Pixels: ^Byte;
    Tail: array[0..20000] of Byte;
  end;

{ ovl32:0022. Loads the picture set SetName and, when SqrPaciBank1 is not nil, copies one picture's
  bytes into it at Index times the picture's byte size. Index above 127 prints
  "Start range error in Load24x24Set" and leaves through QuitGame. Callers in ovl03 and ovl10
  pass 40, 24 or 5 as Unused; this routine never reads it. }
procedure Load24x24Set(SetName: string; Index, Unused: Byte);
var
  Loaded: Pointer;
  CopyBytes, DestOfs: Word;
begin
  if Index > PicIndexMask then
  begin
    RestoreVideoMode;
    WriteLn('Start range error in Load24x24Set');
    QuitGame;
  end;
  Loaded := nil;
  LoadPicture(SetName, 1, 0, 0, Loaded);
  CopyBytes := PMemPic(Loaded)^.ItemCount * PMemPic(Loaded)^.ByteSize;
  DestOfs := Index * PMemPic(Loaded)^.ByteSize;
  if SqrPaciBank1 <> nil then
    Move(PMemPic(Loaded)^.Tail, PMemPic(SqrPaciBank1)^.Tail[DestOfs], CopyBytes);
  ReleasePicture(Loaded);
  FlushKeyboard;
end;

{ ovl32:00F1. Draws the picture PicCode at cell (PicCol, PicRow). When PicCode is above
  PicIndexMask, bit 7 is cleared and the source is SqrPaciBank2; otherwise the source is SqrPaciBank1
  and the code is passed whole. Both paths pass NoBlitFlags and the destination DrawBuf to
  DrawPictureItem. Unused is never read (DrawAreaView passes 1, ovl31 passes 0). }
procedure DrawCellPicture(PicCol, PicRow: Shortint; PicCode, Unused: Byte);
begin
  if PicCode > PicIndexMask then
    DrawPictureItem(PicCol, PicRow, PicCode and PicIndexMask, NoBlitFlags, SqrPaciBank2, DrawBuf)
  else
    DrawPictureItem(PicCol, PicRow, PicCode, NoBlitFlags, SqrPaciBank1, DrawBuf);
end;
{ ovl32:014E. Frees both pictures of one slot in PictureSlots, when the pointer is not nil,
  through ReleasePicture (FreeMem, then the pointer is set nil). Slot selects the
  record, stride 8. QUIRK ovl32:0151: UnusedWord is allocated and never read or written. }
procedure FreePictureSlot(Slot: Byte);
var
  UnusedWord: Word;
begin
  if PictureSlots[Slot].FirstPic <> nil then ReleasePicture(PictureSlots[Slot].FirstPic);
  if PictureSlots[Slot].SecondPic <> nil then ReleasePicture(PictureSlots[Slot].SecondPic);
end;
{ ovl32:01C8. Loads picture Block of the set SetName into the first pointer of slot Slot of
  the picture table PictureSlots and picture Block + $80 (its mirrored half) into the second.
  CHEAD and CBODY sets: a name ending in T adds $40 to Block and loses that letter. COMSPR and
  ICON: the name is used as it is, and ICON pictures are recoloured with PictureRemap13To0. Any other set
  takes the file number TileSet as a suffix and both pictures are recoloured with PictureRemap13To8
  (RemapPictureColors, from the identity map PictureRemapFrom). Flushes the keyboard at the end. StartGame
  loads COMSPR pictures 0 to 11 into slots 13 to 24 and picture 25 into slot 25 with it. }
procedure LoadPictureSlot(SetName: string; Block, Slot: Byte);
var
  Suffix: string[1];
  UnusedByte: Byte;  { QUIRK ovl32:01CB: one byte of the frame (bp-$103) is never used }
begin
  if (Copy(SetName, 1, 5) = 'CHEAD') or (Copy(SetName, 1, 5) = 'CBODY') then
  begin
    if UpCase(SetName[Length(SetName)]) = 'T' then Inc(Block, AltPictures);
    SetName := Copy(SetName, 1, Length(SetName) - 1);
    Suffix := '';
    LoadPicture(SetName + Suffix, Block, 1, 0, PictureSlots[Slot].FirstPic);
    LoadPicture(SetName + Suffix, Block + MirrorPictures, 1, 0, PictureSlots[Slot].SecondPic);
  end
  else if (SetName = 'COMSPR') or (SetName = 'ICON') then
  begin
    Suffix := '';
    LoadPicture(SetName + Suffix, Block, 1, 0, PictureSlots[Slot].FirstPic);
    LoadPicture(SetName + Suffix, Block + MirrorPictures, 1, 0, PictureSlots[Slot].SecondPic);
    if SetName = 'ICON' then
    begin
      RemapPictureColors(@PictureRemapFrom, @PictureRemap13To0, 0, 0, PictureSlots[Slot].FirstPic);
      RemapPictureColors(@PictureRemapFrom, @PictureRemap13To0, 0, 0, PictureSlots[Slot].SecondPic);
    end;
  end
  else
  begin
    Str(TileSet, Suffix);
    LoadPicture(SetName + Suffix, Block, 1, 0, PictureSlots[Slot].FirstPic);
    RemapPictureColors(@PictureRemapFrom, @PictureRemap13To8, 0, 0, PictureSlots[Slot].FirstPic);
    LoadPicture(SetName + Suffix, Block + MirrorPictures, 1, 0, PictureSlots[Slot].SecondPic);
    RemapPictureColors(@PictureRemapFrom, @PictureRemap13To8, 0, 0, PictureSlots[Slot].SecondPic);
  end;
  FlushKeyboard;
end;
{ ovl32:04FC. Draws the picture PicIndex, mirror half Mirror, from the table at PictureSlots.
  Nothing happens when that pointer is nil. Otherwise a picture of the same height and
  width is allocated, the bytes are copied (MirrorPicture when IconSet is above
  IconSetCopyLimit, otherwise Move of the tail and the pixels), and DrawPictureItemClipped draws
  it at the cell times CellStep. The copy is then freed. DrawPartyMarker passes the
  marker cell, the icon set PartyFacing, and the walk frame split into half and picture. }
procedure DrawIcon(CellCol, CellRow: Shortint; IconSet, Mirror, PicIndex: Byte);
var
  Dest: Pointer;
begin
  if PictureSlots[PicIndex].Pics[Mirror] <> nil then
  begin
    with PMemPic(PictureSlots[PicIndex].Pics[Mirror])^ do
    begin
      AllocatePicture(Height, WidthCols, OneItem, AllocatePixels, Dest);
      if IconSet > IconSetCopyLimit then
        MirrorPicture(PictureSlots[PicIndex].Pics[Mirror], Dest)
      else
      begin
        Move(Tail, PMemPic(Dest)^.Tail, ByteSize);
        if VideoAdapter = AdapterEga then
          Move(Pixels^, PMemPic(Dest)^.Pixels^, ByteSize shr 1 shr 1)
        else
          Move(Pixels^, PMemPic(Dest)^.Pixels^, ByteSize);
      end;
    end;
    DrawPictureItemClipped(CellCol * CellStep, CellRow * CellStep, NoPicIndex, BlitFlagBit, Dest, DrawBuf);
    ReleasePicture(Dest);
  end;
end;

begin
end.

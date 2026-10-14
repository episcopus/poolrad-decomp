unit RES07;
{ The picture unit: loads a DAX picture block into a picture record (routine
  0111), unpacks the 4-bit pixel data of a picture for the active video adapter
  (02A5), blits pictures, cells and sprites with clipping (08D4, 0D71, 15C7,
  1951) and builds the 8x8 tile and sprite banks that combat, the 3D view and
  the title draw from. Evidence: callers ovl32 LoadPictureSlot/Load24x24Set,
  ovl34 Load8x8Bank, ovl28 DrawSprite, ovl01 ShowTitleScreen
  (build/packets/res07.md); picture format and roles: whitepaper 4.2.3, 5.16. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses Dos, POOLVARS, RES04, RES05;

type
  { an 8-byte, 16-entry 4-bit colour palette; a picture holds it at +9 }
  TPalette = array[0..7] of Byte;
  PPalette = ^TPalette;
  { the pixel-buffer pointer at +$13 is indexed byte-wise (the array bound is
    only there so the index compiles, like the picture record's tail) }
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;
  { a 16-entry colour map: entry I is the colour index that colour I becomes (1E5C) }
  TColorMap = array[0..15] of Byte;
  PColorMap = ^TColorMap;

  { An in-memory picture (whitepaper 4.2.3): the DAX header fields at +0..+$10,
    then ByteSize (the bytes per item), the pixel-buffer pointer at +$13 and the
    packed pixel data from +$17 on (variable length, so the last field is a
    one-byte array indexed with $R- off, like ovl32's TMemPic). }
  TPicture = record
    Height: Word;                 { +0 }
    WidthCols: Word;              { +2 }
    XPos: Word;                   { +4 }
    YPos: Word;                   { +6 }
    ItemCount: Byte;              { +8 }
    Palette: TPalette;            { +9, 8 bytes }
    ByteSize: Word;               { +$11 }
    Pixels: PByteArray;           { +$13 }
    Data: array[0..0] of Byte;    { +$17, the packed pixel data }
  end;
  PPicture = ^TPicture;

function ColorMatchMask(Color: Byte; Data: LongInt): Byte;
function PaletteColor(Index: Byte; Source: PPalette): Byte;
procedure SetVideoMode(Mode: Byte);
procedure RestoreVideoMode;
procedure LoadPicture(Text: string; BlockId, AllocFlags, Color: Byte; var Target);
procedure UnpackPicturePixels(Source: Pointer; Offset: Word; AllocFlags, Color: Byte; Data: Pointer);
procedure DrawPictureItem(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
procedure DrawPictureItemClipped(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
function MirrorByte(Value: Byte): Byte;
function MirrorWord(Value: Word): Word;
function SwapNibbles(Value: Byte): Byte;
procedure MirrorPicture(Source, Dest: Pointer);
procedure ShowPicture(PicCol, PicRow: Integer; Buf: Pointer);
procedure FlushPictureChanges;
procedure RemapPictureColours(FromMap, ToMap: Pointer; FirstItem: Integer; Flicker: Byte; Pic: Pointer);
procedure AllocatePicture(Height, WidthCols: Word; ItemCount, AllocFlags: Byte; var Pic);
procedure ReleasePicture(var Pic);
procedure FillPictureRect(FirstCol, FirstRow: Integer; Width, Height: Word; Colour: Byte; Palette: Pointer; Target: Pointer);
procedure SetPaletteRegister(Register, Color: Byte);
implementation

{ 0464:0000: retf 6: one Byte and one LongInt parameter; 6 bytes of locals.
  Returns a bit mask of the eight nibbles of Data (four bytes) that equal Color:
  bit 7 is the high nibble of Data[0], bit 0 the low nibble of Data[3]. }
function ColorMatchMask(Color: Byte; Data: LongInt): Byte;
var
  { the four bytes of Data (one picture cell), indexed as bytes }
  CellBytes: array[0..3] of Byte absolute Data;
  Sum, Target, Mask, I: Byte;
begin
  Sum := 0;
  Target := Color shl 4;
  Mask := $80;
  for I := 0 to 3 do
  begin
    if (CellBytes[I] and $F0) = Target then Inc(Sum, Mask);
    Mask := Mask shr 1;
    if (CellBytes[I] and $0F) = Color then Inc(Sum, Mask);
    Mask := Mask shr 1;
  end;
  ColorMatchMask := Sum;
end;
{ 0464:007B: retf 6: a palette pointer and a nibble index. Copies the eight
  palette bytes to a local and returns the palette colour for pixel value Index:
  even Index takes the high nibble, odd Index the low nibble of Pal[Index shr 1]. }
function PaletteColor(Index: Byte; Source: PPalette): Byte;
var
  Pal: TPalette;
begin
  Pal := Source^;
  if Odd(Index) then
    PaletteColor := Pal[Index shr 1] and $0F
  else
    PaletteColor := (Pal[Index shr 1] and $F0) shr 4;
end;
{ 0464:00CF: sets video mode A through INT 10h function 0, the way the game
  changes the EGA mode: the mode that was current (ds4A1D) is kept in
  SavedVideoMode so the restore routine can go back, then ds4A1D becomes A.
  Called by res08_init with $0D and by the restore routine. }
procedure SetVideoMode(Mode: Byte);
var
  { QUIRK 0464:00D2: the original allocates a two-byte local it never reads or
    writes; the compiler keeps declared locals, so the source had one too. }
  UnusedMode: Byte;
begin
  SavedVideoMode := ds4A1D;
  Regs.AH := 0;                      { INT 10h function 0: set video mode }
  Regs.AL := Mode;
  Intr($10, Regs);
  ds4A1D := Mode;
end;

{ 0464:00FF: restores the video mode saved at the last mode set through
  SavedVideoMode. Called by the picture loaders before they draw a range or
  name error message, and by the loaders that switch modes to show a picture. }
procedure RestoreVideoMode;
begin
  SetVideoMode(SavedVideoMode);
end;
{ 0464:0111: loads DAX picture block A of the set Text (with the '.dax'
  extension) into the caller's picture pointer: frees any picture already there,
  copies the header fields into locals, AllocatePicture (B = the pixel-buffer
  flag), stores the X/Y position and palette into the new picture, unpacks the
  pixels through 02A5 (C = the colour key, offset $11 = the pixel data), frees
  the DAX block and flushes the keyboard. Target is untyped so ovl32, ovl34,
  ovl28 and ovl11 can each pass their own pointer variable. }
procedure LoadPicture(Text: string; BlockId, AllocFlags, Color: Byte; var Target);
var
  DaxHeight, DaxWidthCols, DaxXPos, DaxYPos: Word;
  DaxItemCount: Byte;
  DaxPalette: TPalette;
  Size: Word;
  PixelOfs: Word;
  Block: Pointer;
  Unused: Byte;    { QUIRK 0464:0114: the original frame has one byte the locals never use }
begin
  if Pointer(Target) <> nil then ReleasePicture(Target);
  LoadDaxBlock(Text, '.dax', BlockId, Size, Block);
  if Size <> 0 then
  begin
    Move(PPicture(Block)^.Height, DaxHeight, 2);
    Move(PPicture(Block)^.WidthCols, DaxWidthCols, 2);
    Move(PPicture(Block)^.XPos, DaxXPos, 2);
    Move(PPicture(Block)^.YPos, DaxYPos, 2);
    Move(PPicture(Block)^.ItemCount, DaxItemCount, 1);
    Move(PPicture(Block)^.Palette, DaxPalette, 8);
    AllocatePicture(DaxHeight, DaxWidthCols, DaxItemCount, AllocFlags, Target);
    with PPicture(Pointer(Target))^ do
    begin
      XPos := DaxXPos;
      YPos := DaxYPos;
      Palette := DaxPalette;
      PixelOfs := $11;
      UnpackPicturePixels(PPicture(Block), PixelOfs, AllocFlags, Color, PPicture(Pointer(Target)));
    end;
    FreeMem(Block, Size);
    FlushKeyboard;
  end;
end;
{ 0464:02A5: unpacks the pixel data of the DAX block Source (its pixels start at Offset,
  $11) into Data, the picture LoadPicture allocated, one item and one cell (four source
  bytes, eight pixels) at a time. Per VideoAdapter: 0 writes two bytes per cell, the
  palette colour of each pixel in 2-bit form (ds25FA), and, when the picture has a pixel
  buffer (Pixels, AllocFlags bit 0), the mask of the pixels equal to Color; 1 writes the
  four EGA plane bytes of each cell (a pixel's colour bits select its planes) and the
  mask; 2 copies ByteSize bytes of each item unchanged and builds the mask from them.
  AllocFlags is never read. Called by LoadPicture (0464:0111) and by ovl28 LoadSpriteList.
  QUIRK 0464:02A5: the frame has 17 bytes above Cell that the code never touches. }
procedure UnpackPicturePixels(Source: Pointer; Offset: Word; AllocFlags, Color: Byte; Data: Pointer);
var
  Unused: array[0..16] of Byte;
  Cell: LongInt;
  CellBytes: array[0..3] of Byte absolute Cell;
  I: Byte;
  Col, Row, OutOfs, PixIndex: Word;
  Mask, Index: Byte;
  Pass, Bit, Plane, Nibble: Byte;
begin
  if Data = nil then Exit;
  with PPicture(Data)^ do
  begin
    OutOfs := 0;
    PixIndex := 0;
    case VideoAdapter of
    0:
    begin
      for I := 1 to ItemCount do
        for Row := 0 to Height - 1 do
          for Col := 0 to WidthCols - 1 do
          begin
            Move(PByteArray(Source)^[Offset], Cell, 4);
            if Pixels <> nil then
            begin
              Mask := ColorMatchMask(Color, Cell);
              Bit := $80;
              for Pass := 1 to 2 do
              begin
                for Index := 4 to 7 do
                begin
                  if (Bit and Mask) > 0 then
                    Pixels^[PixIndex] := Pixels^[PixIndex] or GlyphPixelMasks[Index];
                  Bit := Bit shr 1;
                end;
                Inc(PixIndex);
              end;
            end;
            for Index := 0 to 3 do
            begin
              if Odd(Index) then
                Data[OutOfs] := Data[OutOfs] or
                  ds25FA[PaletteColor(CellBytes[Index shr 1] and $0F, @Palette), Index]
              else
                Data[OutOfs] := Data[OutOfs] or
                  ds25FA[PaletteColor((CellBytes[Index shr 1] and $F0) shr 4, @Palette), Index];
            end;
            if Pixels <> nil then
              Data[OutOfs] := Data[OutOfs] and not Pixels^[PixIndex - 2];
            Inc(OutOfs);
            for Index := 4 to 7 do
            begin
              if Odd(Index) then
                Data[OutOfs] := Data[OutOfs] or
                  ds25FA[PaletteColor(CellBytes[Index shr 1] and $0F, @Palette), Index - 4]
              else
                Data[OutOfs] := Data[OutOfs] or
                  ds25FA[PaletteColor((CellBytes[Index shr 1] and $F0) shr 4, @Palette), Index - 4];
            end;
            if Pixels <> nil then
              Data[OutOfs] := Data[OutOfs] and not Pixels^[PixIndex - 1];
            Inc(OutOfs);
            Inc(Offset, 4);
          end;
    end;
    1:
    begin
      for I := 1 to ItemCount do
        for Row := 0 to Height - 1 do
          for Col := 0 to WidthCols - 1 do
          begin
            Move(PByteArray(Source)^[Offset], Cell, 4);
            if Pixels <> nil then
            begin
              Pixels^[PixIndex] := ColorMatchMask(Color, Cell);
              Inc(PixIndex);
            end;
            Bit := $80;
            for Index := 0 to 7 do
            begin
              if Odd(Index) then
                Nibble := CellBytes[Index shr 1] and $0F
              else
                Nibble := CellBytes[Index shr 1] shr 4;
              for Plane := 0 to 3 do
                if (EgaPlaneBitMasks[Plane] and Nibble) > 0 then
                  Data[OutOfs + Plane] := Data[OutOfs + Plane] or Bit;
              Bit := Bit shr 1;
            end;
            if Pixels <> nil then
              for Plane := 0 to 3 do
                Data[OutOfs + Plane] := Data[OutOfs + Plane] and not Pixels^[PixIndex - 1];
            Inc(OutOfs, 4);
            Inc(Offset, 4);
          end;
    end;
    2:
    begin
      for I := 1 to ItemCount do
      begin
        Move(PByteArray(Source)^[Offset], Data[OutOfs], ByteSize);
        if Pixels <> nil then
          for Col := OutOfs to OutOfs + ByteSize - 1 do
          begin
            if (Data[Col] shr 4) = Color then Pixels^[Col] := $F0;
            if (Data[Col] and $0F) = Color then Inc(Pixels^[Col], $0F);
            Data[Col] := Data[Col] and not Pixels^[Col];
          end;
        Inc(OutOfs, ByteSize);
        Inc(Offset, ByteSize);
      end;
    end;
  end;
  end;
end;
{ 0464:08D4: copies picture Source (item PicIndex of it) into Dest at cell column Col and
  pixel row Row * 8, one source row of bytes at a time, and marks the rows it changed in the
  trackers (ds4A28, ds4C20, ds4AD0, ds4D70). With bit 0 of Flags and a pixel buffer in Source,
  the copy is masked: a destination byte keeps the bits its Pixels mask marks and takes the
  source bits. Per VideoAdapter the bytes per cell are 2 (0) or 4 (1 and 2); adapter 1 reads
  one mask byte per four data bytes. Called by DrawCellPicture (ovl32:00F1, flags 0 and
  DrawBuf) and by ovl34 Put8x8Symbol (ovl34:015D). It does no clipping of its own: the
  item must lie inside Dest (RightRoom is a Word and is added as it is). }
procedure DrawPictureItem(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
var
  LeftCol: Integer;
  RightRoom, SrcRowBytes, ItemOfs, DestOfs, SrcLastRow, SrcRow, MaskOfs: Word;
  BytesToNextMask: Byte;
  FirstRow, LeftBytes: Word;
  HasMask: Boolean;
begin
  HasMask := ((Flags and 1) > 0) and (PPicture(Source)^.Pixels <> nil);
  FirstRow := Row * 8;
  DestOfs := FirstRow * PPicture(Dest)^.WidthCols;
  SrcLastRow := PPicture(Source)^.Height - 1;
  LeftCol := Col;
  RightRoom := PPicture(Dest)^.WidthCols - (Col + PPicture(Source)^.WidthCols);
  case VideoAdapter of
    0, 2:
    begin
      if VideoAdapter = 0 then
      begin
        LeftBytes := LeftCol * 2;
        SrcRowBytes := PPicture(Source)^.WidthCols * 2;
        LeftCol := LeftCol * 2;
        RightRoom := RightRoom * 2;
        ItemOfs := PicIndex * PPicture(Source)^.ByteSize;
        DestOfs := DestOfs * 2;
      end
      else
      begin
        LeftBytes := LeftCol * 4;
        SrcRowBytes := PPicture(Source)^.WidthCols * 4;
        LeftCol := LeftCol * 4;
        RightRoom := RightRoom * 4;
        ItemOfs := PicIndex * PPicture(Source)^.ByteSize;
        DestOfs := DestOfs * 4;
      end;
      if HasMask then
        for SrcRow := 0 to SrcLastRow do
        begin
          ds4A28[FirstRow] := 1;
          Inc(DestOfs, LeftCol);
          if ds4C20[FirstRow] > DestOfs then
          begin
            ds4AD0[FirstRow] := LeftBytes;
            ds4C20[FirstRow] := DestOfs;
          end;
          for ds70C7 := 1 to SrcRowBytes do
          begin
            PPicture(Dest)^.Data[DestOfs] := (PPicture(Dest)^.Data[DestOfs] and
              PPicture(Source)^.Pixels^[ItemOfs]) or PPicture(Source)^.Data[ItemOfs];
            Inc(ItemOfs);
            Inc(DestOfs);
          end;
          if DestOfs - 1 > ds4D70[FirstRow] then ds4D70[FirstRow] := DestOfs - 1;
          Inc(DestOfs, RightRoom);
          Inc(FirstRow);
        end
      else
        for SrcRow := 0 to SrcLastRow do
        begin
          ds4A28[FirstRow] := 1;
          Inc(DestOfs, LeftCol);
          if ds4C20[FirstRow] > DestOfs then
          begin
            ds4AD0[FirstRow] := LeftBytes;
            ds4C20[FirstRow] := DestOfs;
          end;
          Move(PPicture(Source)^.Data[ItemOfs], PPicture(Dest)^.Data[DestOfs], SrcRowBytes);
          Inc(ItemOfs, SrcRowBytes);
          Inc(DestOfs, SrcRowBytes);
          if DestOfs - 1 > ds4D70[FirstRow] then ds4D70[FirstRow] := DestOfs - 1;
          Inc(DestOfs, RightRoom);
          Inc(FirstRow);
        end;
    end;
    1:
    begin
      LeftBytes := LeftCol;
      SrcRowBytes := PPicture(Source)^.WidthCols * 4;
      LeftCol := LeftCol * 4;
      RightRoom := RightRoom * 4;
      ItemOfs := PicIndex * PPicture(Source)^.ByteSize;
      MaskOfs := ItemOfs shr 1 shr 1;
      BytesToNextMask := 4;
      DestOfs := DestOfs * 4;
      if HasMask then
        for SrcRow := 0 to SrcLastRow do
        begin
          ds4A28[FirstRow] := 1;
          Inc(DestOfs, LeftCol);
          if ds4C20[FirstRow] > DestOfs then
          begin
            ds4AD0[FirstRow] := LeftBytes;
            ds4C20[FirstRow] := DestOfs;
          end;
          for ds70C7 := 1 to SrcRowBytes do
          begin
            PPicture(Dest)^.Data[DestOfs] := (PPicture(Dest)^.Data[DestOfs] and
              PPicture(Source)^.Pixels^[MaskOfs]) or PPicture(Source)^.Data[ItemOfs];
            Inc(ItemOfs);
            Dec(BytesToNextMask);
            if BytesToNextMask = 0 then
            begin
              BytesToNextMask := 4;
              Inc(MaskOfs);
            end;
            Inc(DestOfs);
          end;
          if DestOfs - 1 > ds4D70[FirstRow] then ds4D70[FirstRow] := DestOfs - 1;
          Inc(DestOfs, RightRoom);
          Inc(FirstRow);
        end
      else
        for SrcRow := 0 to SrcLastRow do
        begin
          ds4A28[FirstRow] := 1;
          Inc(DestOfs, LeftCol);
          if ds4C20[FirstRow] > DestOfs then
          begin
            ds4AD0[FirstRow] := LeftBytes;
            ds4C20[FirstRow] := DestOfs;
          end;
          Move(PPicture(Source)^.Data[ItemOfs], PPicture(Dest)^.Data[DestOfs], SrcRowBytes);
          Inc(ItemOfs, SrcRowBytes);
          Inc(DestOfs, SrcRowBytes);
          if DestOfs - 1 > ds4D70[FirstRow] then ds4D70[FirstRow] := DestOfs - 1;
          Inc(DestOfs, RightRoom);
          Inc(FirstRow);
        end;
    end;
  end;
end;
{ 0464:0D71: retf 16: same frame as DrawPictureItem. Bit 0 of Flags is tested. }
{ 0464:0D71: the clipping version of DrawPictureItem (08D4). Draws item PicIndex of
  Source with its top-left cell at column Col and pixel row Row * 8, cut to Dest on
  all four sides. Bit 0 of Flags masks the picture (Source needs a pixel buffer);
  bit 2 first copies the destination bytes that are about to be overwritten into the
  screen buffer ds4A24 (SaveOfs, the same layout as the picture rows). The range
  checks run only while ds5370 is nonzero (set by the loader); when it is 0 the
  picture is drawn with no check at all. Per VideoAdapter: 0 and 2 copy bytes (2 or
  4 per cell), 1 copies the four EGA planes and reads one mask byte per four data
  bytes. The change marks go into ds4A28, ds4AD0, ds4C20 and ds4D70 per pixel row.
  QUIRK 0464:0D71: SaveOfs starts at the top-cut bytes only (no PicIndex offset), and
  the adapter 1 mask phase is set once per call, so it carries from row to row. }
procedure DrawPictureItemClipped(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
var
  LeftCut: Word;           { source cells cut off on the left (Col < 0) }
  RightCut: Word;          { source cells cut off on the right }
  LeftCol: Word;           { the first destination cell column }
  RightRoom: Word;         { destination cells right of the picture (0 when it is cut) }
  LeftMaskCut: Word;       { adapter 1: mask bytes cut off on the left }
  RightMaskCut: Word;      { adapter 1: mask bytes cut off on the right }
  VisibleBytes: Word;      { bytes of each source row that land in Dest }
  SrcOfs: Word;            { source byte offset of the next byte }
  DestOfs: Word;           { destination byte offset of the next byte }
  SaveOfs: Word;           { byte offset in the save buffer ds4A24 }
  SrcLastRow: Word;        { last source pixel row that is drawn }
  SrcRow: Word;            { source row loop counter }
  MaskOfs: Word;           { adapter 1: mask byte offset }
  BytesToNextMask: Byte;   { adapter 1: data bytes left before the next mask byte }
  FirstRow: Word;          { first destination pixel row: Row * 8, or 0 when Row < 0 }
  LeftBytes: Word;         { the first changed byte of the row (ds4AD0) }
  HasMask: Boolean;        { Flags bit 0 is set and Source has a pixel buffer }
  SaveBackground: Boolean; { Flags bit 2 is set }
begin
  if (Source = nil) or (Dest = nil) then Exit;
  HasMask := ((Flags and 1) > 0) and (PPicture(Source)^.Pixels <> nil);
  SaveBackground := (Flags and 4) > 0;
  if ds5370 <> 0 then
  begin
    if Col < 0 then
    begin
      LeftCut := Abs(Col);
      if LeftCut > PPicture(Source)^.WidthCols then Exit;
      LeftCol := 0;
    end
    else
    begin
      LeftCut := 0;
      LeftCol := Col;
      if LeftCol > PPicture(Dest)^.WidthCols then Exit;
    end;
    if Col + PPicture(Source)^.WidthCols > PPicture(Dest)^.WidthCols then
    begin
      RightCut := Col + PPicture(Source)^.WidthCols - PPicture(Dest)^.WidthCols;
      if RightCut > PPicture(Source)^.WidthCols then Exit;
      RightRoom := 0;
    end
    else
    begin
      RightCut := 0;
      RightRoom := PPicture(Dest)^.WidthCols - (Col + PPicture(Source)^.WidthCols);
      if RightRoom > PPicture(Dest)^.WidthCols then Exit;
    end;
    if Row < 0 then
    begin
      SrcOfs := Abs(Row) * PPicture(Source)^.WidthCols * 8;
      DestOfs := 0;
      FirstRow := 0;
      SrcLastRow := PPicture(Source)^.Height - 1 - Abs(Row) * 8;
      if (PPicture(Source)^.ByteSize - 1 < SrcOfs) or
         (SrcLastRow > PPicture(Source)^.Height - 1) then Exit;
    end
    else
    begin
      SrcOfs := 0;
      FirstRow := Row * 8;
      DestOfs := FirstRow * PPicture(Dest)^.WidthCols;
      { the original stores the default here and again in the else below (0464:0F3F, 0F95) }
      SrcLastRow := PPicture(Source)^.Height - 1;
      if Row * 8 + PPicture(Source)^.Height > PPicture(Dest)^.Height then
        SrcLastRow := PPicture(Dest)^.Height - 1 - Row * 8
      else
        SrcLastRow := PPicture(Source)^.Height - 1;
      if (PPicture(Source)^.ByteSize - 1 < SrcOfs) or
         (PPicture(Dest)^.ByteSize - 1 < DestOfs) or
         (SrcLastRow > PPicture(Source)^.Height - 1) then Exit;
    end;
  end
  else
  begin
    LeftCut := 0;
    RightCut := 0;
    SrcOfs := 0;
    FirstRow := Row * 8;
    DestOfs := FirstRow * PPicture(Dest)^.WidthCols;
    SrcLastRow := PPicture(Source)^.Height - 1;
    LeftCol := Col;
    RightRoom := PPicture(Dest)^.WidthCols - (Col + PPicture(Source)^.WidthCols);
  end;
  case VideoAdapter of
    0, 2:
    begin
      if VideoAdapter = 0 then
      begin
        LeftBytes := LeftCol * 2;
        VisibleBytes := (PPicture(Source)^.WidthCols - LeftCut - RightCut) * 2;
        LeftCut := LeftCut * 2;
        RightCut := RightCut * 2;
        LeftCol := LeftCol * 2;
        RightRoom := RightRoom * 2;
        SrcOfs := SrcOfs * 2;
        SaveOfs := SrcOfs;
        SrcOfs := SrcOfs + PicIndex * PPicture(Source)^.ByteSize;
        DestOfs := DestOfs * 2;
      end
      else
      begin
        LeftBytes := LeftCol * 4;
        VisibleBytes := (PPicture(Source)^.WidthCols - LeftCut - RightCut) * 4;
        LeftCut := LeftCut * 4;
        RightCut := RightCut * 4;
        LeftCol := LeftCol * 4;
        RightRoom := RightRoom * 4;
        SrcOfs := SrcOfs * 4;
        SaveOfs := SrcOfs;
        SrcOfs := SrcOfs + PicIndex * PPicture(Source)^.ByteSize;
        DestOfs := DestOfs * 4;
      end;
      for SrcRow := 0 to SrcLastRow do
      begin
        ds4A28[FirstRow] := 1;
        Inc(SrcOfs, LeftCut);
        Inc(SaveOfs, LeftCut);
        Inc(DestOfs, LeftCol);
        if ds4C20[FirstRow] > DestOfs then
        begin
          ds4AD0[FirstRow] := LeftBytes;
          ds4C20[FirstRow] := DestOfs;
        end;
        if SaveBackground then
          Move(PPicture(Dest)^.Data[DestOfs], PPicture(ds4A24)^.Data[SaveOfs], VisibleBytes);
        Inc(SaveOfs, VisibleBytes);
        if HasMask then
        begin
          for ds70C7 := 1 to VisibleBytes do
          begin
            PPicture(Dest)^.Data[DestOfs] := (PPicture(Dest)^.Data[DestOfs] and
              PPicture(Source)^.Pixels^[SrcOfs]) or PPicture(Source)^.Data[SrcOfs];
            Inc(SrcOfs);
            Inc(DestOfs);
          end;
        end
        else
        begin
          Move(PPicture(Source)^.Data[SrcOfs], PPicture(Dest)^.Data[DestOfs], VisibleBytes);
          Inc(SrcOfs, VisibleBytes);
          Inc(DestOfs, VisibleBytes);
        end;
        if DestOfs - 1 > ds4D70[FirstRow] then ds4D70[FirstRow] := DestOfs - 1;
        Inc(SrcOfs, RightCut);
        Inc(SaveOfs, RightCut);
        Inc(DestOfs, RightRoom);
        Inc(FirstRow);
      end;
    end;
    1:
    begin
      LeftBytes := LeftCol;
      VisibleBytes := (PPicture(Source)^.WidthCols - LeftCut - RightCut) * 4;
      LeftCut := LeftCut * 4;
      RightCut := RightCut * 4;
      LeftCol := LeftCol * 4;
      RightRoom := RightRoom * 4;
      SrcOfs := SrcOfs * 4;
      SaveOfs := SrcOfs;
      SrcOfs := SrcOfs + PicIndex * PPicture(Source)^.ByteSize;
      { two shifts by 1: the original does not compile shr 2 this way (res07-shift-two-forms) }
      MaskOfs := SrcOfs shr 1 shr 1;
      LeftMaskCut := LeftCut shr 1 shr 1;
      RightMaskCut := RightCut shr 1 shr 1;
      BytesToNextMask := 4;
      DestOfs := DestOfs * 4;
      for SrcRow := 0 to SrcLastRow do
      begin
        ds4A28[FirstRow] := 1;
        Inc(SrcOfs, LeftCut);
        Inc(MaskOfs, LeftMaskCut);
        Inc(SaveOfs, LeftCut);
        Inc(DestOfs, LeftCol);
        if ds4C20[FirstRow] > DestOfs then
        begin
          ds4AD0[FirstRow] := LeftBytes;
          ds4C20[FirstRow] := DestOfs;
        end;
        if SaveBackground then
          Move(PPicture(Dest)^.Data[DestOfs], PPicture(ds4A24)^.Data[SaveOfs], VisibleBytes);
        Inc(SaveOfs, VisibleBytes);
        if HasMask then
        begin
          for ds70C7 := 1 to VisibleBytes do
          begin
            PPicture(Dest)^.Data[DestOfs] := (PPicture(Dest)^.Data[DestOfs] and
              PPicture(Source)^.Pixels^[MaskOfs]) or PPicture(Source)^.Data[SrcOfs];
            Inc(SrcOfs);
            Dec(BytesToNextMask);
            if BytesToNextMask = 0 then
            begin
              BytesToNextMask := 4;
              Inc(MaskOfs);
            end;
            Inc(DestOfs);
          end;
        end
        else
        begin
          Move(PPicture(Source)^.Data[SrcOfs], PPicture(Dest)^.Data[DestOfs], VisibleBytes);
          Inc(SrcOfs, VisibleBytes);
          Inc(DestOfs, VisibleBytes);
        end;
        if DestOfs - 1 > ds4D70[FirstRow] then ds4D70[FirstRow] := DestOfs - 1;
        Inc(SrcOfs, RightCut);
        Inc(MaskOfs, RightMaskCut);
        Inc(SaveOfs, RightCut);
        Inc(DestOfs, RightRoom);
        Inc(FirstRow);
      end;
    end;
  end;
end;
{ 0464:1484: reverses the eight bits of X: bit 0 becomes bit 7, bit 1 bit 6,
  and so on. The byte-sized mirror used to flip an 8-pixel byte of a picture. }
function MirrorByte(Value: Byte): Byte;
var
  Mirrored: Byte;
begin
  Mirrored := Value shl 7;
  Inc(Mirrored, (Value and $02) shl 5);
  Inc(Mirrored, (Value and $04) shl 3);
  Inc(Mirrored, (Value and $08) shl 1);
  Inc(Mirrored, (Value and $10) shr 1);
  Inc(Mirrored, (Value and $20) shr 3);
  Inc(Mirrored, (Value and $40) shr 5);
  Inc(Mirrored, (Value and $80) shr 7);
  MirrorByte := Mirrored;
end;

{ 0464:1509: reverses the order of the eight 2-bit groups of X: the group in
  bits 1..0 moves to bits 15..14, and so on. The word-sized mirror used to flip
  a 16-bit unit of a picture row (15C7 applies it to every word of a row). The
  masks come from GlyphPixelMasks (DS:25E5), which holds them in the opposite
  order, so the statements run from element 7 down to 0. }
function MirrorWord(Value: Word): Word;
var
  Mirrored: Word;
begin
  Mirrored := (Value and GlyphPixelMasks[7]) shl 14;
  Inc(Mirrored, (Value and GlyphPixelMasks[6]) shl 10);
  Inc(Mirrored, (Value and GlyphPixelMasks[5]) shl 6);
  Inc(Mirrored, (Value and GlyphPixelMasks[4]) shl 2);
  Inc(Mirrored, (Value and GlyphPixelMasks[3]) shr 2);
  Inc(Mirrored, (Value and GlyphPixelMasks[2]) shr 6);
  Inc(Mirrored, (Value and GlyphPixelMasks[1]) shr 10);
  Inc(Mirrored, (Value and GlyphPixelMasks[0]) shr 14);
  MirrorWord := Mirrored;
end;
{ 0464:1596: swaps the two nibbles of X: the low nibble becomes the high one.
  The byte-sized companion of 1484 for flipping an 8-pixel byte. }
function SwapNibbles(Value: Byte): Byte;
var
  Swapped: Byte;
begin
  Swapped := Value shl 4;
  Inc(Swapped, (Value and $F0) shr 4);
  SwapNibbles := Swapped;
end;
{ 0464:15C7: copies the picture Source into Dest mirrored: the palette is copied
  as is, then the pixel data of every row is reversed (each 16-bit unit through
  MirrorWord for adapter 0, each byte through MirrorByte in 4-byte groups for
  adapter 1, each byte through SwapNibbles for adapter 2). The pixel buffer at
  +$13 is mirrored too when it is not nil: word by word in mode 0, byte by byte
  within the row in mode 1, and in place in mode 2. Called by ovl32 DrawIcon
  (icon sets above 3) and res12. }
procedure MirrorPicture(Source, Dest: Pointer);
var
  DestOfs, SrcLastOfs, RowOfs, RowBytes: Word;
  Col, Row: Word;
  I: Byte;
  PixelWord: Word;    { one 16-bit pixel unit, mirrored through MirrorWord }
begin
  if (Source = nil) or (Dest = nil) then Exit;
  with PPicture(Source)^ do
  begin
    Move(Palette, PPicture(Dest)^.Palette, 8);
    case VideoAdapter of
      0:
        begin
          RowBytes := WidthCols * 2;
          SrcLastOfs := RowBytes - 2;
          DestOfs := 0;
          for Row := 1 to Height do
          begin
            RowOfs := DestOfs;
            for Col := 0 to WidthCols - 1 do
            begin
              Move(Data[SrcLastOfs - DestOfs + RowOfs], PixelWord, 2);
              PixelWord := MirrorWord(PixelWord);
              Move(PixelWord, PPicture(Dest)^.Data[DestOfs], 2);
              if Pixels <> nil then
              begin
                Move(Pixels^[SrcLastOfs - DestOfs + RowOfs], PixelWord, 2);
                PixelWord := MirrorWord(PixelWord);
                Move(PixelWord, PPicture(Dest)^.Pixels^[DestOfs], 2);
              end;
              Inc(DestOfs, 2);
            end;
            Inc(SrcLastOfs, RowBytes);
          end;
        end;
      1:
        begin
          RowBytes := WidthCols * 4;
          SrcLastOfs := RowBytes - 4;
          DestOfs := 0;
          for Row := 1 to Height do
          begin
            RowOfs := DestOfs;
            for Col := 1 to WidthCols do
            begin
              for I := 0 to 3 do
                PPicture(Dest)^.Data[DestOfs + I] :=
                  MirrorByte(Data[SrcLastOfs - DestOfs + RowOfs + I]);
              Inc(DestOfs, 4);
            end;
            Inc(SrcLastOfs, RowBytes);
          end;
          if Pixels <> nil then
          begin
            SrcLastOfs := 0;
            for Row := 1 to Height do
            begin
              for Col := 0 to WidthCols - 1 do
                PPicture(Dest)^.Pixels^[SrcLastOfs + WidthCols - Col - 1] :=
                  MirrorByte(Pixels^[SrcLastOfs + Col]);
              Inc(SrcLastOfs, WidthCols);
            end;
          end;
        end;
      2:
        begin
          RowBytes := WidthCols * 4;
          SrcLastOfs := RowBytes - 1;
          DestOfs := 0;
          for Row := 1 to Height do
          begin
            RowOfs := DestOfs;
            for Col := 1 to RowBytes do
            begin
              PPicture(Dest)^.Data[DestOfs] :=
                SwapNibbles(Data[SrcLastOfs - DestOfs + RowOfs]);
              if Pixels <> nil then
                PPicture(Dest)^.Pixels^[DestOfs] :=
                  SwapNibbles(Pixels^[SrcLastOfs - DestOfs + RowOfs]);
              Inc(DestOfs);
            end;
            Inc(SrcLastOfs, RowBytes);
          end;
        end;
    end;
  end;
end;

{ 0464:1951: shows a picture at (PicCol, PicRow) by copying its packed pixel data
  straight to the video hardware, one branch per video adapter. PicRow * 8 is the
  first pixel row, and PicCol the first cell column. Adapter 0 moves a
  WidthCols*2-byte row per screen row to the segment ds4EC0[Row] at column
  PicCol*2; adapter 1 writes, per row and per cell column, the four plane bytes of
  the source cell (the plane-interleaved layout, 4 bytes per cell, one byte per
  EGA plane: each byte holds eight pixels of that plane, written through the map
  mask EgaPlaneBitMasks[Plane] on port 3C5 to Mem[$A000:ds5050[Row] + Col]);
  adapter 2 is the adapter-0 move with four bytes per column and the ds51E0
  segment table. Called by ShowTitleScreen, ovl28 DrawSprite and ovl34 Put8x8Symbol. }
procedure ShowPicture(PicCol, PicRow: Integer; Buf: Pointer);
var
  Col, Row: Integer;
  FirstCol, FirstRow: Word;
  LastCol, LastRow: Word;
  RowBytes, SourceOfs: Word;
  Plane: Byte;
begin
  if Buf = nil then Exit;
  with PPicture(Buf)^ do
  begin
    case VideoAdapter of
      0:
        begin
          RowBytes := WidthCols * 2;
          SourceOfs := 0;
          FirstRow := PicRow * 8;
          LastRow := FirstRow + Height - 1;
          FirstCol := PicCol * 2;
          for Row := FirstRow to LastRow do
          begin
            Move(PPicture(Buf)^.Data[SourceOfs], Mem[ds4EC0[Row]:FirstCol], RowBytes);
            Inc(SourceOfs, RowBytes);
          end;
        end;
      1:
        begin
          SourceOfs := 0;
          FirstRow := PicRow * 8;
          LastRow := FirstRow + Height - 1;
          FirstCol := PicCol;
          LastCol := FirstCol + WidthCols - 1;
          Port[$3C4] := 2;
          for Row := FirstRow to LastRow do
            for Col := FirstCol to LastCol do
            begin
              for Plane := 0 to 3 do
              begin
                Port[$3C5] := EgaPlaneBitMasks[Plane];
                Mem[$A000:ds5050[Row] + Col] := PPicture(Buf)^.Data[SourceOfs];
                Inc(SourceOfs);
              end;
            end;
          Port[$3C5] := $0F;
        end;
      2:
        begin
          RowBytes := WidthCols * 4;
          SourceOfs := 0;
          FirstRow := PicRow * 8;
          LastRow := FirstRow + Height - 1;
          FirstCol := PicCol * 4;
          for Row := FirstRow to LastRow do
          begin
            Move(PPicture(Buf)^.Data[SourceOfs], Mem[ds51E0[Row]:FirstCol], RowBytes);
            Inc(SourceOfs, RowBytes);
          end;
        end;
    end;
  end;
end;
{ 0464:1B52: presents the changed regions the blitters marked in ds4A28 (the
  per-row changed flag) and the tracker arrays, one branch per video adapter. Per
  changed row the staging buffer DrawBuf holds the changed bytes at
  Data[ds4C20[Row] .. ds4D70[Row]]: ds4C20 is the first (lowest) changed byte
  offset, a minimum that starts at $FFFF, and ds4D70 the last (highest), which
  starts at 0. ds4AD0[Row] is the screen-side byte column of that first changed
  byte (LeftCol * 2 on adapter 0, LeftCol * 1 on adapter 1, LeftCol * 4 on
  adapter 2). Adapter 0 moves each changed span to the segment ds4EC0[Row+8] at
  column ds4AD0[Row]+2; adapter 1 writes the four EGA planes byte by byte through
  port 3C5 (stride 4 in the source) into the off-screen page $A200, then copies
  $A200 onto the visible page $A000 in GC write mode 1 (GC register 5 := 1,
  restored to 0); adapter 2 moves the spans to the ds51E0 segments at column
  ds4AD0[Row]+4. Finally the trackers are reset. Called after every sprite or
  picture blit. }
procedure FlushPictureChanges;
var
  Row: Word;
  SrcOfs, DestOfs, BaseOfs: Word;
  Unused: Word;    { QUIRK 0464:1B55: the original frame has one word the locals never use }
begin
  case VideoAdapter of
    0:
      for Row := 0 to $A7 do
        if ds4A28[Row] <> 0 then
          Move(PPicture(DrawBuf)^.Data[ds4C20[Row]],
            Mem[ds4EC0[Row + 8]:ds4AD0[Row] + 2],
            ds4D70[Row] - ds4C20[Row] + 1);
    1:
      begin
        Port[$3C4] := 2;
        for Row := 0 to $A7 do
          if ds4A28[Row] <> 0 then
          begin
            BaseOfs := ds5050[Row + 8] + ds4AD0[Row] + 1;
            Port[$3C5] := EgaPlaneBitMasks[0];
            SrcOfs := ds4C20[Row];
            DestOfs := BaseOfs;
            repeat
              Mem[$A200:DestOfs] := PPicture(DrawBuf)^.Data[SrcOfs];
              Inc(SrcOfs, 4);
              Inc(DestOfs);
            until SrcOfs > ds4D70[Row];
            Port[$3C5] := EgaPlaneBitMasks[1];
            SrcOfs := ds4C20[Row] + 1;
            DestOfs := BaseOfs;
            repeat
              Mem[$A200:DestOfs] := PPicture(DrawBuf)^.Data[SrcOfs];
              Inc(SrcOfs, 4);
              Inc(DestOfs);
            until SrcOfs > ds4D70[Row];
            Port[$3C5] := EgaPlaneBitMasks[2];
            SrcOfs := ds4C20[Row] + 2;
            DestOfs := BaseOfs;
            repeat
              Mem[$A200:DestOfs] := PPicture(DrawBuf)^.Data[SrcOfs];
              Inc(SrcOfs, 4);
              Inc(DestOfs);
            until SrcOfs > ds4D70[Row];
            Port[$3C5] := EgaPlaneBitMasks[3];
            SrcOfs := ds4C20[Row] + 3;
            DestOfs := BaseOfs;
            repeat
              Mem[$A200:DestOfs] := PPicture(DrawBuf)^.Data[SrcOfs];
              Inc(SrcOfs, 4);
              Inc(DestOfs);
            until SrcOfs > ds4D70[Row];
          end;
        Port[$3C5] := $0F;
        DestOfs := ds5050[8] + 1;
        Port[$3CE] := 5;
        Port[$3CF] := 1;
        for Row := 0 to $A7 do
        begin
          if ds4A28[Row] <> 0 then
            Move(Mem[$A200:DestOfs + ds4AD0[Row]], Mem[$A000:DestOfs + ds4AD0[Row]],
              (ds4D70[Row] - ds4C20[Row]) shr 1 shr 1 + 1);
          Inc(DestOfs, $28);
        end;
        Port[$3CF] := 0;
      end;
    2:
      for Row := 0 to $A7 do
        if ds4A28[Row] <> 0 then
          Move(PPicture(DrawBuf)^.Data[ds4C20[Row]],
            Mem[ds51E0[Row + 8]:ds4AD0[Row] + 4],
            ds4D70[Row] - ds4C20[Row] + 1);
  end;
  FillChar(ds4A28, $A8, 0);
  FillChar(ds4C20, $150, $FF);
  FillChar(ds4D70, $150, 0);
end;
{ 0464:1E5C: recolours item FirstItem of picture Pic (item 0 when FirstItem is
  negative). For every colour index I whose FromMap and ToMap entries differ, each pixel
  whose palette colour is FromMap[I] becomes ToMap[I]. The changes go to a scratch copy
  of Pic (AllocatePicture) that is copied back at the end: because of the QUIRK at 1F51
  the colour loop and the copy back run over exactly one item, item FirstItem, never the
  items from FirstItem on. The scratch copy of a negative FirstItem holds ItemCount items
  but only item 0 is used. FirstItem is an item index (the byte offset of an item is
  FirstItem * ByteSize). Flicker (nonzero) makes each change random: adapters 0 and 2
  change each matching pixel with chance 1 in 4, adapter 1 changes a random subset of the
  matching pixels of each cell. Adapter 0 compares 2-bit pixel pairs (ds25FA,
  GlyphPixelMasks), adapter 1 the four EGA planes (EgaPlaneBitMasks), adapter 2 the two
  nibbles of each byte. Called by LoadPictureSlot (ovl32), LoadSpriteList (ovl28),
  AnimateAreaDoors (ovl18, the door frame index) and ovl16, ovl17 (the others 0).
  QUIRK 0464:1F51: the header inside the colour loop tests FirstItem again; the header
  before the loop has already set it to 0, so Items is 1 for every colour: a negative
  FirstItem recolours and copies back item 0 only. }
procedure RemapPictureColours(FromMap, ToMap: Pointer; FirstItem: Integer; Flicker: Byte; Pic: Pointer);
var
  FromMapCopy: TColorMap;            { FromMap, copied on entry }
  ToMapCopy: TColorMap;              { ToMap, copied on entry }
  PicOfs: Word;                      { byte offset in Pic of the pixel byte being read }
  ScratchOfs: Word;                  { byte offset in the scratch copy of the byte being written }
  Items: Byte;                       { items allocated and copied: ItemCount for a negative FirstItem, else 1 }
  ColByte: Word;                     { byte column loop variable }
  PixelRow: Word;                    { pixel row loop variable }
  Mask: Byte;                        { adapter 1: the pixels of the cell that have the colour }
  PlaneMask: array[0..3] of Byte;    { adapter 1: per EGA plane $00 (the colour bit is set) or $FF }
  Plane: Byte;                       { EGA plane loop variable }
  Unused: Byte;                      { the original frame has one byte the locals never use }
  Quad: Byte;                        { pixel pair loop variable (adapter 0) }
  RowBytes: Word;                    { bytes per pixel row }
  FromHigh: Byte;                    { adapter 2: the FromMap colour in the high nibble }
  ToHigh: Byte;                      { adapter 2: the ToMap colour in the high nibble }
  Colour: Byte;                      { colour index loop variable }
  Scratch: Pointer;                  { the scratch copy of Pic the changes are written to }
begin
  FromMapCopy := PColorMap(FromMap)^;
  ToMapCopy := PColorMap(ToMap)^;
  if Pic = nil then Exit;
  with PPicture(Pic)^ do
  begin
    if FirstItem < 0 then
    begin
      FirstItem := 0;
      Items := ItemCount;
    end
    else
      Items := 1;
    PicOfs := FirstItem * ByteSize;
    ScratchOfs := 0;
  end;
  AllocatePicture(PPicture(Pic)^.Height, PPicture(Pic)^.WidthCols, Items, 0, Scratch);
  PPicture(Scratch)^.Palette := PPicture(Pic)^.Palette;
  Move(PPicture(Pic)^.Data[PicOfs], PPicture(Scratch)^.Data[ScratchOfs],
    PPicture(Scratch)^.ItemCount * PPicture(Scratch)^.ByteSize);
  for Colour := 0 to 15 do
  begin
    with PPicture(Pic)^ do
    begin
      if FirstItem < 0 then
      begin
        FirstItem := 0;
        Items := ItemCount;
      end
      else
        Items := 1;
      PicOfs := FirstItem * ByteSize;
      ScratchOfs := 0;
    end;
    if FromMapCopy[Colour] <> ToMapCopy[Colour] then
    begin
      with PPicture(Scratch)^ do
      begin
        case VideoAdapter of
        0:
        begin
          RowBytes := WidthCols * 2;
          for ds70C7 := FirstItem to Items + FirstItem - 1 do
            for PixelRow := 1 to Height do
              for ColByte := 1 to RowBytes do
              begin
                for Quad := 0 to 3 do
                  if (PPicture(Pic)^.Data[PicOfs] and GlyphPixelMasks[Quad + 4]) =
                    ds25FA[PaletteColor(FromMapCopy[Colour], @Palette), Quad] then
                    if (Flicker = 0) or ((Flicker <> 0) and (Random(4) = 0)) then
                      Data[ScratchOfs] := (Data[ScratchOfs] and not GlyphPixelMasks[Quad + 4]) or
                        ds25FA[PaletteColor(ToMapCopy[Colour], @Palette), Quad];
                Inc(PicOfs);
                Inc(ScratchOfs);
              end;
        end;
        1:
        begin
          for Plane := 0 to 3 do
            if (FromMapCopy[Colour] and EgaPlaneBitMasks[Plane]) > 0 then
              PlaneMask[Plane] := 0
            else
              PlaneMask[Plane] := $FF;
          for ds70C7 := FirstItem to Items + FirstItem - 1 do
            for PixelRow := 1 to Height do
              for ColByte := 1 to WidthCols do
              begin
                if Flicker <> 0 then
                  Mask := Random(256) and Random(256)
                else
                  Mask := $FF;
                for Plane := 0 to 3 do
                  Mask := (PPicture(Pic)^.Data[PicOfs + Plane] xor PlaneMask[Plane]) and Mask;
                for Plane := 0 to 3 do
                  if (ToMapCopy[Colour] and EgaPlaneBitMasks[Plane]) > 0 then
                    Data[ScratchOfs + Plane] := Data[ScratchOfs + Plane] or Mask
                  else
                    Data[ScratchOfs + Plane] := Data[ScratchOfs + Plane] and not Mask;
                Inc(PicOfs, 4);
                Inc(ScratchOfs, 4);
              end;
        end;
        2:
        begin
          RowBytes := WidthCols * 4;
          FromHigh := FromMapCopy[Colour] shl 4;
          ToHigh := ToMapCopy[Colour] shl 4;
          for ds70C7 := FirstItem to Items + FirstItem - 1 do
            for PixelRow := 1 to Height do
              for ColByte := 1 to RowBytes do
              begin
                if (PPicture(Pic)^.Data[PicOfs] and $F0) = FromHigh then
                  if (Flicker = 0) or ((Flicker <> 0) and (Random(4) = 0)) then
                    Data[ScratchOfs] := (Data[ScratchOfs] and $0F) or ToHigh;
                if (PPicture(Pic)^.Data[PicOfs] and $0F) = FromMapCopy[Colour] then
                  if (Flicker = 0) or ((Flicker <> 0) and (Random(4) = 0)) then
                    Data[ScratchOfs] := (Data[ScratchOfs] and $F0) or ToMapCopy[Colour];
                Inc(PicOfs);
                Inc(ScratchOfs);
              end;
        end;
        end;
      end;
    end;
  end;
  with PPicture(Pic)^ do
    Move(PPicture(Scratch)^.Data[0], Data[FirstItem * ByteSize], Items * ByteSize);
  ReleasePicture(Scratch);
end;
{ 0464:248E: allocates a picture record of Height * WidthCols * 2 bytes per
  item (times 2 again when the video adapter is not 0, the EGA planar case) times
  ItemCount, plus $17 header bytes, zeroes it, stores the header fields and, when
  bit 0 of AllocFlags is set, a second block for the pixel buffer (a quarter of
  the size for VideoAdapter 1). Pic is untyped so ovl11 can pass its sprite
  banks and ovl28 its list pointers. }
procedure AllocatePicture(Height, WidthCols: Word; ItemCount, AllocFlags: Byte; var Pic);
var
  ItemBytes, BlockBytes: Word;
begin
  ItemBytes := Height * WidthCols * 2;
  if VideoAdapter <> 0 then ItemBytes := ItemBytes shl 1;
  BlockBytes := ItemCount * ItemBytes;
  GetMem(PPicture(Pointer(Pic)), BlockBytes + $17);
  FillChar(PPicture(Pointer(Pic))^, BlockBytes + $17, 0);
  PPicture(Pointer(Pic))^.Height := Height;
  PPicture(Pointer(Pic))^.WidthCols := WidthCols;
  PPicture(Pointer(Pic))^.ByteSize := ItemBytes;
  PPicture(Pointer(Pic))^.ItemCount := ItemCount;
  if AllocFlags and 1 > 0 then
  begin
    if VideoAdapter = 1 then
    begin
      GetMem(PPicture(Pointer(Pic))^.Pixels, BlockBytes shr 1 shr 1);
      FillChar(PPicture(Pointer(Pic))^.Pixels^, BlockBytes shr 1 shr 1, 0);
    end
    else
    begin
      GetMem(PPicture(Pointer(Pic))^.Pixels, BlockBytes);
      FillChar(PPicture(Pointer(Pic))^.Pixels^, BlockBytes, 0);
    end;
  end;
end;
{ 0464:2595: frees a picture: the pixel buffer at +$13 when it is not nil (a
  quarter of the size for VideoAdapter 1) and the picture block itself
  (ItemCount * ByteSize + $17 bytes), then stores nil in the caller's variable.
  Pic is untyped so ovl28 can pass its typed sprite banks. }
procedure ReleasePicture(var Pic);
var
  Size: Word;
begin
  if Pointer(Pic) <> nil then
  begin
    with PPicture(Pointer(Pic))^ do
    begin
      Size := ItemCount * ByteSize;
      if Pixels <> nil then
      begin
        if VideoAdapter = 1 then
          FreeMem(Pixels, Size shr 1 shr 1)
        else
          FreeMem(Pixels, Size);
      end;
      FreeMem(PPicture(Pointer(Pic)), Size + $17);
      Pointer(Pic) := nil;
    end;
  end;
end;
{ 0464:2632: fills a rectangle of picture Target with palette colour Colour (Palette is
  the 8-byte PPalette). Width and FirstCol are in cells of 8 pixels (2, 4 or 1x4 bytes per
  cell), but FirstRow and Height are PIXEL rows: the loop runs once per pixel row, from
  row FirstRow for Height rows, with no * 8. FirstCol and FirstRow may be negative: the
  rectangle is clipped at the picture's left, top, right and bottom edges. VideoAdapter 0
  writes two bytes per cell (ds0D02[PaletteColor(Colour)]), 2 writes four bytes per cell
  (ds0D06[Colour]) and 1 writes one byte per EGA plane through the plane mask of Colour
  (EgaPlaneBitMasks). Every row it touches is marked in ds4A28 and in the trackers ds4C20,
  ds4AD0 and ds4D70 for FlushPictureChanges. Called by DrawWallDescriptors (ovl29:0174,
  four times, FirstCol = 2, the wall descriptors' pixel rows and the ds6A60..ds6A63
  colours) and by DrawIconCell (ovl16:34DF).
  QUIRK 0464:2707: a rectangle that starts above row 0 is drawn one row too far: the row
  bound is Height - |FirstRow| and the loop includes it. }
procedure FillPictureRect(FirstCol, FirstRow: Integer; Width, Height: Word; Colour: Byte; Palette: Pointer; Target: Pointer);
var
  Pal: TPalette;
  ClipLeft, RightOver, StartCol, RightRoom, Count, LastRow, DestOfs, Row: Word;
  Mask: array[0..3] of Byte;
  TrackRow, StartBytes: Word;
  PlaneIndex: Byte;
begin
  Pal := PPalette(Palette)^;
  if Target = nil then Exit;
  if FirstCol < 0 then
  begin
    ClipLeft := Abs(FirstCol);
    StartCol := 0;
  end
  else
  begin
    ClipLeft := 0;
    StartCol := FirstCol;
  end;
  if FirstCol + Width > PPicture(Target)^.WidthCols then
  begin
    RightOver := FirstCol + Width - PPicture(Target)^.WidthCols;
    RightRoom := 0;
  end
  else
  begin
    RightOver := 0;
    RightRoom := PPicture(Target)^.WidthCols - (FirstCol + Width);
  end;
  if FirstRow < 0 then
  begin
    DestOfs := 0;
    TrackRow := 0;
    LastRow := Height - Abs(FirstRow);
  end
  else
  begin
    TrackRow := FirstRow;
    DestOfs := TrackRow * PPicture(Target)^.WidthCols;
    LastRow := Height - 1;
    if FirstRow + Height > PPicture(Target)^.Height then
      LastRow := PPicture(Target)^.Height - 1 - FirstRow
    else
      LastRow := Height - 1;
  end;
  case VideoAdapter of
    0, 2:
    begin
      if VideoAdapter = 0 then
      begin
        StartBytes := StartCol * 2;
        Count := (Width - ClipLeft - RightOver) * 2;
        StartCol := StartCol * 2;
        RightRoom := RightRoom * 2;
        DestOfs := DestOfs * 2;
      end
      else
      begin
        Count := (Width - ClipLeft - RightOver) * 4;
        StartCol := StartCol * 4;
        RightRoom := RightRoom * 4;
        DestOfs := DestOfs * 4;
        StartBytes := StartCol;
      end;
      for Row := 0 to LastRow do
      begin
        ds4A28[TrackRow] := 1;
        Inc(DestOfs, StartCol);
        if ds4C20[TrackRow] > DestOfs then
        begin
          ds4AD0[TrackRow] := StartBytes;
          ds4C20[TrackRow] := DestOfs;
        end;
        if VideoAdapter = 0 then
          FillChar(PPicture(Target)^.Data[DestOfs], Count, ds0D02[PaletteColor(Colour, @Pal)])
        else
          FillChar(PPicture(Target)^.Data[DestOfs], Count, ds0D06[Colour]);
        Inc(DestOfs, Count);
        if DestOfs - 1 > ds4D70[TrackRow] then ds4D70[TrackRow] := DestOfs - 1;
        Inc(DestOfs, RightRoom);
        Inc(TrackRow);
      end;
    end;
    1:
    begin
      StartBytes := StartCol;
      Count := Width - ClipLeft - RightOver;
      StartCol := StartCol * 4;
      RightRoom := RightRoom * 4;
      DestOfs := DestOfs * 4;
      FillChar(Mask, 4, 0);
      for PlaneIndex := 0 to 3 do
        if (EgaPlaneBitMasks[PlaneIndex] and Colour) > 0 then Mask[PlaneIndex] := $FF;
      for Row := 0 to LastRow do
      begin
        ds4A28[TrackRow] := 1;
        Inc(DestOfs, StartCol);
        if ds4C20[TrackRow] > DestOfs then
        begin
          ds4AD0[TrackRow] := StartBytes;
          ds4C20[TrackRow] := DestOfs;
        end;
        for ds70C7 := 1 to Count do
        begin
          Move(Mask, PPicture(Target)^.Data[DestOfs], 4);
          Inc(DestOfs, 4);
        end;
        if DestOfs - 1 > ds4D70[TrackRow] then ds4D70[TrackRow] := DestOfs - 1;
        Inc(DestOfs, RightRoom);
        Inc(TrackRow);
      end;
    end;
  end;
end;
{ 0464:2A0D: sets one EGA palette register through INT 10h function $10
  (AL=0): Register is the palette register and Color the colour value, mapped from
  the 0..15 palette range to the hardware's 0..7 and 16..23. Called by ovl31_e2/e3
  (0,8)/(8,0) and (0,0)/(8,8) and by ShowTitleScreen (1,9). }
procedure SetPaletteRegister(Register, Color: Byte);
begin
  Regs.AH := $10;                    { INT 10h function $10: set palette register }
  Regs.AL := 0;
  if Color < 8 then
    Regs.BH := Color
  else
    Regs.BH := Color + 8;
  Regs.BL := Register;
  Intr($10, Regs);
end;

begin
end.

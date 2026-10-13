unit RES07;
{ The picture unit: loads a DAX picture block into a picture record (LoadPicture,
  0111), unpacks the 4-bit pixel data of a picture for the active video adapter
  (02A5), blits pictures, cells and sprites with clipping (08D4, 0D71, 15C7,
  1951) and builds the 8x8 tile and sprite banks that combat, the 3D view and
  the title draw from. Evidence: callers ovl32 LoadPictureSlot/Load24x24Set,
  ovl34 Load8x8Bank, ovl28 DrawSprite, ovl01 ShowTitleScreen
  (build/packets/res07.md); picture format and roles: whitepaper 4.2.3, 5.16. }
{$A-,F+,S-,R-,G-,I-}
interface
uses Dos, POOLVARS;

type
  { an 8-byte, 16-entry 4-bit colour palette; a picture holds it at +9 }
  TPalette = array[0..7] of Byte;
  PPalette = ^TPalette;

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
    Pixels: ^Byte;                { +$13 }
    Data: array[0..0] of Byte;    { +$17, the packed pixel data }
  end;
  PPicture = ^TPicture;

function ColorMatchMask(Color: Byte; Data: LongInt): Byte;
function PaletteColor(Index: Byte; Source: PPalette): Byte;
procedure SetVideoMode(Mode: Byte);
procedure RestoreVideoMode;
procedure res07_fn_0111(Text: string; A, B, C: Byte; var Target);
procedure res07_fn_02A5(Data: Pointer; Offset: Word; A, B: Byte; Sprite: Pointer);
procedure res07_fn_08D4(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
procedure res07_fn_0D71(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
function MirrorByte(Value: Byte): Byte;
function MirrorWord(Value: Word): Word;
function SwapNibbles(Value: Byte): Byte;
procedure res07_fn_15C7(Source, Dest: Pointer);
procedure res07_fn_1951(X, Y: Integer; Buf: Pointer);
procedure res07_fn_1B52;
procedure res07_fn_1E5C(P1, P2: Pointer; A: Word; B: Byte; P3: Pointer);
procedure AllocatePicture(Height, WidthCols: Word; ItemCount, AllocFlags: Byte; var Pic);
procedure ReleasePicture(var Pic);
procedure res07_fn_2632(A, B, C, D: Word; E: Byte; F, G: Pointer);
procedure res07_fn_2A0D(A, B: Byte);
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
{ 0464:0111: retf 14. Text is a string value. Target is untyped var so ovl32, ovl34,
  ovl28 and ovl11 can each pass their pointer variable: the routine frees it when it is not
  nil, then loads the picture there. }
{@stub} procedure res07_fn_0111(Text: string; A, B, C: Byte; var Target); begin end;
{ 0464:02A5: frame not read }
{@stub} procedure res07_fn_02A5(Data: Pointer; Offset: Word; A, B: Byte; Sprite: Pointer); begin end;
{ 0464:08D4: retf 16: two Integers, two Bytes, two Pointers. DrawCellPicture passes the cell,
  the picture index, flags 0, a picture pointer and DrawBuf. }
{@stub} procedure res07_fn_08D4(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer); begin end;
{ 0464:0D71: retf 16: same frame as res07_fn_08D4. Bit 0 of Flags is tested. }
{@stub} procedure res07_fn_0D71(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer); begin end;
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
{ 0464:15C7: retf 8: two Pointers. Returns at once when either is nil. }
{@stub} procedure res07_fn_15C7(Source, Dest: Pointer); begin end;
{ 0464:1951: frame not read }
{@stub} procedure res07_fn_1951(X, Y: Integer; Buf: Pointer); begin end;
{ 0464:1B52: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure res07_fn_1B52; begin end;
{ 0464:1E5C: retf 16: 16 bytes of parameters; 68 bytes of locals }
{@stub} procedure res07_fn_1E5C(P1, P2: Pointer; A: Word; B: Byte; P3: Pointer); begin end;
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
{ 0464:2632: retf 18: 18 bytes of parameters; 36 bytes of locals }
{@stub} procedure res07_fn_2632(A, B, C, D: Word; E: Byte; F, G: Pointer); begin end;
{ 0464:2A0D: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_2A0D(A, B: Byte); begin end;

begin
end.

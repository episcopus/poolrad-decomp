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
uses POOLVARS;

type
  { an 8-byte, 16-entry 4-bit colour palette; a picture holds it at +9 }
  TPalette = array[0..7] of Byte;
  PPalette = ^TPalette;

function ColorMatchMask(Color: Byte; Data: LongInt): Byte;
function PaletteColor(Index: Byte; Source: PPalette): Byte;
procedure res07_fn_00CF(A: Byte);
procedure res07_fn_00FF;
procedure res07_fn_0111(Text: string; A, B, C: Byte; var Target);
procedure res07_fn_02A5(Data: Pointer; Offset: Word; A, B: Byte; Sprite: Pointer);
procedure res07_fn_08D4(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
procedure res07_fn_0D71(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
procedure res07_fn_1484;
procedure res07_fn_1509;
procedure res07_fn_1596;
procedure res07_fn_15C7(Source, Dest: Pointer);
procedure res07_fn_1951(X, Y: Integer; Buf: Pointer);
procedure res07_fn_1B52;
procedure res07_fn_1E5C(P1, P2: Pointer; A: Word; B: Byte; P3: Pointer);
procedure res07_fn_248E(Height, Width: Word; ItemCount, AllocFlags: Byte; var Pic);
procedure res07_fn_2595(var Pic);
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
{ 0464:00CF: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res07_fn_00CF(A: Byte); begin end;
{ 0464:00FF: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_00FF; begin end;
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
{ 0464:1484: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res07_fn_1484; begin end;
{ 0464:1509: frame not read }
{@stub} procedure res07_fn_1509; begin end;
{ 0464:1596: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res07_fn_1596; begin end;
{ 0464:15C7: retf 8: two Pointers. Returns at once when either is nil. }
{@stub} procedure res07_fn_15C7(Source, Dest: Pointer); begin end;
{ 0464:1951: frame not read }
{@stub} procedure res07_fn_1951(X, Y: Integer; Buf: Pointer); begin end;
{ 0464:1B52: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure res07_fn_1B52; begin end;
{ 0464:1E5C: retf 16: 16 bytes of parameters; 68 bytes of locals }
{@stub} procedure res07_fn_1E5C(P1, P2: Pointer; A: Word; B: Byte; P3: Pointer); begin end;
{ 0464:248E: retf 12. GetMems a picture (height * width, plus a pixel buffer when bit 0
  of AllocFlags is set) and stores the pointer. Pic is untyped so ovl11 can pass its
  PT8x8Bank banks. }
{@stub} procedure res07_fn_248E(Height, Width: Word; ItemCount, AllocFlags: Byte; var Pic); begin end;
{ 0464:2595: retf 4: one var Pointer. Frees the picture (FreeMem) and nils the pointer.
  Pic is untyped so ovl28 can pass its typed sprite banks. }
{@stub} procedure res07_fn_2595(var Pic); begin end;
{ 0464:2632: retf 18: 18 bytes of parameters; 36 bytes of locals }
{@stub} procedure res07_fn_2632(A, B, C, D: Word; E: Byte; F, G: Pointer); begin end;
{ 0464:2A0D: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_2A0D(A, B: Byte); begin end;

begin
end.

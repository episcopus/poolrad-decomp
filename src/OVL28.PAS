unit OVL28;
{ ovl28: the 3D sprite and picture unit (whitepaper 4.x). It draws the 8x8 sprites of the 3D view
  (Show3DSprite and its helpers), loads PIC/FINAL picture records into the sprite banks through
  res07_fn_0111 and frees them again, and shows the HEAD/BODY window of the character screen. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
type
  { One 8-byte slot of the sprite list ovl28_e2 builds and FreeSpriteList frees: a far pointer at +0. }
  TSpriteSlot = record
    Sprite: Pointer;              { +0: the loaded sprite bank (nil when empty) }
    Filler: array[0..3] of Byte;  { +4..+7: never read }
  end;
  { The list of loaded sprites: a count byte, a flag, and the slots at +6 with a stride of 8
    (FreeSpriteList frees slot I at Rec + 8*I - 2, ovl28_e2 reads and fills the same slots). }
  TSpriteList = record
    Count: ShortInt;                      { +0: the number of slots in use (signed: the for loop exits with jg) }
    Flag: Byte;                           { +1: set to 1 by ovl28_e2 }
    Filler: array[0..3] of Byte;          { +2..+5: never read }
    Slots: array[1..7] of TSpriteSlot;    { +6: the slots }
    Tail: array[0..3] of Byte;            { +$3E..+$41: never read }
  end;
  PSpriteList = ^TSpriteList;
procedure DrawSprite(Col, Row: Integer; Direct: Byte; Sprite: Pointer);
procedure DrawHeadSprite(Col, Row: Byte; Sprite: Pointer);
procedure DrawBodySprite(Col, Row: Byte; Sprite: Pointer);
procedure ovl28_e2;
procedure FreeSpriteList(Rec: PSpriteList);
procedure ovl28_e4;
procedure LoadHeadBodySprites(HeadBank, BodyBank: Byte);
procedure ShowHeadBodySprites(Col, Row: Byte; Direct: Byte);
procedure ovl28_e7;
implementation
uses RES04, RES05, RES07;

{ ovl28:0000. Draws the 8x8 sprite Sprite at column Col and row Row. A nil Sprite draws nothing. When
  Direct is set it blits the sprite one pixel up and left onto the screen buffer ds4A20 through
  res07_fn_0D71 (mode 0, the flag 1) and steps the display through res07_fn_1B52; otherwise it
  copies it into the staging buffer with res07_fn_1951. Called by DrawHeadSprite, DrawBodySprite and
  ShowHeadBodySprites inside this unit, and from ovl03, ovl07_e8, ovl18 and ovl25 (the packet's callers). }
procedure DrawSprite(Col, Row: Integer; Direct: Byte; Sprite: Pointer);
begin
  if Sprite <> nil then
  begin
    if Direct <> 0 then
    begin
      res07_fn_0D71(Col - 1, Row - 1, 0, 1, Sprite, ds4A20);
      res07_fn_1B52;
    end
    else
      res07_fn_1951(Col, Row, Sprite);
  end;
end;

{ ovl28:0050. Draws the 8x8 sprite Sprite of a bank at column Col and row Row without an offset
  (through DrawSprite, the staging buffer path). Called by ShowHeadBodySprites (Show3DSprite). }
procedure DrawHeadSprite(Col, Row: Byte; Sprite: Pointer);
begin
  DrawSprite(Col, Row, 0, Sprite);
end;

{ ovl28:0070. Draws the 8x8 sprite Sprite at column Col and row Row plus 5 (through DrawSprite, the
  staging buffer path). Called by ShowHeadBodySprites (Show3DSprite). }
procedure DrawBodySprite(Col, Row: Byte; Sprite: Pointer);
begin
  DrawSprite(Col, Row + 5, 0, Sprite);
end;

{ ovl28:00A2: retf 12: 12 bytes of parameters; 296 bytes of locals }
{@stub} procedure ovl28_e2; begin end;
{ ovl28:048F: retf 4: 4 bytes of parameters; 6 bytes of locals }
{ ovl28:048F. Frees the sprite list Rec^: it frees the bank of every used slot (through
  res07_fn_2595), then zeroes the whole $42-byte record, clears the picture name DS:6B0A and sets
  the current bank DS:6B1C to $FF. Called by ovl10, ovl14, ovl18 and ovl28_e2. }
procedure FreeSpriteList(Rec: PSpriteList);
begin
  with Rec^ do
    for ds70C7 := 1 to Count do
      res07_fn_2595(Slots[ds70C7].Sprite);
  FillChar(Rec^, $42, 0);
  ds6B0A := 0;
  ds6B1C := $FF;
end;
{ ovl28:04F9: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl28_e4; begin end;
{ ovl28:05D9. Loads the HEAD and the BODY 8x8 sprite bank for the picture number DS:5376: for each
  bank that is asked for (not $FF) and not already loaded (DS:6B00, DS:6B05) it loads the picture
  through res07_fn_0111 from the file HEAD<number> or BODY<number> into DS:6B01 or DS:6B06, then
  records the loaded number. Flushes the keyboard at the end. Called by ovl07_e7, ovl28_e4 and
  res12_fn_27D9. }
procedure LoadHeadBodySprites(HeadBank, BodyBank: Byte);
var
  Num: string[1];                 { Str(DS:5376): the picture number in the file name }
begin
  Str(ds5376, Num);
  if HeadBank <> $FF then
    if (ds6B00 = $FF) or (ds6B00 <> HeadBank) then
    begin
      res07_fn_0111('HEAD' + Num, HeadBank, 0, 0, @ds6B01);
      ds6B00 := HeadBank;
    end;
  if BodyBank <> $FF then
    if (ds6B05 = $FF) or (ds6B05 <> BodyBank) then
    begin
      res07_fn_0111('BODY' + Num, BodyBank, 0, 0, @ds6B06);
      ds6B05 := BodyBank;
    end;
  FlushKeyboard;
end;
{ ovl28:0697. Shows the 3D sprite at its column and row: when Direct is set it draws the HEAD
  sprite and the BODY sprite (5 rows lower, DS:6B01 and DS:6B06) over the 3D view, otherwise it
  draws the HEAD sprite through the staging buffer. Called by ovl07_e7, res12_fn_27D9 and
  ovl28_e4. }
procedure ShowHeadBodySprites(Col, Row: Byte; Direct: Byte);
begin
  if Direct <> 0 then
  begin
    DrawHeadSprite(Col, Row, ds6B01);
    DrawBodySprite(Col, Row, ds6B06);
  end
  else
    DrawSprite(Col, Row, 0, ds6B01);
end;
{ ovl28:0708: retf 6: 6 bytes of parameters; 70 bytes of locals }
{@stub} procedure ovl28_e7; begin end;

begin
end.

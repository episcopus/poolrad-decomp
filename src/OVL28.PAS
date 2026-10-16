unit OVL28;
{ ovl28: the 3D sprite and picture unit. It draws the 8x8 sprites of the 3D view (DrawSprite,
  Show3DSprite), loads the pictures of a DAX block into a sprite list (LoadSpriteList) and frees them
  again (FreeSpriteList), and shows the HEAD/BODY window of the character screen
  (ShowHeadBodyWindow). Whitepaper 5.16. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
const
  FreeMemoryFloor = 3900;   { MaxAvail below this skips a sprite (ovl28:026C) }
  PicBlock1Sprites = 4;     { the most sprites PIC block 1 keeps (ovl28:01CC) }
  Last3DSpriteSlot = 3;     { the highest legal slot Show3DSprite draws (ovl28:0727) }
  NoBank = $FF;             { LoadHeadBodySprites: no HEAD/BODY picture number loaded }
type
  { One loaded sprite picture: what AllocatePicture allocates and ReleasePicture frees (the same record
    ovl32 draws: height and width at +0 and +2, item count at +8, byte size at +$11, pixels at +$13,
    whitepaper 4.2.3). LoadSpriteList reads the sprite's base screen column and row from +4 and +6
    (Show3DSprite adds 2 to each and passes them to DrawPictureItemClipped) and the byte size from +$11. The
    height, width and item count are set by the allocator and not read here; the pixel pointer at
    +$13 is not declared because this unit never reads it. }
  TSpritePicture = record
    Height, WidthCols: Word;      { +0, +2: set by AllocatePicture, not read here }
    X: Word;                      { +4: the sprite's base column }
    Y: Word;                      { +6: the sprite's base row }
    ItemCount: Byte;              { +8: AllocatePicture's item count (1 for a sprite) }
    Palette: array[0..7] of Byte; { +9..+$10: 8 palette bytes LoadSpriteList Moves in }
    ByteSize: Word;               { +$11: the pixel byte count of one sprite }
  end;
  PSpritePicture = ^TSpritePicture;
  { One 8-byte slot of the sprite list LoadSpriteList builds and FreeSpriteList frees. The 4 bytes at +0
    are copied from the picture data and the picture pointer is at +4 (FreeSpriteList frees
    Rec + 8*I - 2, slot I's +4, which is where LoadSpriteList's AllocatePicture stores it). }
  TSpriteSlot = record
    Data: array[0..3] of Byte;    { +0: 4 bytes of picture data LoadSpriteList Moves in }
    Sprite: PSpritePicture;       { +4: the allocated picture (nil when empty) }
  end;
  { The list of loaded sprites: a count byte, a flag, and the slots at +2 with a stride of 8. }
  TSpriteList = record
    Count: ShortInt;                      { +0: the number of slots in use (signed: the for loop exits with jg) }
    Flag: Byte;                           { +1: set to 1 by LoadSpriteList }
    Slots: array[1..7] of TSpriteSlot;    { +2: the slots (slot I at +2 + 8*(I-1)) }
    Tail: array[0..7] of Byte;            { +$3A..+$41: never read }
  end;
  PSpriteList = ^TSpriteList;
  String8 = string[8];            { the picture base name LoadSpriteList takes and stores in DS:6B0A }
procedure DrawSprite(Col, Row: Integer; Direct: Byte; Sprite: Pointer);
procedure DrawHeadSprite(Col, Row: Byte; Sprite: Pointer);
procedure DrawBodySprite(Col, Row: Byte; Sprite: Pointer);
procedure LoadSpriteList(Name: String8; Bank: Byte; Mode: Byte; List: PSpriteList);
procedure FreeSpriteList(Rec: PSpriteList);
procedure ShowHeadBodyWindow;
procedure ShowHeadBodySprites(Col, Row: Byte; WithBody: Byte);
procedure LoadHeadBodySprites(HeadBank, BodyBank: Byte);
procedure Show3DSprite(Slot: Byte; Rec: PSpriteList);
implementation
uses RES04, RES05, RES09, RES07;

{ ovl28:0000. Draws the 8x8 sprite Sprite at column Col and row Row. A nil Sprite draws nothing. When
  Direct is set it blits the sprite one column and one row up and left (Col - 1, Row - 1) onto the
  screen buffer DrawBuf through
  DrawPictureItemClipped (mode 0, the flag 1) and steps the display through FlushPictureChanges; otherwise it
  copies it into the staging buffer with ShowPicture. Called by DrawHeadSprite, DrawBodySprite and
  ShowHeadBodySprites inside this unit, and from ovl03, ShowEncounterPicture, ovl18 and ovl25 (the packet's callers). }
procedure DrawSprite(Col, Row: Integer; Direct: Byte; Sprite: Pointer);
begin
  if Sprite <> nil then
  begin
    if Direct <> 0 then
    begin
      DrawPictureItemClipped(Col - 1, Row - 1, 0, 1, Sprite, DrawBuf);
      FlushPictureChanges;
    end
    else
      ShowPicture(Col, Row, Sprite);
  end;
end;

{ ovl28:0050. Draws the 8x8 sprite Sprite of a bank at column Col and row Row without an offset
  (through DrawSprite, the staging buffer path). Called by ShowHeadBodySprites. }
procedure DrawHeadSprite(Col, Row: Byte; Sprite: Pointer);
begin
  DrawSprite(Col, Row, 0, Sprite);
end;

{ ovl28:0070. Draws the 8x8 sprite Sprite at column Col and row Row plus 5 (through DrawSprite, the
  staging buffer path). Called by ShowHeadBodySprites. }
procedure DrawBodySprite(Col, Row: Byte; Sprite: Pointer);
begin
  DrawSprite(Col, Row + 5, 0, Sprite);
end;

{ ovl28:00A2. Loads the sprite pictures of block Bank of the DAX file <Name><TileSet>.dax (for
  example PIC or FINAL, ovl18 passes 'FINAL') into the sprite list List^, unless that file and block
  are already loaded (the name and block of the last load are kept in LastSpriteFile and LastSpriteBank). The test
  compares Name and Bank only, not the TileSet digit, so a TileSet change with the same name and
  block does not reload. It frees the old list first (FreeSpriteList), reads the block (LoadDaxBlock)
  and walks it: a count byte (at most PicBlock1Sprites for PIC block 1), then per sprite 4 bytes into
  the slot, the Height and WidthCols words, and when at least FreeMemoryFloor bytes of heap are free
  (MaxAvail) it allocates the picture (AllocatePicture(Height, WidthCols, 1, Mode, slot)), reads its X
  and Y words (one byte after Y is skipped) and 8 palette bytes, and decodes Row + 1 bytes of pixel
  data (UnpackPicturePixels), Row being the picture's ByteSize (twice the byte size when VideoAdapter is 0)
  minus one. PIC and FINAL pictures are stored as differences: the first picture's data is kept in
  Prev and every later picture's bytes are xored with it before decoding. When bit 0 of Mode is set
  and VideoAdapter is not 0, the picture also goes through RemapPictureColors with the two 16-byte tables
  SpriteRemapFrom and SpriteRemapTo. Frees Prev and the block at the end and calls FlushKeyboard (which does nothing,
  QUIRK 0899:010A).
  QUIRK ovl28:0269: when MaxAvail is below FreeMemoryFloor the jump to the loop end skips not only
  the allocation but also the offset advance past the sprite's X, Y, skipped byte, palette and
  Row + 1 pixel bytes, so every later sprite of the block is read from the middle of the skipped one
  (and every later offset is wrong). List^.Count still becomes the number loaded (Loaded), but the
  slots keep the index I: a skipped slot stays nil below Count and a loaded slot sits above it.
  QUIRK ovl28:046C: the final FreeMem(Prev, Row + 1) frees with the last picture's Row, not the
  first picture's size Prev was allocated with (FreeMem ignores the size, so it is harmless).
  Note ovl28:00D9: FreeSpriteList is passed @List^ (les/push es/push di), the same pointer as List.
  Parameters: Name (the file base name), Bank (the DAX block), Mode (passed on to the allocator and
  the decoder; bit 0 enables RemapPictureColors), List (the sprite list to fill). Side effects: the heap,
  LastSpriteFile, LastSpriteBank. Callers: ovl03:0856, ShowEncounterPicture, ovl18:0006, RedrawView (packet). }
procedure LoadSpriteList(Name: String8; Bank: Byte; Mode: Byte; List: PSpriteList);
var
  Size: Word;
  Block: Pointer;
  Offset: Word;
  I: Byte;
  Height, WidthCols: Word;
  Digit: string[1];
  Prev: PByteArray;
  J: Word;
  Row: Word;
  IsPicOrFinal: Boolean;
  PrevAllocated: Boolean;
  Loaded: Byte;
begin
  if (Name = LastSpriteFile) and (Bank = LastSpriteBank) then Exit;
  FreeSpriteList(@List^);
  LastSpriteFile := Name;
  LastSpriteBank := Bank;
  IsPicOrFinal := (Name = 'PIC') or (Name = 'FINAL');
  Str(TileSet, Digit);
  LoadDaxBlock(Name + Digit, '.dax', Bank, Size, Block);
  if Size = 0 then Exit;
  Offset := 0;
  PrevAllocated := False;
  with List^ do
  begin
    Count := PByteArray(Block)^[Offset];
    if (Name = 'PIC') and (Bank = 1) and (Byte(Count) > PicBlock1Sprites) then
      Count := PicBlock1Sprites;
    Inc(Offset);
    Flag := 1;
    Loaded := 0;
    for I := 1 to Byte(Count) do
    begin
      Move(PByteArray(Block)^[Offset], Slots[I].Data, 4);
      Inc(Offset, 4);
      Move(PByteArray(Block)^[Offset], Height, 2);
      Inc(Offset, 2);
      Move(PByteArray(Block)^[Offset], WidthCols, 2);
      Inc(Offset, 2);
      if MaxAvail >= FreeMemoryFloor then
      begin
        Inc(Loaded);
        AllocatePicture(Height, WidthCols, 1, Mode, Slots[I].Sprite);
        with Slots[I].Sprite^ do
        begin
          Move(PByteArray(Block)^[Offset], X, 2);
          Inc(Offset, 2);
          Move(PByteArray(Block)^[Offset], Y, 2);
          Inc(Offset, 3);
          Move(PByteArray(Block)^[Offset], Palette, 8);
          Inc(Offset, 8);
        end;
        if VideoAdapter = AdapterCga then
          Row := Slots[I].Sprite^.ByteSize * 2 - 1
        else
          Row := Slots[I].Sprite^.ByteSize - 1;
        if IsPicOrFinal then
        begin
          if I = 1 then
          begin
            GetMem(Prev, Row + 1);
            Move(PByteArray(Block)^[Offset], Prev^, Row + 1);
            PrevAllocated := True;
          end
          else
            for J := Offset to Offset + Row do
              PByteArray(Block)^[J] := PByteArray(Block)^[J] xor Prev^[J - Offset];
        end;
        UnpackPicturePixels(Block, Offset, Mode, 0, Slots[I].Sprite);
        if ((Mode and 1) > 0) and (VideoAdapter <> AdapterCga) then
          RemapPictureColors(@SpriteRemapFrom, @SpriteRemapTo, 0, 0, Slots[I].Sprite);
        Inc(Offset, Row + 1);
      end;
    end;
    Count := Loaded;
  end;
  if IsPicOrFinal and PrevAllocated then
    FreeMem(Prev, Row + 1);
  FreeMem(Block, Size);
  FlushKeyboard;
end;

{ ovl28:048F. Frees the sprite list Rec^: it frees the picture of every used slot (through
  ReleasePicture), then zeroes the whole SizeOf(TSpriteList)-byte record, clears the picture name
  DS:6B0A and sets the current bank DS:6B1C to NoBank. Called by ovl10, ovl14, ovl18 and
  LoadSpriteList. }
procedure FreeSpriteList(Rec: PSpriteList);
begin
  with Rec^ do
    for SharedLoopIndex := 1 to Count do
      ReleasePicture(Slots[SharedLoopIndex].Sprite);
  FillChar(Rec^, SizeOf(TSpriteList), 0);
  LastSpriteFile := '';
  LastSpriteBank := NoBank;
end;
{ ovl28:04F9. Shows the HEAD/BODY picture window of the character screen: when the character record
  DS:5D92 has both a HEAD and a BODY picture bank it draws the window (columns 28..38, rows 1..11)
  and loads and shows the HEAD and BODY sprites of those banks. Does nothing when either bank is 0.
  QUIRK ovl28:056C, ovl28:0593: the two Str() calls into V1 and V2 are computed and never read
  (a port may drop them). Called by ovl16:33E7 and ovl19:031E. }
procedure ShowHeadBodyWindow;
var
  V1, V2: string[3];              { the Str() of the two picture numbers, computed but not used }
begin
  if (SelectedCharacter^.HeadBank = 0) or (SelectedCharacter^.BodyBank = 0) then
    Exit;
  DrawWindow($1C, 1, $26, $B, 0, 0, '');
  with SelectedCharacter^ do
  begin
    Str(HeadPictureNumbers[HeadBank], V1);
    Str(BodyPictureNumbers[BodyBank], V2);
    LoadHeadBodySprites(HeadPictureNumbers[HeadBank], BodyPictureNumbers[BodyBank]);
  end;
  ShowHeadBodySprites($1C, 1, 1);
end;
{ ovl28:05D9. Loads the HEAD and the BODY 8x8 sprite bank for the picture number TileSet: for each
  bank that is asked for (not NoBank) and not already loaded (DS:6B00, DS:6B05) it loads the picture
  through LoadPicture from the file HEAD<number> or BODY<number> into DS:6B01 or DS:6B06, then
  records the loaded number. Calls FlushKeyboard at the end, which does nothing (QUIRK 0899:010A).
  Called by ShowHeadBody, ShowHeadBodyWindow and RedrawView. }
procedure LoadHeadBodySprites(HeadBank, BodyBank: Byte);
var
  Num: string[1];                 { Str(TileSet): the picture number in the file name }
begin
  Str(TileSet, Num);
  if HeadBank <> NoBank then
    if (HeadBankIndex = NoBank) or (HeadBankIndex <> HeadBank) then
    begin
      LoadPicture('HEAD' + Num, HeadBank, 0, 0, HeadSpriteBank);
      HeadBankIndex := HeadBank;
    end;
  if BodyBank <> NoBank then
    if (BodyBankIndex = NoBank) or (BodyBankIndex <> BodyBank) then
    begin
      LoadPicture('BODY' + Num, BodyBank, 0, 0, BodySpriteBank);
      BodyBankIndex := BodyBank;
    end;
  FlushKeyboard;
end;
{ ovl28:0697. Shows the HEAD/BODY sprites of the character screen at column Col and row Row. Both
  arms draw through the staging buffer (DrawHeadSprite and DrawBodySprite pass Direct 0 to
  DrawSprite): when WithBody is not 0 it draws the HEAD sprite DS:6B01 and the BODY sprite DS:6B06
  (5 rows lower), otherwise only the HEAD sprite. WithBody is not a Direct flag; every path goes
  through ShowPicture. Called by ShowHeadBody, RedrawView and ShowHeadBodyWindow. }
procedure ShowHeadBodySprites(Col, Row: Byte; WithBody: Byte);
begin
  if WithBody <> 0 then
  begin
    DrawHeadSprite(Col, Row, HeadSpriteBank);
    DrawBodySprite(Col, Row, BodySpriteBank);
  end
  else
    DrawSprite(Col, Row, 0, HeadSpriteBank);
end;
{ ovl28:0708. Copies the sprite list Rec^ into a local record and shows slot Slot (only 1..3 are
  legal; another slot restores the saved video mode with RestoreVideoMode, which calls
  SetVideoMode(SavedVideoMode) so the range message is readable, then ends the game with
  'Illegal range in Show3DSprite.'): the sprite is drawn at its base column and row plus 2 (X + 3 -
  1, Y + 3 - 1) through DrawPictureItemClipped onto the screen buffer DrawBuf and the display is stepped.
  A nil slot leaves early. Called by ShowEncounterPicture. }
procedure Show3DSprite(Slot: Byte; Rec: PSpriteList);
var
  List: TSpriteList;
begin
  List := Rec^;
  if (Slot < 1) or (Slot > Last3DSpriteSlot) then
  begin
    RestoreVideoMode;
    WriteLn(Output, 'Illegal range in Show3DSprite.');
    QuitGame;
  end;
  if List.Slots[Slot].Sprite <> nil then
    with List.Slots[Slot].Sprite^ do
      DrawPictureItemClipped(X + 3 - 1, Y + 3 - 1, 0, 1, List.Slots[Slot].Sprite, DrawBuf)
  else
    Exit;
  FlushPictureChanges;
end;

begin
end.

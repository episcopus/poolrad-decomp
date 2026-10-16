unit OVL18;
{ PoolNarrative: the ending narrative and door animation (whitepaper 5.x). ShowEndingNarrative
  shows the dragon's death and the Tyranthraxus and Bane speech as text lines and FINAL pictures,
  running the AnimateFinalPicture animation between the speech blocks, and AnimateAreaDoors animates the doors of
  the area view. Both draw through the res07 primitives. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure AnimateFinalPicture(Col, Row: Word; Bank, Cycles: Byte);
procedure ShowEndingNarrative;
procedure AnimateAreaDoors(Flag: Byte);
implementation
uses OVL27, OVL28, RES06, RES07, RES12;

{ ovl18:0006. Animates the FINAL ending picture at (Col, Row): loads the FINAL<TileSet>
  frames of bank Bank through LoadSpriteList and shows them Cycles times, drawing each frame
  through DrawSprite and waiting that frame's data delay, scaled by (GameSpeed + 3) ticks of
  the GameClock timer, before stepping to the next one, then frees the list. The frame
  cursor is the sprite list's Flag field (the loader sets it to 1); Count is read as a
  byte here (ovl18:00E1 compares it with a byte cmp/jbe although the shared type says
  ShortInt). Called by ShowEndingNarrative. }
procedure AnimateFinalPicture(Col, Row: Word; Bank, Cycles: Byte);
var
  Sprites: TSpriteList;         { the loaded FINAL frames, top of the frame }
  NowTick, StartTick: LongInt;  { the timer now, and when the current frame started }
  DoneCycles: Byte;             { full passes shown so far }
begin
  DoneCycles := 0;
  StartTick := GameClock;
  FillChar(Sprites, SizeOf(TSpriteList), 0);
  LoadSpriteList('FINAL', Bank, 2, @Sprites);
  DrawPictureItemClipped(Col - 1, Row - 1, 0, 0, Sprites.Slots[1].Sprite, DrawBuf);
  FlushPictureChanges;
  repeat
    DrawSprite(Col, Row, 1, Sprites.Slots[Sprites.Flag].Sprite);
    NowTick := GameClock;
    if (NowTick - StartTick) > LongInt(Sprites.Slots[Sprites.Flag].Data) * (GameSpeed + 3) then
    begin
      Inc(Sprites.Flag);
      if Sprites.Flag > Byte(Sprites.Count) then
      begin
        Sprites.Flag := 1;
        Inc(DoneCycles);
      end;
      StartTick := NowTick;
    end;
  until DoneCycles = Cycles;
  FreeSpriteList(@Sprites);
end;
{ ovl18:02A4. The ending narrative (PoolNarrative): it shows the dragon's death and the
  Tyranthraxus and Bane speech as lines of text (DrawTextAt on column 1, rows $11 onwards, colour
  10), loads the FINAL<number> pictures (whose number is Str(TileSet) in DS:4713) through
  LoadPicture and draws them with DrawPictureItemClipped, running the AnimateFinalPicture
  animation between the speech blocks, and restores the view mode DS:49F3 at the end.
  Callers: ovl03:2E10. Gets its picture
  number from DS:4713 and its lines from the code's literal pool. }
procedure ShowEndingNarrative;
begin
  Str(TileSet, FinalPictureNumber);
  SavedViewMode := ViewMode;
  ViewMode := 7;
  FinalPictureBank := nil;
  ClearRect(1, $11, $26, $16);
  DrawTextAt(1, $11, $A, 'Mortally wounded, the dragon roars!');
  DrawTextAt(1, $12, $A, 'The spirit of Tyranthraxus flares up');
  DrawTextAt(1, $13, $A, 'from the dragon''s body.');
  RedrawView;
  LoadPicture('FINAL' + FinalPictureNumber, 1, 0, 0, FinalPictureBank);
  DrawPictureItemClipped(0, 0, 0, 0, FinalPictureBank, DrawBuf);
  AnimateFinalPicture(3, 5, 2, (10 - GameSpeed) * 5 div 2);
  LoadPicture('FINAL' + FinalPictureNumber, 3, 0, 0, FinalPictureBank);
  DrawPictureItemClipped(0, 0, 0, 0, FinalPictureBank, DrawBuf);
  if GameVars2^[830] > 1 then
  begin
    LoadPicture('FINAL' + FinalPictureNumber, 4, 0, 0, FinalPictureBank);
    DrawPictureItemClipped(0, $B, 0, 0, FinalPictureBank, DrawBuf);
  end;
  if GameVars2^[830] > 2 then
  begin
    LoadPicture('FINAL' + FinalPictureNumber, 5, 0, 0, FinalPictureBank);
    DrawPictureItemClipped($D, 9, 0, 0, FinalPictureBank, DrawBuf);
  end;
  if GameVars2^[830] > 3 then
  begin
    LoadPicture('FINAL' + FinalPictureNumber, 6, 0, 0, FinalPictureBank);
    DrawPictureItemClipped(0, 9, 0, 0, FinalPictureBank, DrawBuf);
  end;
  ClearRect(1, $11, $26, $16);
  DrawTextAt(1, $11, $A, '"Fools, you have but slain the body');
  DrawTextAt(1, $12, $A, 'I possessed.  I cannot be defeated!"');
  DrawTextAt(1, $13, $A, 'With the power of the pool of radiance');
  DrawTextAt(1, $14, $A, 'which I moved here, to my lair,');
  DrawTextAt(1, $15, $A, 'I will still rule, by possessing one');
  DrawTextAt(1, $16, $A, 'of you!"');
  AnimateFinalPicture(3, 1, 7, (10 - GameSpeed) * 5 div 2);
  ClearRect(1, $11, $26, $16);
  DrawTextAt(1, $11, $A, '"No Lord Bane!  I can still rule here!');
  DrawTextAt(1, $12, $A, 'I have not failed.  Do not call me back');
  DrawTextAt(1, $13, $A, 'through the pool!"');
  DrawTextAt(1, $14, $A, 'Noooo...');
  AnimateFinalPicture(3, 1, 8, 1);
  DelayByGameSpeed;
  DelayByGameSpeed;
  DelayByGameSpeed;
  ViewMode := SavedViewMode;
  RedrawView;
end;
{ ovl18:06B3. Animates the doors of the area view (Flag 1) or clears them (flag 0): it draws the
  doors of the two block-code tables DS:0900 and DS:090B through RemapPictureColors (bit 7 of a code
  selects the second SQRPACI bank SqrPaciBank2, otherwise SqrPaciBank1), stepping the area view through
  DS:094D/DS:095F and stepping the display, then clears the doors. Called by ovl03:31B4 and
  ovl17:1602. }
procedure AnimateAreaDoors(Flag: Byte);
var
  DoorCol: Byte;                  { the door index within a block-code table }
  DoorRow: Byte;                  { the animation step, 0 to 8 }
begin
  if Flag <> 0 then
  begin
    DrawAreaView($11, $F);
    FlushPictureChanges;
    for DoorRow := 0 to 8 do
    begin
      for DoorCol := 0 to $A do
        if DoorBlockCodesFirst[DoorCol] > $7F then
          RemapPictureColors(@DoorRemapFrom, @DoorRemapToFirst, DoorBlockCodesFirst[DoorCol] and $7F, 1,
            Pointer(SqrPaciBank2))
        else
          RemapPictureColors(@DoorRemapFrom, @DoorRemapToFirst, DoorBlockCodesFirst[DoorCol], 1, Pointer(SqrPaciBank1));
      for DoorCol := 0 to $11 do
        if DoorBlockCodesSecond[DoorCol] > $7F then
          RemapPictureColors(@DoorRemapFrom, @DoorRemapToSecond, DoorBlockCodesSecond[DoorCol] and $7F, 1,
            Pointer(SqrPaciBank2))
        else
          RemapPictureColors(@DoorRemapFrom, @DoorRemapToSecond, DoorBlockCodesSecond[DoorCol], 1, Pointer(SqrPaciBank1));
      DrawAreaView(DoorViewColumns[DoorRow], DoorViewRows[DoorRow]);
      FlushPictureChanges;
    end;
  end;
  for DoorCol := 0 to $A do
    if DoorBlockCodesFirst[DoorCol] > $7F then
      RemapPictureColors(@DoorRemapFrom, @DoorRemapToFirst, DoorBlockCodesFirst[DoorCol] and $7F, 0, Pointer(SqrPaciBank2))
    else
      RemapPictureColors(@DoorRemapFrom, @DoorRemapToFirst, DoorBlockCodesFirst[DoorCol], 0, Pointer(SqrPaciBank1));
  for DoorCol := 0 to $11 do
    if DoorBlockCodesSecond[DoorCol] > $7F then
      RemapPictureColors(@DoorRemapFrom, @DoorRemapToSecond, DoorBlockCodesSecond[DoorCol] and $7F, 0, Pointer(SqrPaciBank2))
    else
      RemapPictureColors(@DoorRemapFrom, @DoorRemapToSecond, DoorBlockCodesSecond[DoorCol], 0, Pointer(SqrPaciBank1));
  if Flag <> 0 then
  begin
    DrawAreaView($17, $19);
    FlushPictureChanges;
    DelayByGameSpeed;
    DelayByGameSpeed;
  end;
end;

begin
end.

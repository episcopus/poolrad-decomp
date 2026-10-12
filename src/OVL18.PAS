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
  frames of bank Bank through ovl28_e2 and shows them Cycles times, drawing each frame
  through DrawSprite and waiting that frame's data delay, scaled by (ds49E2 + 3) ticks of
  the res06_fn_0C3F timer, before stepping to the next one, then frees the list. The frame
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
  StartTick := res06_fn_0C3F;
  FillChar(Sprites, SizeOf(TSpriteList), 0);
  ovl28_e2('FINAL', Bank, 2, @Sprites);
  res07_fn_0D71(Col - 1, Row - 1, 0, 0, Sprites.Slots[1].Sprite, DrawBuf);
  res07_fn_1B52;
  repeat
    DrawSprite(Col, Row, 1, Sprites.Slots[Sprites.Flag].Sprite);
    NowTick := res06_fn_0C3F;
    if (NowTick - StartTick) > LongInt(Sprites.Slots[Sprites.Flag].Data) * (ds49E2 + 3) then
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
  Tyranthraxus and Bane speech as lines of text (res06_fn_0626 on column 1, rows $11 onwards, colour
  10), loads the FINAL<number> pictures (whose number is Str(TileSet) in DS:4713) through
  res07_fn_0111 and draws them with res07_fn_0D71, running the AnimateFinalPicture
  animation between the speech blocks, and restores the view mode DS:49F3 at the end.
  Callers: ovl03:2E10. Gets its picture
  number from DS:4713 and its lines from the code's literal pool. }
procedure ShowEndingNarrative;
begin
  Str(TileSet, ds4713);
  ds4712 := ds49F3;
  ds49F3 := 7;
  ds470E := nil;
  res06_fn_0DD3(1, $11, $26, $16);
  res06_fn_0626(1, $11, $A, 'Mortally wounded, the dragon roars!');
  res06_fn_0626(1, $12, $A, 'The spirit of Tyranthraxus flares up');
  res06_fn_0626(1, $13, $A, 'from the dragon''s body.');
  res12_fn_27D9;
  res07_fn_0111('FINAL' + ds4713, 1, 0, 0, ds470E);
  res07_fn_0D71(0, 0, 0, 0, ds470E, DrawBuf);
  AnimateFinalPicture(3, 5, 2, (10 - ds49E2) * 5 div 2);
  res07_fn_0111('FINAL' + ds4713, 3, 0, 0, ds470E);
  res07_fn_0D71(0, 0, 0, 0, ds470E, DrawBuf);
  if ds49D6^[830] > 1 then
  begin
    res07_fn_0111('FINAL' + ds4713, 4, 0, 0, ds470E);
    res07_fn_0D71(0, $B, 0, 0, ds470E, DrawBuf);
  end;
  if ds49D6^[830] > 2 then
  begin
    res07_fn_0111('FINAL' + ds4713, 5, 0, 0, ds470E);
    res07_fn_0D71($D, 9, 0, 0, ds470E, DrawBuf);
  end;
  if ds49D6^[830] > 3 then
  begin
    res07_fn_0111('FINAL' + ds4713, 6, 0, 0, ds470E);
    res07_fn_0D71(0, 9, 0, 0, ds470E, DrawBuf);
  end;
  res06_fn_0DD3(1, $11, $26, $16);
  res06_fn_0626(1, $11, $A, '"Fools, you have but slain the body');
  res06_fn_0626(1, $12, $A, 'I possessed.  I cannot be defeated!"');
  res06_fn_0626(1, $13, $A, 'With the power of the pool of radiance');
  res06_fn_0626(1, $14, $A, 'which I moved here, to my lair,');
  res06_fn_0626(1, $15, $A, 'I will still rule, by possessing one');
  res06_fn_0626(1, $16, $A, 'of you!"');
  AnimateFinalPicture(3, 1, 7, (10 - ds49E2) * 5 div 2);
  res06_fn_0DD3(1, $11, $26, $16);
  res06_fn_0626(1, $11, $A, '"No Lord Bane!  I can still rule here!');
  res06_fn_0626(1, $12, $A, 'I have not failed.  Do not call me back');
  res06_fn_0626(1, $13, $A, 'through the pool!"');
  res06_fn_0626(1, $14, $A, 'Noooo...');
  AnimateFinalPicture(3, 1, 8, 1);
  res06_fn_0DBE;
  res06_fn_0DBE;
  res06_fn_0DBE;
  ds49F3 := ds4712;
  res12_fn_27D9;
end;
{ ovl18:06B3. Animates the doors of the area view (Flag 1) or clears them (flag 0): it draws the
  doors of the two block-code tables DS:0900 and DS:090B through res07_fn_1E5C (bit 7 of a code
  selects the second SQRPACI bank ds5E56, otherwise ds5E52), stepping the area view through
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
    res07_fn_1B52;
    for DoorRow := 0 to 8 do
    begin
      for DoorCol := 0 to $A do
        if ds0900[DoorCol] > $7F then
          res07_fn_1E5C(@ds091D, @ds092D, ds0900[DoorCol] and $7F, 1, Pointer(ds5E56))
        else
          res07_fn_1E5C(@ds091D, @ds092D, ds0900[DoorCol], 1, Pointer(ds5E52));
      for DoorCol := 0 to $11 do
        if ds090B[DoorCol] > $7F then
          res07_fn_1E5C(@ds091D, @ds093D, ds090B[DoorCol] and $7F, 1, Pointer(ds5E56))
        else
          res07_fn_1E5C(@ds091D, @ds093D, ds090B[DoorCol], 1, Pointer(ds5E52));
      DrawAreaView(ds094D[DoorRow], ds095F[DoorRow]);
      res07_fn_1B52;
    end;
  end;
  for DoorCol := 0 to $A do
    if ds0900[DoorCol] > $7F then
      res07_fn_1E5C(@ds091D, @ds092D, ds0900[DoorCol] and $7F, 0, Pointer(ds5E56))
    else
      res07_fn_1E5C(@ds091D, @ds092D, ds0900[DoorCol], 0, Pointer(ds5E52));
  for DoorCol := 0 to $11 do
    if ds090B[DoorCol] > $7F then
      res07_fn_1E5C(@ds091D, @ds093D, ds090B[DoorCol] and $7F, 0, Pointer(ds5E56))
    else
      res07_fn_1E5C(@ds091D, @ds093D, ds090B[DoorCol], 0, Pointer(ds5E52));
  if Flag <> 0 then
  begin
    DrawAreaView($17, $19);
    res07_fn_1B52;
    res06_fn_0DBE;
    res06_fn_0DBE;
  end;
end;

begin
end.

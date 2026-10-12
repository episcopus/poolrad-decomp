unit OVL28;
{ ovl28: the 3D sprite and picture unit (whitepaper 4.x). It draws the 8x8 sprites of the 3D view
  (Show3DSprite and its helpers), loads PIC/FINAL picture records into the sprite banks through
  res07_fn_0111 and frees them again, and shows the HEAD/BODY window of the character screen. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure DrawSprite(Col, Row: Integer; Direct: Byte; Sprite: Pointer);
procedure DrawHeadSprite(Col, Row: Byte; Sprite: Pointer);
procedure DrawBodySprite(Col, Row: Byte; Sprite: Pointer);
procedure ovl28_e2;
procedure ovl28_e3;
procedure ovl28_e4;
procedure ovl28_e6;
procedure ovl28_e5;
procedure ovl28_e7;
implementation
uses RES05, RES07;

{ ovl28:0000. Draws the 8x8 sprite Sprite at column X and row Y. A nil Sprite draws nothing. When
  Direct is set it blits the sprite one pixel up and left onto the screen buffer ds4A20 through
  res07_fn_0D71 (mode 0, the flag 1) and steps the display through res07_fn_1B52; otherwise it
  copies it into the staging buffer with res07_fn_1951. Called by DrawHeadSprite, DrawBodySprite and
  ovl28_e5 inside this unit, and from ovl03, ovl07_e8, ovl18 and ovl25 (the packet's callers). }
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
  (through DrawSprite, the staging buffer path). Called by ovl28_e5 (Show3DSprite). }
procedure DrawHeadSprite(Col, Row: Byte; Sprite: Pointer);
begin
  DrawSprite(Col, Row, 0, Sprite);
end;

{ ovl28:0070. Draws the 8x8 sprite Sprite at column Col and row Row plus 5 (through DrawSprite, the
  staging buffer path). Called by ovl28_e5 (Show3DSprite). }
procedure DrawBodySprite(Col, Row: Byte; Sprite: Pointer);
begin
  DrawSprite(Col, Row + 5, 0, Sprite);
end;

{ ovl28:00A2: retf 12: 12 bytes of parameters; 296 bytes of locals }
{@stub} procedure ovl28_e2; begin end;
{ ovl28:048F: retf 4: 4 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl28_e3; begin end;
{ ovl28:04F9: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl28_e4; begin end;
{ ovl28:05D9: retf 4: 4 bytes of parameters; 258 bytes of locals }
{@stub} procedure ovl28_e6; begin end;
{ ovl28:0697: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl28_e5; begin end;
{ ovl28:0708: retf 6: 6 bytes of parameters; 70 bytes of locals }
{@stub} procedure ovl28_e7; begin end;

begin
end.

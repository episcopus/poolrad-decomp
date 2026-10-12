unit OVL26;
{ The area view (whitepaper 5.x): ShowAreaView shows either the 3D wall view or the scrolling map
  window, DrawPartyMarker draws the animated party marker onto that window. The callers are the
  view dispatcher of the resident unit (res12_fn_27D9, view types 3 and 4) and the wilderness map
  screen (res12_fn_2B5E, after the text windows of ovl27_e2). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure DrawPartyMarker;
procedure ShowAreaView;
implementation
uses POOLVARS, OVL27, OVL29, OVL32, RES07;

const
  { Where the party cell in the 5x5 map window stops being the centre cell 2: ovl27_e1 clamps the
    window to columns 0..39 and rows 0..31 of the 44-column map, so a column of 42 (a row of 34)
    puts the party at cell 3, and 43 (35) or more at cell 4 (ovl26:001F, ovl26:0043). }
  Cell3Column = $2A;
  Cell4Column = $2B;
  Cell3Row = $22;
  Cell4Row = $23;

{ ovl26:0000. Draws the animated party marker onto the 5x5 map window that ShowAreaView just drew
  (through ovl27_e1). The marker cell is the party position, MapBaseX[AreaViewKind] plus
  TGameState.MapX and TGameState.MapY, folded the same way ShowAreaView clamps the window:
  columns and rows 0 and 1 are kept, everything up to the fold constants becomes the centre cell
  2, and past them the cell shows 3 and 4. PicLoad draws the marker itself (ovl32_e5) with the
  icon set ds6AAF and the walk animation MarkerFrame (MarkerFrame mod 2 picks the mirrored half,
  MarkerFrame div 2 + 9 the picture 9 to 11); the frame then steps to the next of its six values.
  Reads and changes: MapBaseX, AreaViewKind, ds49D2^, ds6AAF, MarkerFrame. Side effect: the view
  on the screen, through ovl32_e5 and the display step res07_fn_1B52 that drawing units call. }
procedure DrawPartyMarker;
var
  MarkerCol: ShortInt;      { the marker cell column in the 5x5 window (0 to 4) }
  MarkerRow: ShortInt;      { the marker cell row in the 5x5 window (0 to 4) }
begin
  MarkerCol := MapBaseX[AreaViewKind] + ds49D2^.MapX;
  if MarkerCol < 2 then
    begin { QUIRK ovl26:001F: the empty branch is in the original: columns 0 and 1 keep their cell } end
  else if MarkerCol < Cell3Column then MarkerCol := 2
  else if MarkerCol < Cell4Column then MarkerCol := 3
  else MarkerCol := 4;
  if ds49D2^.MapY < 2 then MarkerRow := ds49D2^.MapY
  else if ds49D2^.MapY < Cell3Row then MarkerRow := 2
  else if ds49D2^.MapY < Cell4Row then MarkerRow := 3
  else MarkerRow := 4;
  ovl32_e5(MarkerCol, MarkerRow, ds6AAF, MarkerFrame mod 2, MarkerFrame div 2 + 9);
  MarkerFrame := (MarkerFrame + 1) mod 6;
  res07_fn_1B52;
end;

{ ovl26:016D. Shows the current area view, the way the view dispatcher of the resident unit asks
  for it (res12_fn_27D9, view types 3 and 4). The kind is AreaViewKind, or 1 whenever the
  ForceWallView word of the game state is set. Kind 1 draws the 3D wall view: it asks GeoLoad for
  the event byte of the party cell (ovl29_e4; bit 7 says the cell is interior), picks the wall id
  table entry ds0C26[WallIndexInside] or ds0C26[WallIndexOutside] accordingly, refreshes
  descriptors 2 to 4 from the special view codes ds6F69 and ds6F68 while ds84E5 is set, hands all
  four descriptors to ovl29_e1, clears ds6AAC when ShowWallOverlays asks, and lets ovl29_e5 draw
  the rest. Kinds 2 to 4 draw the 5x5 map window (ovl27_e1) around the party position minus 2,
  clamped to columns 0..39 and rows 0..31, then DrawPartyMarker. Reads: AreaViewKind, ds49D2^,
  ds6AAD, ds6AAE, ds6AAF, ds6F68, ds6F69, ds84E5, ds0C26, MapBaseX. Changes: ds6A60 to ds6A63,
  ds6AB1, ds6AAC. Side effect: the view on the screen.
  QUIRK ovl26:018C: the three helpers below are nested functions of this routine: the caller
  pushes its frame as their static link (push bp at ovl26:01D7, 01E3, 01EF), which is why they
  carry 4 parameter bytes and live in the code right before this routine. }
procedure ShowAreaView;
var
  WindowLeft: ShortInt;     { the map window left column (0 to 39) }
  WindowTop: ShortInt;      { the map window top row (0 to 31) }
  ViewKind: Byte;           { AreaViewKind, or 1 when the state record forces the wall view }

  { ovl26:00C7. Purpose unknown beyond the mapping: turns the special view code (ds6F69, a
    location code the loaders and the script command $F7 set when they also set ds84E5) into wall
    view descriptor 2 (ds6A61): codes 8 and $41 give 0, anything else $0F. ovl29_fn_0174 draws
    with the descriptors; what the values select is still open. }
  function WallDesc2FromCode(SpecialCode: Byte): Byte;
  begin
    case SpecialCode of
      8:   WallDesc2FromCode := 0;
      $41: WallDesc2FromCode := 0;
      $E8: WallDesc2FromCode := $0F;
    else
      WallDesc2FromCode := $0F;
    end;
  end;

  { ovl26:00FB. Purpose unknown beyond the mapping: turns the special view code (ds6F69) into wall
    view descriptor 3 (ds6A62): code 8 gives 8, anything else 7. }
  function WallDesc3FromCode(SpecialCode: Byte): Byte;
  begin
    case SpecialCode of
      8:   WallDesc3FromCode := 8;
      $41: WallDesc3FromCode := 7;
      $E8: WallDesc3FromCode := 7;
    else
      WallDesc3FromCode := 7;
    end;
  end;

  { ovl26:012F. Purpose unknown beyond the mapping: turns the special view code (ds6F68, set with
    ds84E5 by the loaders and by the script command $F1) into wall view descriptor 4 (ds6A63):
    code $0B gives 8, code 6 gives 1, anything else 6. }
  function WallDesc4FromCode(SpecialCode: Byte): Byte;
  begin
    case SpecialCode of
      $0B: WallDesc4FromCode := 8;
      9:   WallDesc4FromCode := 6;
      $DB: WallDesc4FromCode := 6;
      6:   WallDesc4FromCode := 1;
    else
      WallDesc4FromCode := 6;
    end;
  end;

begin
  ViewKind := AreaViewKind;
  if ds49D2^.ForceWallView <> 0 then ViewKind := 1;
  case ViewKind of
    1:
      begin
        ds6AB1 := ovl29_e4(ds6AAD, ds6AAE);
        if ds6AB1 > $7F then
          ds6A60 := ds0C26[ds49D2^.WallIndexInside]
        else
          ds6A60 := ds0C26[ds49D2^.WallIndexOutside];
        if ds84E5 <> 0 then
        begin
          ds6A61 := WallDesc2FromCode(ds6F69);
          ds6A62 := WallDesc3FromCode(ds6F69);
          ds6A63 := WallDesc4FromCode(ds6F68);
        end;
        ovl29_e1(ds6A60, ds6A61, ds6A62, ds6A63);
        if ds49D2^.ShowWallOverlays <> 0 then ds6AAC := 0;
        ovl29_e5(ds6AAD, ds6AAE, ds6AAF);
      end;
    2..4:
      begin
        WindowLeft := MapBaseX[ViewKind] + ds49D2^.MapX - 2;
        if WindowLeft < 0 then WindowLeft := 0;
        if WindowLeft > $27 then WindowLeft := $27;
        WindowTop := ds49D2^.MapY - 2;
        if WindowTop < 0 then WindowTop := 0;
        if WindowTop > $1F then WindowTop := $1F;
        ovl27_e1(WindowLeft, WindowTop);
        DrawPartyMarker;
      end;
  end;
end;

begin
end.

unit OVL26;
{ The area view (whitepaper 5.2.1): ShowAreaView shows either the 3D wall view or the scrolling map
  window, DrawPartyMarker draws the animated party marker onto that window. The callers are the
  view dispatcher of the resident unit (res12_fn_27D9, view types 3 and 4) and the wilderness map
  screen (res12_fn_2B5E, after the text windows of DrawAdventureScreen). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure DrawPartyMarker;
procedure ShowAreaView;
implementation
uses POOLVARS, OVL27, OVL29, OVL32, RES07;

const
  { Where the party cell in the 5x5 map window stops being the centre cell 2: ShowAreaView clamps
    the window to columns 0..39 and rows 0..31 of the 44-column map (ovl26:0137), and the marker
    is the party position within that window, so a party column of 42 (a party row of 34) puts the
    marker at cell 3 and 43 (35) or more at cell 4 (ovl26:001F, ovl26:0043). }
  Cell3Column = $2A;
  Cell4Column = $2B;
  Cell3Row = $22;
  Cell4Row = $23;

{ ovl26:0000. Draws the animated party marker onto the 5x5 map window that ShowAreaView just drew
  (through DrawAreaView). The marker cell is the party position within that window, MapBaseX[AreaViewKind]
  plus GameVars^[VarMapX] (the column) and GameVars^[VarMapY] (the row), folded with the same edge
  limits ShowAreaView clamps the window to (ovl26:0137): columns and rows 0 and 1 stay at the edges,
  2 to 41 (rows 2 to 33) become the centre cell 2, 42 (row 34) cell 3 and 43 (row 35) or more cell 4.
  PicLoad draws the marker itself (ovl32_e5) with the icon set ds6AAF and the walk animation
  MarkerFrame (MarkerFrame mod 2 picks the mirrored half, MarkerFrame div 2 + 9 the picture 9 to
  11); the frame then steps to the next of its six values.
  Reads and changes: MapBaseX, AreaViewKind, GameVars^, ds6AAF, MarkerFrame. Side effect: the view
  on the screen, through ovl32_e5 and the display step res07_fn_1B52 that drawing units call. }
procedure DrawPartyMarker;
var
  MarkerCol: ShortInt;      { the marker cell column in the 5x5 window (0 to 4) }
  MarkerRow: ShortInt;      { the marker cell row in the 5x5 window (0 to 4) }
begin
  MarkerCol := MapBaseX[AreaViewKind] + GameVars^[VarMapX];
  if MarkerCol < 2 then
    begin { QUIRK ovl26:001F: the empty branch is in the original: columns 0 and 1 keep their cell } end
  else if MarkerCol < Cell3Column then MarkerCol := 2
  else if MarkerCol < Cell4Column then MarkerCol := 3
  else MarkerCol := 4;
  if GameVars^[VarMapY] < 2 then MarkerRow := GameVars^[VarMapY]
  else if GameVars^[VarMapY] < Cell3Row then MarkerRow := 2
  else if GameVars^[VarMapY] < Cell4Row then MarkerRow := 3
  else MarkerRow := 4;
  ovl32_e5(MarkerCol, MarkerRow, ds6AAF, MarkerFrame mod 2, MarkerFrame div 2 + 9);
  MarkerFrame := (MarkerFrame + 1) mod 6;
  res07_fn_1B52;
end;

{ ovl26:016D. Shows the current area view, the way the view dispatcher of the resident unit asks
  for it (res12_fn_27D9, view types 3 and 4). The kind is AreaViewKind, or 1 whenever the
  game variable VarForceWallView is set. Kind 1 draws the 3D wall view: it asks GeoLoad for
  the event byte of the party cell (ovl29_e4; bit 7 says the cell is interior), picks the wall id
  table entry ds0C26[VarWallIndexInside] or ds0C26[VarWallIndexOutside] accordingly, refreshes
  descriptors 2 to 4 from the special view codes ds6F69 and ds6F68 while ds84E5 is set, hands all
  four descriptors to ovl29_e1, clears ds6AAC when VarShowWallOverlays asks, and lets ovl29_e5 draw
  the rest. Kinds 2 to 4 draw the 5x5 map window (DrawAreaView) around the party position minus 2,
  clamped to columns 0..39 and rows 0..31, then DrawPartyMarker. Reads: AreaViewKind, GameVars^,
  ds6AAD, ds6AAE, ds6AAF, ds6F68, ds6F69, ds84E5, ds0C26, MapBaseX. Changes: ds6A60 to ds6A63,
  ds6AB1, ds6AAC. Side effect: the view on the screen.
  QUIRK ovl26:018C: the three helpers below are nested functions of this routine: the caller
  pushes its frame as their static link (push bp at ovl26:01D7, 01E3, 01EF), which is why they
  carry 4 parameter bytes and live in the code right before this routine. }
procedure ShowAreaView;
var
  WindowLeft: ShortInt;     { the map window left column (0 to 39) }
  WindowTop: ShortInt;      { the map window top row (0 to 31) }
  ViewKind: Byte;           { AreaViewKind, or 1 when VarForceWallView forces the wall view }

  { ovl26:00C7. Purpose unknown beyond the mapping: turns the special view code (ds6F69) into wall
    view descriptor 2 (ds6A61): codes 8 and $41 give 0, anything else $0F. This unit only reads
    ds6F69; whitepaper 5.2.1 records who sets it together with ds84E5. The descriptors reach the
    screen through ovl29_fn_0174; what the values select is still open. }
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
    view descriptor 3 (ds6A62): code 8 gives 8, anything else 7. This unit only reads ds6F69. }
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

  { ovl26:012F. Purpose unknown beyond the mapping: turns the special view code (ds6F68) into wall
    view descriptor 4 (ds6A63): code $0B gives 8, code 6 gives 1, anything else 6. This unit only
    reads ds6F68; whitepaper 5.2.1 records who sets it together with ds84E5. }
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
  if GameVars^[VarForceWallView] <> 0 then ViewKind := 1;
  case ViewKind of
    1:
      begin
        ds6AB1 := ovl29_e4(ds6AAD, ds6AAE);
        if ds6AB1 > $7F then
          ds6A60 := ds0C26[GameVars^[VarWallIndexInside]]
        else
          ds6A60 := ds0C26[GameVars^[VarWallIndexOutside]];
        if ds84E5 <> 0 then
        begin
          ds6A61 := WallDesc2FromCode(ds6F69);
          ds6A62 := WallDesc3FromCode(ds6F69);
          ds6A63 := WallDesc4FromCode(ds6F68);
        end;
        ovl29_e1(ds6A60, ds6A61, ds6A62, ds6A63);
        if GameVars^[VarShowWallOverlays] <> 0 then ds6AAC := 0;
        ovl29_e5(ds6AAD, ds6AAE, ds6AAF);
      end;
    2..4:
      begin
        WindowLeft := MapBaseX[ViewKind] + GameVars^[VarMapX] - 2;
        if WindowLeft < 0 then WindowLeft := 0;
        if WindowLeft > $27 then WindowLeft := $27;
        WindowTop := GameVars^[VarMapY] - 2;
        if WindowTop < 0 then WindowTop := 0;
        if WindowTop > $1F then WindowTop := $1F;
        DrawAreaView(WindowLeft, WindowTop);
        DrawPartyMarker;
      end;
  end;
end;

{ ovl26:02A0. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
  (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the area view unit runs no code
  at start-up. }
begin
end.

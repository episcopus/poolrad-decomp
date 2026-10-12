unit OVL26;
{ The area view (whitepaper 5.x): ovl26_e1 shows either the 3D wall view or the scrolling map
  window, DrawPartyMarker draws the party's animated marker onto that window. The callers are the view
  dispatcher of the resident unit (res12_fn_27D9, view types 3 and 4) and the wilderness map screen
  (res12_fn_2B5E, after ovl27_e2's text windows). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure DrawPartyMarker;
procedure ovl26_fn_00C7;
procedure ovl26_fn_00FB;
procedure ovl26_fn_012F;
procedure ovl26_e1;
implementation
uses POOLVARS, OVL27, OVL29, OVL32, RES07;

const
  { Where the party's cell in the 5x5 map window stops being the centre cell 2: ovl27_e1 clamps the
    window to columns 0..39 and rows 0..31 of the 44-column map, so a column of 42 (a row of 34)
    puts the party at cell 3 and 43 (35) or more at cell 4 (ovl26:001F, ovl26:0043). }
  Cell3Column = $2A;
  Cell4Column = $2B;
  Cell3Row = $22;
  Cell4Row = $23;

{ ovl26:0000. Draws the party's animated marker onto the 5x5 map window that ovl26_e1 just drew
  (through ovl27_e1). The marker's cell is the party's position, MapBaseX[AreaViewKind] +
  TGameState.MapX and TGameState.MapY, folded the same way ovl26_e1 clamps the window: columns and
  rows 0 and 1 are kept, everything up to the fold constants becomes the centre cell 2, and past
  them the cell shows 3 and 4. The marker itself is drawn by PicLoad (ovl32_e5) with the icon set
  ds6AAF and the walk animation MarkerFrame (MarkerFrame mod 2 picks the mirrored half,
  MarkerFrame div 2 + 9 the picture 9 to 11); the frame then steps to the next of its six values.
  Reads and changes: MapBaseX, AreaViewKind, ds49D2^, ds6AAF, MarkerFrame. Side effect: the view on
  the screen, through ovl32_e5 and the display step res07_fn_1B52 that every drawing unit calls. }
procedure DrawPartyMarker;
var
  MarkerCol: ShortInt;      { the marker's cell column in the 5x5 window (0 to 4) }
  MarkerRow: ShortInt;      { the marker's cell row in the 5x5 window (0 to 4) }
begin
  MarkerCol := MapBaseX[AreaViewKind] + ds49D2^.MapX;
  if MarkerCol < 2 then
    begin { QUIRK ovl26:001F: the empty branch is the original's: columns 0 and 1 keep their cell } end
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

{ ovl26:00C7. retf 4: 4 bytes of parameters; 2 bytes of locals.
  Purpose unknown: really a nested Byte function of ovl26_e1 (its caller pushes ovl26_e1's frame
  as the static link: push bp at ovl26:01D7): it maps the special view code ds6F69 to the wall view
  descriptor ds6A61 (codes 8 and $41 give 0, anything else $0F). Kept a top level stub because the
  matcher cannot see nested routines yet; see the notes on ovl26_e1. }
{@stub} procedure ovl26_fn_00C7; begin end;
{ ovl26:00FB. retf 4: 4 bytes of parameters; 2 bytes of locals.
  Purpose unknown: a nested Byte function of ovl26_e1 mapping the special view code ds6F69 to the
  wall view descriptor ds6A62 (code 8 gives 8, anything else 7). Kept a top level stub like
  ovl26_fn_00C7. }
{@stub} procedure ovl26_fn_00FB; begin end;
{ ovl26:012F. retf 4: 4 bytes of parameters; 2 bytes of locals.
  Purpose unknown: a nested Byte function of ovl26_e1 mapping the special view code ds6F68 to the
  wall view descriptor ds6A63 (code $0B gives 8, code 6 gives 1, anything else 6). Kept a top level
  stub like ovl26_fn_00C7. }
{@stub} procedure ovl26_fn_012F; begin end;

{ ovl26:016D. retf 0: 0 bytes of parameters; 4 bytes of locals.
  Shows the current area view: AreaViewKind 1 (or the state record's word at $1CC set) draws the
  3D wall view through GeoLoad (ovl29_e4 for the cell's event byte, ovl29_e1 for the four view
  descriptors, ovl29_e5 for the rest), kinds 2 to 4 draw the 5x5 map window through ovl27_e1 and
  then the party marker (DrawPartyMarker). Fully analysed and probed, but blocked on the matcher: its
  three helpers are nested functions (above), whose calls and code the matcher cannot verify yet;
  see re/symbols.toml notes. }
{@stub} procedure ovl26_e1; begin end;

begin
end.

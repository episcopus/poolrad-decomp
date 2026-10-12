unit OVL29;
{ The wall view and GEO loader (whitepaper 5.2): SetWallDescriptors stores the four wall view
  descriptors (ds6A60..ds6A63) that ShowAreaView passes; CellInRange tests a 16x16 block map cell;
  EventByteAt reads the event byte of a map cell; ovl29_e5 draws the wall view and its overlay labels;
  LoadWallSet and Load3DMap load the WALLDEF and GEO data. Design doc whitepaper 5.2. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure DrawWallMap(Col, Row: ShortInt; Dir: Byte);
procedure SetWallDescriptors(Wall1, Wall2, Wall3, Wall4: Byte);
procedure DrawWallDescriptors;
procedure DrawWallPiece(Col, Row: ShortInt; Wall, Piece: Byte);
function CellInRange(Col, Row: ShortInt): Boolean;
function DoorKindAt(Col, Row: ShortInt; Dir: Byte): Byte;
function WallIdAt(Col, Row: ShortInt; Dir: Byte): Byte;
function EventByteAt(Col, Row: ShortInt): Byte;
procedure StepDisplay;
procedure ovl29_e5(A, B, C: Byte);
procedure LoadWallSet;
procedure Load3DMap;
implementation
uses POOLVARS, RES07, OVL34;
const
  { The facing directions the map routines take (the step tables ds2736/ds273F are indexed by
    them); which wall nibble and door bit pair each one selects is whitepaper 4.2.1. }
  DirNorth = 0;
  DirEast = 2;
  DirSouth = 4;
  DirWest = 6;
  MapLast = $F;          { the last row and column of the 16x16 area map }
  DoorOpen = 1;          { DoorKindAt's answer for a side with no wall }
  WallSymbols = $104;    { the 8x8 symbol of a map cell with no wall; plus 1/2/4/8 per wall side }
  PartyArrow = $100;     { the 8x8 symbol of the party arrow facing north; plus Dir div 2 }
  MapWindowHalf = 5;     { the overhead map window reaches 5 cells each side of the party }
  ViewLast = 10;         { the last tile column and row of the 11x11 tile 3D view }
  ViewLeft = 3;          { the screen column (and row) of the view's first tile, counted from 1 }

{ ovl29:0000. Draws the overhead wall map in the view instead of the 3D walls (ovl29_e5 calls it
  while ds6AAC is nonzero): an 11x11 window of the 16x16 area map, placed so that the party cell
  (Col, Row) is centred where the map allows (the window's left column and top row are clamped to
  0..5), one 8x8 symbol per cell: WallSymbols plus 1, 2, 4 and 8 for a wall on the north, east,
  south and west side (WallIdAt nonzero). Then the party arrow, PartyArrow + Dir div 2 (Dir 0, 2,
  4, 6), goes on the party's cell, and StepDisplay shows the result. The map's symbols go through
  Put8x8Symbol with Direct 1, Attr 0. QUIRK ovl29:0003: the frame holds 256 more bytes that no code
  uses (Unused). The map placed a second routine at ovl29:0143; it is this routine's tail. }
procedure DrawWallMap(Col, Row: ShortInt; Dir: Byte);
var
  PartyCol: ShortInt;
  PartyRow: ShortInt;
  ViewCol: ShortInt;
  ViewRow: ShortInt;
  LeftCol: ShortInt;
  TopRow: ShortInt;
  MapCol: ShortInt;
  MapRow: ShortInt;
  Symbol: Word;
  Unused: string;
begin
  LeftCol := Col - MapWindowHalf;
  if LeftCol < 0 then LeftCol := 0;
  if LeftCol > MapWindowHalf then LeftCol := MapWindowHalf;
  PartyCol := Col - LeftCol;
  TopRow := Row - MapWindowHalf;
  if TopRow < 0 then TopRow := 0;
  if TopRow > MapWindowHalf then TopRow := MapWindowHalf;
  PartyRow := Row - TopRow;
  for ViewRow := 0 to ViewLast do
  begin
    MapRow := ViewRow + TopRow;
    for ViewCol := 0 to ViewLast do
    begin
      MapCol := ViewCol + LeftCol;
      Symbol := WallSymbols;
      if WallIdAt(MapCol, MapRow, DirNorth) > 0 then Inc(Symbol);
      if WallIdAt(MapCol, MapRow, DirEast) > 0 then Inc(Symbol, 2);
      if WallIdAt(MapCol, MapRow, DirSouth) > 0 then Inc(Symbol, 4);
      if WallIdAt(MapCol, MapRow, DirWest) > 0 then Inc(Symbol, 8);
      Put8x8Symbol(ViewCol + ViewLeft - 1, ViewRow + ViewLeft - 1, Symbol, 1, 0);
    end;
  end;
  Put8x8Symbol(PartyCol + ViewLeft - 1, PartyRow + ViewLeft - 1, Dir shr 1 + PartyArrow, 1, 0);
  StepDisplay;
end;
{ ovl29:0155: retf 8: 8 bytes of parameters; 0 bytes of locals }
{ ovl29:0155. Stores the four wall view descriptors: A..D into ds6A60..ds6A63 (descriptor 1..4;
  whitepaper 5.2). Called by ovl26 ShowAreaView with the wall view ids. }
procedure SetWallDescriptors(Wall1, Wall2, Wall3, Wall4: Byte);
begin
  ds6A60 := Wall1;
  ds6A61 := Wall2;
  ds6A62 := Wall3;
  ds6A63 := Wall4;
end;
{ ovl29:0174. Draws the four wall view descriptors ds6A60..ds6A63 through res07_fn_2632 (A=2,
  B and D the descriptor's screen position/size, C=$B, E the descriptor, F=@ds260A's 8-byte
  structure, G=DrawBuf). Called by ovl29_e5. }
procedure DrawWallDescriptors;
begin
  res07_fn_2632(2, $10, $B, $2B, ds6A60, @ds260A, DrawBuf);
  res07_fn_2632(2, $3B, $B, 1, ds6A61, @ds260A, DrawBuf);
  res07_fn_2632(2, $3C, $B, 2, ds6A62, @ds260A, DrawBuf);
  res07_fn_2632(2, $3E, $B, $2A, ds6A63, @ds260A, DrawBuf);
end;
{ ovl29:0211. Draws piece Piece (0..9) of wall Wall (a wall id 1..15) in the 3D view: the piece's
  Width x Height tiles (ds0C96, ds0CA0), taken in order from the wall's tile list ds6A58^[Wall]
  starting at ds0C8C[Piece], go row by row to the view cells from (Col, Row) on. Cells outside the
  11x11 view (0..ViewLast) and tile number 0 are skipped; each drawn tile is an 8x8 symbol at
  screen column Col + ViewLeft - 1 (Put8x8Symbol with Direct 1, the 3D view path). Called by
  ovl29_e5 with the piece positions ds0CAA/ds0CBE, shifted per distance and side. }
procedure DrawWallPiece(Col, Row: ShortInt; Wall, Piece: Byte);
var
  LastCol: Integer;
  LastRow: Integer;
  TileCol: Integer;
  TileRow: Integer;
  Tile: Byte;
begin
  Tile := ds0C8C[Piece];
  LastCol := ds0C96[Piece] + Col - 1;
  LastRow := ds0CA0[Piece] + Row - 1;
  for TileRow := Row to LastRow do
    for TileCol := Col to LastCol do
    begin
      if (TileRow >= 0) and (TileRow <= ViewLast) and (TileCol >= 0) and (TileCol <= ViewLast) then
        if ds6A58^[Wall, Tile] > 0 then
          Put8x8Symbol(TileCol + ViewLeft - 1, TileRow + ViewLeft - 1, ds6A58^[Wall, Tile], 1, 1);
      Inc(Tile);
    end;
end;
{ ovl29:031F: retf 4: 4 bytes of parameters; 2 bytes of locals }
{ ovl29:031F. True when both X and Y are in 0..$F (a map cell inside the 16x16 block). Signed
  ShortInt parameters; the four compares are in the order X <= $F, X >= 0, Y <= $F, Y >= 0. Called
  by DoorKindAt, WallIdAt, EventByteAt and ovl29_e5. }
function CellInRange(Col, Row: ShortInt): Boolean;
begin
  if (Col > $F) or (Col < 0) or (Row > $F) or (Row < 0) then
    CellInRange := False
  else
    CellInRange := True;
end;
{ ovl29:0350. The passage kind of the side Dir of map cell (Col, Row): DoorOpen (1) when that side
  has no wall (WallIdAt 0), else the door bit pair of the door plane GeoCells^.Cells (bits 0-1
  north, 2-3 east, 4-5 south, 6-7 west). The ovl14 movement code takes 0 as a solid wall, 1 as
  open and 2 or 3 as two kinds of locked door (DoWildernessMenu offers Bash, Pick and Knock).
  A cell outside the 16x16 map answers 0 while ds84DC is 0 or $A; otherwise the coordinates wrap
  to the opposite edge (Col > 15 becomes 0, Col < 0 becomes 15, the same for Row). }
function DoorKindAt(Col, Row: ShortInt; Dir: Byte): Byte;
var
  Kind: Byte;
begin
  if not CellInRange(Col, Row) and ((ds84DC = 0) or (ds84DC = $A)) then
    DoorKindAt := 0
  else begin
    if Col > MapLast then Col := 0;
    if Col < 0 then Col := MapLast;
    if Row > MapLast then Row := 0;
    if Row < 0 then Row := MapLast;
    Kind := DoorOpen;
    if WallIdAt(Col, Row, Dir) > 0 then
      case Dir of
        DirWest: Kind := (GeoCells^.Cells[Row, Col] and $C0) shr 6;
        DirSouth: Kind := (GeoCells^.Cells[Row, Col] and $30) shr 4;
        DirEast: Kind := (GeoCells^.Cells[Row, Col] and $0C) shr 2;
        DirNorth: Kind := GeoCells^.Cells[Row, Col] and $03;
      end;
    DoorKindAt := Kind;
  end;
end;
{ ovl29:047B. The wall id (0..15, 0 = no wall) on the side Dir of map cell (Col, Row): the high
  nibble of WallsNE for north, its low nibble for east, the high nibble of WallsSW for south and
  its low nibble for west (whitepaper 4.2.1). Off-map cells answer 0 while ds84DC is 0 or $A and
  wrap otherwise, as in DoorKindAt. QUIRK ovl29:047B: a Dir other than 0, 2, 4, 6 leaves the
  result unassigned. }
function WallIdAt(Col, Row: ShortInt; Dir: Byte): Byte;
begin
  if not CellInRange(Col, Row) and ((ds84DC = 0) or (ds84DC = $A)) then
    WallIdAt := 0
  else begin
    if Col > MapLast then Col := 0;
    if Col < 0 then Col := MapLast;
    if Row > MapLast then Row := 0;
    if Row < 0 then Row := MapLast;
    case Dir of
      DirNorth: WallIdAt := (GeoCells^.WallsNE[Row, Col] and $F0) shr 4;
      DirEast: WallIdAt := GeoCells^.WallsNE[Row, Col] and $0F;
      DirSouth: WallIdAt := (GeoCells^.WallsSW[Row, Col] and $F0) shr 4;
      DirWest: WallIdAt := GeoCells^.WallsSW[Row, Col] and $0F;
    end;
  end;
end;
{ ovl29:057A. The event byte of map cell (Col, Row) from the event plane GeoCells^.Events (bit 7 =
  interior cell, whitepaper 4.2.1); ShowAreaView asks for the party cell and tests bit 7, MoveParty
  keeps it in ds6AB1. Off-map cells answer 0 while ds84DC is 0 or $A and wrap otherwise, as in
  DoorKindAt. }
function EventByteAt(Col, Row: ShortInt): Byte;
begin
  if not CellInRange(Col, Row) and ((ds84DC = 0) or (ds84DC = $A)) then
    EventByteAt := 0
  else begin
    if Col > MapLast then Col := 0;
    if Col < 0 then Col := MapLast;
    if Row > MapLast then Row := 0;
    if Row < 0 then Row := MapLast;
    EventByteAt := GeoCells^.Events[Row, Col];
  end;
end;
{ ovl29:05F3. Steps the picture display (res07_fn_1B52, the same call ovl34 uses after a
  direct blit). No parameters. Called by ovl29_fn_0143 and ovl29_e5. }
procedure StepDisplay;
begin
  res07_fn_1B52;
end;
{ ovl29:05FD: retf 6: 6 bytes of parameters; 24 bytes of locals.
  Draws the rest of the wall view: with ds6AAC at 0 it draws the four descriptors through
  DrawWallDescriptors, otherwise it calls DrawWallMap; A and B are the party cell (ds6AAD, ds6AAE)
  and C the icon set of the marker (ds6AAF). }
{@stub} procedure ovl29_e5(A, B, C: Byte); begin end;
{ ovl29:0E08: retf 4: 4 bytes of parameters; 280 bytes of locals }
{@stub} procedure LoadWallSet; begin end;
{ ovl29:10C7: retf 2: 2 bytes of parameters; 272 bytes of locals }
{@stub} procedure Load3DMap; begin end;

begin
end.

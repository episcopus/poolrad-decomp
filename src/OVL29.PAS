unit OVL29;
{ GeoLoad: the 3D area map and the wall view (whitepaper 4.2.1, 4.2.4, 5.2.2). Load3DMap loads a GEO
  block into the four 16x16 planes of GeoCells^ and LoadWallSet loads WALLDEF wallsets into the wall
  tiles WallTiles^ with their 8x8 tile banks. WallIdAt, DoorKindAt and EventByteAt read a cell's wall
  id, door kind and event byte (CellInRange and the off-map wrap shared by all three). DrawWallView
  draws the 3D view from ten wall pieces (DrawWallPiece) or, in WallMapMode, the overhead wall map
  (DrawWallMap); SetWallDescriptors and DrawWallDescriptors keep and draw the view's frame. }
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
procedure DrawWallView(Col0, Row0: ShortInt; Dir: Byte);
procedure LoadWallSet(BlockId, First: Byte);
procedure Load3DMap(BlockId: Byte);
implementation
uses POOLVARS, RES04, RES05, RES07, OVL34;
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
  { The ten wall pieces (WallPieceFirstTile..WallPieceRow): the front, left and right walls of
    the far (two cells ahead), middle and near rows of the view, and the edge of a far front wall. }
  PieceFarFront = 0;
  PieceFarLeft = 1;
  PieceFarRight = 2;
  PieceMidFront = 3;
  PieceMidLeft = 4;
  PieceMidRight = 5;
  PieceNearFront = 6;
  PieceNearLeft = 7;
  PieceNearRight = 8;
  PieceFarEdge = 9;
  ViewDepth = 2;         { the view reaches two cells ahead of the party }
  { DrawWallMap: a map cell's symbol is WallSymbols plus one bit per side that has a wall. }
  WallBitNorth = 1;
  WallBitEast = 2;
  WallBitSouth = 4;
  WallBitWest = 8;
  { DrawWallView: how many tile columns a wall piece moves per cell to the side, per row. }
  FarCellStep = 2;       { the far row (two cells ahead) }
  MidCellStep = 3;       { the middle row (one cell ahead) }
  NearCellStep = 7;      { the party's row }
  { Put8x8Symbol's last two arguments: Direct 1 draws through res07_fn_08D4 into the 3D view;
    Attr goes on to res07_fn_08D4 (its meaning is not known yet): 0 for the overhead map's
    symbols, 1 for the wall tiles. }
  DrawDirect = 1;
  MapSymbolAttr = 0;
  WallTileAttr = 1;
  GeoBlockSize = $402;   { a GEO block: a size word and four 256-byte planes (whitepaper 4.2.1) }
  GeoPlaneSize = $100;   { one 16x16 plane of a GEO block }
  WallSetSize = $30C;    { one WALLDEF wallset: five walls of 156 tiles (whitepaper 4.2.4) }
  LastWallSlot = 3;      { the wallset slots of the wall tiles are 1..3 }
  WallsPerSet = 5;
  LastWallTile = $9B;    { the tiles of one wall are 0..155 }

{ ovl29:0000. Draws the overhead wall map in the view instead of the 3D walls (DrawWallView calls it
  while WallMapMode is nonzero): an 11x11 window of the 16x16 area map, placed so that the party cell
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
      if WallIdAt(MapCol, MapRow, DirNorth) > 0 then Inc(Symbol, WallBitNorth);
      if WallIdAt(MapCol, MapRow, DirEast) > 0 then Inc(Symbol, WallBitEast);
      if WallIdAt(MapCol, MapRow, DirSouth) > 0 then Inc(Symbol, WallBitSouth);
      if WallIdAt(MapCol, MapRow, DirWest) > 0 then Inc(Symbol, WallBitWest);
      Put8x8Symbol(ViewCol + ViewLeft - 1, ViewRow + ViewLeft - 1, Symbol, DrawDirect, MapSymbolAttr);
    end;
  end;
  Put8x8Symbol(PartyCol + ViewLeft - 1, PartyRow + ViewLeft - 1, Dir shr 1 + PartyArrow, DrawDirect, MapSymbolAttr);
  StepDisplay;
end;
{ ovl29:0155. Stores the four wall view descriptors Wall1..Wall4 into ds6A60..ds6A63 (descriptor 1..4;
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
  structure, G=DrawBuf). Called by DrawWallView. }
procedure DrawWallDescriptors;
begin
  res07_fn_2632(2, $10, $B, $2B, ds6A60, @ds260A, DrawBuf);
  res07_fn_2632(2, $3B, $B, 1, ds6A61, @ds260A, DrawBuf);
  res07_fn_2632(2, $3C, $B, 2, ds6A62, @ds260A, DrawBuf);
  res07_fn_2632(2, $3E, $B, $2A, ds6A63, @ds260A, DrawBuf);
end;
{ ovl29:0211. Draws piece Piece (0..9) of wall Wall (a wall id 1..15) in the 3D view: the piece's
  Width x Height tiles (WallPieceWidth, WallPieceHeight), taken in order from the wall's tile list WallTiles^[Wall]
  starting at WallPieceFirstTile[Piece], go row by row to the view cells from (Col, Row) on. Cells outside the
  11x11 view (0..ViewLast) and tile number 0 are skipped; each drawn tile is an 8x8 symbol at
  screen column Col + ViewLeft - 1 (Put8x8Symbol with Direct 1, the 3D view path). Called by
  DrawWallView with the piece positions WallPieceCol/WallPieceRow, shifted per distance and side. }
procedure DrawWallPiece(Col, Row: ShortInt; Wall, Piece: Byte);
var
  LastCol: Integer;
  LastRow: Integer;
  TileCol: Integer;
  TileRow: Integer;
  Tile: Byte;
begin
  Tile := WallPieceFirstTile[Piece];
  LastCol := WallPieceWidth[Piece] + Col - 1;
  LastRow := WallPieceHeight[Piece] + Row - 1;
  for TileRow := Row to LastRow do
    for TileCol := Col to LastCol do
    begin
      if (TileRow >= 0) and (TileRow <= ViewLast) and (TileCol >= 0) and (TileCol <= ViewLast) then
        if WallTiles^[Wall, Tile] > 0 then
          Put8x8Symbol(TileCol + ViewLeft - 1, TileRow + ViewLeft - 1, WallTiles^[Wall, Tile], DrawDirect, WallTileAttr);
      Inc(Tile);
    end;
end;
{ ovl29:031F. True when both Col and Row are in 0..$F (a map cell inside the 16x16 block). Signed
  ShortInt parameters; the four compares are in the order Col <= $F, Col >= 0, Row <= $F, Row >= 0. Called
  by DoorKindAt, WallIdAt, EventByteAt and DrawWallView. }
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
{ ovl29:05F3. Steps the picture display (FlushPictureChanges, the same call ovl34 uses after a
  direct blit). No parameters. Called by DrawWallMap and DrawWallView. }
procedure StepDisplay;
begin
  FlushPictureChanges;
end;
{ ovl29:05FD. Draws the 3D view for the party at map cell (Col0, Row0) facing Dir (0, 2, 4, 6):
  while WallMapMode is set it draws the overhead wall map (DrawWallMap) instead. Otherwise it draws
  the view's frame (DrawWallDescriptors), then the walls from the farthest row of cells (ViewDepth
  ahead) to the party's own row, so nearer walls cover farther ones, and shows the result
  (StepDisplay). Each wall goes through DrawWallPiece at its piece position WallPieceCol/Row[n]
  moved by Shift tiles per cell to the side: far row, up to four cells each side, front walls
  (piece 0, FarCellStep tiles per cell) and the edge piece 9 where a front wall ends, then the side walls of
  the nearest three cells each side (pieces 1, 2); middle row, three cells from two to the left and
  from two to the right, front (3) and side walls (4, 5), MidCellStep tiles per cell; near row, two cells
  each side, front (6) and side walls (7, 8), NearCellStep tiles per cell. Wall ids come from WallIdAt with
  the facing direction for front walls and the left (Dir + 6) or right (Dir + 2) direction for
  side walls; the step tables ds2736/ds273F move one cell. Called by ShowAreaView and the
  movement loop (A key). QUIRK ovl29:05FD: two locals (Unused1, Unused2) are never used. }
procedure DrawWallView(Col0, Row0: ShortInt; Dir: Byte);
var
  DirLeft: Byte;
  DirRight: Byte;
  DirBack: Byte;
  BaseCol: Integer;
  BaseRow: Integer;
  StepCol: Integer;
  StepRow: Integer;
  Col: Integer;
  Row: Integer;
  Count: Byte;
  Shift: Integer;
  Depth: Byte;
  FrontWall: Byte;
  SideWall: Byte;
  Unused1: Byte;
  EdgeWall: Byte;
  Unused2: Byte;
begin
  if WallMapMode <> 0 then
    DrawWallMap(Col0, Row0, Dir)
  else
  begin
    DrawWallDescriptors;
    DirLeft := (Dir + 6) mod 8;
    DirBack := (Dir + 4) mod 8;
    DirRight := (Dir + 2) mod 8;
    BaseCol := Col0;
    BaseRow := Row0;
    StepCol := ds2736[Dir];
    StepRow := ds273F[Dir];
    Depth := ViewDepth;
    Inc(BaseCol, Depth * StepCol);
    Inc(BaseRow, Depth * StepRow);
    repeat
      case Depth of
        2:  { the far row }
        begin
          Col := BaseCol;
          Row := BaseRow;
          Count := 0;
          Shift := 0;
          EdgeWall := 0;
          while Count < 4 do
          begin
            FrontWall := WallIdAt(Col, Row, Dir);
            if not CellInRange(Col, Row) then
              if WallIdAt(Col, Row, DirRight) = 0 then
                EdgeWall := 0;
            if FrontWall <> 0 then
            begin
              if EdgeWall > 0 then
                DrawWallPiece(WallPieceCol[PieceFarEdge] + Shift + 1, WallPieceRow[PieceFarEdge], EdgeWall, PieceFarEdge);
              EdgeWall := FrontWall;
              DrawWallPiece(WallPieceCol[PieceFarFront] + Shift, WallPieceRow[PieceFarFront], FrontWall, PieceFarFront);
            end
            else
            begin
              if EdgeWall > 0 then
                if WallIdAt(Col - ds2736[DirLeft], Row - ds273F[DirLeft], DirLeft) <> 0 then
                  DrawWallPiece(WallPieceCol[PieceFarEdge] + Shift + 1, WallPieceRow[PieceFarEdge], EdgeWall, PieceFarEdge);
              EdgeWall := 0;
            end;
            Inc(Count);
            Dec(Shift, FarCellStep);
            Col := Col + ds2736[DirLeft];
            Row := Row + ds273F[DirLeft];
          end;
          Col := BaseCol;
          Row := BaseRow;
          Count := 0;
          Shift := 0;
          EdgeWall := 0;
          while Count < 4 do
          begin
            FrontWall := WallIdAt(Col, Row, Dir);
            if not CellInRange(Col, Row) then
              if WallIdAt(Col, Row, DirLeft) = 0 then
                EdgeWall := 0;
            if FrontWall <> 0 then
            begin
              if EdgeWall > 0 then
                DrawWallPiece(WallPieceCol[PieceFarEdge] + Shift - 1, WallPieceRow[PieceFarEdge], EdgeWall, PieceFarEdge);
              EdgeWall := FrontWall;
              DrawWallPiece(WallPieceCol[PieceFarFront] + Shift, WallPieceRow[PieceFarFront], FrontWall, PieceFarFront);
            end
            else
            begin
              if EdgeWall > 0 then
                if WallIdAt(Col - ds2736[DirRight], Row - ds273F[DirRight], DirRight) <> 0 then
                  DrawWallPiece(WallPieceCol[PieceFarEdge] + Shift - 1, WallPieceRow[PieceFarEdge], EdgeWall, PieceFarEdge);
              EdgeWall := 0;
            end;
            Inc(Count);
            Inc(Shift, FarCellStep);
            Col := Col + ds2736[DirRight];
            Row := Row + ds273F[DirRight];
          end;
          Col := BaseCol;
          Row := BaseRow;
          Count := 0;
          Shift := 0;
          while Count < 3 do
          begin
            SideWall := WallIdAt(Col, Row, DirLeft);
            if SideWall <> 0 then
              if Count = 0 then
                DrawWallPiece(WallPieceCol[PieceFarLeft] + Shift, WallPieceRow[PieceFarLeft], SideWall, PieceFarLeft)
              else
                DrawWallPiece(WallPieceCol[PieceFarLeft] + Shift - 1, WallPieceRow[PieceFarLeft], SideWall, PieceFarLeft);
            Inc(Count);
            Dec(Shift, FarCellStep);
            Col := Col + ds2736[DirLeft];
            Row := Row + ds273F[DirLeft];
          end;
          Col := BaseCol;
          Row := BaseRow;
          Count := 0;
          Shift := 0;
          while Count < 3 do
          begin
            SideWall := WallIdAt(Col, Row, DirRight);
            if SideWall <> 0 then
              if Count = 0 then
                DrawWallPiece(WallPieceCol[PieceFarRight] + Shift, WallPieceRow[PieceFarRight], SideWall, PieceFarRight)
              else
                DrawWallPiece(WallPieceCol[PieceFarRight] + Shift + 1, WallPieceRow[PieceFarRight], SideWall, PieceFarRight);
            Inc(Count);
            Inc(Shift, FarCellStep);
            Col := Col + ds2736[DirRight];
            Row := Row + ds273F[DirRight];
          end;
        end;
        1:  { the middle row }
        begin
          Col := BaseCol + ds2736[DirLeft];
          Col := Col + ds2736[DirLeft];
          Row := BaseRow + ds273F[DirLeft];
          Row := Row + ds273F[DirLeft];
          Count := 0;
          Shift := -2 * MidCellStep;
          while Count < 3 do
          begin
            FrontWall := WallIdAt(Col, Row, Dir);
            if FrontWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceMidFront] + Shift, WallPieceRow[PieceMidFront], FrontWall, PieceMidFront);
            SideWall := WallIdAt(Col, Row, DirLeft);
            if SideWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceMidLeft] + Shift, WallPieceRow[PieceMidLeft], SideWall, PieceMidLeft);
            Inc(Count);
            Inc(Shift, MidCellStep);
            Col := Col + ds2736[DirRight];
            Row := Row + ds273F[DirRight];
          end;
          Col := BaseCol + ds2736[DirRight];
          Col := Col + ds2736[DirRight];
          Row := BaseRow + ds273F[DirRight];
          Row := Row + ds273F[DirRight];
          Count := 0;
          Shift := 2 * MidCellStep;
          while Count < 3 do
          begin
            FrontWall := WallIdAt(Col, Row, Dir);
            if FrontWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceMidFront] + Shift, WallPieceRow[PieceMidFront], FrontWall, PieceMidFront);
            SideWall := WallIdAt(Col, Row, DirRight);
            if SideWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceMidRight] + Shift, WallPieceRow[PieceMidRight], SideWall, PieceMidRight);
            Inc(Count);
            Dec(Shift, MidCellStep);
            Col := Col + ds2736[DirLeft];
            Row := Row + ds273F[DirLeft];
          end;
        end;
        0:  { the party's row }
        begin
          Col := BaseCol + ds2736[DirLeft];
          Row := BaseRow + ds273F[DirLeft];
          Count := 0;
          Shift := -NearCellStep;
          while Count < 2 do
          begin
            FrontWall := WallIdAt(Col, Row, Dir);
            if FrontWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceNearFront] + Shift, WallPieceRow[PieceNearFront], FrontWall, PieceNearFront);
            SideWall := WallIdAt(Col, Row, DirLeft);
            if SideWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceNearLeft] + Shift, WallPieceRow[PieceNearLeft], SideWall, PieceNearLeft);
            Inc(Count);
            Inc(Shift, NearCellStep);
            Col := Col + ds2736[DirRight];
            Row := Row + ds273F[DirRight];
          end;
          Col := BaseCol + ds2736[DirRight];
          Row := BaseRow + ds273F[DirRight];
          Count := 0;
          Shift := NearCellStep;
          while Count < 2 do
          begin
            FrontWall := WallIdAt(Col, Row, Dir);
            if FrontWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceNearFront] + Shift, WallPieceRow[PieceNearFront], FrontWall, PieceNearFront);
            SideWall := WallIdAt(Col, Row, DirRight);
            if SideWall <> 0 then
              DrawWallPiece(WallPieceCol[PieceNearRight] + Shift, WallPieceRow[PieceNearRight], SideWall, PieceNearRight);
            Inc(Count);
            Dec(Shift, NearCellStep);
            Col := Col + ds2736[DirLeft];
            Row := Row + ds273F[DirLeft];
          end;
        end;
      end;
      BaseCol := BaseCol + ds2736[DirBack];
      BaseRow := BaseRow + ds273F[DirBack];
      Dec(Depth);
    until Depth = $FF;
    StepDisplay;
  end;
end;
{ ovl29:0E08. Loads the WALLDEF<TileSet>.DAX block BlockId (one to three wallsets of $30C
  bytes, whitepaper 4.2.4) into the wall tiles from wallset slot First (1..3) on; any other First
  does nothing. A missing block or one that does not fit in the slots left is fatal (Unable to
  load wallset in LoadWallSet. on Output, a key, QuitGame). For each wallset slot filled it marks
  the slot's ds6AAEWords pair $FFFF, adds Delta (SymbolBase[First] - SymbolBase[1], the slot's
  8x8 bank base) to every tile number at or above ds272C, and loads the slot's 8x8 tiles with
  Load8x8Bank: block BlockId for a single wallset, BlockId * 10 + n for the n-th of several
  (block 0 counting as 10 there). Finally ds6AAEWords[First] records (BlockId, First).
  The size check does not ask for a multiple of $30C: a partial last wallset is copied whole
  (reading past the block) and counted, and only the slot test of ovl29:0F5B (1..3) keeps its
  tiles in range. QUIRK ovl29:101A: BlockId 0 becomes 10 inside the loop and back to 0 after it. }
procedure LoadWallSet(BlockId, First: Byte);
var
  Size: Word;
  Block: Pointer;
  Offset: Word;
  Delta: Word;
  Wall: Byte;
  WallSet: Word;
  Tile: Word;
  Count: Byte;
  Num: string[1];
  Key: Char;
begin
  if (First < 1) or (First > LastWallSlot) then Exit;
  Str(TileSet, Num);
  LoadDaxBlock('WALLDEF' + Num, '.dax', BlockId, Size, Block);
  if (Size = 0) or (Size div WallSetSize + First > LastWallSlot + 1) then
  begin
    RestoreVideoMode;
    WriteLn(Output, 'Unable to load wallset in LoadWallSet.');
    Key := ReadGameKey;
    RestoreVideoMode;
    QuitGame;
  end;
  Delta := SymbolBase[First] - SymbolBase[1];
  Offset := 0;
  WallSet := 1;
  repeat
    Move(TByteArray(Block^)[Offset], WallSets^[First + WallSet - 1], WallSetSize);
    Inc(Offset, WallSetSize);
    Inc(WallSet);
  until Offset >= Size;
  FreeMem(Block, Size);
  Count := WallSet - 1;
  for WallSet := 1 to Count do
    if First + WallSet - 1 in [1..LastWallSlot] then
    begin
      ds6AAEWords[First + WallSet - 1].A := $FFFF;
      ds6AAEWords[First + WallSet - 1].B := $FFFF;
      for Wall := 1 to WallsPerSet do
        for Tile := 0 to LastWallTile do
          if WallSets^[First + WallSet - 1, Wall, Tile] >= ds272C then
            Inc(WallSets^[First + WallSet - 1, Wall, Tile], Delta);
      if Count > 1 then
      begin
        if BlockId = 0 then BlockId := 10;
        Load8x8Bank(BlockId * 10 + WallSet, First + WallSet - 1);
      end
      else
        Load8x8Bank(BlockId, First + WallSet - 1);
    end;
  if BlockId = 10 then BlockId := 0;
  ds6AAEWords[First].A := BlockId;
  ds6AAEWords[First].B := First;
end;
{ ovl29:10C7. Loads the 3D area map: block BlockId of GEO<TileSet>.DAX, which must be exactly
  $402 bytes (else Unable to load geo in Load3DMap. on Output, a key, QuitGame). It skips the
  size word, copies the four 256-byte planes into GeoCells^ (WallsNE, WallsSW, Events, Cells;
  whitepaper 4.2.1), frees the block and records BlockId in GameVars^[VarGeoBlock]. }
procedure Load3DMap(BlockId: Byte);
var
  Size: Word;
  Block: Pointer;
  Offset: Word;
  Num: string[1];
  Key: Char;
begin
  Str(TileSet, Num);
  LoadDaxBlock('GEO' + Num, '.dax', BlockId, Size, Block);
  if (Size = 0) or (Size <> GeoBlockSize) then
  begin
    RestoreVideoMode;
    WriteLn(Output, 'Unable to load geo in Load3DMap.');
    Key := ReadGameKey;
    RestoreVideoMode;
    QuitGame;
  end;
  Offset := 2;
  Move(TByteArray(Block^)[Offset], GeoCells^.WallsNE, GeoPlaneSize);
  Inc(Offset, GeoPlaneSize);
  Move(TByteArray(Block^)[Offset], GeoCells^.WallsSW, GeoPlaneSize);
  Inc(Offset, GeoPlaneSize);
  Move(TByteArray(Block^)[Offset], GeoCells^.Events, GeoPlaneSize);
  Inc(Offset, GeoPlaneSize);
  Move(TByteArray(Block^)[Offset], GeoCells^.Cells, GeoPlaneSize);
  FreeMem(Block, Size);
  GameVars^[VarGeoBlock] := BlockId;
end;

{ Initialisation (ovl29:1206): empty (55 89 E5 5D CB). }
begin
end.

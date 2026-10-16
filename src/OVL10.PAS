unit OVL10;
{ The start of a battle (whitepaper 5.5.2): StartBattle (entry 1, called by RunCombat) resets the
  combat state, CreateCombatMap allocates the 50x25 cell combat map CombatMap^ and builds it (a
  dungeon map from the walls around the party, BuildDungeonMap, or a wilderness map from the area map
  block the party stands on, BuildWildernessMap with its river and feature scatterers), then
  PrepareCombatants gives every character of the party list a combat record and PlaceAllCombatants
  puts each one on the map: every side has an 11x6 placement grid in four groups (PlacementCells),
  laid on the map from an origin in area map steps, and FindStartCell walks rings of that grid
  until TryPlaceAt finds a free passable cell. }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
procedure ScatterRareTiles;
function PassageKind(Col, Row: ShortInt; Dir: Byte): Byte;
procedure BuildDungeonMap;
function BlockTerrainFlags: Byte;
procedure PlaceRiver;
procedure PlaceTallFeatures;
procedure ScatterTerrainFeatures;
procedure BuildWildernessMap;
procedure CreateCombatMap;
procedure PrepareCombatants;
function IsBeyondGrid(Col, Row: ShortInt): Boolean;
function TryPlaceAt(Index: Byte; Col, Row, OriginCol, OriginRow: ShortInt; Group: Byte): Boolean;
function FindStartCell(Index: Byte): Boolean;
procedure PlaceAllCombatants;
procedure StartBattle;
implementation
uses POOLVARS, RES04, RES06, RES07, RES12, OVL13, OVL16, OVL24, OVL25, OVL28, OVL29, OVL31, OVL32;

const
  MapLastCol = 49;              { the combat map is 50 cells wide }
  MapLastRow = 24;              { and 25 cells high }
  GroundTile = $17;             { the tile a wilderness map starts filled with (ovl10:11C8) }
  GroundPicture = $16;          { CombatTiles[GroundTile].Picture: the scatterers only change such cells }
  { The tile ids the feature tiles are counted from (ovl10:0E39); the same id is the tile a body
    leaves on the map (BodyTile in ovl31). }
  FeatureBase = $1F;
  { BlockTerrainFlags bits, named for what the builders of this unit do with them. }
  FlagPlain = 1;                { tested by no routine of this unit }
  FlagMany2ATiles = 2;          { ScatterTerrainFeatures: tiles $2A..$2D on 45 of 255 rolls }
  FlagSome2ATiles = 4;          { ScatterTerrainFeatures: tiles $2A..$2D on 25 of 255 rolls }
  FlagMostTall = 8;             { PlaceTallFeatures: the highest chance, 7 in 100 }
  FlagRiverOften = $10;         { PlaceRiver: a river on 75 in 100 }
  FlagRiverSometimes = $20;     { PlaceRiver: a river on 35 in 100 }
  FlagTallKinds4To6 = $40;      { PlaceTallFeatures: only kinds 4..6; tiles $39..$3C on 30 of 255 rolls }
  { No tall features, tiles $3D..$41 on 15 of 255 rolls; BlockTerrainFlags turns it into
    FlagPlain while game word 435 is $FF. }
  Flag3DTiles = $80;
  { The river tiles (PlaceRiver): a river row is RiverWest beside RiverEast, a bridge row
    BridgeWest beside BridgeEast. }
  RiverWest = $32;
  RiverEast = $33;
  BridgeWest = $34;
  BridgeEast = $35;
  GridLastCol = 10;             { a placement grid is 11 cells wide }
  GridLastRow = 5;              { and 6 cells high }
  CombatantClearLoopLast = $FF; { QUIRK ovl10:0872: clear loop reaches 255, though the party has 72 combatants }
  LaterRingLastCellCount = 11;  { later placement rings contain 12 cells (ovl10:0802) }
  FacingOffsetRight = 1;       { placement-search offsets relative to the current facing }
  FacingOffsetBack = 2;
  FacingOffsetLeft = 3;
  MapEdge = 15;                 { the 16x16 area map's last column and row }
  { What PassageKind and WallSideKind answer for a side of an area map cell. }
  SideOpen = 0;
  SideWall = 1;
  SideDoor = 3;
  CostBlocked = $FF;            { a CombatTiles cost no combatant may stand on }
  AreaViewDungeon = 1;          { AreaViewKind of the 3D wall view: the battle is fought in a dungeon }
  MoraleMask = $7F;             { low seven bits of B84 carry the computer's morale value (ovl09:10D7) }
  MaxComputerMorale = $66;      { CheckMorale zeroes thresholds above this (ovl09:0431) }
  HookBattleStart = 8;          { the RunAffectHooks kind StartBattle runs for every character }
  { Words of GameVars2^ (the second game word block) this unit reads or writes. }
  Var2BattleWord = 819;         { cleared when a battle starts; meaning unknown }

{ ovl10:0000. Scatters rare tiles over the plain ground (GroundPicture cells) of the combat map:
  on a d100 roll of 98 tile $1A, of 99 tile $1B, and on 100, unless WallViewMode is $A, one time in 100
  tile $1C (d10 of 1..6) or $1D (7..10). Called last by both map builders. }
procedure ScatterRareTiles;
var
  Col, Row: ShortInt;
  Roll: Byte;
begin
  for Col := 0 to MapLastCol do
    for Row := 0 to MapLastRow do
      if CombatTiles[CombatMap^.Cells[Row, Col]].Picture = GroundPicture then
      begin
        Roll := RollDice(1, 100);
        case Roll of
          1..97: ;
          98: CombatMap^.Cells[Row, Col] := $1A;
          99: CombatMap^.Cells[Row, Col] := $1B;
          100:
            if WallViewMode <> $A then
              if RollDice(1, 100) = 1 then
                case RollDice(1, 10) of
                  1..6: CombatMap^.Cells[Row, Col] := $1C;
                  7..10: CombatMap^.Cells[Row, Col] := $1D;
                end;
        end;
      end;
end;
{ ovl10:01AD. The passage between area map cell (Col, Row) and its neighbour in direction Dir
  (0 north, 2 east, 4 south, 6 west, steps DirStepX/DirStepY): WallSideKind of this side of the cell
  OR WallSideKind of the opposite side of the neighbour: 0 open, 1 a wall, 3 a door. Called by
  BuildDungeonMap for the three drawn sides of every cell and by FindStartCell to find open
  directions for the placement groups. }
function PassageKind(Col, Row: ShortInt; Dir: Byte): Byte;
var
  Here, There: Byte;
  OppositeDir: Byte;

  { ovl10:012B. Nested in PassageKind: the kind of side Dir of area map cell (Col, Row): 1 a solid
    wall (DoorKindAt 0), 0 no wall (WallIdAt 0), 3 a door. Off the 16x16 map: 0 for the west and
    east sides (Dir 2 or 6) on the party's row (PartyMapRow), else 1, so a corridor the party stands in
    stays open beyond the map's edge. }
  function WallSideKind(Col, Row: ShortInt; Dir: Byte): Byte;
  begin
    if (Col >= 0) and (Col <= MapEdge) and (Row >= 0) and (Row <= MapEdge) then
    begin
      if DoorKindAt(Col, Row, Dir) = 0 then
        WallSideKind := SideWall
      else if WallIdAt(Col, Row, Dir) = 0 then
        WallSideKind := SideOpen
      else
        WallSideKind := SideDoor;
    end
    else if (Row = PartyMapRow) and ((Dir = DirEast) or (Dir = DirWest)) then
      WallSideKind := SideOpen
    else
      WallSideKind := SideWall;
  end;

begin
  OppositeDir := (Dir + 4) mod 8;
  Here := WallSideKind(Col, Row, Dir);
  There := WallSideKind(Col + DirStepX[Dir], Row + DirStepY[Dir], OppositeDir);
  PassageKind := Here or There;
end;
{ ovl10:0810. Builds the combat map of a dungeon battle (CreateCombatMap calls it when
  AreaViewKind is AreaViewDungeon): every area map cell within 6 columns and 2 rows of the party
  (PartyMapColumn, PartyMapRow) becomes a skewed block of the combat map, 6 columns right and 5 rows down per
  area column and row from the party's block at (21, 10), drawn from its west, north and east
  passages (PassageKind) by the four nested drawers below, then ScatterRareTiles. Globals: reads
  PartyMapColumn, PartyMapRow and the area map (through PassageKind), writes CombatMap^.Cells. }
procedure BuildDungeonMap;
var
  CellCol, CellRow: ShortInt;   { area cell offset from the party: -6..6, -2..2 }
  MapX, MapY: ShortInt;         { the area map cell being drawn }
  Unused: array[0..1] of Byte;  { frame slots the compiler keeps (no use in 0221..08A4) }
  North, West, East: Byte;      { PassageKind of the three drawn sides of the cell }
  Unused2: Byte;

  { ovl10:0221. Stores Picture + 1 (a CombatTiles index) at the combat map cell of sub-cell
    (SubCol, SubRow) of the area cell being drawn, when that cell is on the 50x25 map. The block
    skews 6 columns right per area column and a further 5 right per area row. }
  procedure SetDungeonCell(SubCol, SubRow, Picture: Byte);
  var
    Col, Row: ShortInt;
  begin
    Col := CellCol * 6 + CellRow * 5 + $15 + SubCol;
    Row := CellRow * 5 + $A + SubRow;
    if (Col >= 0) and (Col <= MapLastCol) and (Row >= 0) and (Row <= MapLastRow) then
      CombatMap^.Cells[Row, Col] := Picture + 1;
  end;

  { ovl10:02BA. The floor of the area cell (sub-rows 2..4 of sub-columns 0..5, GroundPicture) and
    its west side: a wall is a diagonal of pictures 4, 3, $D down sub-rows 2..4, a door two
    pictures at (1, 2) and (5, 4). }
  procedure DrawFloorAndWest;
  var
    SubCol, SubRow: Byte;
  begin
    for SubRow := 2 to 4 do
      for SubCol := 0 to 5 do
        SetDungeonCell(SubCol, SubRow, GroundPicture);
    if West = SideWall then
      for SubRow := 2 to 4 do
      begin
        SetDungeonCell(SubRow - 1, SubRow, 4);
        SetDungeonCell(SubRow, SubRow, 3);
        SetDungeonCell(SubRow + 1, SubRow, $D);
      end
    else if West = SideDoor then
    begin
      SetDungeonCell(1, 2, 8);
      SetDungeonCell(5, 4, 0);
    end;
  end;

  { ovl10:0377. The north side of the area cell: sub-columns 3..4 of sub-rows 0..1 are a wall
    (pictures 5 over $A) when North is SideWall, else floor. }
  procedure DrawNorthSide;
  var
    Unused: array[0..1] of Byte;  { a frame slot the compiler keeps (sub sp, 2; no use) }
  begin
    if North = SideWall then
    begin
      SetDungeonCell(3, 0, 5);
      SetDungeonCell(4, 0, 5);
      SetDungeonCell(3, 1, $A);
      SetDungeonCell(4, 1, $A);
    end
    else
    begin
      SetDungeonCell(3, 0, GroundPicture);
      SetDungeonCell(4, 0, GroundPicture);
      SetDungeonCell(3, 1, GroundPicture);
      SetDungeonCell(4, 1, GroundPicture);
    end;
  end;

  { Picture table for the corner drawers, raw CombatTiles picture ids with artwork meaning not viewed
    (Purpose unknown): NorthWest top-left $0/$D/$F/5/$12/2, top-right $0/$11/5, bottom-left
    $0/$10/$A/$14/7/1/3, bottom-right $0/$17/$A/$D/$15/6. NorthEast top-left 4/$0/$F/5,
    top-right $0/$18/1/$B/3/9/5/$11/$13, bottom-left $0/$10/$A, bottom-right
    $0/4/8/$C/$E/$17/$A (ovl10:040F, 0615). The case tables below map side conditions to each position. }
  { ovl10:040F. The north-west corner of the area cell: the four pictures of sub-columns 1..2,
    sub-rows 0..1, chosen from North, West and whether the corner is open on the far side (the
    west passage of the cell to the north and the north passage of the cell to the west both
    open: OpenCorner). The four cases of K pick the top-left, top-right, bottom-left and
    bottom-right picture in turn. }
  procedure DrawNorthWestCorner;
  var
    K: Byte;
    TopLeft, BottomLeft, TopRight, BottomRight: Byte;
    OpenCorner: Byte;
  begin
    if (PassageKind(MapX, MapY - 1, DirWest) = SideOpen)
      and (PassageKind(MapX - 1, MapY, DirNorth) = SideOpen) then
      OpenCorner := 1
    else
      OpenCorner := 0;
    for K := 1 to 4 do
      case K of
        1:
          case North of
            SideOpen:
              case West of
                SideOpen: TopLeft := GroundPicture;
                SideDoor: TopLeft := $D;
                SideWall:
                  if OpenCorner <> 0 then
                    TopLeft := 0
                  else
                    TopLeft := $D;
              end;
            SideDoor, SideWall:
              if West = SideOpen then
                if OpenCorner <> 0 then
                  TopLeft := $F
                else
                  TopLeft := 5
              else if OpenCorner <> 0 then
                TopLeft := $12
              else
                TopLeft := 2;
          end;
        2:
          case North of
            SideOpen: TopRight := GroundPicture;
            SideDoor: TopRight := $11;
            SideWall: TopRight := 5;
          end;
        3:
          case West of
            SideOpen:
              if North = SideOpen then
                BottomLeft := GroundPicture
              else if OpenCorner <> 0 then
                BottomLeft := $10
              else
                BottomLeft := $A;
            SideDoor:
              if OpenCorner <> 0 then
                BottomLeft := $14
              else
                BottomLeft := 7;
            SideWall:
              if OpenCorner <> 0 then
                BottomLeft := 1
              else
                BottomLeft := 3;
          end;
        4:
          case West of
            SideOpen, SideDoor:
              case North of
                SideOpen: BottomRight := GroundPicture;
                SideDoor: BottomRight := $17;
                SideWall: BottomRight := $A;
              end;
            SideWall:
              case North of
                SideOpen: BottomRight := $D;
                SideDoor: BottomRight := $15;
                SideWall: BottomRight := 6;
              end;
          end;
      end;
    SetDungeonCell(1, 0, TopLeft);
    SetDungeonCell(2, 0, TopRight);
    SetDungeonCell(1, 1, BottomLeft);
    SetDungeonCell(2, 1, BottomRight);
  end;

  { ovl10:0615. The north-east corner of the area cell: the four pictures of sub-columns 5..6,
    sub-rows 0..1, chosen from North, East, the east passage of the cell to the north (NorthEast),
    the north passage of the cell to the east (EastNorth) and OpenCorner (both open). The four
    cases of K pick the top-left, top-right, bottom-left and bottom-right picture in turn. }
  procedure DrawNorthEastCorner;
  var
    K: Byte;
    TopLeft, BottomLeft, TopRight, BottomRight: Byte;
    OpenCorner: Byte;
    NorthEast, EastNorth: Byte;
  begin
    NorthEast := PassageKind(MapX, MapY - 1, DirEast);
    EastNorth := PassageKind(MapX + 1, MapY, DirNorth);
    if (NorthEast = SideOpen) and (EastNorth = SideOpen) then
      OpenCorner := 1
    else
      OpenCorner := 0;
    for K := 1 to 4 do
      case K of
        1:
          case North of
            SideOpen:
              if NorthEast = SideWall then
                TopLeft := 4
              else
                TopLeft := GroundPicture;
            SideDoor: TopLeft := $F;
            SideWall: TopLeft := 5;
          end;
        2:
          if North = SideOpen then
            case NorthEast of
              SideOpen: TopRight := GroundPicture;
              SideDoor:
                if (East = SideOpen) and (EastNorth <> SideOpen) then
                  TopRight := $18
                else
                  TopRight := 1;
              SideWall:
                if (East = SideOpen) and (EastNorth <> SideOpen) then
                  TopRight := $B
                else
                  TopRight := 3;
            end
          else if East <> SideOpen then
            TopRight := 9
          else if EastNorth <> SideOpen then
            TopRight := 5
          else if OpenCorner <> 0 then
            TopRight := $11
          else
            TopRight := $13;
        3:
          case North of
            SideOpen: BottomLeft := GroundPicture;
            SideDoor: BottomLeft := $10;
            SideWall: BottomLeft := $A;
          end;
        4:
          if North = SideOpen then
          begin
            if NorthEast = SideOpen then
              BottomRight := GroundPicture
            else if East <> SideOpen then
              BottomRight := 4
            else if EastNorth = SideOpen then
              BottomRight := 8
            else
              BottomRight := $C;
          end
          else if East <> SideOpen then
            BottomRight := $E
          else if EastNorth = SideOpen then
            BottomRight := $17
          else
            BottomRight := $A;
      end;
    SetDungeonCell(5, 0, TopLeft);
    SetDungeonCell(6, 0, TopRight);
    SetDungeonCell(5, 1, BottomLeft);
    SetDungeonCell(6, 1, BottomRight);
  end;

begin
  for CellRow := -2 to 2 do
    for CellCol := -6 to 6 do
    begin
      MapX := PartyMapColumn + CellCol;
      MapY := PartyMapRow + CellRow;
      West := PassageKind(MapX, MapY, DirWest);
      North := PassageKind(MapX, MapY, DirNorth);
      East := PassageKind(MapX, MapY, DirEast);
      DrawFloorAndWest;
      DrawNorthSide;
      DrawNorthWestCorner;
      DrawNorthEastCorner;
    end;
  ScatterRareTiles;
end;

{ ovl10:08A4. Maps the wilderness block code (CombatBlock) through an ordered table of terrain flags.
  QUIRK ovl10:08AA..0B14: the first matching range wins for overlapping codes 3, 4 and 7 (value 3),
  $28, $29 and $2B (value 1), $7C (value 8), and $F5 (value $20). QUIRK ovl10:0B68: a code in no
  range leaves local Flags unassigned, so the returned byte is unset. QUIRK ovl10:0B6B: when
  Flag3DTiles is set and game word VarAreaDoors is $FF, that bit is replaced by FlagPlain. Called by
  the wilderness builders for every test. }
function BlockTerrainFlags: Byte;
var
  Flags: Byte;
begin
  case CombatBlock of
    1..2, $28..$29, $4F..$56, $5B..$5C, $2B, $F1: Flags := 1;
    $A8..$B1: Flags := $21;
    $B9, $BC..$C0: Flags := $11;
    3..4, 6..7, 8..9, $13..$15, $17..$19: Flags := 3;
    3..4, 7, $A..$12, $16, $1A..$24, $C9..$D0: Flags := 2;
    $D1..$D5: Flags := $12;
    $25, $39, $40, $9A..$9E, $A4..$A5, $B4, $F3, $EF..$F0, $FA, $FC: Flags := 4;
    $27..$2C, $99, $9F: Flags := 5;
    $2D..$2E, $33..$38, $43..$4D, $5D..$61: Flags := $44;
    $B5..$B8, $BA, $C1..$C8: Flags := $14;
    $2F..$32, $62..$65, $F2: Flags := $40;
    $26: Flags := $41;
    $B2..$B3: Flags := $60;
    $3A..$3C, $41..$42: Flags := $48;
    $3D..$3F, $79..$7C, $87..$89, $8B, $8D, $90..$93, $95, $97..$98, $A0..$A2, $A6..$A7, $D6..$D8,
      $EE: Flags := 8;
    $57..$5A, $A3, $E0: Flags := $88;
    $7D, $7C, $8A, $8C, $8E, $8F, $94, $96: Flags := 9;
    $7E..$85, $E5..$E7: Flags := $28;
    $D9..$DF: Flags := $18;
    $4E, $F5, $E8..$E9: Flags := $20;
    $6D, $F4..$F6: Flags := $80;
    $6E..$71, $73..$78: Flags := $81;
    $66..$6C, $72: Flags := $90;
    $E1..$E4, $EA..$ED: Flags := $A0;
  end;
  if (Flags and Flag3DTiles) <> 0 then
    if GameVars^[VarAreaDoors] = $FF then
    begin
      Dec(Flags, Flag3DTiles);
      Flags := Flags or FlagPlain;
    end;
  BlockTerrainFlags := Flags;
end;
{ ovl10:0BDE. Draws a river on the wilderness combat map: with FlagRiverSometimes 35 in 100,
  with FlagRiverOften 75 in 100, otherwise never. The river runs down a diagonal, one column
  right per row, as the tile pair RiverWest, RiverEast; its top column is 34 - 5d4 moved left to
  the next column with (Col + 2) mod 7 = 0. Each row gets a bridge (PlaceBridge) on a d20 of 1,
  and the row after a bridge always (the odd count), so a bridge is two rows high; a river with
  no bridge gets one on rows 7..15. }
procedure PlaceRiver;
var
  Chance: Byte;                 { in 100 }
  Bridges: Byte;                { the bridge rows placed so far }
  StartCol: ShortInt;           { the river's column on row 0 }
  Col, Row: ShortInt;
  Unused: Byte;                 { QUIRK ovl10:0BE1: a byte of the frame nothing uses }

  { ovl10:0B97. Puts the bridge tiles BridgeWest, BridgeEast on the river cells of (Row, Col)
    and counts the bridge rows. }
  procedure PlaceBridge(Row, Col: ShortInt);
  begin
    CombatMap^.Cells[Row, Col] := BridgeWest;
    CombatMap^.Cells[Row, Col + 1] := BridgeEast;
    Inc(Bridges);
  end;

begin
  Chance := 0;
  Bridges := 0;
  if (BlockTerrainFlags and FlagRiverSometimes) <> 0 then Chance := 35;
  if (BlockTerrainFlags and FlagRiverOften) <> 0 then Chance := 75;
  if RollDice(1, 100) <= Chance then
  begin
    Col := 34 - RollDice(5, 4);
    while (Col + 2) mod 7 > 0 do Dec(Col);
    StartCol := Col;
    for Row := 0 to MapLastRow do
      if Col <= MapLastCol then
      begin
        CombatMap^.Cells[Row, Col] := RiverWest;
        CombatMap^.Cells[Row, Col + 1] := RiverEast;
        if (RollDice(1, 20) = 1) or Odd(Bridges) then PlaceBridge(Row, Col);
        Inc(Col);
      end;
    if Bridges = 0 then
    begin
      Row := 12 - RollDice(1, 9) + 4;
      Col := StartCol + Row;
      PlaceBridge(Row, Col);
      PlaceBridge(Row + 1, Col + 1);
    end;
  end;
end;

{ ovl10:0D13. Puts two-cell features on the plain ground: for every ground cell whose northern
  neighbour is ground too, with Chance in 100 (1 by default and for FlagMany2ATiles, 3 for
  FlagSome2ATiles, 4 for FlagTallKinds4To6, 7 for FlagMostTall, none for Flag3DTiles; the last
  flag tested wins), a kind 1..6: a d10 of 1..8 halved and rounded up gives 1..4, 9 and 10 give
  d2 + 4; with FlagTallKinds4To6 the kind is d3 + 3 instead. The cell gets tile Kind + $23 and,
  for kinds below 5, the cell above tile Kind + $1F. }
procedure PlaceTallFeatures;
var
  Unused: Byte;                 { QUIRK ovl10:0D16: the first byte of the frame nothing uses }
  Chance: Byte;
  Kind: Byte;
  Col, Row: ShortInt;
begin
  Chance := 1;
  if (BlockTerrainFlags and FlagMany2ATiles) <> 0 then Chance := 1;
  if (BlockTerrainFlags and FlagSome2ATiles) <> 0 then Chance := 3;
  if (BlockTerrainFlags and FlagTallKinds4To6) <> 0 then Chance := 4;
  if (BlockTerrainFlags and FlagMostTall) <> 0 then Chance := 7;
  if (BlockTerrainFlags and Flag3DTiles) <> 0 then Chance := 0;
  for Col := 0 to MapLastCol do
    for Row := 1 to MapLastRow do
      if (CombatTiles[CombatMap^.Cells[Row, Col]].Picture = GroundPicture)
        and (CombatTiles[CombatMap^.Cells[Row - 1, Col]].Picture = GroundPicture)
        and (RollDice(1, 100) <= Chance) then
      begin
        Kind := RollDice(1, 10);
        if Kind > 8 then
          Kind := RollDice(1, 2) + 4
        else
          Kind := (Kind + 1) shr 1;
        if (BlockTerrainFlags and FlagTallKinds4To6) <> 0 then Kind := RollDice(1, 3) + 3;
        CombatMap^.Cells[Row, Col] := Kind + FeatureBase + 4;
        if Kind < 5 then CombatMap^.Cells[Row - 1, Col] := Kind + FeatureBase;
      end;
end;

{ ovl10:0E9E. Scatters single-cell features over the plain ground: a d255 roll per ground cell is
  compared with five cumulative chances set from BlockTerrainFlags. Up to Chance3D: a d4 of 1..3
  gives tiles $3D..$3F, a 4 the pair $40 below $41 when the cell above is ground; then tiles
  $37..$39 (Chance37), $2A..$2D (Chance2A), $39..$3C (Chance39) and $2E..$31 (Chance2E; a 4
  becomes a d3 without FlagTallKinds4To6). Note the sums add the chances in different orders;
  the totals are the same. }
procedure ScatterTerrainFeatures;
var
  Chance3D, Chance37, Chance2A, Chance2E, Chance39: Byte;
  Roll: Byte;
  Col, Row: ShortInt;
begin
  Chance3D := 0;
  Chance37 := 6;
  Chance2A := $F;
  Chance2E := $28;
  Chance39 := 0;
  if (BlockTerrainFlags and FlagMany2ATiles) <> 0 then
  begin
    Chance2A := $2D;
    Chance2E := $A;
  end;
  if (BlockTerrainFlags and FlagSome2ATiles) <> 0 then Chance2A := $19;
  if (BlockTerrainFlags and FlagTallKinds4To6) <> 0 then
  begin
    Chance2E := 5;
    Chance39 := $1E;
  end;
  if (BlockTerrainFlags and Flag3DTiles) <> 0 then
  begin
    Chance3D := $F;
    Chance2E := $19;
    Chance2A := $A;
  end;
  for Col := 0 to MapLastCol do
    for Row := 0 to MapLastRow do
      if CombatTiles[CombatMap^.Cells[Row, Col]].Picture = GroundPicture then
      begin
        Roll := RollDice(1, $FF);
        if Roll <= Chance3D then
        begin
          Roll := RollDice(1, 4);
          if (Roll = 4) and (Row > 0)
            and (CombatTiles[CombatMap^.Cells[Row - 1, Col]].Picture = GroundPicture) then
          begin
            CombatMap^.Cells[Row - 1, Col] := $41;
            CombatMap^.Cells[Row, Col] := $40;
          end;
          if Roll < 4 then CombatMap^.Cells[Row, Col] := Roll + FeatureBase + $1D;
        end
        else if Roll <= Chance37 + Chance3D then
          CombatMap^.Cells[Row, Col] := RollDice(1, 3) + FeatureBase + $17
        else if Roll <= Chance2A + Chance3D + Chance37 then
          CombatMap^.Cells[Row, Col] := RollDice(1, 4) + FeatureBase + $A
        else if Roll <= Chance39 + Chance2A + Chance3D + Chance37 then
        begin
          Roll := (RollDice(1, 10) - 1) div 3 + 1;
          CombatMap^.Cells[Row, Col] := Roll + FeatureBase + $19;
        end
        else if Roll <= Chance2E + Chance39 + Chance2A + Chance3D + Chance37 then
        begin
          Roll := RollDice(1, 4);
          if (Roll = 4) and ((BlockTerrainFlags and FlagTallKinds4To6) = 0) then Roll := RollDice(1, 3);
          CombatMap^.Cells[Row, Col] := Roll + FeatureBase + $E;
        end;
      end;
end;

{ ovl10:11B4. Builds the combat map of a wilderness battle: fills it with GroundTile, takes the
  area map block under the party (GameVars^ VarMapX, VarMapY, the column moved by 13 or 26 for
  AreaViewKind 3 and 4 like MapBaseX) as CombatBlock, then adds a river (PlaceRiver), the tall
  features, the scattered features and the rare tiles. }
procedure BuildWildernessMap;
var
  Col, Row: ShortInt;
  Unused: array[0..1] of Byte;  { QUIRK ovl10:11B7: two bytes of the frame nothing uses }
begin
  FillChar(CombatMap^.Cells, SizeOf(CombatMap^.Cells), GroundTile);
  Col := GameVars^[VarMapX];
  Row := GameVars^[VarMapY];
  if AreaViewKind = 3 then Inc(Col, $D);
  if AreaViewKind = 4 then Inc(Col, $1A);
  CombatBlock := AreaMap[Row, Col];
  PlaceRiver;
  PlaceTallFeatures;
  ScatterTerrainFeatures;
  ScatterRareTiles;
end;

{ ovl10:1244. Loads DungCom (AreaViewKind 1) or WildCom and then RandCom at index $22, allocates
  CombatMap^ (CombatMapSize bytes), clears ShowCursor, sets CursorKind to 1 and clears the Head6
  tile gate before building the dungeon or wilderness map. QUIRK ovl10:1244: Load24x24Set's final
  argument ($18, $21 or 5) is not read by that routine. }
procedure CreateCombatMap;
begin
  if AreaViewKind = AreaViewDungeon then
    Load24x24Set('DungCom', 0, $18)
  else
    Load24x24Set('WildCom', 0, $21);
  Load24x24Set('RandCom', $22, 5);
  GetMem(CombatMap, CombatMapSize);
  CombatMap^.ShowCursor := 0;
  CombatMap^.CursorKind := 1;
  CombatMap^.Head6 := 0;
  if AreaViewKind = AreaViewDungeon then
    BuildDungeonMap
  else
    BuildWildernessMap;
end;

{ ovl10:12E1. Walks the party list (PartyListHead) and readies each character for the battle: calls
  RecalcCombatValues on it, allocates and zeroes its Combat record, sets NoBody for list entries past
  game word VarPartySize, gives it the icon set FacingCombatDir of the party facing (turned half
  round, + 4 mod 8, for side 1), and marks a party-side NoBody member computer-run when B84's
  low-seven-bit morale is 0 or above MaxComputerMorale. It then stores Var2Morale plus
  ComputerRun in B84; Var2Morale is the morale source [I] (ovl09:10D7 reads B84 as morale). }
procedure PrepareCombatants;
var
  Who: PCharacter;
  Count: Byte;
  Morale: Byte;
begin
  Who := PCharacter(PartyListHead);
  Count := 0;
  while Who <> nil do
  begin
    RecalcCombatValues(Who);
    Inc(Count);
    GetMem(Who^.Combat, CombatRecordSize);
    FillChar(Who^.Combat^, CombatRecordSize, 0);
    if Count > GameVars2^[VarPartySize] then Who^.Combat^.NoBody := 1;
    Who^.Combat^.IconSet := FacingCombatDir[PartyFacing shr 1];
    if Who^.Side = SideMonsters then Who^.Combat^.IconSet := (Who^.Combat^.IconSet + 4) mod 8;
    Morale := Who^.B84 and MoraleMask;
    if (Who^.Side = SideParty) and (Who^.Combat^.NoBody = 1) and
       ((Morale = 0) or (Morale > MaxComputerMorale)) then
      Who^.B84 := GameVars2^[Var2Morale] + ComputerRun;
    Who := Who^.Next;
  end;
end;

{ ovl10:1403. True when grid cell (Col, Row) lies beyond the 11x6 placement grid in both
  directions: Col outside 0..10 and Row outside 0..5. QUIRK ovl10:1413: a cell off the grid in one direction only answers
  False. FindStartCell uses it to end a ring or a group. }
function IsBeyondGrid(Col, Row: ShortInt): Boolean;
begin
  if ((Col >= 0) and (Col < GridLastCol + 1)) or ((Row >= 0) and (Row < GridLastRow + 1)) then
    IsBeyondGrid := False
  else
    IsBeyondGrid := True;
end;

{ ovl10:1434. Tries to put combatant Index on grid cell (Col, Row) of placement group Group of
  the side PlacingSide, whose grid origin is (OriginCol, OriginRow) in area map steps. The cell
  must be on the grid and free in PlacementCells; the combatant's map cell is then column
  Col + 6 OriginCol + 5 OriginRow + 22, row Row + 5 OriginRow + 10 (CombatantTable[Index]). True,
  and the grid cell used, when ProbeStep finds no occupant there and a tile that is not off the
  map or blocked. QUIRK ovl10:1434: X and Y are stored before ProbeStep; if ProbeStep rejects an
  otherwise valid cell, the attempted coordinates remain in CombatantTable[Index]. }
function TryPlaceAt(Index: Byte; Col, Row, OriginCol, OriginRow: ShortInt; Group: Byte): Boolean;
var
  Occupant, Tile: Byte;
begin
  if (Col < 0) or (Row < 0) or (Col > GridLastCol) or (Row > GridLastRow)
    or (PlacementCells[PlacingSide, Group, Row, Col] = 0) then
    TryPlaceAt := False
  else
  begin
    CombatantTable[Index].X := Col + OriginCol * 6 + OriginRow * 5 + $16;
    CombatantTable[Index].Y := Row + OriginRow * 5 + $A;
    ProbeStep(CombatantRecord[Index], DirNone, Occupant, Tile);
    if (Occupant = 0) and (Tile > 0) and (CombatTiles[Tile].Cost < CostBlocked) then
    begin
      TryPlaceAt := True;
      PlacementCells[PlacingSide, Group, Row, Col] := 0;
    end
    else
      TryPlaceAt := False;
  end;
end;

{ ovl10:1577. Finds a start cell for combatant Index on the placement grid of the side
  PlacingSide and places it there (TryPlaceAt); False when every group is used up. The search
  walks rings: phase 1 starts a ring at RingStartCol/RingStartRow of the group's facing (from
  GroupFacing) moved Ring steps backwards, phases 2 and 3 alternate Reach steps to either side.
  A ring ends after FirstRingCells of the side for the first ring, 12 cells for later ones, or
  when it leaves the grid while not IsBeyondGrid. For side 0 facing an odd direction, the first
  ring of group 0 is followed by one more skipped ring when one of the three FacingWallDirs from
  the party's area map cell is not a plain wall (PassageKind answers 1 for a wall on both sides;
  outside the dungeon view every direction counts as open). A cell beyond the grid moves on to
  the next group (up to 3) whose FacingWallDirs direction is open, with its origin one area map
  step that way. }
function FindStartCell(Index: Byte): Boolean;
var
  Placed: Boolean;
  First: Byte;                  { 1 until the first ring has ended }
  Failed: Byte;                 { 1 when no group is left }
  OutOfGrid: Byte;
  OpenSide: Byte;               { 1 when one of the three directions is not a wall }
  Phase: Byte;                  { 1: start a ring, 2 and 3: the two sides of it; 0: no open group }
  Dir: Byte;
  Facing: Byte;
  I: Byte;
  StepX, StepY: ShortInt;
  MapX, MapY: ShortInt;         { a cell of the area map near the party }
  Ring: Byte;
  Reach: Byte;
  OriginCol, OriginRow: ShortInt;
  RingCells: Byte;
  Group: Byte;
  RingCol, RingRow: ShortInt;
  Col, Row: ShortInt;
begin
  First := 1;
  Failed := 0;
  Phase := 1;
  Ring := 0;
  Group := 0;
  OriginCol := SideOriginCol[PlacingSide];
  OriginRow := SideOriginRow[PlacingSide];
  repeat
    Facing := GroupFacing[SideFacing[PlacingSide], Group] shr 1;
    case Phase of
      1:
        begin { begin a ring at its facing edge, offset backwards by Ring cells }
          StepX := DirStepX[FacingCombatDir[(Facing + FacingOffsetBack) mod 4]];
          StepY := DirStepY[FacingCombatDir[(Facing + FacingOffsetBack) mod 4]];
          RingCol := RingStartCol[Group > 0, Facing] + StepX * Ring;
          RingRow := RingStartRow[Group > 0, Facing] + StepY * Ring;
          Col := RingCol;
          Row := RingRow;
          Reach := 1;
          Phase := 2;
          RingCells := 1;
        end;
      2:
        begin { take the next cell on one side of the ring }
          StepX := DirStepX[FacingCombatDir[(Facing + FacingOffsetRight) mod 4]];
          StepY := DirStepY[FacingCombatDir[(Facing + FacingOffsetRight) mod 4]];
          Col := RingCol + StepX * Reach;
          Row := RingRow + StepY * Reach;
          Phase := 3;
          Inc(RingCells);
        end;
      3:
        begin { take the opposite side and increase the distance from the ring start }
          StepX := DirStepX[FacingCombatDir[(Facing + FacingOffsetLeft) mod 4]];
          StepY := DirStepY[FacingCombatDir[(Facing + FacingOffsetLeft) mod 4]];
          Col := RingCol + StepX * Reach;
          Row := RingRow + StepY * Reach;
          Phase := 2;
          Inc(Reach);
          Inc(RingCells);
        end;
    end;
    if (Col < 0) or (Row < 0) or (Col > GridLastCol) or (Row > GridLastRow) then
      OutOfGrid := 1
    else
      OutOfGrid := 0;
    if Phase > 1 then
      if ((OutOfGrid <> 0) and not IsBeyondGrid(Col, Row))
        or ((First <> 0) and (RingCells >= FirstRingCells[PlacingSide]))
        or ((First = 0) and (RingCells > LaterRingLastCellCount)) then
      begin
        Inc(Ring);
        if (PlacingSide = SideParty) and Odd(SideFacing[SideParty]) and (Group = 0) and (Ring = 1) then
        begin
          MapX := SideOriginCol[PlacingSide] + PartyMapColumn;
          MapY := SideOriginRow[PlacingSide] + PartyMapRow;
          OpenSide := 0;
          for I := 1 to 3 do
          begin
            Dir := FacingWallDirs[SideFacing[PlacingSide], I];
            if (AreaViewKind > AreaViewDungeon) or (PassageKind(MapX, MapY, Dir) <> SideWall) then OpenSide := 1;
          end;
          if OpenSide <> 0 then Inc(Ring);
        end;
        Phase := 1;
        First := 0;
      end;
    if OutOfGrid <> 0 then
      if IsBeyondGrid(Col, Row) then
      begin
        Placed := False;
        Phase := 0;
        while (Group < 3) and (Phase <> 1) do { find the next open side group }
        begin
          Inc(Group);
          MapX := SideOriginCol[PlacingSide] + PartyMapColumn;
          MapY := SideOriginRow[PlacingSide] + PartyMapRow;
          Dir := FacingWallDirs[SideFacing[PlacingSide], Group];
          if (AreaViewKind > AreaViewDungeon) or (PassageKind(MapX, MapY, Dir) <> SideWall) then
          begin
            OriginCol := SideOriginCol[PlacingSide] + DirStepX[Dir];
            OriginRow := SideOriginRow[PlacingSide] + DirStepY[Dir];
            Ring := 0;
            Phase := 1;
          end;
        end;
        if Phase <> 1 then Failed := 1;
      end;
    if OutOfGrid = 0 then Placed := TryPlaceAt(Index, Col, Row, OriginCol, OriginRow, Group);
  until Placed or (Failed <> 0);
  if Failed <> 0 then
    FindStartCell := False
  else
    FindStartCell := True;
end;

{ ovl10:19F5. Puts every character of the party list on the combat map. It clears CombatantTable,
  sets the two sides' grids: side 0 at the origin facing the party facing (PartyFacing), side 1
  VarStepsAhead area map steps ahead facing back; the first ring of a side holds half its
  combatants (PartySideCount/EnemySideCount, rounded up); each of the 4 groups of a side's PlacementCells is the
  shape PlacementShapes of the side's facing (group 1: shape 4). Then every character becomes
  combatant Index (CombatantRecord, CombatantTable Unk2 and Kind from CombatSize) and gets a cell
  from FindStartCell. A placed character with Flag10D 0 is taken off again and, outside a duel and
  unless NoBody, leaves a body (BodyTile, BodyTable). One that finds no cell and has NoBody is cut
  out of the list through RemoveSelectedCharacter; the list ends after the last character kept. }
procedure PlaceAllCombatants;
var
  Col, Row: ShortInt;
  Prev: PCharacter;
  Who: PCharacter;
  Index: Byte;
  Group: Byte;
  Shape: Byte;
  PlacedCount: Byte;            { counted, never read }
  DroppedCount: Byte;           { counted, never read }
begin
  RecountCombatSides;
  DroppedCount := 0;
  PlacedCount := 0;
  for Index := 1 to CombatantClearLoopLast do CombatantTable[Index].Kind := 0;
  RebuildOccupancy;
  SideOriginCol[SideParty] := 0;
  SideOriginRow[SideParty] := 0;
  SideFacing[SideParty] := PartyFacing shr 1;
  SideOriginCol[SideMonsters] := SideOriginCol[SideParty] + DirStepX[PartyFacing] * GameVars2^[VarStepsAhead];
  SideOriginRow[SideMonsters] := SideOriginRow[SideParty] + DirStepY[PartyFacing] * GameVars2^[VarStepsAhead];
  SideFacing[SideMonsters] := ((PartyFacing + 4) mod 8) shr 1;
  for PlacingSide := SideParty to SideMonsters do
    FirstRingCells[PlacingSide] := (SideCounts[PlacingSide] + 1) shr 1;
  for PlacingSide := SideParty to SideMonsters do
    for Group := 0 to 3 do
    begin
      if Group = 1 then
        Shape := 4
      else
        Shape := SideFacing[PlacingSide];
      for Row := 0 to GridLastRow do
        for Col := 0 to GridLastCol do
          if (PlacementShapes[Shape, Row].Lo > Col) or (PlacementShapes[Shape, Row].Hi < Col) then
            PlacementCells[PlacingSide, Group, Row, Col] := 0
          else
            PlacementCells[PlacingSide, Group, Row, Col] := 1;
    end;
  Index := 1;
  CombatantTable[0].Kind := 1;
  Prev := PCharacter(PartyListHead);
  Who := PCharacter(PartyListHead);
  while Who <> nil do
  begin
    DiscardWaitingKey;
    CombatantRecord[Index] := Who;
    PlacingSide := Who^.Side;
    CombatantTable[Index].Unk2 := Index;
    CombatantTable[Index].Kind := Who^.CombatSize and 7;
    if FindStartCell(Index) then
    begin
      Prev := Who;
      if Who^.Flag10D = 0 then
      begin
        CombatantTable[Index].Kind := 0;
        if (DuelMode = 0) and (Who^.Combat^.NoBody = 0) then
        begin
          Col := CombatantTable[Index].X;
          Row := CombatantTable[Index].Y;
          Inc(BodyCount);
          BodyTable[BodyCount].Tile := CombatMap^.Cells[Row, Col];
          CombatMap^.Cells[Row, Col] := BodyTile;
          BodyTable[BodyCount].Who := Who;
          BodyTable[BodyCount].X := Col;
          BodyTable[BodyCount].Y := Row;
        end;
      end;
      RebuildOccupancy;
      Inc(Index);
      Inc(CombatantTable[0].Kind);
      Inc(PlacedCount);
    end
    else
    begin
      CombatantTable[Index].Kind := 0;
      if Who^.Combat^.NoBody = 1 then
      begin
        Inc(DroppedCount);
        CombatantRecord[Index] := nil;
        SelectedCharacter := Who;
        RemoveSelectedCharacter(True, False);
        Who := Prev;
      end
      else
      begin
        Prev := Who;
        Inc(Index);
        Inc(CombatantTable[0].Kind);
      end;
    end;
    Who := Who^.Next;
  end;
  Prev^.Next := nil;
end;

{ ovl10:1E31 (entry 1, called by RunCombat). Starts a battle: frees the picture animation and the
  HEAD/BODY sprites, then sets HeadBankIndex and BodyBankIndex to $FF (no sprite loaded). It prints
  'A battle begins...' on row 24, resets the round state (MagicToggleOn, CombatRound, AttackRoll, the bodies,
  the lists CloudList and LootListBoundary, game word Var2BattleWord), caps Var2Morale at 100, creates the map,
  discards waiting keys, prepares combatants, discards waiting keys again, places them, and discards
  waiting keys once more. It allocates CombatAnimationPicture, centres the view on the first party character, calls
  DrawCombatScreen, runs HookBattleStart for each character, calls UpdateMonsterMorale and enters ViewModeCombat. }
procedure StartBattle;
var
  Unused: array[0..9] of Byte;  { QUIRK ovl10:1E34: ten bytes of the frame nothing uses }
  Who: PCharacter;
begin
  FreeSpriteList(@PictureAnimation);
  ReleasePicture(HeadSpriteBank);
  ReleasePicture(BodySpriteBank);
  HeadBankIndex := $FF;
  BodyBankIndex := $FF;
  ClearPromptLine;
  DelayByGameSpeed;
  DrawTextAt(0, $18, $A, 'A battle begins...');
  MagicToggleOn := False;
  CombatRound := 0;
  AttackRoll := 0;
  BodyCount := 0;
  CloudList := nil;
  LootListBoundary := nil;
  FillChar(BodyTable, SizeOf(BodyTable), 0);
  GameVars2^[Var2BattleWord] := 0;
  if GameVars2^[Var2Morale] > 100 then GameVars2^[Var2Morale] := 100;
  CreateCombatMap;
  DiscardWaitingKey;
  PrepareCombatants;
  DiscardWaitingKey;
  PlaceAllCombatants;
  DiscardWaitingKey;
  AllocatePicture($18, 3, 4, 1, CombatAnimationPicture);
  CombatMap^.ViewX := CombatantX(PCharacter(PartyListHead)) - 3;
  CombatMap^.ViewY := CombatantY(PCharacter(PartyListHead)) - 3;
  DrawCombatScreen;
  Who := PCharacter(PartyListHead);
  while Who <> nil do
  begin
    RunAffectHooks(HookBattleStart, Who);
    Who := Who^.Next;
  end;
  UpdateMonsterMorale;
  ViewMode := ViewModeCombat;
end;

begin
end.

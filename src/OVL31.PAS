unit OVL31;
{ The combat map view (whitepaper 5.5): the 50x25 cell combat map CombatMap^, seen through a 7x7
  cell window whose top left cell is (ViewX, ViewY), and the combatants on it. CombatantTable holds
  each combatant's cell and footprint kind (Footprints: one cell, two cells or a 2x2 square),
  CellOccupant which combatant stands on each cell (RebuildOccupancy), CombatantViewCol/Row its place
  in the window. ScrollViewTo and MoveCombatCursor scroll the window and move the cursor,
  RedrawGround/RedrawMapCell/DrawCursorAt repaint cells, SetCombatantIcon turns a combatant,
  PlaceCombatant and RemoveCombatant put one on the map and take it off (leaving a body,
  BodyTable). Everything that changes the map runs only in view mode 5 (ds49F3). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
function FootprintCell(Kind, Index: Byte; var DX, DY: ShortInt): Boolean;
procedure UpdateViewPositions;
procedure ovl31_e2;
procedure ovl31_e3;
procedure DrawCursorAt(CellX, CellY: ShortInt);
procedure RedrawMapCell(CellX, CellY: ShortInt);
procedure RebuildOccupancy;
procedure GetMapCell(CellX, CellY: ShortInt; var Occupant, Tile: Byte);
procedure RedrawGround(Col, Row: ShortInt; Occupant: Byte);
function IsInView(Col, Row: ShortInt): Boolean;
function IsCombatantInView(Who: PCharacter; AllCells: Byte): Boolean;
function ScrollViewTo(CellX, CellY: ShortInt; Margin: Byte): Boolean;
procedure MoveCombatCursor(CellX, CellY: ShortInt; Margin, Dir: Byte);
procedure SetCombatantIcon(Who: PCharacter; IconSet, Mirror, NoDraw: Byte);
function CombatantX(Who: PCharacter): ShortInt;
function CombatantY(Who: PCharacter): ShortInt;
function CombatantKind(Who: PCharacter): Byte;
function CombatantIndex(Who: PCharacter): Byte;
procedure ProbeStep(Who: PCharacter; Dir: Byte; var Occupant, Tile: Byte);
procedure RemoveCombatant(Who: PCharacter);
function PlaceCombatant(Who: PCharacter; CellX, CellY: Byte; Restore: Byte): Boolean;
procedure ShowCursorOn(Who: PCharacter; Margin, ShowCursor: Byte);
implementation
uses RES03, RES06, RES07, OVL32;

const
  MapLastCol = $31;             { the combat map is 50 cells wide (GetMapCell, ovl31:04C7) }
  MapLastRow = $18;             { and 25 cells high (ovl31:04D3) }
  ViewLast = 6;                 { the view shows cells 0..6 of the window in each direction }
  ViewCentre = 3;               { the window's centre cell, column and row }
  MaxCentreCol = $2E;           { the centre column stops at 46 = 49 - 3 (ovl31:08A2) }
  MaxCentreRow = $15;           { the centre row stops at 21 = 24 - 3 (ovl31:08DA) }
  CellStep = 3;                 { a cell is 3 picture units wide and high (DrawCellPicture) }
  FootprintCells = 3;           { footprint cells are numbered 0..3 }
  CursorIcon = $19;             { the DrawIcon picture of the cursor (ovl31:0236) }
  DirNone = 8;                  { the direction with no step (ds2736[8] = ds273F[8] = 0) }
  CentreMargin = 3;             { how far from the centre a cell may be before the view scrolls }
  NoReach = $FF;                { ScrollViewTo's Margin that always scrolls and redraws }
  ViewModeCombat = 5;           { ds49F3 during combat (RemoveCombatant, PlaceCombatant) }
  KindMask = $7F;               { TCharacter.CombatSize bits that are the footprint kind }
  CostBlocked = $FF;            { a CombatTiles cost no combatant may stand on }
  FirstProbeTile = $17;         { the tile ProbeStep answers before any cell is looked at }
  TileKept = $1E;               { a tile that is never replaced by a body and always wins ProbeStep }
  TileBody = $1F;               { the tile a body leaves on the map }
  MaxBodies = 8;                { BodyTable holds 8 records }
  { SetSoundDriverIdle (the sound unit) is called with 0 before RemoveCombatant's work and with 10 after;
    what the two values select is not known. }
  BeforeRemoval = 0;
  AfterRemoval = $A;
  DyingFlags = 5;               { the flags res07_fn_0D71 draws DyingPicture with }

{ ovl31:0000. Cell Index (0..3) of footprint kind Kind: its offset (DX, DY) from the combatant's
  cell, from Footprints. True when that cell exists (DX >= 0); kind 0 has no cells. Kind 1 is one
  cell, 2 is two cells one above the other, 3 two side by side, 4 a 2x2 square (DS:2844 bytes).
  Called by every routine here that walks a footprint and by ovl30's ScanTargets. }
function FootprintCell(Kind, Index: Byte; var DX, DY: ShortInt): Boolean;
begin
  FootprintCell := False;
  if Kind = 0 then Exit;
  DX := Footprints[Kind, Index].DX;
  DY := Footprints[Kind, Index].DY;
  if DX >= 0 then FootprintCell := True;
end;

{ ovl31:0068. Recomputes every combatant's place in the view, CombatantViewCol/Row[I] = its map
  cell minus the view origin. Called by ScrollViewTo after the view moved. }
procedure UpdateViewPositions;
var
  I: Byte;
begin
  for I := 1 to CombatantTable[0].Kind do
  begin
    CombatantViewCol[I] := CombatantTable[I].X - CombatMap^.ViewX;
    CombatantViewRow[I] := CombatantTable[I].Y - CombatMap^.ViewY;
  end;
end;

{ ovl31:00E3. Purpose unknown: when VideoAdapter is 1 it calls SetPaletteRegister(0, 8) and then
  SetPaletteRegister(8, 0); ovl31_e3 makes the calls (0, 0) and (8, 8). Called by ovl16_e3, ovl19 and
  res12_fn_2B88. }
procedure ovl31_e2;
begin
  case VideoAdapter of
    1:
      begin
        SetPaletteRegister(0, 8);
        SetPaletteRegister(8, 0);
      end;
  end;
end;

{ ovl31:0105. Purpose unknown: when VideoAdapter is 1 it calls SetPaletteRegister(0, 0) and then
  SetPaletteRegister(8, 8), the counterpart of ovl31_e2. Called by ovl08, ovl16 and ovl19_e5. }
procedure ovl31_e3;
begin
  case VideoAdapter of
    1:
      begin
        SetPaletteRegister(0, 0);
        SetPaletteRegister(8, 8);
      end;
  end;
end;

{ ovl31:0127. Draws the cursor on map cell (CellX, CellY): every cell of the cursor's footprint
  (CombatMap^.CursorKind) that is in view gets its ground picture again and, when
  CombatMap^.ShowCursor is set, the cursor icon; then the combatant standing on (CellX, CellY), if it is in
  view, is drawn over it. Called by MoveCombatCursor. }
procedure DrawCursorAt(CellX, CellY: ShortInt);
var
  ViewCol, ViewRow, DX, DY: ShortInt;
  J, Occupant, Tile: Byte;
begin
  ViewCol := CellX - CombatMap^.ViewX;
  ViewRow := CellY - CombatMap^.ViewY;
  for J := 0 to FootprintCells do
    if FootprintCell(CombatMap^.CursorKind, J, DX, DY) then
      if IsInView(ViewCol + DX, ViewRow + DY) then
      begin
        DrawCellPicture((ViewCol + DX) * CellStep, (ViewRow + DY) * CellStep,
          CombatTiles[CombatMap^.Cells[CellY + DY, CellX + DX]].Picture, 0);
        if CombatMap^.ShowCursor <> 0 then
          DrawIcon(ViewCol + DX, ViewRow + DY, 0, 0, CursorIcon);
      end;
  GetMapCell(CellX, CellY, Occupant, Tile);
  if Occupant > 0 then
    if IsCombatantInView(CombatantRecord[Occupant], 0) then
      DrawIcon(CombatantViewCol[Occupant], CombatantViewRow[Occupant],
        CombatantRecord[Occupant]^.Combat^.IconSet, 0, CombatantRecord[Occupant]^.CombatIcon);
end;

{ ovl31:02D5. Repaints map cell (CellX, CellY) without the cursor: the ground under it (RedrawGround) and
  the combatant standing there, if it is in view. Called by MoveCombatCursor for the cell the cursor
  leaves, and by ovl08, ovl13. }
procedure RedrawMapCell(CellX, CellY: ShortInt);
var
  ViewCol, ViewRow: ShortInt;
  Occupant, Tile: Byte;
begin
  ViewCol := CellX - CombatMap^.ViewX;
  ViewRow := CellY - CombatMap^.ViewY;
  RedrawGround(ViewCol, ViewRow, 0);
  GetMapCell(CellX, CellY, Occupant, Tile);
  if Occupant > 0 then
    if IsCombatantInView(CombatantRecord[Occupant], 0) then
      DrawIcon(CombatantViewCol[Occupant], CombatantViewRow[Occupant],
        CombatantRecord[Occupant]^.Combat^.IconSet, 0, CombatantRecord[Occupant]^.CombatIcon);
end;

{ ovl31:03A0. Rebuilds CellOccupant from CombatantTable: clears it, writes each active combatant's
  index into the cells of its footprint, and refreshes its view position. Called after a combatant
  is placed or removed (PlaceCombatant, RemoveCombatant) and by ovl10, ovl13, ovl24. }
procedure RebuildOccupancy;
var
  I, J: Byte;
  DX, DY: ShortInt;
begin
  FillChar(CellOccupant, SizeOf(CellOccupant), 0);
  for I := 1 to CombatantTable[0].Kind do
    if CombatantTable[I].Kind > 0 then
    begin
      for J := 0 to FootprintCells do
        if FootprintCell(CombatantTable[I].Kind, J, DX, DY) then
          CellOccupant[CombatantTable[I].Y + DY, CombatantTable[I].X + DX] := I;
      CombatantViewCol[I] := CombatantTable[I].X - CombatMap^.ViewX;
      CombatantViewRow[I] := CombatantTable[I].Y - CombatMap^.ViewY;
    end;
end;

{ ovl31:04BE. The tile id (CombatMap^.Cells) and the combatant (CellOccupant, 0 for none) of map
  cell (CellX, CellY); both are 0 for a cell off the 50x25 map. Called here and by ovl13, ovl22. }
procedure GetMapCell(CellX, CellY: ShortInt; var Occupant, Tile: Byte);
begin
  if (CellX >= 0) and (CellX <= MapLastCol) and (CellY >= 0) and (CellY <= MapLastRow) then
  begin
    Tile := CombatMap^.Cells[CellY, CellX];
    Occupant := CellOccupant[CellY, CellX];
  end
  else
  begin
    Occupant := 0;
    Tile := 0;
  end;
end;

{ ovl31:052B. Repaints the ground: with Occupant 0 it looks up the combatant on view cell (Col, Row)
  first. When there is one, the ground pictures of all its footprint cells that are in view are
  drawn (the combatant itself is erased); otherwise only view cell (Col, Row), when it is in view.
  Called by RedrawMapCell, SetCombatantIcon, RemoveCombatant and ovl08, ovl13, ovl24. }
procedure RedrawGround(Col, Row: ShortInt; Occupant: Byte);
var
  MapCol, MapRow, DX, DY: ShortInt;
  J, Tile, Kind: Byte;
begin
  if Occupant = 0 then
  begin
    MapCol := Col + CombatMap^.ViewX;
    MapRow := Row + CombatMap^.ViewY;
    GetMapCell(MapCol, MapRow, Occupant, Tile);
  end;
  if Occupant > 0 then
  begin
    Col := CombatantViewCol[Occupant];
    Row := CombatantViewRow[Occupant];
    MapCol := Col + CombatMap^.ViewX;
    MapRow := Row + CombatMap^.ViewY;
    Kind := CombatantTable[Occupant].Kind;
    for J := 0 to FootprintCells do
      if FootprintCell(Kind, J, DX, DY) then
        if IsInView(Col + DX, Row + DY) then
          DrawCellPicture((Col + DX) * CellStep, (Row + DY) * CellStep,
            CombatTiles[CombatMap^.Cells[MapRow + DY, MapCol + DX]].Picture, 0);
  end
  else if IsInView(Col, Row) then
    DrawCellPicture(Col * CellStep, Row * CellStep, CombatTiles[CombatMap^.Cells[MapRow, MapCol]].Picture, 0);
end;

{ ovl31:06E9. True when view cell (Col, Row) is inside the 7x7 window (0..ViewLast both ways).
  Called here and by ovl13, res12_fn_1A29, res12_fn_1CE0. }
function IsInView(Col, Row: ShortInt): Boolean;
begin
  if (Col < 0) or (Col > ViewLast) or (Row < 0) or (Row > ViewLast) then
    IsInView := False
  else
    IsInView := True;
end;

{ ovl31:071A. True when combatant Who can be seen: with AllCells set every cell of its footprint
  must be in view, otherwise one is enough. False for a combatant whose Kind is 0 (not on the map).
  QUIRK ovl31:071D: the frame holds two bytes no code uses (Spare). }
function IsCombatantInView(Who: PCharacter; AllCells: Byte): Boolean;
var
  J, Index: Byte;
  DX, DY: ShortInt;
  Spare: array[0..1] of Byte;
begin
  IsCombatantInView := True;
  Index := CombatantIndex(Who);
  if CombatantTable[Index].Kind = 0 then
  begin
    IsCombatantInView := False;
    Exit;
  end;
  for J := 0 to FootprintCells do
    if FootprintCell(CombatantTable[Index].Kind, J, DX, DY) then
      if not IsInView(CombatantViewCol[Index] + DX, CombatantViewRow[Index] + DY) then
      begin
        IsCombatantInView := False;
        if AllCells <> 0 then Exit;
      end
      else
      begin
        IsCombatantInView := True;
        if AllCells = 0 then Exit;
      end;
end;

{ ovl31:07D4. Scrolls the view so that map cell (CellX, CellY) lies within Margin cells of the window's
  centre: returns False and does nothing when it already does. Otherwise the centre moves one cell at
  a time towards (CellX, CellY), never past columns 3..46 and rows 3..21, the new origin is stored in
  CombatMap^, all 49 cell pictures are drawn and the combatants' view positions are updated
  (UpdateViewPositions); returns True. Margin NoReach ($FF) counts as 0 and always redraws.
  Called by MoveCombatCursor. }
function ScrollViewTo(CellX, CellY: ShortInt; Margin: Byte): Boolean;
var
  Reach: Byte;
  PicCol, PicRow: Byte;
  I, J: Byte;
  MapCol, MapRow: ShortInt;     { the window's centre first, then the cell being drawn }
  MinX, MaxX, MinY, MaxY: ShortInt;
begin
  ScrollViewTo := False;
  MapCol := CombatMap^.ViewX + ViewCentre;
  MapRow := CombatMap^.ViewY + ViewCentre;
  Reach := Margin;
  if Margin = NoReach then Reach := 0;
  MinX := MapCol - Reach;
  MaxX := MapCol + Reach;
  MinY := MapRow - Reach;
  MaxY := MapRow + Reach;
  if (Margin <> NoReach) and (CellX >= MinX) and (CellX <= MaxX) and (CellY >= MinY) and (CellY <= MaxY) then Exit;
  if CellX < MinX then
    while (CellX < MapCol) and (MapCol > ViewCentre) do Dec(MapCol)
  else if CellX > MaxX then
    while (CellX > MapCol) and (MapCol < MaxCentreCol) do Inc(MapCol);
  if CellY < MinY then
    while (CellY < MapRow) and (MapRow > ViewCentre) do Dec(MapRow)
  else if CellY > MaxY then
    while (CellY > MapRow) and (MapRow < MaxCentreRow) do Inc(MapRow);
  CombatMap^.ViewX := MapCol - ViewCentre;
  CombatMap^.ViewY := MapRow - ViewCentre;
  PicRow := 0;
  MapRow := CombatMap^.ViewY;
  for J := 0 to ViewLast do
  begin
    PicCol := 0;
    MapCol := CombatMap^.ViewX;
    for I := 0 to ViewLast do
    begin
      DrawCellPicture(PicCol, PicRow, CombatTiles[CombatMap^.Cells[MapRow, MapCol]].Picture, 1);
      Inc(PicCol, CellStep);
      Inc(MapCol);
    end;
    Inc(PicRow, CellStep);
    Inc(MapRow);
  end;
  UpdateViewPositions;
  ScrollViewTo := True;
end;

{ ovl31:0996. Moves the cursor from map cell (CellX, CellY) one step in direction Dir (ds2736/ds273F;
  DirNone stays): scrolls the view when the new cell is more than Margin cells from the centre
  (ScrollViewTo) and then redraws every combatant in view whose record has Flag10D set, repaints the
  old cell (RedrawMapCell), clamps the new cell to the map when it is out of view, draws the cursor
  there (DrawCursorAt) and shows the frame (FlushPictureChanges). Called by the combat code (ovl08, ovl09,
  ovl13, ovl22) and here. }
procedure MoveCombatCursor(CellX, CellY: ShortInt; Margin, Dir: Byte);
var
  Who: PCharacter;
  I: Byte;
  NewX, NewY: ShortInt;
begin
  NewX := CellX + ds2736[Dir];
  NewY := CellY + ds273F[Dir];
  if ScrollViewTo(NewX, NewY, Margin) then
    for I := 1 to CombatantTable[0].Kind do
    begin
      Who := CombatantRecord[I];
      if (Who^.Flag10D <> 0) and (CombatantTable[I].Kind > 0) then
        if IsCombatantInView(Who, 0) then
          DrawIcon(CombatantViewCol[I], CombatantViewRow[I], Who^.Combat^.IconSet, 0, Who^.CombatIcon);
    end;
  RedrawMapCell(CellX, CellY);
  if not IsInView(NewX - CombatMap^.ViewX, NewY - CombatMap^.ViewY) then
  begin
    if NewX > MapLastCol then NewX := MapLastCol;
    if NewX < 0 then NewX := 0;
    if NewY > MapLastRow then NewY := MapLastRow;
    if NewY < 0 then NewY := 0;
  end;
  DrawCursorAt(NewX, NewY);
  FlushPictureChanges;
end;

{ ovl31:0AF8. Turns combatant Who to the icon set IconSet: brings it into view first when part of
  it is outside (MoveCombatCursor on its cell), erases it (RedrawGround) when the icon set changes
  by more than the low two bits or Mirror or NoDraw is set, stores IconSet in Who^.Combat^ and,
  unless NoDraw, draws it with Mirror and shows the frame. Called by ovl08, ovl09, ovl13, ovl22. }
procedure SetCombatantIcon(Who: PCharacter; IconSet, Mirror, NoDraw: Byte);
var
  Index: Byte;
begin
  Index := CombatantIndex(Who);
  if not IsCombatantInView(Who, 1) then
    MoveCombatCursor(CombatantX(Who), CombatantY(Who), CentreMargin, DirNone);
  if (Who^.Combat^.IconSet div 4 <> IconSet div 4) or (Mirror <> 0) or (NoDraw <> 0) then
    RedrawGround(0, 0, Index);
  if IconSet <> Who^.Combat^.IconSet then
    Who^.Combat^.IconSet := IconSet;
  if NoDraw = 0 then
    if IsCombatantInView(Who, 1) then
    begin
      DrawIcon(CombatantViewCol[Index], CombatantViewRow[Index], IconSet, Mirror, Who^.CombatIcon);
      FlushPictureChanges;
    end;
end;

{ ovl31:0BE7. The map column of combatant Who (CombatantTable). Called widely by the combat units. }
function CombatantX(Who: PCharacter): ShortInt;
begin
  CombatantX := CombatantTable[CombatantIndex(Who)].X;
end;

{ ovl31:0C0F. The map row of combatant Who (CombatantTable). Called widely by the combat units. }
function CombatantY(Who: PCharacter): ShortInt;
begin
  CombatantY := CombatantTable[CombatantIndex(Who)].Y;
end;

{ ovl31:0C37. The footprint kind of combatant Who (CombatantTable; 0 when it is not on the map).
  Called by ovl13, ovl24, res12. }
function CombatantKind(Who: PCharacter): Byte;
begin
  CombatantKind := CombatantTable[CombatantIndex(Who)].Kind;
end;

{ ovl31:0C5F. The combatant number of character record Who: the I (1..count) with
  CombatantRecord[I] = Who, or 0 when it is not among them. QUIRK ovl31:0C71: with a count of 0
  the loop still looks at entry 1 and then runs on until I wraps round to 0. }
function CombatantIndex(Who: PCharacter): Byte;
var
  Found: Boolean;
  I: Byte;
begin
  Found := False;
  CombatantIndex := 0;
  I := 0;
  repeat
    Inc(I);
    if CombatantRecord[I] = Who then Found := True;
  until Found or (I = CombatantTable[0].Kind);
  if Found then CombatantIndex := I;
end;

{ ovl31:0CB9. Looks at the cells combatant Who's footprint would cover after one step in direction
  Dir (DirNone: where it stands): Occupant is another combatant on one of them (0 for none; the
  last one found), Tile the tile that decides the step: 0 when any cell is off the map or tile 0,
  else TileKept when any cell has it, else the cell tile with the largest CombatTiles cost (from
  cost 1 up; FirstProbeTile when no cell exists). Called by PlaceCombatant and ovl08, ovl10, ovl24. }
procedure ProbeStep(Who: PCharacter; Dir: Byte; var Occupant, Tile: Byte);
var
  J, Index, CellWho, CellTile, BestCost: Byte;
  NewX, NewY, CellX, CellY, DX, DY: ShortInt;
begin
  Occupant := 0;
  Tile := FirstProbeTile;
  BestCost := 1;
  Index := CombatantIndex(Who);
  CellX := CombatantTable[Index].X;
  CellY := CombatantTable[Index].Y;
  for J := 0 to FootprintCells do
    if FootprintCell(CombatantTable[Index].Kind, J, DX, DY) then
    begin
      NewX := CellX + DX + ds2736[Dir];
      NewY := CellY + DY + ds273F[Dir];
      GetMapCell(NewX, NewY, CellWho, CellTile);
      if CellWho = Index then CellWho := 0;
      if CellWho > 0 then Occupant := CellWho;
      if (CellTile = 0) or (Tile = 0) then
        Tile := 0
      else if (CellTile = TileKept) or (Tile = TileKept) then
        Tile := TileKept
      else if CombatTiles[CellTile].Cost >= BestCost then
      begin
        BestCost := CombatTiles[CellTile].Cost;
        Tile := CellTile;
      end;
    end;
end;

{ ovl31:0E11. Takes combatant Who off the combat map (it dies or leaves). Outside view mode 5 it only
  makes the PlaySound(ds261E) call and waits (DelayByGameSpeed). In combat it does nothing when Who
  already has a body record; otherwise it brings Who into view, erases it, draws DyingPicture on
  each of its cells, and unless Who^.Combat^.NoBody is set adds a body record (BodyTable: who, cell,
  the tile under it) and puts TileBody on its cell (a TileKept cell stays). Then the res03 call and
  the wait, the ground is redrawn, its Kind is cleared, CellOccupant rebuilt, the view redrawn round
  its centre and four bytes of its combat record cleared. SetSoundDriverIdle brackets the whole.
  QUIRK ovl31:0E41: the search for an existing body record tests BodyTable[ds70C7] (the sprite list
  loop counter of FreeSpriteList) every time, not BodyTable[I]; I only counts to 9.
  QUIRK ovl31:0E69: the early exit skips the closing SetSoundDriverIdle(10).
  QUIRK ovl31:0E14: the frame holds two bytes no code uses (Spare). }
procedure RemoveCombatant(Who: PCharacter);
var
  Index, I: Byte;
  DX, DY, CellX, CellY: ShortInt;
  Spare: array[0..1] of Byte;
begin
  SetSoundDriverIdle(BeforeRemoval);
  if ds49F3 <> ViewModeCombat then
  begin
    PlaySound(ds261E);
    DelayByGameSpeed;
  end
  else
  begin
    I := 1;
    while (I < MaxBodies + 1) and (BodyTable[ds70C7].Who <> Who) do
      Inc(I);
    if I < MaxBodies + 1 then Exit;
    Index := CombatantIndex(Who);
    CellX := CombatantX(Who);
    CellY := CombatantY(Who);
    if not IsCombatantInView(Who, 1) then
      MoveCombatCursor(CellX, CellY, CentreMargin, DirNone);
    RedrawGround(0, 0, Index);
    for I := 0 to FootprintCells do
      if FootprintCell(CombatantTable[Index].Kind, I, DX, DY) then
        res07_fn_0D71((CombatantViewCol[Index] + DX) * CellStep, (CombatantViewRow[Index] + DY) * CellStep,
          0, DyingFlags, DyingPicture, DrawBuf);
    FlushPictureChanges;
    if Who^.Combat^.NoBody = 0 then
    begin
      Inc(BodyCount);
      BodyTable[BodyCount].Tile := CombatMap^.Cells[CellY, CellX];
      if CombatMap^.Cells[CellY, CellX] <> TileKept then
        CombatMap^.Cells[CellY, CellX] := TileBody;
      BodyTable[BodyCount].Who := Who;
      BodyTable[BodyCount].X := CellX;
      BodyTable[BodyCount].Y := CellY;
    end;
    PlaySound(ds261E);
    DelayByGameSpeed;
    RedrawGround(0, 0, Index);
    CombatantTable[CombatantIndex(Who)].Kind := 0;
    RebuildOccupancy;
    MoveCombatCursor(CombatMap^.ViewX + ViewCentre, CombatMap^.ViewY + ViewCentre, CentreMargin, DirNone);
    Who^.Combat^.Initiative := 0;
    Who^.Combat^.Moves := 0;
    Who^.Combat^.PendingSpell := 0;
    Who^.Combat^.B7 := 0;
  end;
  SetSoundDriverIdle(AfterRemoval);
end;

{ ovl31:10A7. Puts combatant Who on map cell (CellX, CellY) with the footprint kind of its record
  (CombatSize and KindMask) and returns True, or clears its Kind again and returns False when
  ProbeStep finds another combatant there, tile 0 or a CostBlocked tile. With Restore set and no
  NoBody flag it takes back its body records (the tile under the body, unless TileBody, becomes the
  one restored; the records are cleared) and, when no other body lies on (CellX, CellY), puts that tile on
  the cell. CellOccupant is rebuilt on success. Outside view mode 5 it only returns True.
  Called by ovl08, ovl22, ovl24. }
function PlaceCombatant(Who: PCharacter; CellX, CellY: Byte; Restore: Byte): Boolean;
var
  Index, I, Occupant, Tile: Byte;
  BodyThere: Boolean;
begin
  if ds49F3 = ViewModeCombat then
  begin
    PlaceCombatant := False;
    Index := CombatantIndex(Who);
    CombatantTable[Index].Kind := Who^.CombatSize and KindMask;
    CombatantTable[Index].X := CellX;
    CombatantTable[Index].Y := CellY;
    ProbeStep(Who, DirNone, Occupant, Tile);
    if (Occupant <> 0) or (Tile = 0) or (CombatTiles[Tile].Cost = CostBlocked) then
      CombatantTable[Index].Kind := 0
    else
    begin
      PlaceCombatant := True;
      if Restore <> 0 then
        if Who^.Combat^.NoBody = 0 then
        begin
          for I := 1 to BodyCount do
            if BodyTable[I].Who = Who then
            begin
              if BodyTable[I].Tile <> TileBody then
                Tile := BodyTable[I].Tile;
              FillChar(BodyTable[I], SizeOf(TBody), 0);
            end;
          BodyThere := False;
          for I := 1 to BodyCount do
            if (BodyTable[I].Who <> nil) and (BodyTable[I].X = CellX) and (BodyTable[I].Y = CellY) then
              BodyThere := True;
          if not BodyThere then
            CombatMap^.Cells[CellY, CellX] := Tile;
        end;
      RebuildOccupancy;
    end;
  end
  else
    PlaceCombatant := True;
end;

{ ovl31:1298. Shows the cursor on combatant Who: the cursor takes Who's footprint kind and is drawn
  (ShowCursor) on Who's cell through MoveCombatCursor (Margin, no step); then the cursor is reset to
  kind 1 and hidden for later moves. Called by ovl08, ovl12, ovl13, ovl24. }
procedure ShowCursorOn(Who: PCharacter; Margin, ShowCursor: Byte);
begin
  CombatMap^.ShowCursor := ShowCursor;
  CombatMap^.CursorKind := CombatantTable[CombatantIndex(Who)].Kind;
  MoveCombatCursor(CombatantX(Who), CombatantY(Who), Margin, DirNone);
  CombatMap^.ShowCursor := 0;
  CombatMap^.CursorKind := 1;
end;

begin
end.

unit OVL27;
{ The area view of the wilderness and the adventure screen (whitepaper 5.2). DrawAreaView paints
  the 5x5 grid of 3x3-tile area blocks around a position on the area map into the 3D view window.
  Entries 3 to 9 of the fixed-position table can override a block while the game variables allow
  it; entries 1 and 2 never do. DrawAdventureScreen frames the three windows of the adventure
  screen: the 3D view on the left, the side window on the right and the text area at the bottom. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure DrawAreaView(LeftCol, TopRow: Integer);
procedure DrawAdventureScreen;
implementation
uses POOLVARS, OVL32, RES09;

const
  ViewBlocks = 5;                { the area view is a 5x5 grid of blocks }
  BlockCells = 3;                { each block is 3x3 cells of the 3D view window }
  SpecialCount = 9;              { entries 1..9 are tested for position; only 3..9 can override a block }

  { Words of the game variables (GameVars^) that decide when a fixed block is drawn. What each
    variable counts is still unknown; the names say which block depends on it. }
  GateVarBlock3 = 396;           { block 3 is drawn while this is not 255 }
  GateVarBlock4State = 466;      { block 4 is drawn while this is nonzero, }
  GateVarBlock4Flags = 380;      { or while bit 3 of this is set, }
  GateVarBlock4Empty = 415;      { or while this is zero }
  GateVarBlockBits = 416;         { bit 1 gates block 5 and bit 0 gates block 7: each is drawn while its bit is clear }
  GateVarBlock8Count = 435;       { blocks 8 and 9 are drawn while this is above 253 }

  { The three windows of the adventure screen, in the grid DrawWindow works in: a column is
    16 pixels wide, a row 4 scanlines. The names give TopRow, LeftCol, BottomRow, RightCol. }
  ViewTop = 1;                    ViewLeft = 1;     ViewBottom = 15;  ViewRight = 15;
  SideTop = 1;                    SideLeft = 17;    SideBottom = 15;  SideRight = 38;
  TextTop = 17;                   TextLeft = 1;     TextBottom = 22;   TextRight = 38;
  Black = 0;                      { EGA colour of the window text (never shown: the text is empty) }
  PlainFrame = 0;                 { the frame set DrawWindow draws around each window }

{ ovl27:0000. Draws the 5x5 grid of 3x3-tile area blocks around map position (LeftCol, TopRow)
  into the 3D view window. The block code comes from AreaMap, minus one. Entries 1 to 9 of
  SpecialBlocks are tested for that position. Entries 1 and 2 have no case arm, so a match leaves
  the map code. Entries 3 to 9 can replace it: entry 6 always, the others only while the game
  variables named above allow. Each block is one picture drawn by ovl32_e2, stepped by BlockCells.
  Parameters: LeftCol and TopRow are the map column and row of the top-left block.
  Callers: ShowAreaView (ovl26:0293) passes MapBaseX[AreaViewKind] plus the party column, minus 2
  (ovl26:023F), and the party row minus 2, then clamps the column to 0..39 (ovl26:025D) and the
  row to 0..31 (ovl26:027F). AnimateAreaDoors, when its byte parameter is nonzero, calls this with (17, 15)
  (ovl18:06C2), then nine times with a word from the table at DS:094D and a word from the table at
  DS:095F (index 0..8, ovl18:07C8), then with (23, 25) (ovl18:08D4). When that byte is zero those
  calls are skipped.
  Globals: reads AreaMap, SpecialBlocks and the words of GameVars^ named above. Side effects:
  the 3D view part of the screen, through ovl32_e2. }
procedure DrawAreaView(LeftCol, TopRow: Integer);
var
  BaseCol, BaseRow: Shortint;    { where in the view window the current block goes, in cells }
  Special: 1..9;                  { index into SpecialBlocks while looking for an override }
  TileCol, TileRow: Shortint;    { position of the current block on the area map }
  Count: Byte;                    { the block code ovl32_e2 draws }
  GridCol, GridRow: Byte;         { position within the 5x5 view grid }
begin
  BaseRow := 0;
  for GridRow := 0 to ViewBlocks - 1 do
  begin
    BaseCol := 0;
    for GridCol := 0 to ViewBlocks - 1 do
    begin
      TileCol := GridCol + LeftCol;
      TileRow := GridRow + TopRow;
      Count := AreaMap[TileRow, TileCol] - 1;
      for Special := 1 to SpecialCount do
        if (TileCol = SpecialBlocks[Special].Col) and (TileRow = SpecialBlocks[Special].Row) then
        begin
          { Entries 1 and 2 have no arm, so a position match leaves Count. Entries 3 to 9 can
            replace it; the case labels are those entries of SpecialBlocks. }
          case Special of
            3: if GameVars^[GateVarBlock3] <> 255 then Count := SpecialBlocks[Special].Pic - 1;
            4: if (GameVars^[GateVarBlock4State] <> 0) or ((GameVars^[GateVarBlock4Flags] and 8) <> 0)
                 or (GameVars^[GateVarBlock4Empty] = 0) then
                 Count := SpecialBlocks[Special].Pic - 1;
            5: if (GameVars^[GateVarBlockBits] and 2) = 0 then Count := SpecialBlocks[Special].Pic - 1;
            6: Count := SpecialBlocks[Special].Pic - 1;
            7: if (GameVars^[GateVarBlockBits] and 1) = 0 then Count := SpecialBlocks[Special].Pic - 1;
            8, 9: if GameVars^[GateVarBlock8Count] > 253 then Count := SpecialBlocks[Special].Pic - 1;
          end
        end;
      { QUIRK ovl27:01CC: the original adds and subtracts 1 from both coordinates, which changes
        nothing; kept for a byte-exact match. The fourth argument is always 1 here and ovl32_e2
        never reads it. }
      ovl32_e2(BaseCol + 1 - 1, BaseRow + 1 - 1, Count, 1);
      Inc(BaseCol, BlockCells);
    end;
    Inc(BaseRow, BlockCells);
  end;
end;

{ ovl27:0207. Frames the three windows of the adventure screen: the 3D view on the left (15x15
  cells), the side window on the right and the text area at the bottom, with no text in them.
  Side effects: the screen (through DrawWindow, which clears each window, draws its frame
  and would centre its text on the top row). }
procedure DrawAdventureScreen;
begin
  DrawWindow(ViewLeft, ViewTop, ViewRight, ViewBottom, PlainFrame, Black, '');
  DrawWindow(SideLeft, SideTop, SideRight, SideBottom, PlainFrame, Black, '');
  DrawWindow(TextLeft, TextTop, TextRight, TextBottom, PlainFrame, Black, '');
end;

{ ovl27:0283. Empty initialisation: push bp, mov bp, sp, pop bp, retf. }
begin
end.

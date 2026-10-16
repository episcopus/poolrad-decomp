unit RES09;
{ Windows: DrawWindow draws a titled window for dialogs and screens (whitepaper 5.9):
  ClearWindow clears its rectangle for the current video adapter (VideoAdapter),
  DrawWindowFrame draws one tile set's frame around it through Put8x8Symbol, and DrawWindow
  centres a title on its top row through DrawTextAt. }
{$A-,F+,S-,R-,G-,I-}
interface
uses RES06;
procedure DrawWindowFrame(LeftCol, TopRow, RightCol, BottomRow: ShortInt; FrameSet: Byte);
procedure ClearWindow(LeftCol, TopRow, RightCol, BottomRow: ShortInt);
procedure DrawWindow(LeftCol, TopRow, RightCol, BottomRow: ShortInt; FrameSet, TextColor: Byte;
  Text: String40);
implementation
uses POOLVARS, OVL34;
type
  { One text-scanline video plane: 100 scanline rows of 80 bytes. The second dimension fixes
    the row stride the compiler multiplies by ($50 in ClearWindow mode 0); the column index
    (LeftCol * BytesPerTextColumn, up to 158) intentionally addresses past it as flat memory. }
  TTextPlane = array[0..99, 0..79] of Byte;
  { One graphics video plane: 50 rows of 160 bytes (stride $A0 in ClearWindow mode 2). }
  TGraphPlane = array[0..49, 0..159] of Byte;
const
  TilesPerFrameSet = 3;       { DrawWindowFrame: corner, side and top tile per frame set }
  FirstFrameTile = $114;      { DrawWindowFrame: TileBase := FrameSet * TilesPerFrameSet + FirstFrameTile }
  TileCorner = 0;             { DrawWindowFrame: the four corners use TileBase + 0 }
  TileVertical = 1;           { DrawWindowFrame: the left/right edges use TileBase + 1 }
  TileHorizontal = 2;         { DrawWindowFrame: the top/bottom edges use TileBase + 2 }
  ScanlinesPerTextRow = 4;    { ClearWindow mode 0: each text row is 4 scanlines }
  LastTextScanline = 3;       { ClearWindow mode 0: BottomCode is the last scanline of BottomRow }
  BytesPerTextColumn = 2;     { ClearWindow mode 0: each text column is 2 bytes }
  GraphRowsPerTextRow = 2;    { ClearWindow mode 2: each text row is 2 graphics rows }
  LastGraphRow = 1;           { ClearWindow mode 2: BottomCode is the last graphics row of BottomRow }
  BytesPerGraphColumn = 4;    { ClearWindow mode 2: each text column is 4 bytes }
var
  { The video memory planes the fill modes of ClearWindow clear (evidence: the FillChar
    segment pushes in 03F1:0137): text planes over $B800/$BA00, graphics planes over
    $B800/$BA00/$BC00/$BE00. }
  VideoText0: TTextPlane absolute $B800:$0000;
  VideoText1: TTextPlane absolute $BA00:$0000;
  VideoGrf0: TGraphPlane absolute $B800:$0000;
  VideoGrf1: TGraphPlane absolute $BA00:$0000;
  VideoGrf2: TGraphPlane absolute $BC00:$0000;
  VideoGrf3: TGraphPlane absolute $BE00:$0000;

{ 03F1:0000. Draws the frame around a window: the four corner tiles
  (TileBase + TileCorner), the top and bottom edges (TileBase + TileHorizontal) and the
  left and right edges (TileBase + TileVertical), with TileBase from FrameSet. The frame
  extends one cell past the window on every side (Dec/Inc first), so the coordinates are
  ShortInt and can reach -1. Drawn through Put8x8Symbol; side effect: the screen. Called by
  DrawWindow. }
procedure DrawWindowFrame(LeftCol, TopRow, RightCol, BottomRow: ShortInt; FrameSet: Byte);
var
  Edge: ShortInt;             { loop position along the edge being drawn }
  TileBase: Word;             { first tile of the frame set: FrameSet * TilesPerFrameSet + FirstFrameTile }
begin
  Dec(LeftCol);
  Dec(TopRow);
  Inc(RightCol);
  Inc(BottomRow);
  TileBase := FrameSet * TilesPerFrameSet + FirstFrameTile;
  Put8x8Symbol(LeftCol, TopRow, TileBase + TileCorner, 0, 0);
  Put8x8Symbol(RightCol, TopRow, TileBase + TileCorner, 0, 0);
  Put8x8Symbol(LeftCol, BottomRow, TileBase + TileCorner, 0, 0);
  Put8x8Symbol(RightCol, BottomRow, TileBase + TileCorner, 0, 0);
  for Edge := LeftCol + 1 to RightCol - 1 do
  begin
    Put8x8Symbol(Edge, TopRow, TileBase + TileHorizontal, 0, 0);
    Put8x8Symbol(Edge, BottomRow, TileBase + TileHorizontal, 0, 0);
  end;
  for Edge := TopRow + 1 to BottomRow - 1 do
  begin
    Put8x8Symbol(LeftCol, Edge, TileBase + TileVertical, 0, 0);
    Put8x8Symbol(RightCol, Edge, TileBase + TileVertical, 0, 0);
  end;
end;
{ 03F1:0137. Clears the window rectangle LeftCol..RightCol by TopRow..BottomRow to 0, by
  video adapter (the VideoAdapter global): 0 fills two text-scanline planes (VideoText0/1),
  1 draws through FillPlaneRect twice, 2 fills four graphics planes (VideoGrf0..3).
  The coordinates are ShortInt (sign-extended to Integer); Row stays Word (the for-loop
  exit test is unsigned). Side effect: video memory. Called by DrawWindow. }
procedure ClearWindow(LeftCol, TopRow, RightCol, BottomRow: ShortInt);
var
  TopCode: Integer;           { first scanline (mode 0) or graphics row (mode 2) to clear }
  BottomCode: Integer;        { last scanline or graphics row to clear }
  LeftCode: Integer;          { first byte column to clear (mode 2 only) }
  Width: Integer;             { bytes to clear per scanline or graphics row }
  Row: Word;                  { the scanline or graphics row being cleared }
begin
  case VideoAdapter of
    0:
      begin
        TopCode := TopRow * ScanlinesPerTextRow;
        BottomCode := BottomRow * ScanlinesPerTextRow + LastTextScanline;
        Width := (RightCol - LeftCol + 1) * BytesPerTextColumn;
        for Row := TopCode to BottomCode do
        begin
          FillChar(VideoText0[Row, LeftCol * BytesPerTextColumn], Width, 0);
          FillChar(VideoText1[Row, LeftCol * BytesPerTextColumn], Width, 0);
        end;
      end;
    1:
      begin
        FillPlaneRect(LeftCol, TopRow, RightCol, BottomRow, 0, 0);
        FillPlaneRect(LeftCol, TopRow, RightCol, BottomRow, 1, 0);
      end;
    2:
      begin
        TopCode := TopRow * GraphRowsPerTextRow;
        BottomCode := BottomRow * GraphRowsPerTextRow + LastGraphRow;
        LeftCode := LeftCol * BytesPerGraphColumn;
        Width := (RightCol - LeftCol + 1) * BytesPerGraphColumn;
        for Row := TopCode to BottomCode do
        begin
          FillChar(VideoGrf0[Row, LeftCode], Width, 0);
          FillChar(VideoGrf1[Row, LeftCode], Width, 0);
          FillChar(VideoGrf2[Row, LeftCode], Width, 0);
          FillChar(VideoGrf3[Row, LeftCode], Width, 0);
        end;
      end;
  end;
end;
{ 03F1:02E8. Draws a titled window for dialogs and screens: clears it (ClearWindow), draws
  its frame (DrawWindowFrame) and centres Text on TopRow in colour TextColor
  (DrawTextAt, skipped when Text is empty). LeftCol/TopRow/RightCol/BottomRow are the
  window's text columns and rows; FrameSet selects the frame tiles. Text is a String40
  value parameter: the compiler copies it to a hidden stack temporary on entry (the
  StrLCopy at 02EE, limit $28), and Length and the 0626 call read that temporary
  ([bp-$29]). Side effect: the screen. Called from ovl01/02/03/04/05/06 and res12. }
procedure DrawWindow(LeftCol, TopRow, RightCol, BottomRow: ShortInt; FrameSet, TextColor: Byte;
  Text: String40);
begin
  ClearWindow(LeftCol, TopRow, RightCol, BottomRow);
  DrawWindowFrame(LeftCol, TopRow, RightCol, BottomRow, FrameSet);
  if Length(Text) <> 0 then
    DrawTextAt((LeftCol + RightCol - Length(Text)) div 2, TopRow, TextColor, Text);
end;

begin
end.

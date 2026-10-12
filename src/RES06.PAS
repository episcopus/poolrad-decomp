unit RES06;
{ Screen text output (whitepaper 5.15), partly decompiled: ShowMessageLine shows a message on the
  bottom line and waits for a key; the rest are stubs. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
type
  String40 = string[40];
procedure SetEgaFillRegisters;
procedure SetActivePage(Plane: Byte);
procedure SetPlaneSegment(Plane: Byte);
procedure FillPlaneRect(LeftCol, TopRow, RightCol, BotRow: ShortInt; Plane, Value: Byte);
procedure LoadGameFont;
procedure res06_fn_01DF(A, B, C, D, Glyph, F: Byte);
procedure res06_fn_05EB(A, Row, B, Width: Byte);
procedure res06_fn_0626(A, Row, Color: Byte; Text: string);
procedure res06_fn_06A7;
procedure res06_fn_0714;
procedure res06_fn_0768(A, B, C, D, E, F: Byte; Text: string);
function res06_fn_09E3(Prompt: string; A: Byte; MaxLen: Byte): string;
procedure res06_fn_0B66;
procedure ShowMessageLine(Color: Byte; Text: String40);
function GameClock: Longint;
procedure ClearFullScreen;
procedure res06_fn_0D68(Text: string; Color: Byte);
procedure DelayCounted;
procedure ClearRect(Left, Top, Right, Bottom: ShortInt);
implementation
uses Crt, Dos, POOLVARS, RES04, RES05;

type
  { One text-scanline video plane: 100 scanline rows of 80 bytes, like RES09's TTextPlane
    (res06 cannot use those names: res09 uses res06). ClearRect indexes [Row, Column]. }
  TTextPlane = array[0..99, 0..79] of Byte;
  { One graphics video plane: 50 rows of 160 bytes, like RES09's TGraphPlane. }
  TGraphPlane = array[0..49, 0..159] of Byte;
var
  { The EGA planes. The text and graphics views share the segments; they are the same
    memory RES09 maps as the VideoText/VideoGrf planes. }
  TextPlane0: TTextPlane absolute $B800:$0000;
  TextPlane1: TTextPlane absolute $BA00:$0000;
  GraphPlane0: TGraphPlane absolute $B800:$0000;
  GraphPlane1: TGraphPlane absolute $BA00:$0000;
  GraphPlane2: TGraphPlane absolute $BC00:$0000;
  GraphPlane3: TGraphPlane absolute $BE00:$0000;

{ 0709:0000: retf 0: 0 bytes of parameters; 0 bytes of locals }
{ 0709:0000. Sets the EGA Graphics Controller registers for the picture fill: GC 0..5 to 0
  (set/reset, enable set/reset, colour compare, data rotate, read map select, mode), GC 7 to
  $0F (colour don't care) and GC 8 to $FF (bit mask), then the Sequencer Map Mask (SC 2) to $0F.
  Port I/O only; no parameters. }
procedure SetEgaFillRegisters;
begin
  Port[$3CE] := 0;  Port[$3CF] := 0;
  Port[$3CE] := 1;  Port[$3CF] := 0;
  Port[$3CE] := 2;  Port[$3CF] := 0;
  Port[$3CE] := 3;  Port[$3CF] := 0;
  Port[$3CE] := 4;  Port[$3CF] := 0;
  Port[$3CE] := 5;  Port[$3CF] := 0;
  Port[$3CE] := 7;  Port[$3CF] := $0F;
  Port[$3CE] := 8;  Port[$3CF] := $FF;
  Port[$3C4] := 2;  Port[$3C5] := $0F;
end;
{ 0709:0071: retf 2: 2 bytes of parameters; 0 bytes of locals }
{ 0709:0071. Sets the EGA/VGA plane the video BIOS page A points at: writes AH=5 (set active
  display page) and AL=A into Regs and calls Intr($10), then stores the selected plane's segment
  (Plane shl 9 + $A000) in ds4A16. Called by res08_init. }
procedure SetActivePage(Plane: Byte);
begin
  Regs.AH := 5;
  Regs.AL := Plane;
  Intr($10, Regs);
  ds4A16 := Plane shl 9 + $A000;
end;
{ 0709:00A0: retf 2: 2 bytes of parameters; 0 bytes of locals }
{ 0709:00A0. Stores the EGA/VGA plane segment of Plane (Plane shl 9 + $A000) in ds4A18. Called by
  FillPlaneRect and res08_init. }
procedure SetPlaneSegment(Plane: Byte);
begin
  ds4A18 := Plane shl 9 + $A000;
end;
{ 0709:00B7: retf 12: 12 bytes of parameters; 10 bytes of locals }
{ 0709:00B7. Fills a rectangle on one EGA plane: byte columns LeftCol..RightCol and cell rows
  TopRow..BotRow (8 scanlines each), on Plane with the byte Value. It saves the current plane
  ds4A1A, points SetPlaneSegment(Plane) at the fill plane, sets the EGA registers
  (SetEgaFillRegisters, GC index 5 to 2), fills scanline by scanline with
  FillChar(Mem[ds4A18:DestOff], RightCol - LeftCol + 1, Value) stepping DestOff by 40, then
  restores GC index 5 to 0, ds4A1A and its plane segment. The Word/LongInt casts keep
  the TopRow * 40 * 8 offset math unsigned. Called by ClearFullScreen, ClearRect and
  ClearWindow. }
procedure FillPlaneRect(LeftCol, TopRow, RightCol, BotRow: ShortInt; Plane, Value: Byte);
var
  SavedPlane: Byte;             { ds4A1A on entry, restored before returning }
  DestOff: Word;                { the EGA offset, +40 per scanline }
  ScanLast: Word;               { (BotRow - TopRow + 1) * 8 - 1: the last scanline index }
  Scan: Word;                   { the scanline index }
begin
  SavedPlane := ds4A1A;
  DestOff := Word(TopRow) * 40 * 8 + LongInt(LeftCol);
  ScanLast := (BotRow - TopRow + 1) * 8 - 1;
  SetPlaneSegment(Plane);
  SetEgaFillRegisters;
  Port[$3CE] := 5;
  Port[$3CF] := 2;
  for Scan := 0 to ScanLast do
  begin
    FillChar(Mem[ds4A18:DestOff], RightCol - LeftCol + 1, Value);
    Inc(DestOff, $28);
  end;
  Port[$3CE] := 5;
  Port[$3CF] := 0;
  ds4A1A := SavedPlane;
  SetPlaneSegment(ds4A1A);
end;
{ 0709:017C. Loads the game's 1-bit font: DAX block 201 ($C9) of 8X8D1.DAX (177 glyphs
  of 8 bytes each) into the GameFont heap block, then frees the DAX buffer. Called once by
  StartGame after it allocates GameFont. Exits at once when the block is missing (size 0).
  Side effects: the heap and the disk through LoadDaxBlock. }
procedure LoadGameFont;
const
  FontBlockId = $C9;      { block 201 of 8X8D1.DAX: the 1-bit font (whitepaper 4.x) }
var
  BlockSize: Word;        { unpacked size LoadDaxBlock returns; 0 when the block is missing }
  Block: Pointer;         { the DAX buffer LoadDaxBlock allocates; freed after the copy }
begin
  LoadDaxBlock('8X8d1', '.dax', FontBlockId, BlockSize, Block);
  if BlockSize = 0 then Exit;
  Move(Block^, GameFont^, BlockSize);
  FreeMem(Block, BlockSize);
end;
{ 0709:01DF: retf 12: 12 bytes of parameters; 18 bytes of locals.
  Draws one rune glyph of the code wheel question as a font character (CheckCodeWheel passes the rune
  index + $40): A and B the screen position, Glyph the character, the rest still open. }
{@stub} procedure res06_fn_01DF(A, B, C, D, Glyph, F: Byte); begin end;
{ 0709:05EB: retf 8: 8 bytes of parameters; 0 bytes of locals }
{ 0709:05EB. Clears (or fills) Width cells of a row: when the column Width is in 0..$27 and the
  row B is in 0..$18 it calls res06_fn_01DF(Width, B, Row, A, $20, 1). BLOCKED (dec-5,
  2026-10-12): the body is settled as two set membership tests, `if not (Width in [0..$27]) then
  Exit; if not (B in [0..$18]) then Exit; ...` (the never-true lower-bound compares and the Exit
  block come from the set), but the routine does not match because a literal-pool byte 64 before the
  entry differs (ours FF, original F8): the pool belongs to the preceding res06_fn_01DF, still a
  stub, so decompile 01DF first. Called by ovl21_e6, ovl25_e3, res06_fn_09E3, ShowMessageLine and
  res06_fn_0D68. }
{@stub} procedure res06_fn_05EB(A, Row, B, Width: Byte); begin end;
{ 0709:0626: retf 10: 10 bytes of parameters; 260 bytes of locals }
{@stub} procedure res06_fn_0626(A, Row, Color: Byte; Text: string); begin end;
{ 0709:06A7: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_06A7; begin end;
{ 0709:0714: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0714; begin end;
{ 0709:0768: retf 16; six bytes and a string; ovl04 passes (1, $11, $26, $16, $A, 1, message). }
{@stub} procedure res06_fn_0768(A, B, C, D, E, F: Byte; Text: string); begin end;
{ 0709:09E3: retf 8: 8 bytes of parameters; 812 bytes of locals.
  The line reader: shows the Prompt and returns what the player types as its string result
  (the caller keeps the result pointer: retf 8 pops Prompt, A and B only). CheckCodeWheel asks for the
  code word with it. }
{@stub} function res06_fn_09E3(Prompt: string; A: Byte; MaxLen: Byte): string; begin end;
{ 0709:0B66: retf 6: 6 bytes of parameters; 346 bytes of locals }
{@stub} procedure res06_fn_0B66; begin end;
{ 0709:0BF5: show a one-line message on row 24 and wait for a key (whitepaper 5.15). }
procedure ShowMessageLine(Color: Byte; Text: String40);
var
  Key: Char;
begin
  res06_fn_05EB(0, 24, 0, 40);
  res06_fn_0626(0, 24, Color, Text);
  Key := ReadGameKey;
end;
{ 0709:0C3F. The game clock in hundredths of a second: reads the DOS time (GetTime) and returns
  Hour * 360000 + Minute * 6000 + Second * 100 + Sec100. Hour * 360000 is a LongInt multiply,
  Minute * 6000 and Second * 100 are Word multiplies (the high word of the product is dropped,
  QUIRK 0709:0C75, 0709:0C85). Called by WaitKeyOrTimeout, ShowTitleScreen, AnimateFinalPicture and
  ovl25_e2. }
function GameClock: Longint;
var
  Hour, Minute, Second, Sec100: Word;
begin
  GetTime(Hour, Minute, Second, Sec100);
  GameClock := Hour * 360000 + Minute * 6000 + Second * 100 + Sec100;
end;
{ 0709:0CAB. Clears the whole screen to 0 by video adapter (the VideoAdapter global):
  0 fills the two text-scanline planes ($BA00 then $B800, one plane each), 1 draws the full
  40 by 25 cell screen through FillPlaneRect on planes 0 and 1, 2 fills the four graphics
  planes ($B800/$BA00/$BC00/$BE00). Called by ovl19. }
procedure ClearFullScreen;
const
  PlaneBytes = $1F40;  { one EGA plane in bytes }
  LastCol = $27;       { rightmost byte column of the 40-column screen }
  LastRow = $18;       { bottom cell row of the 25-row screen }
begin
  case VideoAdapter of
    0:
      begin
        FillChar(TextPlane1, PlaneBytes, 0);
        FillChar(TextPlane0, PlaneBytes, 0);
      end;
    1:
      begin
        FillPlaneRect(0, 0, LastCol, LastRow, 0, 0);
        FillPlaneRect(0, 0, LastCol, LastRow, 1, 0);
      end;
    2:
      begin
        FillChar(GraphPlane0, PlaneBytes, 0);
        FillChar(GraphPlane1, PlaneBytes, 0);
        FillChar(GraphPlane2, PlaneBytes, 0);
        FillChar(GraphPlane3, PlaneBytes, 0);
      end;
  end;
end;
{ 0709:0D68: retf 6: 6 bytes of parameters; 42 bytes of locals.
  Shows the Text and waits: CheckCodeWheel passes the failure message of a wrong code word and the
  colour 14. }
{ 0709:0D68. BLOCKED (dec-5, 2026-10-12): shows Text on the bottom line in colour Color
  (res06_fn_05EB clears the row, res06_fn_0626 shows the text, DelayCounted waits, res06_fn_05EB
  clears again). Our frame is 256 bytes too big (a string temp our source creates), so it is left
  a stub. }
{@stub} procedure res06_fn_0D68(Text: string; Color: Byte); begin end;
{ 0709:0DBE: retf 0: 0 bytes of parameters; 0 bytes of locals }
{ 0709:0DBE. A delay of ds49E2 * 225 milliseconds (Crt.Delay). No parameters. Called while
  drawing many screens (ovl03, ovl10, ovl12, ovl13, ovl18, ovl19, ovl20). }
procedure DelayCounted;
begin
  Delay(ds49E2 * 225);
end;
{ 0709:0DD3. Clears the Left..Right by Top..Bottom rectangle to 0 by video adapter (the
  VideoAdapter global), the Byte-coordinate twin of ClearWindow: 0 fills the text-scanline
  rows Top*4..Bottom*4+3 on both planes, 1 draws the rectangle through FillPlaneRect on
  planes 0 and 1, 2 fills the graphics rows Top*2..Bottom*2+1 on all four planes. Called by
  the menu screens (HealMenu, VisitTemple, ShopMain), ShowEndingNarrative and others.
  Side effect: video memory. }
procedure ClearRect(Left, Top, Right, Bottom: ShortInt);
const
  ScanlinesPerTextRow = 4;  { each text row is 4 scanlines }
  LastTextScanline = 3;     { BottomCode is the last scanline of Bottom }
  BytesPerTextColumn = 2;   { each text column is 2 bytes }
  GraphRowsPerTextRow = 2;  { each text row is 2 graphics rows }
  LastGraphRow = 1;         { BottomCode is the last graphics row of Bottom }
  BytesPerGraphColumn = 4;  { each text column is 4 bytes }
var
  TopCode: Integer;         { first scanline (mode 0) or graphics row (mode 2) to clear }
  BottomCode: Integer;      { last scanline or graphics row to clear }
  LeftCode: Integer;        { first byte column to clear (mode 2 only) }
  Width: Integer;           { bytes to clear per scanline or graphics row }
  Row: Word;                { the scanline or graphics row being cleared }
begin
  case VideoAdapter of
    0:
      begin
        TopCode := Top * ScanlinesPerTextRow;
        BottomCode := Bottom * ScanlinesPerTextRow + LastTextScanline;
        Width := (Right - Left + 1) * BytesPerTextColumn;
        for Row := TopCode to BottomCode do
        begin
          FillChar(TextPlane0[Row, Left * BytesPerTextColumn], Width, 0);
          FillChar(TextPlane1[Row, Left * BytesPerTextColumn], Width, 0);
        end;
      end;
    1:
      begin
        FillPlaneRect(Left, Top, Right, Bottom, 0, 0);
        FillPlaneRect(Left, Top, Right, Bottom, 1, 0);
      end;
    2:
      begin
        TopCode := Top * GraphRowsPerTextRow;
        BottomCode := Bottom * GraphRowsPerTextRow + LastGraphRow;
        LeftCode := Left * BytesPerGraphColumn;
        Width := (Right - Left + 1) * BytesPerGraphColumn;
        for Row := TopCode to BottomCode do
        begin
          FillChar(GraphPlane0[Row, LeftCode], Width, 0);
          FillChar(GraphPlane1[Row, LeftCode], Width, 0);
          FillChar(GraphPlane2[Row, LeftCode], Width, 0);
          FillChar(GraphPlane3[Row, LeftCode], Width, 0);
        end;
      end;
  end;
end;

begin
end.

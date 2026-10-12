unit RES06;
{ Screen text output (whitepaper 5.15): the 8 by 8 font (LoadGameFont, DrawGlyph), text on cells
  (ClearTextCells, DrawTextAt), the bottom message line (ShowMessageLine, FlashMessageLine), the
  line editor (ReadInputLine, ReadNumber), screen clearing and the game clock. ShowPagedText, the
  word-wrapping pager, is still a stub (held: nested routines). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
type
  String40 = string[40];
procedure SetEgaFillRegisters;
procedure SetActivePage(Plane: Byte);
procedure SetPlaneSegment(Plane: Byte);
procedure FillPlaneRect(LeftCol, TopRow, RightCol, BotRow: ShortInt; Plane, Value: Byte);
procedure LoadGameFont;
procedure DrawGlyph(Col, Row, Color, Count, Glyph, Cook: Byte);
procedure ClearTextCells(Col, Row, Color, Count: Byte);
procedure DrawTextAt(Col, Row, Color: Byte; Text: string);
procedure ShowPagedText(Left, Top, Right, Bottom, Color, ClearFirst: Byte; Text: string);
function ReadInputLine(Prompt: String40; Color: Byte; MaxLen: Byte): String40;
function ReadNumber(Prompt: String40; Color: Byte): Word;
procedure ShowMessageLine(Color: Byte; Text: String40);
function GameClock: Longint;
procedure ClearFullScreen;
procedure FlashMessageLine(Text: String40; Color: Byte);
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
  { One text-scanline plane as words: 200 rows of 40 words. DrawGlyph mode 0 writes one
    assembled 16-bit pixel row per scanline through it (2-D indexing keeps the $50 row
    stride the compiler multiplies by, proven by a make tpc probe). }
  TWordPlane = array[0..199, 0..39] of Word;
  { The game font in the GameFont block: 8 bytes per glyph, one per pixel row, the top bit the
    leftmost pixel. DrawGlyph indexes it [Glyph, Row] (2-D: the row is added after the glyph
    offset, 0709:027C..028E). 177 glyphs fill the $588-byte block. }
  TFont = array[0..176, 0..7] of Byte;
  PFont = ^TFont;
var
  { The EGA planes. The text and graphics views share the segments; they are the same
    memory RES09 maps as the VideoText/VideoGrf planes. }
  TextPlane0: TTextPlane absolute $B800:$0000;
  TextPlane1: TTextPlane absolute $BA00:$0000;
  GraphPlane0: TGraphPlane absolute $B800:$0000;
  GraphPlane1: TGraphPlane absolute $BA00:$0000;
  GraphPlane2: TGraphPlane absolute $BC00:$0000;
  GraphPlane3: TGraphPlane absolute $BE00:$0000;
  { The text planes as words, same memory as TextPlane0/1 above. }
  WordPlane0: TWordPlane absolute $B800:$0000;
  WordPlane1: TWordPlane absolute $BA00:$0000;

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
{ 0709:01DF. Draws Count copies of the GameFont glyph Glyph from cell Col rightwards on
  text row Row in Color, one per outer iteration (Col advances). Cook nonzero cooks Glyph
  through UpCase into 0..63, else the raw byte indexes the font. By VideoAdapter: 0 writes
  the 8 font rows as byte-swapped 16-bit pixel rows to the two text-scanline planes
  (even rows to $B800, odd rows to $BA00, 4 scanlines per text row); 1 writes the 8 font
  bytes to the two EGA pages through the Sequencer Map Mask (masks from EgaPlaneMasks, colour
  gating); 2 builds two colour nibbles per font-bit pair and writes them to all four
  graphics planes (2 rows per text row, 4 bytes per column). Exits at once for
  out-of-range cells, a nil GameFont, or Count 0. Glyph stays Byte in the
  signature because ovl02 passes Integer expressions (changing it to Char would break its
  four matched call sites); the Ord(Chr()) bridges compile to nothing (proven by tpc
  probes) and are revisited when DrawGlyph itself is reviewed. Side effect: video memory.
  Called by CheckCodeWheel, ovl03, ovl25, ClearTextCells, DrawTextAt and DrawTextRun. }
procedure DrawGlyph(Col, Row, Color, Count, Glyph, Cook: Byte);
const
  MaxCol = $27;         { widest cell column }
  MaxRow = $18;         { deepest text row }
  CookedGlyphMod = $40; { cooked glyph index wraps into 0..63 }
  TopBit = $80;         { starting font-bit mask }
  GraphStride = $28;    { bytes per scanline in the 320-wide graphics plane }
  MapMaskRestore = $0F; { Sequencer Map Mask value restored after mode 1 }
var
  I: Byte;              { outer copy counter, 1..Count }
  Index: Byte;          { GameFont glyph index: Glyph raw, or cooked }
  DestOff: Word;        { dest scanline (mode 0) or pixel offset (mode 1); font row (mode 2) }
  FontRow: Word;        { font row (mode 0); dest graph row (mode 2) }
  ColBase: Word;        { A*4 byte column base (mode 2) }
  Acc: Word;            { assembled 16-bit pixel row (mode 0) }
  Pix: Byte;            { two colour nibbles (mode 2) }
  Bit: Byte;            { bit/column counter: 0..7 (mode 0) or 0..3 }
  Mask: Byte;           { font bit mask, $80 shrank per bit (modes 0 and 2) }
  Plane: Byte;          { graphics plane 0..3 (mode 2) }
  Line: Byte;           { row counter: 0..3 (mode 0), 0..7 (mode 1), 0..1 (mode 2) }
  Unused: Byte;         { never referenced; the original frame has this byte before the for limit }
begin
  if (Col > MaxCol) or (Row > MaxRow) or (GameFont = nil) then Exit;
  if Cook <> 0 then
    Index := Ord(UpCase(Chr(Glyph))) mod CookedGlyphMod
  else
    Index := Glyph;
  for I := 1 to Count do
  begin
  case VideoAdapter of
      0:
        begin
          Color := ds25D5[Color];
          DestOff := Row * 4;
          FontRow := 0;
          for Line := 0 to 3 do
          begin
            Acc := 0;
            Mask := TopBit;
            for Bit := 0 to 7 do
            begin
              if PFont(GameFont)^[Index, FontRow] and Mask > 0 then
                Acc := Acc or (GlyphPixelMasks[Bit] and GlyphColorPatterns[Color]);
              Mask := Mask shr 1;
            end;
            WordPlane0[DestOff, Col] := Swap(Acc);
            Inc(FontRow);
            Acc := 0;
            Mask := TopBit;
            for Bit := 0 to 7 do
            begin
              if PFont(GameFont)^[Index, FontRow] and Mask > 0 then
                Acc := Acc or (GlyphPixelMasks[Bit] and GlyphColorPatterns[Color]);
              Mask := Mask shr 1;
            end;
            WordPlane1[DestOff, Col] := Swap(Acc);
            Inc(FontRow);
            Inc(DestOff);
          end;
        end;
      1:
        begin
          DestOff := Row * 8 * GraphStride + Col;
          Port[$3C4] := 2;
          for Line := 0 to 7 do
          begin
            for Bit := 0 to 3 do
            begin
              Port[$3C5] := EgaPlaneMasks[3 - Bit];
              if (EgaPlaneMasks[3 - Bit] and Color) > 0 then
              begin
                Mem[ds4A16:DestOff] := PFont(GameFont)^[Index, Line];
                Mem[ds4A18:DestOff] := PFont(GameFont)^[Index, Line];
              end
              else
              begin
                Mem[ds4A16:DestOff] := 0;
                Mem[ds4A18:DestOff] := 0;
              end;
            end;
            Inc(DestOff, GraphStride);
          end;
          Port[$3C5] := MapMaskRestore;
        end;
      2:
        begin
          DestOff := 0;
          FontRow := Row * 2;
          ColBase := Col * 4;
          for Line := 0 to 1 do
          begin
            for Plane := 0 to 3 do
            begin
              Mask := TopBit;
              for Bit := 0 to 3 do
              begin
                if PFont(GameFont)^[Index, DestOff] and Mask > 0 then
                  Pix := Color shl 4
                else
                  Pix := 0;
                Mask := Mask shr 1;
                if PFont(GameFont)^[Index, DestOff] and Mask > 0 then
                  Pix := Pix or Color;
                Mask := Mask shr 1;
                case Plane of
                  0: GraphPlane0[FontRow, Bit + ColBase] := Pix;
                  1: GraphPlane1[FontRow, Bit + ColBase] := Pix;
                  2: GraphPlane2[FontRow, Bit + ColBase] := Pix;
                  3: GraphPlane3[FontRow, Bit + ColBase] := Pix;
                end;
              end;
              Inc(DestOff);
            end;
            Inc(FontRow);
          end;
        end;
    end;
    Inc(Col);
  end;
end;
{ 0709:05EB. Draws Count space glyphs (GlyphSpace) in Color from cell Col of text row Row, that
  is, clears Count cells of a row to the background; nothing when the cell is off the 40 by 25
  screen. QUIRK 0709:05EE, 05FA: the Byte parameters are also compared below 0, which is never
  true; the compiler keeps the compares. Called by
  ovl21_e6, ovl25_e3, ReadInputLine, ShowMessageLine (row 24, 40 cells) and FlashMessageLine. }
procedure ClearTextCells(Col, Row, Color, Count: Byte);
const
  GlyphSpace = $20;
begin
  if (Col < 0) or (Col > $27) or (Row < 0) or (Row > $18) then Exit;
  DrawGlyph(Col, Row, Color, Count, GlyphSpace, 1);
end;
{ 0709:0626. Draws Text in Color from cell Col of text row Row, one DrawGlyph per character
  (cooked through UpCase into the 64-glyph text set), advancing Col; nothing when Col is past
  column 39. QUIRK 0709:0647: Row is also tested against 39, not 24; DrawGlyph then skips rows
  past 24, and characters past column 39. Called
  by ShowMessageLine (row 24), ShowCredits, CheckCodeWheel, StartGame and many menus. }
procedure DrawTextAt(Col, Row, Color: Byte; Text: string);
var
  Len, I: Byte;
begin
  if (Col > $27) or (Row > $27) then Exit;
  Len := Length(Text);
  for I := 1 to Len do
  begin
    DrawGlyph(Col, Row, Color, 1, Ord(Text[I]), 1);
    Inc(Col);
  end;
end;
{ 0709:0768: retf 16; six bytes and a string; ovl04 passes (1, $11, $26, $16, $A, 1, message). }
{ DRAFT STASHED (dec-1): full ShowPagedText with nested DrawTextRun/SkipSpaces is in
  scratch/SHOWPAGEDTEXT.DRAFT.PAS and matches except the nested pool bytes (escalated:
  nested code with globals/calls needs address-aware pool compare). }
{@stub} procedure ShowPagedText(Left, Top, Right, Bottom, Color, ClearFirst: Byte; Text: string); begin end;
{ 0709:09E3. The line reader: shows Prompt in Color on the bottom line (row 24) and lets the
  player type up to MaxLen characters after it, echoed in white: ' '..'z' are added, Backspace
  removes the last one; Enter or Esc ends. Returns the line in upper case (Esc returns what was
  typed too). The row is cleared at the end. CheckCodeWheel asks for the code word with it. }
function ReadInputLine(Prompt: String40; Color: Byte; MaxLen: Byte): String40;
const
  BottomRow = 24;
  ScreenCols = 40;
  EchoColor = 15;           { white }
  KeyBackspace = #8;
  KeyEnter = #13;
  KeyEsc = #27;
var
  Col: Byte;                { screen column of the last character shown }
  Line: string;
  Key: Char;
begin
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Prompt);
  Col := Length(Prompt);
  Line := '';
  repeat
    Key := ReadGameKey;
    case Key of
      ' '..'z':
        if Length(Line) < MaxLen then
        begin
          Line := Line + Key;
          Inc(Col);
          DrawTextAt(Col, BottomRow, EchoColor, Key);
        end;
      KeyBackspace:
        if Length(Line) > 0 then
        begin
          Line := Copy(Line, 1, Length(Line) - 1);
          ClearTextCells(Col, BottomRow, 0, 1);
          Dec(Col);
        end;
    end;
  until (Key = KeyEnter) or (Key = KeyEsc);
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  for Col := 1 to Length(Line) do
    Line[Col] := UpCase(Line[Col]);
  ReadInputLine := Line;
end;
{ 0709:0B66. Asks for a number on the bottom line: reads up to 6 characters with
  ReadInputLine (Prompt in Color) until Val accepts them as a number from 0 to 65536, and
  returns it as a Word. QUIRK 0709:0BBF: 65536 itself is accepted and returns 0. Called by
  ovl03_fn_0951. }
function ReadNumber(Prompt: String40; Color: Byte): Word;
const
  MaxDigits = 6;
var
  Value: Longint;
  Answer: String40;
  Code: Integer;
begin
  repeat
    Answer := ReadInputLine(Prompt, Color, MaxDigits);
    Val(Answer, Value, Code);
    if (Code = 0) and ((Value > 65536) or (Value < 0)) then
      Code := 1;
  until Code = 0;
  ReadNumber := Value;
end;
{ 0709:0BF5: show a one-line message on row 24 and wait for a key (whitepaper 5.15). }
procedure ShowMessageLine(Color: Byte; Text: String40);
var
  Key: Char;
begin
  ClearTextCells(0, 24, 0, 40);
  DrawTextAt(0, 24, Color, Text);
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
{ 0709:0D68. Shows Text in Color on the bottom line (row 24) for a moment: clears the row
  (ClearTextCells), writes the text (DrawTextAt), waits DelayCounted and clears the row again;
  no key is waited for, unlike ShowMessageLine. CheckCodeWheel shows a wrong code word with it,
  ovl14 'Not Here' and the river's stench, in colour 14. }
procedure FlashMessageLine(Text: String40; Color: Byte);
const
  BottomRow = 24;
  ScreenCols = 40;
begin
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Text);
  DelayCounted;
  ClearTextCells(0, BottomRow, 0, ScreenCols);
end;
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

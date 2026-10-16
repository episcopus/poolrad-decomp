unit RES06;
{ Screen text output (whitepaper 5.15): the 8 by 8 font (LoadGameFont, DrawGlyph), text on cells
  (ClearTextCells, DrawTextAt), the bottom message line (ShowMessageLine, FlashMessageLine), the
  line editor (ReadInputLine, ReadNumber), the word-wrapping pager (ShowPagedText, with its nested
  DrawTextRun and SkipSpaces), screen clearing and the game clock. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
type
  String40 = string[40];
procedure SetEgaFillRegisters;
procedure SetActivePage(Page: Byte);
procedure SetPageSegment(Page: Byte);
procedure FillPlaneRect(LeftCol, TopRow, RightCol, BotRow: ShortInt; Page, Value: Byte);
procedure LoadGameFont;
procedure DrawGlyph(Col, Row, Color, Count, Glyph, TextSet: Byte);
procedure ClearTextCells(Col, Row, Color, Count: Byte);
procedure DrawTextAt(Col, Row, Color: Byte; Text: string);
procedure ShowPagedText(Left, Top, Right, Bottom, Color, ClearFirst: Byte; Text: string);
function ReadInputLine(Prompt: String40; Color: Byte; MaxLen: Byte): String40;
function ReadNumber(Prompt: String40; Color: Byte): Word;
procedure ShowMessageLine(Color: Byte; Text: String40);
function GameClock: Longint;
procedure ClearFullScreen;
procedure FlashMessageLine(Text: String40; Color: Byte);
procedure DelayByGameSpeed;
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
const
  LastCol = $27;                 { rightmost cell column of the 40-column screen }
  LastRow = $18;                 { deepest cell row of the 25-row screen }
  BottomRow = 24;                { the bottom message row }
  ScreenCols = 40;               { cells per screen row }
  GlyphSpace = $20;              { the space glyph ClearTextCells fills with }
  GcIndex = $3CE;                { EGA Graphics Controller index port }
  GcData = $3CF;                 { EGA Graphics Controller data port }
  SeqIndex = $3C4;               { EGA Sequencer index port }
  SeqData = $3C5;                { EGA Sequencer data port }
  GcMode = 5;                    { GC register 5: mode }
  WriteMode2 = 2;                { mode 2: the CPU data is the colour }
  GcBitMask = 8;                 { GC register 8: bit mask }
  SeqMapMask = 2;                { SC register 2: the plane map mask }
  MapMaskAll = $0F;              { all four planes enabled }
var
  { The planes below are the CGA/Tandy video memory (VideoAdapter 0 and 2): the scanline banks
    $B800, $BA00 and, for the graphics planes, $BC00 and $BE00. DrawGlyph modes 0 and 2 and
    ClearFullScreen/ClearRect fill them directly; RES09 maps the same memory as its VideoText and
    VideoGrf planes. The EGA display pages (VideoAdapter 1) are a different memory: page 0 at
    $A000 and page 1 at $A200 (Page shl 9 + $A000; the add at 0709:0096 and 0709:00AD). In this
    unit they are reached only through ActivePageSegment (SetActivePage) and FillPageSegment (SetPageSegment), never
    through the planes above. RES07 writes $A000 and $A200 directly (0464:1951, 0464:1B52). }
  TextPlane0: TTextPlane absolute $B800:$0000;
  TextPlane1: TTextPlane absolute $BA00:$0000;
  GraphPlane0: TGraphPlane absolute $B800:$0000;
  GraphPlane1: TGraphPlane absolute $BA00:$0000;
  GraphPlane2: TGraphPlane absolute $BC00:$0000;
  GraphPlane3: TGraphPlane absolute $BE00:$0000;
  { The text planes as words, same memory as TextPlane0/1 above. }
  WordPlane0: TWordPlane absolute $B800:$0000;
  WordPlane1: TWordPlane absolute $BA00:$0000;

{ 0709:0000. Sets the EGA Graphics Controller registers for the picture fill: GC 0..5 to 0
  (set/reset, enable set/reset, colour compare, data rotate, read map select, mode), GC 7 to
  $0F (colour don't care) and GC 8 to $FF (bit mask), then the Sequencer Map Mask (SC 2) to
  MapMaskAll. Port I/O only; no parameters. }
procedure SetEgaFillRegisters;
begin
  Port[GcIndex] := 0;  Port[GcData] := 0;
  Port[GcIndex] := 1;  Port[GcData] := 0;
  Port[GcIndex] := 2;  Port[GcData] := 0;
  Port[GcIndex] := 3;  Port[GcData] := 0;
  Port[GcIndex] := 4;  Port[GcData] := 0;
  Port[GcIndex] := GcMode;  Port[GcData] := 0;
  Port[GcIndex] := 7;  Port[GcData] := $0F;
  Port[GcIndex] := GcBitMask;  Port[GcData] := $FF;
  Port[SeqIndex] := SeqMapMask;  Port[SeqData] := MapMaskAll;
end;
{ 0709:0071. Selects display page Page through the video BIOS: writes AH=5 (INT 10h set active
  display page) and AL=Page into Regs, calls Intr($10), then stores the page's segment
  (Page shl 9 + $A000; one $200-paragraph page) in ActivePageSegment. Called by res08_init. }
procedure SetActivePage(Page: Byte);
begin
  Regs.AH := 5;
  Regs.AL := Page;
  Intr($10, Regs);
  ActivePageSegment := Page shl 9 + $A000;
end;
{ 0709:00A0. Stores the segment of display page Page (Page shl 9 + $A000) in FillPageSegment: the page
  the rectangle fill writes through. Called by FillPlaneRect and res08_init. }
procedure SetPageSegment(Page: Byte);
begin
  FillPageSegment := Page shl 9 + $A000;
end;
{ 0709:00B7. Fills a rectangle on one display page: byte columns LeftCol..RightCol and cell rows
  TopRow..BotRow (8 scanlines each), on page Page with the byte Value. It saves the current page
  FillTextPage, points SetPageSegment(Page) at the fill page, sets the EGA registers
  (SetEgaFillRegisters, then the GC mode register to write mode 2), fills scanline by scanline
  with FillChar(Mem[FillPageSegment:DestOff], RightCol - LeftCol + 1, Value) stepping DestOff by 40, then
  restores the GC mode to 0, FillTextPage and its page segment. The Word/LongInt casts keep
  the TopRow * 40 * 8 offset math unsigned. Called by ClearFullScreen, ClearRect and
  ClearWindow. }
procedure FillPlaneRect(LeftCol, TopRow, RightCol, BotRow: ShortInt; Page, Value: Byte);
var
  SavedPage: Byte;              { FillTextPage on entry, restored before returning }
  DestOff: Word;                { the page offset, +40 per scanline }
  ScanLast: Word;               { (BotRow - TopRow + 1) * 8 - 1: the last scanline index }
  Scan: Word;                   { the scanline index }
begin
  SavedPage := FillTextPage;
  DestOff := Word(TopRow) * 40 * 8 + LongInt(LeftCol);
  ScanLast := (BotRow - TopRow + 1) * 8 - 1;
  SetPageSegment(Page);
  SetEgaFillRegisters;
  Port[GcIndex] := GcMode;
  Port[GcData] := WriteMode2;
  for Scan := 0 to ScanLast do
  begin
    FillChar(Mem[FillPageSegment:DestOff], RightCol - LeftCol + 1, Value);
    Inc(DestOff, $28);
  end;
  Port[GcIndex] := GcMode;
  Port[GcData] := 0;
  FillTextPage := SavedPage;
  SetPageSegment(FillTextPage);
end;
{ 0709:017C. Loads the game's 1-bit font: DAX block 201 ($C9) of 8X8D1.DAX (177 glyphs
  of 8 bytes each) into the GameFont heap block, then frees the DAX buffer. Called once by
  StartGame after it allocates GameFont. Exits at once when the block is missing (size 0).
  Side effects: the heap and the disk through LoadDaxBlock. }
procedure LoadGameFont;
const
  FontBlockId = $C9;      { block 201 of 8X8D1.DAX: the 1-bit font, 177 glyphs of 8 bytes
                              (whitepaper 4.2.3 and 5.15) }
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
  text row Row in Color, one per outer iteration (Col advances). TextSet nonzero cooks Glyph
  through UpCase into the 64-glyph text set (mod 64), else the raw byte indexes the font.
  By VideoAdapter: 0 writes the 8 font rows as byte-swapped 16-bit pixel rows to the two
  text-scanline banks (even scanlines to $B800, odd to $BA00, 4 scanlines per text row);
  1 writes the 8 font bytes to the two EGA display pages (ActivePageSegment/FillPageSegment) through the
  Sequencer Map Mask (masks from EgaPlaneMasks, colour gating); 2 builds two colour nibbles
  per font-bit pair and writes them to all four graphics banks (2 rows per text row, 4 bytes
  per column). Exits at once for out-of-range cells, a nil GameFont, or Count 0. Glyph stays
  Byte in the signature because ovl02 passes Integer expressions and the constant 1 for TextSet
  (a Char or Boolean parameter would not accept those); the Ord(Chr()) bridges compile to
  nothing (proven by tpc probes). QUIRK 0709:021A: with TextSet 0 a Glyph above 176 reads past
  the 177-glyph font block (range checks are off). Side effect: video memory.
  Called by CheckCodeWheel, ovl03, ovl25, ClearTextCells, DrawTextAt and DrawTextRun. }
procedure DrawGlyph(Col, Row, Color, Count, Glyph, TextSet: Byte);
const
  CookedGlyphMod = $40; { cooked glyph index wraps into 0..63 }
  TopBit = $80;         { starting font-bit mask }
  GraphStride = $28;    { bytes per scanline in the 320-wide graphics plane }
  MapMaskRestore = $0F; { Sequencer Map Mask value restored after mode 1 }
var
  I: Byte;              { outer copy counter, 1..Count }
  Index: Byte;          { GameFont glyph index: Glyph raw, or cooked }
  DestOff: Word;        { dest scanline (mode 0) or pixel offset (mode 1); mode 2: the font row
                          (the names of this pair are the original's, see QUIRK 0709:047B) }
  FontRow: Word;        { font row (mode 0); mode 2: the graph row (see QUIRK 0709:047B) }
  ColBase: Word;        { byte column base: Col * 4 (mode 2) }
  Acc: Word;            { assembled 16-bit pixel row (mode 0) }
  Pix: Byte;            { two colour nibbles (mode 2) }
  Bit: Byte;            { bit/column counter: 0..7 (mode 0) or 0..3 }
  Mask: Byte;           { font bit mask, $80 shrank per bit (modes 0 and 2) }
  Bank: Byte;           { graphics bank 0..3 (mode 2) }
  Line: Byte;           { row counter: 0..3 (mode 0), 0..7 (mode 1), 0..1 (mode 2) }
  Unused: Byte;         { never referenced; the original frame has this byte before the for limit }
begin
  if (Col > LastCol) or (Row > LastRow) or (GameFont = nil) then Exit;
  if TextSet <> 0 then
    Index := Ord(UpCase(Chr(Glyph))) mod CookedGlyphMod
  else
    Index := Glyph;
  for I := 1 to Count do
  begin
    case VideoAdapter of
      0:
        begin
          Color := TextColourMap4[Color];
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
          Port[SeqIndex] := SeqMapMask;
          for Line := 0 to 7 do
          begin
            for Bit := 0 to 3 do
            begin
              Port[SeqData] := EgaPlaneMasks[3 - Bit];
              if (EgaPlaneMasks[3 - Bit] and Color) > 0 then
              begin
                Mem[ActivePageSegment:DestOff] := PFont(GameFont)^[Index, Line];
                Mem[FillPageSegment:DestOff] := PFont(GameFont)^[Index, Line];
              end
              else
              begin
                Mem[ActivePageSegment:DestOff] := 0;
                Mem[FillPageSegment:DestOff] := 0;
              end;
            end;
            Inc(DestOff, GraphStride);
          end;
          Port[SeqData] := MapMaskRestore;
        end;
      2:
        begin
          { QUIRK 0709:047B: the names of DestOff and FontRow are the other way round in this
            mode: DestOff holds the font row and FontRow the graph row of the destination (the
            slots are fixed by the original frame). }
          DestOff := 0;
          FontRow := Row * 2;
          ColBase := Col * 4;
          for Line := 0 to 1 do
          begin
            for Bank := 0 to 3 do
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
                case Bank of
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
  ReadAmount, ClearPromptLine, ReadInputLine, ShowMessageLine (row 24, 40 cells) and FlashMessageLine. }
procedure ClearTextCells(Col, Row, Color, Count: Byte);
begin
  if (Col < 0) or (Col > LastCol) or (Row < 0) or (Row > LastRow) then Exit;
  DrawGlyph(Col, Row, Color, Count, GlyphSpace, 1);
end;
{ 0709:0626. Draws Text in Color from cell Col of text row Row, one DrawGlyph per character
  (cooked through UpCase into the 64-glyph text set), advancing Col; nothing when Col is past
  column 39. QUIRK 0709:0647: Row is also tested against LastCol (39), not LastRow (24);
  DrawGlyph then skips rows past 24, and characters past column 39. Called
  by ShowMessageLine (row 24), ShowCredits, CheckCodeWheel, StartGame and many menus. }
procedure DrawTextAt(Col, Row, Color: Byte; Text: string);
var
  Len, I: Byte;
begin
  if (Col > LastCol) or (Row > LastCol) then Exit;
  Len := Length(Text);
  for I := 1 to Len do
  begin
    DrawGlyph(Col, Row, Color, 1, Ord(Text[I]), 1);
    Inc(Col);
  end;
end;
{ 0709:0768. Shows Text with word wrap in the Left..Right by Top..Bottom rectangle, paging
  with 'Press any key to continue' when the GlyphRow cursor passes Bottom. The Text value
  parameter (which the compiler materializes to a hidden stack copy on entry, the StrLCopy
  at 076F) is scanned word by word: leading BreakChars are skipped, the word run stops
  at a blank or a BreakChar, trailing BreakChars (Text[WordEnd + 1], 0709:08C9) are absorbed,
  and the word is drawn when (WordEnd - WordStart) + GlyphCol still fits in Right, else a new
  line starts. Out-of-range coordinates exit at once, as does empty text. A nonzero ClearFirst
  clears the rectangle first. The GlyphCol/GlyphRow cursor is kept inside the rectangle, reset
  to (Left, Top) when it leaves. Color passes through to the glyph drawer. Width is computed
  but never read. QUIRK 0709:0795: Bottom is tested against LastCol (39), not LastRow (24).
  QUIRK 0709:0919: the (WordEnd - WordStart) + GlyphCol = Right and Text[WordEnd] = ' ' test is
  dead: the enclosing test already took (WordEnd - WordStart) + GlyphCol > Right. Side effects:
  video memory, the keyboard on paging. Called by the menu, shop, temple, credit and script
  screens.
  06A7 draws the Text[WordStart..WordEnd] run glyph by glyph at advancing GlyphCol with the Crt
  delay; 0714 skips blank Text chars while WordStart stays below Len. Both are nested (they
  reach the parent frame through the frame link, push bp; push cs; call) and get L2 with their
  parent. }
procedure ShowPagedText(Left, Top, Right, Bottom, Color, ClearFirst: Byte; Text: string);
const
  MoreKeyColor = $0D;  { ShowMessageLine colour of the 'Press any key to continue' prompt }
var
  Len: Byte;         { Length(Text); the scan stops past it }
  Width: Byte;       { Right - Left + 1; written but never read }
  WordStart: Byte;   { first Text char of the word being measured }
  WordEnd: Byte;     { last Text char drawn: the blank or break character that ended the word,
                       or the last character of the text }
  Unused: Byte;      { never referenced; the original frame has this byte at [bp-105h] }
  { 0709:06A7. Draws Text[WordStart..WordEnd] glyph by glyph through DrawGlyph at (GlyphCol,
    GlyphRow) in Color, waiting the Crt delay after each glyph when WaitAfterTextRun is set,
    advancing WordStart and GlyphCol. Nested in ShowPagedText. }
  procedure DrawTextRun;
  begin
    while WordStart <= WordEnd do
    begin
      DrawGlyph(GlyphCol, GlyphRow, Color, 1, Ord(Text[WordStart]), 1);
      if WaitAfterTextRun <> 0 then Delay(GameSpeed * 10);
      Inc(WordStart);
      Inc(GlyphCol);
    end;
  end;
  { 0709:0714. Skips blank Text chars while WordStart stays below Len. Nested in ShowPagedText. }
  procedure SkipSpaces;
  begin
    while (WordStart < Len) and (Text[WordStart] = ' ') do Inc(WordStart);
  end;
begin
  if (Left > LastCol) or (Top > LastRow) or (Right > LastCol) or (Bottom > LastCol) then Exit;
  if (GlyphCol < Left) or (GlyphCol > Right) or (GlyphRow < Top) or (GlyphRow > Bottom) then
  begin
    GlyphCol := Left;
    GlyphRow := Top;
  end;
  if ClearFirst <> 0 then
  begin
    ClearRect(Left, Top, Right, Bottom);
    GlyphCol := Left;
    GlyphRow := Top;
  end;
  WordStart := 1;
  Len := Length(Text);
  if Len = 0 then Exit;
  Width := Right - Left + 1;
  repeat
    WordEnd := WordStart;
    while (WordEnd < Len) and (Text[WordEnd] in BreakChars) do Inc(WordEnd);
    while (WordEnd < Len) and not (Text[WordEnd] in BreakChars) and (Text[WordEnd] <> ' ') do Inc(WordEnd);
    if Text[WordEnd] <> ' ' then
      while (WordEnd + 1 < Len) and (Text[WordEnd + 1] in BreakChars) do Inc(WordEnd);
    if (WordEnd - WordStart) + GlyphCol > Right then
    begin
      if ((WordEnd - WordStart) + GlyphCol = Right) and (Text[WordEnd] = ' ') then
      begin
        Dec(WordEnd);
        DrawTextRun;
      end;
      GlyphCol := Left;
      Inc(GlyphRow);
      SkipSpaces;
      if GlyphRow > Bottom then
        if WordStart < Len then
        begin
          GlyphCol := Left;
          GlyphRow := Top;
          ShowMessageLine(MoreKeyColor, 'Press any key to continue');
          FlushKeyboard;
          ClearRect(Left, Top, Right, Bottom);
          DrawTextRun;
        end;
    end
    else
      DrawTextRun;
  until WordStart > Len;
  if GlyphCol > Right then
  begin
    GlyphCol := Left;
    Inc(GlyphRow);
  end;
end;
{ 0709:09E3. The line reader: shows Prompt in Color on the bottom row (BottomRow) and lets the
  player type up to MaxLen characters after it, echoed in white (EchoColor 15): ' '..'z' are
  added, Backspace removes the last one; Enter or Esc ends. Returns the line in upper case (Esc
  returns what was typed too). The row is cleared at the end. CheckCodeWheel asks for the code
  word with it (prompt 'INPUT THE CODE WORD: '). }
function ReadInputLine(Prompt: String40; Color: Byte; MaxLen: Byte): String40;
const
  EchoColor = 15;           { white }
  KeyBackspace = #8;
  KeyEnter = #13;
  KeyEsc = #27;
var
  Col: Byte;                { the cell the echo last used: it starts at Length(Prompt) and is
                              incremented before the first glyph is drawn, so the first typed
                              character lands one blank cell past the prompt's last character
                              (QUIRK 0709:0A7E: the gap is the original's; the code word prompt
                              already ends with a space) }
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
  ReadNumberCommand. }
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
{ 0709:0BF5. Shows Text in Color on the bottom row (BottomRow): clears the row's ScreenCols
  cells (ClearTextCells), writes the text (DrawTextAt) and waits for a key; the key is read
  through ReadGameKey and discarded (the local Key is assigned and never read, QUIRK 0709:0C36).
  Returns nothing. Called from the paging prompt, the menus and the credit and temple screens
  (twelve call sites). }
procedure ShowMessageLine(Color: Byte; Text: String40);
var
  Key: Char;                { the discarded key; see the QUIRK in the routine comment }
begin
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Text);
  Key := ReadGameKey;
end;
{ 0709:0C3F. The game clock in hundredths of a second: reads the DOS time (GetTime) and returns
  Hour * 360000 + Minute * 6000 + Second * 100 + Sec100. Hour * 360000 is a LongInt multiply;
  Minute * 6000 is a Word multiply, so a minute from 11 up (11 * 6000 = 66000) wraps by 65536 per
  overflowed minute and the clock falls back within the hour (QUIRK 0709:0C75); Second * 100 can
  never overflow (at most 5900), so 0709:0C85 is harmless. Callers compare deadlines with
  GameClock >= Limit, so a wrap can miss a deadline set just before it or pass one at once.
  Called by WaitKeyOrTimeout, ShowTitleScreen, AnimateFinalPicture and ReadPromptChoice. }
function GameClock: Longint;
var
  Hour, Minute, Second, Sec100: Word;
begin
  GetTime(Hour, Minute, Second, Sec100);
  GameClock := Hour * 360000 + Minute * 6000 + Second * 100 + Sec100;
end;
{ 0709:0CAB. Clears the whole screen to 0 by video adapter (the VideoAdapter global):
  0 fills the two text-scanline banks ($BA00 then $B800), 1 draws the full 40 by 25 cell screen
  through FillPlaneRect on display pages 0 and 1, 2 fills the four graphics banks
  ($B800/$BA00/$BC00/$BE00). Called by ovl19. }
procedure ClearFullScreen;
const
  BankBytes = $1F40;   { one 8000-byte scanline bank (or display page) }
begin
  case VideoAdapter of
    0:
      begin
        FillChar(TextPlane1, BankBytes, 0);
        FillChar(TextPlane0, BankBytes, 0);
      end;
    1:
      begin
        FillPlaneRect(0, 0, LastCol, LastRow, 0, 0);
        FillPlaneRect(0, 0, LastCol, LastRow, 1, 0);
      end;
    2:
      begin
        FillChar(GraphPlane0, BankBytes, 0);
        FillChar(GraphPlane1, BankBytes, 0);
        FillChar(GraphPlane2, BankBytes, 0);
        FillChar(GraphPlane3, BankBytes, 0);
      end;
  end;
end;
{ 0709:0D68. Shows Text in Color on the bottom line (row 24) for a moment: clears the row
  (ClearTextCells), writes the text (DrawTextAt), waits DelayByGameSpeed and clears the row again;
  no key is waited for, unlike ShowMessageLine. CheckCodeWheel shows a wrong code word with it,
  ovl14 'Not Here' and the river's stench, in colour 14. }
procedure FlashMessageLine(Text: String40; Color: Byte);
begin
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Text);
  DelayByGameSpeed;
  ClearTextCells(0, BottomRow, 0, ScreenCols);
end;
{ 0709:0DBE. A delay of GameSpeed * 225 milliseconds (Crt.Delay): 225 milliseconds per GameSpeed
  step. No parameters. Called while
  drawing many screens (ovl03, ovl10, ovl12, ovl13, ovl18, ovl19, ovl20). }
procedure DelayByGameSpeed;
begin
  Delay(GameSpeed * 225);
end;
{ 0709:0DD3. Clears the Left..Right by Top..Bottom rectangle to 0 by video adapter (the
  VideoAdapter global), the Byte-coordinate twin of ClearWindow: 0 fills the text-scanline
  rows Top*4..Bottom*4+3 on both text banks, 1 draws the rectangle through FillPlaneRect on
  display pages 0 and 1, 2 fills the graphics rows Top*2..Bottom*2+1 on all four graphics
  banks. Called by the menu screens (HealMenu, VisitTemple, ShopMain), ShowEndingNarrative
  and others. Side effect: video memory. }
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

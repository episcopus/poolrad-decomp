unit OVL25;
{ The menu unit (whitepaper 5.8): the prompt line on text row 24 and the list menus built on it.
  ReadPromptChoice shows a title and a row of words ("Heal Exit", "Yes No"), lets the player pick a
  word by its capital letter, by Space, by Enter or by stepping the highlight with ',' and '.', and
  animates the picture in PictureAnimation while it waits. ChooseFromList draws a list of menu lines
  (TMenuLine, built by NewMenuList and freed by FreeMenuList) in a window, moves a highlight over it
  (Home/End, with Next/Prev/Exit words added to the prompt) and returns the key and the chosen line.
  AskYesNo and ClearPromptLine are the small helpers the game calls everywhere. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06;
function GetMenuLine(Index: Integer; List: PMenuLine): PMenuLine;
function CountMenuLines(List: PMenuLine): Integer;
function ReadPromptChoice(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char;
procedure ClearPromptLine;
function ChooseFromList(Title, Prompt: String40; HeadingColor, LineColor, HighlightColor: Byte;
  Left, Top, Right, Bottom: ShortInt; List: PMenuLine; WithExit: Byte; var Redraw: Byte;
  var Choice: Integer; var Selected: PMenuLine): Char;
function AskYesNo(Prompt: String40; TitleColor, WordColor, HotColor: Byte): Char;
procedure NewMenuList(Count: Integer; var List: PMenuLine);
procedure FreeMenuList(var List: PMenuLine);
implementation
uses RES04, RES09, OVL28, Crt;

const
  PromptRow = $18;              { the text row of the prompt line (ovl25:0469, ovl25:0253) }
  PromptLeftCol = 0;            { the title starts in column 0 (ovl25:0466); its words follow it }
  LastTextCol = $27;            { the last of the 40 text columns (ovl25:032B) }
  TextCols = $28;               { ClearPromptLine blanks 40 columns (ovl25:0707) }
  Space = $20;                  { the blank res06_fn_01DF draws (ovl25:036C) }
  MaxPromptWords = 20;          { the word spans of the prompt, 40 bytes cleared (ovl25:00ED) }
  KeyNone = #0;                 { the extended-key prefix of ReadGameKey; also what Escape returns }
  KeyEnter = #13;
  KeyEscape = #27;
  KeyPrevWord = ',';            { steps the prompt highlight left, wrapping (ovl25:05C4) }
  KeyNextWord = '.';            { steps it right, wrapping (ovl25:05E8) }
  KeyYes = 'Y';
  KeyNo = 'N';
  { Keypad digits 1..9 and '\' become extended keys when the caller accepts them (ovl25:0697):
    '\' gives '7' and digit k gives KeypadScanLetters[k - 1]. }
  KeypadBackslash = '\';
  KeypadBackslashKey = '7';
  { The scan code letters of the extended keys the list menu handles (ovl25:0FF4..102A); the oracle
    shows End moving the highlight down and Home up in the character creation lists. }
  ScanHome = 'G';
  ScanEnd = 'O';
  ScanPgUp = 'I';
  ScanPgDn = 'Q';
  { The words the list menu adds to its prompt, and their capitals (ovl25:103D..1066). }
  KeyPrevPage = 'P';
  KeyNextPage = 'N';
  KeyExitList = 'E';
  { The animated picture: drawn at column 3, row 3 (ovl25:04AD); a frame's Delay counts 10 GameClock
    ticks (ovl25:04E4). }
  PictureCol = 3;
  PictureRow = 3;
  TicksPerDelay = 10;
  { Game variable 511 (GameVars^ word $1FF): while it is nonzero the prompt animates the picture even
    when its caller did not ask for it and steps a frame on every pass of its wait loop; the prompt
    clears it when it returns (ovl25:048E, ovl25:0507, ovl25:06D8). }
  VarAnimateNow = $1FF;
  { NewMenuList allocates 46 bytes per line: the Text, Flag29 and Next fields of TMenuLine
    (ovl25:1146, ovl25:1234), not the whole item record. }
  MenuLineBytes = $2E;

{ ovl25:0000. Returns line Index of the menu line list List, counting from 0, or nil when the list is
  shorter. Called by ChooseFromList and its nested routines and by ovl16 (packet). }
function GetMenuLine(Index: Integer; List: PMenuLine): PMenuLine;
var
  Line: PMenuLine;
  I: Integer;
begin
  I := 0;
  Line := List;
  while (Line <> nil) and (I <> Index) do
  begin
    Line := Line^.Next;
    Inc(I);
  end;
  if I = Index then
    GetMenuLine := Line
  else
    GetMenuLine := nil;
end;

{ ovl25:0067. Returns the number of lines of the menu line list List (0 for nil). Called by
  ChooseFromList. }
function CountMenuLines(List: PMenuLine): Integer;
var
  Line: PMenuLine;
  N: Integer;
begin
  N := 0;
  Line := List;
  while Line <> nil do
  begin
    Inc(N);
    Line := Line^.Next;
  end;
  CountMenuLines := N;
end;

{ ovl25:03BD. The prompt line: shows Title in TitleColor at the left of text row 24 and the words of
  Prompt after it, then waits for the player's choice and returns the key. A word is a run starting
  with a capital letter or digit; capitals are drawn in HotColor, other letters in WordColor, and the
  word PromptWordChoice (kept between calls, reset to 1 when out of range) is highlighted in
  HotColor. ',' and '.' step the highlight (wrapping), a capital or digit that starts a word picks
  that word and returns its letter, Space returns ' ', Enter returns #13 when either colour is
  nonzero, Escape returns #0. With ExtKeys nonzero an extended key returns its scan code letter and
  the keypad digits return the scan letter of their key (KeypadScanLetters), both with ExtKey set to
  1; otherwise extended keys are read and ignored. While waiting it animates PictureAnimation when
  Animate (passed to DrawSprite as Direct) or game variable VarAnimateNow is nonzero, and returns
  PromptTimeoutKey when PromptTimeout is above 0 and that many ticks have passed. On return it clears
  VarAnimateNow and copies ExtKey into LastPromptExtKey. Called by ChooseFromList and AskYesNo and
  by many units (the Temple, the shops, ovl14's area keys).
  QUIRK ovl25:043D: two more clock values (Start plus 30 and plus 80) are computed and never read.
  QUIRK ovl25:0662: a hotkey that is a capital inside a word, not its first letter, searches the
  word spans past their end (the loop has no bound).
  QUIRK ovl25:0530: the timeout counts from the last animation frame, not from the start. }
function ReadPromptChoice(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char;
type
  { One word of the prompt: the positions of its first and last character in Prompt. }
  TWordSpan = record
    Start, Stop: Byte;
  end;
var
  Start: Longint;               { GameClock at the start or at the last animation frame }
  Unused30, Unused80: Longint;  { QUIRK ovl25:043D: computed, never read }
  Key: Char;
  J, I: Byte;
  Done: Boolean;
  PromptLen, WordsCol: Byte;
  Words: array[1..MaxPromptWords] of TWordSpan;
  WordCount: Byte;
  AcceptsEnter: Boolean;

  { ovl25:00CB (nested). Splits Text (the prompt) into Words: every capital letter or digit after
    the first word's start begins a new word whose previous one ends two characters earlier (one
    separator assumed); the last word ends at the end of the text. Sets WordCount. }
  procedure SplitPromptWords(Text: String40);
  var
    Count, I, Len, Spare: Byte;   { Spare: a byte the original reserves and never uses }
  begin
    FillChar(Words, SizeOf(Words), 0);
    Count := 1;
    Len := Length(Text);
    for I := 1 to Len do
      if Text[I] in ['0'..'9', 'A'..'Z'] then
        if Words[Count].Start = 0 then
          Words[Count].Start := I
        else
        begin
          Words[Count].Stop := I - 2;
          Inc(Count);
          Words[Count].Start := I;
        end;
    Words[Count].Stop := Len;
    WordCount := Count;
  end;

  { ovl25:01DA (nested). Draws the prompt's words on row 24 from column WordsCol, one character at a
    time through res06_fn_01DF: the characters of word Chosen (when HotColor is nonzero) and every
    capital or digit in HotColor, the rest in WordColor; then blanks the row to column 39. }
  procedure DrawPromptWords(Chosen: Byte);
  var
    I: Byte;
  begin
    if PromptLen > 0 then
    begin
      for I := 1 to PromptLen do
        if (Words[Chosen].Start <= I) and (Words[Chosen].Stop >= I) and (HotColor <> 0) then
          res06_fn_01DF(WordsCol + I - 1, PromptRow, HotColor, 1, Ord(Prompt[I]), 1)
        else if Prompt[I] in ['0'..'9', 'A'..'Z'] then
          res06_fn_01DF(WordsCol + I - 1, PromptRow, HotColor, 1, Ord(Prompt[I]), 1)
        else
          res06_fn_01DF(WordsCol + I - 1, PromptRow, WordColor, 1, Ord(Prompt[I]), 1);
      if WordsCol + PromptLen < LastTextCol then
        res06_fn_01DF(WordsCol + PromptLen, PromptRow, 0, LastTextCol - PromptLen - WordsCol + 1,
          Space, 1);
    end;
  end;

begin
  LastPromptExtKey := 0;
  AcceptsEnter := (WordColor <> 0) or (HotColor <> 0);
  SplitPromptWords(Prompt);
  if PromptWordChoice > WordCount then
    PromptWordChoice := 1;
  PromptLen := Length(Prompt);
  Key := KeyNone;
  ExtKey := 0;
  Done := False;
  Start := GameClock;
  Unused30 := GameClock + 30;
  Unused80 := Unused30 + 50;
  if Length(Title) <> 0 then
    res06_fn_0626(PromptLeftCol, PromptRow, TitleColor, Title);
  WordsCol := Length(Title) + PromptLeftCol;
  DrawPromptWords(PromptWordChoice);
  repeat
    if ((GameVars^[VarAnimateNow] <> 0) or (Animate <> 0)) and (PictureAnimation.Current > 0) then
    begin
      DrawSprite(PictureCol, PictureRow, Animate,
        PictureAnimation.Frames[PictureAnimation.Current].Sprite);
      if (GameClock - Start >= PictureAnimation.Frames[PictureAnimation.Current].Delay * TicksPerDelay)
        or (GameVars^[VarAnimateNow] <> 0) then
      begin
        Inc(PictureAnimation.Current);
        if PictureAnimation.Current > PictureAnimation.Count then
          PictureAnimation.Current := 1;
        Start := GameClock;
      end;
    end;
    if (PromptTimeout > 0) and (GameClock - Start >= PromptTimeout) then
    begin
      Key := PromptTimeoutKey;
      Done := True;
    end
    else if KeyPressed then
    begin
      Key := ReadGameKey;
      if Key = KeyNone then
      begin
        Key := ReadGameKey;
        if ExtKeys <> 0 then
        begin
          ExtKey := 1;
          Done := True;
        end;
      end
      else
        case Key of
          KeyEscape:
            begin
              Done := True;
              Key := KeyNone;
            end;
          KeyEnter:
            if AcceptsEnter then
            begin
              Key := KeyEnter;
              Done := True;
            end;
          KeyPrevWord:
            begin
              if PromptWordChoice = 1 then
                PromptWordChoice := WordCount
              else
                Dec(PromptWordChoice);
              DrawPromptWords(PromptWordChoice);
            end;
          KeyNextWord:
            begin
              if PromptWordChoice = WordCount then
                PromptWordChoice := 1
              else
                Inc(PromptWordChoice);
              DrawPromptWords(PromptWordChoice);
            end;
        else
          Key := UpCase(Key);
          if Key in [' ', '0'..'9', 'A'..'Z'] then
            if Key = ' ' then
              Done := True
            else
              for I := 1 to PromptLen do
                if Prompt[I] = Key then
                begin
                  Done := True;
                  J := 1;
                  while Words[J].Start <> I do
                    Inc(J);
                  PromptWordChoice := J;
                  DrawPromptWords(PromptWordChoice);
                end;
          if ExtKeys <> 0 then
            if Key in ['1'..'9', KeypadBackslash] then
            begin
              if Key = KeypadBackslash then
                Key := KeypadBackslashKey
              else
                Key := KeypadScanLetters[Ord(Key) - Ord('1')];
              ExtKey := 1;
              Done := True;
            end;
        end;
    end;
  until Done;
  GameVars^[VarAnimateNow] := 0;
  ReadPromptChoice := Key;
  LastPromptExtKey := ExtKey;
end;

{ ovl25:06FB. Blanks the prompt line: res06_fn_05EB over the 40 columns of text row 24. Called by
  the loader (ovl07, ovl11), the area keys and many other units before they draw a new prompt. }
procedure ClearPromptLine;
begin
  res06_fn_05EB(0, PromptRow, 0, TextCols);
end;

{ ovl25:0D9A. The list menu: shows the lines of List in the window Left..Right, Top..Bottom (lines
  with Flag29 set are headings: drawn in HeadingColor and skipped by the highlight, the others in
  LineColor), highlights line Choice (0-based) in HighlightColor and asks through ReadPromptChoice
  with Title and Prompt plus " Next", " Prev" (when there are more lines below or above the page)
  and " Exit" (when WithExit is nonzero). Home and End move the highlight, PgUp/PgDn and the P and N
  words turn the page; any other key returns that key with Choice and Selected set to the
  highlighted line; Escape, E and #0 return #0 with Selected nil. The page is redrawn on entry only
  when Redraw is nonzero or ListMenuTop (the first shown line, kept between calls) had to be
  reset; Redraw is cleared. A nil List returns #0 at once with Choice 0 and Selected nil. Called by
  the Temple (HealMenu), the shops (ChooseShopItem) and ovl05, ovl07, ovl15, ovl16, ovl19, ovl21.
  QUIRK ovl25:0E5F: the lines are counted twice (CountMenuLines into LineCount, then a loop into
  Total) and the two counts are used for different checks. }
function ChooseFromList(Title, Prompt: String40; HeadingColor, LineColor, HighlightColor: Byte;
  Left, Top, Right, Bottom: ShortInt; List: PMenuLine; WithExit: Byte; var Redraw: Byte;
  var Choice: Integer; var Selected: PMenuLine): Char;
var
  Width: Byte;
  LineCount: Integer;
  ExtKey: Byte;
  Height: Integer;
  Key: Char;
  Words: String40;
  HasNext, HasPrev: Byte;
  Line: PMenuLine;
  HeadingCount, Total: Integer;

  { ovl25:0711 (nested). Returns the last heading line among the first Count lines of List; when
    there is none, List itself if its first line is a heading, else nil. Its only caller, DrawListPage,
    stores the result and never reads it. }
  function LastHeadingBefore(Count: Integer; List: PMenuLine): PMenuLine;
  var
    Line, Found: PMenuLine;
    I: Integer;
  begin
    I := 0;
    Line := List;
    Found := nil;
    while (Line <> nil) and (I < Count) do
    begin
      if Line^.Flag29 <> 0 then
        Found := Line;
      Line := Line^.Next;
      Inc(I);
    end;
    if (Found = nil) and (List^.Flag29 <> 0) then
      LastHeadingBefore := List
    else
      LastHeadingBefore := Found;
  end;

  { ovl25:07A4 (nested). Clears the window and draws the lines from line TopLine on, one per row
    from Top to Bottom, headings in HeadingColor and the others in LineColor, each padded with
    blanks to the window width.
    QUIRK ovl25:07F9: the heading found by LastHeadingBefore is never used. }
  procedure DrawListPage(TopLine: Integer);
  var
    Line, Heading: PMenuLine;
    Row: ShortInt;
  begin
    ClearWindow(Left, Top, Right, Bottom);
    Line := GetMenuLine(TopLine, List);
    Heading := LastHeadingBefore(TopLine, List);
    Row := Top;
    while (Line <> nil) and (Row <= Bottom) do
    begin
      if Line^.Flag29 <> 0 then
        res06_fn_0626(Left, Row, HeadingColor, Line^.Text)
      else
        res06_fn_0626(Left, Row, LineColor, Line^.Text);
      if Length(Line^.Text) < Width then
        res06_fn_01DF(Left + Length(Line^.Text), Row, 0, Width - Length(Line^.Text), Space, 1);
      Line := Line^.Next;
      Inc(Row);
    end;
  end;

  { ovl25:08D7 (nested). Returns the position of the first non-blank character of Text (the length
    when all but the last are blanks). }
  function FirstNonBlank(Text: String40): Byte;
  var
    I, Len: Byte;
  begin
    I := 1;
    Len := Length(Text);
    while (I < Len) and (Text[I] = ' ') do
      Inc(I);
    FirstNonBlank := I;
  end;

  { ovl25:0923 (nested). Returns the position of the last non-blank character of Text (1 when all
    are blanks). }
  function LastNonBlank(Text: String40): Byte;
  var
    I: Byte;
  begin
    I := Length(Text);
    while (I > 1) and (Text[I] = ' ') do
      Dec(I);
    LastNonBlank := I;
  end;

  { ovl25:0969 (nested). Redraws the text of line LineNo, without its leading and trailing blanks,
    in HighlightColor at its row of the page (Top plus LineNo minus ListMenuTop). }
  procedure HighlightListLine(LineNo: Integer);
  var
    Line: PMenuLine;
    First, Len: Byte;
  begin
    Line := GetMenuLine(LineNo, List);
    First := FirstNonBlank(Line^.Text);
    Len := LastNonBlank(Line^.Text) - First + 1;
    res06_fn_0626(Left + First - 1, Top + (LineNo - ListMenuTop), HighlightColor,
      Copy(Line^.Text, First, Len));
  end;

  { ovl25:0A08 (nested). Redraws the trimmed text of line LineNo in its own colour (HeadingColor for
    a heading, LineColor otherwise): the highlight is taken off. }
  procedure UnhighlightListLine(LineNo: Integer);
  var
    Line: PMenuLine;
    First, Len: Byte;
  begin
    Line := GetMenuLine(LineNo, List);
    First := FirstNonBlank(Line^.Text);
    Len := LastNonBlank(Line^.Text) - First + 1;
    if Line^.Flag29 <> 0 then
      res06_fn_0626(Left + First - 1, Top + (LineNo - ListMenuTop), HeadingColor,
        Copy(Line^.Text, First, Len))
    else
      res06_fn_0626(Left + First - 1, Top + (LineNo - ListMenuTop), LineColor,
        Copy(Line^.Text, First, Len));
  end;

  { ovl25:0B03 (nested). While line Choice is a heading (at most Height times), moves Choice one
    line down (Down) or up, wrapping inside the page shown and the list. }
  procedure SkipHeadingLines(Down: Boolean);
  var
    N: Integer;
  begin
    N := 0;
    if Down then
    begin
      while (N < Height) and (GetMenuLine(Choice, List)^.Flag29 <> 0) do
      begin
        Inc(N);
        Inc(Choice);
        if ListMenuTop + Height - 1 < Choice then
          Choice := ListMenuTop;
        if LineCount - 1 < Choice then
          Choice := ListMenuTop;
      end;
    end
    else
      while (N < Height) and (GetMenuLine(Choice, List)^.Flag29 <> 0) do
      begin
        Inc(N);
        Dec(Choice);
        if Choice < ListMenuTop then
          Choice := ListMenuTop + Height - 1;
        if LineCount - 1 < Choice then
          Choice := LineCount - 1;
      end;
  end;

  { ovl25:0C33 (nested). Turns the page down (Down) or up: moves ListMenuTop by Height (not past the
    last page or the first line), keeps the highlight at the same row of the page, skips headings
    and redraws the page. }
  procedure ScrollListPage(Down: Boolean);
  var
    RowOnPage: Integer;
  begin
    RowOnPage := Choice - ListMenuTop;
    if Down then
    begin
      Inc(ListMenuTop, Height);
      if LineCount - Height < ListMenuTop then
        ListMenuTop := LineCount - Height;
    end
    else
    begin
      Dec(ListMenuTop, Height);
      if ListMenuTop < 0 then
        ListMenuTop := 0;
    end;
    Choice := ListMenuTop + RowOnPage;
    SkipHeadingLines(Down);
    DrawListPage(ListMenuTop);
  end;

  { ovl25:0CC5 (nested). Moves the highlight one line down (Down, the End key) or up (Home), wrapping
    inside the page shown, then skips headings in the same direction. }
  procedure MoveListCursor(Down: Boolean);
  var
    Spare: array[0..1] of PMenuLine;  { 8 bytes the original reserves and never uses }
  begin
    if Down then
    begin
      Inc(Choice);
      if ListMenuTop + Height - 1 < Choice then
        Choice := ListMenuTop;
      if LineCount - 1 < Choice then
        Choice := ListMenuTop;
    end
    else
    begin
      Dec(Choice);
      if Choice < ListMenuTop then
        Choice := ListMenuTop + Height - 1;
      if LineCount - 1 < Choice then
        Choice := LineCount - 1;
    end;
    SkipHeadingLines(Down);
  end;

begin
  if List = nil then
  begin
    Choice := 0;
    Selected := nil;
    ChooseFromList := KeyNone;
    Exit;
  end;
  PromptWordChoice := 1;
  Width := Right - Left + 1;
  LineCount := CountMenuLines(List);
  Height := Bottom - Top + 1;
  Line := List;
  HeadingCount := 0;
  while (Line <> nil) and (Line^.Flag29 <> 0) do
  begin
    Line := Line^.Next;
    Inc(HeadingCount);
  end;
  Line := List;
  Total := 0;
  while Line <> nil do
  begin
    Line := Line^.Next;
    Inc(Total);
  end;
  if ListMenuTop > Choice then
  begin
    ListMenuTop := Choice;
    Redraw := 1;
  end;
  if ListMenuTop > Total then
  begin
    ListMenuTop := 0;
    Redraw := 1;
  end;
  Inc(Choice);
  MoveListCursor(False);
  if Redraw <> 0 then
    DrawListPage(ListMenuTop);
  Redraw := 0;
  repeat
    HighlightListLine(Choice);
    Words := Prompt;
    HasNext := 0;
    HasPrev := 0;
    if LineCount - Height > ListMenuTop then
    begin
      Words := Words + ' Next';
      HasNext := 1;
    end;
    if ListMenuTop > HeadingCount then
    begin
      Words := Words + ' Prev';
      HasPrev := 1;
    end;
    if WithExit <> 0 then
      Words := Words + ' Exit';
    Key := ReadPromptChoice(Title, Words, HeadingColor, LineColor, HighlightColor, 1, 0, ExtKey);
    UnhighlightListLine(Choice);
    if ExtKey <> 0 then
      case Key of
        ScanHome: MoveListCursor(False);
        ScanEnd: MoveListCursor(True);
        ScanPgUp: if HasPrev <> 0 then ScrollListPage(False);
        ScanPgDn: if HasNext <> 0 then ScrollListPage(True);
      end
    else
      case Key of
        KeyPrevPage: ScrollListPage(False);
        KeyNextPage: ScrollListPage(True);
        KeyEscape, KeyExitList, KeyNone:
          begin
            Selected := nil;
            ChooseFromList := KeyNone;
            Exit;
          end;
      else
        Selected := GetMenuLine(Choice, List);
        ChooseFromList := Key;
        Exit;
      end;
  until False;
end;

{ ovl25:10D1. Asks Prompt with the words "Yes No" (the highlight starts on No) through
  ReadPromptChoice until the key is Y or N and returns it; Escape asks again. Called by the Temple
  (AskCastAnyway, ChargeForCure) and ovl08, ovl13, ovl15, ovl16. }
function AskYesNo(Prompt: String40; TitleColor, WordColor, HotColor: Byte): Char;
var
  ExtKey: Byte;
  Key: Char;
begin
  PromptWordChoice := 2;
  repeat
    Key := ReadPromptChoice(Prompt, 'Yes No', TitleColor, WordColor, HotColor, 0, 0, ExtKey);
  until Key in [KeyYes, KeyNo];
  AskYesNo := Key;
end;

{ ovl25:1140. Builds a list of Count blank menu lines (at least one) in List: each is a 46-byte
  block from the heap with an empty Text, Flag29 0 and Next linking to the following one. Called by
  the Temple (HealMenu), ovl03 and ovl16. }
procedure NewMenuList(Count: Integer; var List: PMenuLine);
var
  Line: PMenuLine;
  I: Integer;
begin
  GetMem(List, MenuLineBytes);
  List^.Next := nil;
  List^.Flag29 := 0;
  List^.Text := '';
  Line := List;
  for I := 2 to Count do
  begin
    GetMem(Line^.Next, MenuLineBytes);
    Line := Line^.Next;
    Line^.Next := nil;
    Line^.Flag29 := 0;
    Line^.Text := '';
  end;
end;

{ ovl25:11F3. Frees every 46-byte line of the list List built by NewMenuList.
  QUIRK ovl25:11F3: List itself is left pointing at the freed first line. }
procedure FreeMenuList(var List: PMenuLine);
var
  Line, Done: PMenuLine;
begin
  Line := List;
  while Line <> nil do
  begin
    Done := Line;
    Line := Line^.Next;
    FreeMem(Done, MenuLineBytes);
  end;
end;

begin
end.

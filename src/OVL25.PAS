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
procedure SplitPromptWords;
procedure DrawPromptWords;
function ReadPromptChoice(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char;
procedure ClearPromptLine;
procedure LastHeadingBefore;
procedure DrawListPage;
procedure FirstNonBlank;
procedure LastNonBlank;
procedure HighlightListLine;
procedure UnhighlightListLine;
procedure SkipHeadingLines;
procedure ScrollListPage;
procedure MoveListCursor;
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
  Space = $20;                  { the blank DrawGlyph draws (ovl25:036C) }
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
  { The animated picture: drawn at column 3, row 3 (ovl25:04AD); a frame's Delay counts tenths of a
    second, 10 GameClock hundredths (ovl25:04E4). }
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

{ ovl25:00CB (nested in ReadPromptChoice). Splits the prompt into words at its capital letters and
  digits. A stub until ReadPromptChoice can match (draft in commit 3c8dac5). }
{@stub} procedure SplitPromptWords; begin end;
{ ovl25:01DA (nested in ReadPromptChoice). Draws the prompt's words on row 24, the chosen word and
  the capitals in the highlight colour. A stub until ReadPromptChoice can match. }
{@stub} procedure DrawPromptWords; begin end;
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
  PromptTimeoutKey when PromptTimeout is above 0 and that many hundredths of a second have passed.
  On return it clears VarAnimateNow and copies ExtKey into LastPromptExtKey. Called by ChooseFromList and AskYesNo and
  by many units (the Temple, the shops, ovl14's area keys).
  QUIRK ovl25:043D: two more clock values (Start plus 30 and plus 80) are computed and never read.
  QUIRK ovl25:0662: a hotkey that is a capital inside a word, not its first letter, searches the
  word spans past their end (the loop has no bound).
  QUIRK ovl25:0530: the timeout counts from the last animation frame, not from the start.
  BLOCKED: a stub. The draft (commit 3c8dac5, notes in re/symbols.toml) differs from the original
  only in address fields inside its nested routines, which the matcher compares byte-exact
  (work/blockers.md, escalate-res06-20261012110841). }
{@stub} function ReadPromptChoice(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char; begin end;

{ ovl25:06FB. Blanks the prompt line: res06_fn_05EB over the 40 columns of text row 24. Called by
  the loader (ovl07, ovl11), the area keys and many other units before they draw a new prompt. }
procedure ClearPromptLine;
begin
  res06_fn_05EB(0, PromptRow, 0, TextCols);
end;

{ ovl25:0711 (nested in ChooseFromList): the last heading line among the first lines of the list.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure LastHeadingBefore; begin end;
{ ovl25:07A4 (nested in ChooseFromList): clears the list window and draws one page of lines.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure DrawListPage; begin end;
{ ovl25:08D7 (nested in ChooseFromList): the position of the first non-blank character of a line.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure FirstNonBlank; begin end;
{ ovl25:0923 (nested in ChooseFromList): the position of the last non-blank character of a line.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure LastNonBlank; begin end;
{ ovl25:0969 (nested in ChooseFromList): redraws a line's trimmed text in the highlight colour.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure HighlightListLine; begin end;
{ ovl25:0A08 (nested in ChooseFromList): redraws a line's trimmed text in its own colour.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure UnhighlightListLine; begin end;
{ ovl25:0B03 (nested in ChooseFromList): moves the highlight past heading lines.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure SkipHeadingLines; begin end;
{ ovl25:0C33 (nested in ChooseFromList): turns the page of the list down or up and redraws it.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure ScrollListPage; begin end;
{ ovl25:0CC5 (nested in ChooseFromList): moves the highlight one line down or up inside the page.
  A stub until ChooseFromList can match (draft in commit 3c8dac5). }
{@stub} procedure MoveListCursor; begin end;
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
  Total) and the two counts are used for different checks.
  BLOCKED: a stub, for the same reason as ReadPromptChoice (draft in commit 3c8dac5). }
{@stub} function ChooseFromList(Title, Prompt: String40; HeadingColor, LineColor, HighlightColor: Byte;
  Left, Top, Right, Bottom: ShortInt; List: PMenuLine; WithExit: Byte; var Redraw: Byte;
  var Choice: Integer; var Selected: PMenuLine): Char; begin end;

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

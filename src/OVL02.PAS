unit OVL02;
{ The code wheel copy protection (whitepaper 5.12): the single routine asks up to three times for
  the code word that the wheel of the manual spells for the runes it draws, and ends the program
  when the third answer is wrong. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure CheckCodeWheel;
implementation
uses POOLVARS, RES04, RES06, RES09;

const
  WheelEntryCount = 13;      { code wheel records in the table at CodeWheelRecords }
  MaxAttempts = 3;           { wrong code words before the game ends }
  RuneCharBase = $40;        { the rune glyphs are characters: index + $40 in the game font }
  NoFourthRune = $FF;        { the fourth rune index of a record that has none }
  Green = 10;                { EGA colour: the prompt text }
  LightRed = 12;             { EGA colour: the path pattern line }
  Yellow = 14;               { EGA colour: the failure message }

{ ovl02:00FD. The code wheel check. Up to MaxAttempts times it picks a wheel record at random,
  clears the question window (DrawWindow), writes the instructions (DrawTextAt), draws the
  record runes as font characters (DrawGlyph: the two runes to match and the third, plus the
  fourth only when the record has one), shows the path pattern as five spaces and the record path
  (DrawTextAt), flushes the keyboard and asks for the code word (ReadInputLine, the line reader
  of res06). A matching answer (the record CodeWord) leaves the routine at once; a wrong one shows
  the failure message (FlashMessageLine), and the third wrong answer ends the program through
  QuitGame. Reads: CodeWheelRecords (the wheel records), Random. Globals: none besides those. Side effect:
  the screen; on the third failure the program halts. }
procedure CheckCodeWheel;
var
  Answer: string[40];     { the code word the player typed, truncated to 40 characters }
  Question: Byte;         { the wheel record Random picked: 0 to 12 }
  Attempt: Byte;          { 1, 2, 3: the answer the program is waiting for }
begin
  for Attempt := 1 to MaxAttempts do
  begin
    Question := Random(WheelEntryCount);
    DrawWindow(1, 1, $26, $16, 0, 0, '');
    DrawTextAt(1, 1, Green, 'USE THE TRANSLATION WHEEL TO DECIPHER');
    DrawTextAt(1, 2, Green, 'THE CODE WORD.');
    DrawTextAt(1, 5, Green, 'MATCH THE ESPRUAR RUNE (OUTER RING)');
    DrawGlyph(8, 6, $0C, 1, CodeWheelRecords[Question].OuterRune + RuneCharBase, 0);
    DrawGlyph(9, 6, $0C, 1, CodeWheelRecords[Question].InnerRune + RuneCharBase, 0);
    DrawTextAt(1, 8, Green, 'WITH THE DETHEK RUNE (INNER RING)');
    DrawGlyph(8, 9, $0C, 1, CodeWheelRecords[Question].ThirdRune + RuneCharBase, 0);
    if CodeWheelRecords[Question].FourthRune <> NoFourthRune then
      DrawGlyph(9, 9, $0C, 1, CodeWheelRecords[Question].FourthRune + RuneCharBase, 0);
    DrawTextAt(1, $0B, Green, 'AND READ THE CODE WORD UNDER THE PATH:');
    DrawTextAt(1, $0D, LightRed, '     ' + CodeWheelRecords[Question].Path);
    DrawTextAt(1, $0E, Green, 'READ FROM THE INSIDE TO THE OUTSIDE.');
    FlushKeyboard;
    Answer := ReadInputLine('INPUT THE CODE WORD: ', 13, 6);
    if Answer = CodeWheelRecords[Question].CodeWord then
      Exit;
    FlashMessageLine('Sorry, that''s incorrect.', Yellow);
  end;
  QuitGame;
end;

{ Initialisation (ovl02:0359): empty (55 89 E5 5D CB). }
begin
end.

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
  WheelEntryCount = 13;      { code wheel records in the table at ds0000 }
  MaxAttempts = 3;           { wrong code words before the game ends }
  RuneCharBase = $40;        { the rune glyphs are characters: index + $40 in the game font }
  NoFourthRune = $FF;        { the fourth rune index of a record that has none }
  Green = 10;                { EGA colour: the prompt text }
  LightRed = 12;             { EGA colour: the path pattern line }
  Yellow = 14;               { EGA colour: the failure message }

{ ovl02:00FD. The code wheel check. Up to MaxAttempts times it picks a wheel record at random,
  clears the question window (res09_fn_02E8), writes the instructions (res06_fn_0626), draws the
  record runes as font characters (res06_fn_01DF: the two runes to match and the third, plus the
  fourth only when the record has one), shows the path pattern as five spaces and the record path
  (res06_fn_0626), flushes the keyboard and asks for the code word (res06_fn_09E3, the line reader
  of res06). A matching answer (the record CodeWord) leaves the routine at once; a wrong one shows
  the failure message (res06_fn_0D68), and the third wrong answer ends the program through
  QuitGame. Reads: ds0000 (the wheel records), Random. Globals: none besides those. Side effect:
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
    res09_fn_02E8(1, 1, $26, $16, 0, 0, '');
    res06_fn_0626(1, 1, Green, 'USE THE TRANSLATION WHEEL TO DECIPHER');
    res06_fn_0626(1, 2, Green, 'THE CODE WORD.');
    res06_fn_0626(1, 5, Green, 'MATCH THE ESPRUAR RUNE (OUTER RING)');
    res06_fn_01DF(8, 6, $0C, 1, ds0000[Question].OuterRune + RuneCharBase, 0);
    res06_fn_01DF(9, 6, $0C, 1, ds0000[Question].InnerRune + RuneCharBase, 0);
    res06_fn_0626(1, 8, Green, 'WITH THE DETHEK RUNE (INNER RING)');
    res06_fn_01DF(8, 9, $0C, 1, ds0000[Question].ThirdRune + RuneCharBase, 0);
    if ds0000[Question].FourthRune <> NoFourthRune then
      res06_fn_01DF(9, 9, $0C, 1, ds0000[Question].FourthRune + RuneCharBase, 0);
    res06_fn_0626(1, $0B, Green, 'AND READ THE CODE WORD UNDER THE PATH:');
    res06_fn_0626(1, $0D, LightRed, '     ' + ds0000[Question].Path);
    res06_fn_0626(1, $0E, Green, 'READ FROM THE INSIDE TO THE OUTSIDE.');
    FlushKeyboard;
    Answer := res06_fn_09E3('INPUT THE CODE WORD: ', 13, 6);
    if Answer = ds0000[Question].CodeWord then
      Exit;
    res06_fn_0D68('Sorry, that''s incorrect.', Yellow);
  end;
  QuitGame;
end;

{ Initialisation (ovl02:0359): empty (55 89 E5 5D CB). }
begin
end.

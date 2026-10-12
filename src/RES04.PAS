unit RES04;
{ The keyboard layer and the way out of the game (whitepaper 5.8). Game code reads keys through
  ReadGameKey, which also handles the Ctrl-S sound switch and the keys of the STING debug mode;
  QuitGame restores the screen and ends the program. }
{$A-,F+,S-,R-,G-,I-}
interface
procedure QuitGame;
function ReadGameKey: Char;
procedure FlushKeyboard;
procedure DiscardWaitingKey;
implementation
uses Crt, Dos, POOLVARS, RES03;

const
  KeyCtrlC = #3;              { quits, in the STING debug mode }
  KeyCtrlD = #4;              { switches DebugMode, in the STING debug mode }
  KeyCtrlS = #19;             { switches the sound off and back on }
  SoundPaused = 2;            { the SoundMode value Ctrl-S sets }
  VideoSetMode = $00;         { INT 10h function: set video mode }

{ 0899:0000. Ends the program: puts the sound back the way it was before a Ctrl-S pause, stops the
  sound unit's output (res03), returns the screen to the video mode saved at start-up, and halts. }
procedure QuitGame;
begin
  SoundMode := SoundModeBeforePause;
  res03_fn_00DC(ds2612);
  Regs.AH := VideoSetMode;
  Regs.AL := SavedVideoMode;
  Intr($10, Regs);
  Halt;
end;

{ 0899:0059. The ReadKey of the game: waits for a key and returns it. Ctrl-S pauses the sound (or
  resumes it if it was paused). When the program was started with the parameter STING (a developers'
  debug mode), Ctrl-D switches DebugMode and Ctrl-C quits. After any key that is not the first half of
  an extended key, the keys typed ahead are thrown away. }
function ReadGameKey: Char;
var
  Key: Char;
begin
  Key := ReadKey;
  if Key = KeyCtrlS then
    if SoundMode <> SoundPaused then
    begin
      SoundModeBeforePause := SoundMode;
      res03_fn_00DC(ds2612);
      SoundMode := SoundPaused;
    end
    else if SoundModeBeforePause in [0, 1] then
    begin
      SoundMode := SoundModeBeforePause;
      res03_fn_017B;
    end;
  if ParamStr(1) = 'STING' then
  begin
    if Key = KeyCtrlD then DebugMode := not DebugMode;
    if Key = KeyCtrlC then QuitGame;
  end;
  if Key <> #0 then
    while KeyPressed do Key := ReadKey;
  ReadGameKey := Key;
end;

{ 0899:0104. Meant to throw away every key typed ahead (called before prompts such as the code
  wheel's), but it returns at once. QUIRK 0899:010A: the Exit comes first, so the loop never runs. }
procedure FlushKeyboard;
var
  Key: Char;
begin
  Exit;
  while KeyPressed do Key := ReadGameKey;
end;

{ 0899:0122. Reads one key if one is waiting and throws it away (through ReadGameKey, so Ctrl-S and
  the debug keys still work). }
procedure DiscardWaitingKey;
var
  Key: Char;
begin
  if KeyPressed then Key := ReadGameKey;
end;

begin
end.

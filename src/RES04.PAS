unit RES04;
{ The keyboard layer and the way out of the game (whitepaper 5.8). Game code reads keys through
  ReadGameKey, which also handles the Ctrl-S sound switch and the keys of the STING debug mode;
  QuitGame copies the saved sound mode, calls the sound unit and ends the program. }
{$A-,F+,S-,R-,G-,I-}
interface
procedure QuitGame;
function ReadGameKey: Char;
procedure FlushKeyboard;
procedure DiscardWaitingKey;
implementation
uses Crt, Dos, POOLVARS, RES03;

const
  KeyExtended = #0;           { first byte of an extended key; the scan code comes on the next read }
  KeyCtrlC = #3;              { quits, in the STING debug mode }
  KeyCtrlD = #4;              { switches DebugMode, in the STING debug mode }
  KeyCtrlS = #19;             { the sound-mode key }
  SoundPaused = 2;            { the SoundMode value the Ctrl-S pause path sets }
  { A second Ctrl-S resumes only when SoundModeBeforePause is one of these (0899:008B).
    What 0 and 1 are is not shown in this unit. }
  ResumeIfSaved0 = 0;
  ResumeIfSaved1 = 1;
  VideoBios = $10;            { INT 10h, video services }
  VideoSetMode = $00;         { INT 10h function: set video mode }

{ 0899:0000. Ends the program. Copies SoundModeBeforePause into SoundMode and calls
  PlaySound(ds2612), the same call as the Ctrl-S pause path, not SilenceSound (the resume
  call at 0899:00A1). What that call does to the sound is not shown here; the sound unit's
  proven stop is 08AE:13B1 (whitepaper 5.14). Then INT 10h function VideoSetMode with
  SavedVideoMode in AL. No writer of SavedVideoMode is in this unit, so where that byte was
  saved is not shown. Then Halt. }
procedure QuitGame;
begin
  SoundMode := SoundModeBeforePause;
  PlaySound(ds2612);
  Regs.AH := VideoSetMode;
  Regs.AL := SavedVideoMode;
  Intr(VideoBios, Regs);
  Halt;
end;

{ 0899:0059. The ReadKey of the game: waits for a key and returns a Char. Ctrl-S, when SoundMode
  is not SoundPaused, saves SoundMode in SoundModeBeforePause, calls PlaySound(ds2612) and
  sets SoundMode to SoundPaused. A later Ctrl-S resumes only when SoundMode is already
  SoundPaused and SoundModeBeforePause is ResumeIfSaved0 or ResumeIfSaved1: it copies the saved
  mode back and calls SilenceSound. Any other second Ctrl-S does nothing. When ParamStr(1) is
  STING, Ctrl-D switches DebugMode and Ctrl-C quits. Those tests, and the Ctrl-S test, use the
  first key. Then, unless that key is KeyExtended, every key still waiting is read into Key
  (0899:00E4), so the function returns the last key in the buffer. The 258-byte frame is
  ParamStr's string temporary. }
function ReadGameKey: Char;
var
  Key: Char;
begin
  Key := ReadKey;
  if Key = KeyCtrlS then
    if SoundMode <> SoundPaused then
    begin
      SoundModeBeforePause := SoundMode;
      PlaySound(ds2612);
      SoundMode := SoundPaused;
    end
    else if SoundModeBeforePause in [ResumeIfSaved0, ResumeIfSaved1] then
    begin
      SoundMode := SoundModeBeforePause;
      SilenceSound;
    end;
  if ParamStr(1) = 'STING' then
  begin
    if Key = KeyCtrlD then DebugMode := not DebugMode;
    if Key = KeyCtrlC then QuitGame;
  end;
  if Key <> KeyExtended then
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

{ 0899:0122. If a key is waiting, reads it through ReadGameKey and throws the result away, so
  Ctrl-S and the STING keys still run. ReadGameKey's own drain can still consume keys past
  that one. }
procedure DiscardWaitingKey;
var
  Key: Char;
begin
  if KeyPressed then Key := ReadGameKey;
end;

{ 0899:013C. Empty initialisation: push bp, mov bp, sp, pop bp, retf, then 15 zero bytes of
  paragraph padding. }
begin
end.

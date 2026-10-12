unit OVL01;
{ Title screens and credits (whitepaper 5.8): ShowTitleScreen loads and shows the title
  picture, waits for a key or a deadline, then shows the credits (ShowCredits);
  WaitKeyOrTimeout waits for a key or a tick-count timeout. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure WaitKeyOrTimeout(Pause: Word);
procedure ShowCredits;
procedure ShowTitleScreen;
implementation
uses Crt, POOLVARS, RES04, RES06, RES07, RES09;

const
  Green = $0A;                { EGA text colour of the credit names }
  LightCyan = $0B;            { EGA text colour of most credit lines }
  Yellow = $0E;               { EGA text colour of the headers }

{ ovl01:0000. Waits for a keypress or a timeout: loops until the res06_fn_0C3F tick count
  reaches Start plus 100 times Pause, or a key is waiting (KeyPressed), then calls
  FlushKeyboard, which does nothing (QUIRK 0899:010A: its first statement is Exit), so a
  pending key still reaches the next screen. Called by the credits (Pause 10) and the title
  sequence (Pause 5). }
procedure WaitKeyOrTimeout(Pause: Word);
var
  Start: Longint;             { res06_fn_0C3F when the wait began }
  Limit: Longint;             { Start plus 100 times Pause: the tick count that ends the wait }
begin
  Start := res06_fn_0C3F;
  Limit := 100 * Pause + Start;
  repeat
  until (res06_fn_0C3F >= Limit) or KeyPressed;
  FlushKeyboard;
end;
{ ovl01:0206. Shows the credits screen: two empty windows (DrawWindow) and some thirty
  name and role lines in green, cyan and yellow (res06_fn_0626), then waits for a key or a
  timeout (WaitKeyOrTimeout). Called by the title sequence (ShowTitleScreen). }
procedure ShowCredits;
begin
  DrawWindow(1, 1, $26, 3, 0, 0, '');
  DrawWindow(1, 5, $26, $17, 0, 0, '');
  res06_fn_0626(5, 1, Green, 'scenario created by:');
  res06_fn_0626($1A, 1, Yellow, 'tsr, inc.');
  res06_fn_0626($0F, 2, Green, 'jim ward');
  res06_fn_0626(2, 3, Green, 'david cook,steve winter,mike breault');
  res06_fn_0626(1, 5, Green, 'game created by:');
  res06_fn_0626($12, 5, Yellow, 'ssi special projects');
  res06_fn_0626($0E, 6, LightCyan, 'version 1.3');
  res06_fn_0626(2, 7, Yellow, 'programming:');
  res06_fn_0626($14, 7, Yellow, 'original');
  res06_fn_0626(2, 8, LightCyan, 'scot bayless');
  res06_fn_0626($14, 8, Yellow, 'programming:');
  res06_fn_0626(2, 9, LightCyan, 'brad myers');
  res06_fn_0626($14, 9, LightCyan, 'keith brors');
  res06_fn_0626(2, $0A, LightCyan, 'russ brown');
  res06_fn_0626($14, $0A, LightCyan, 'brad myers');
  res06_fn_0626(2, $0B, LightCyan, 'ted greer');
  res06_fn_0626(2, $0D, Yellow, 'graphic arts:');
  res06_fn_0626($14, $0D, Yellow, 'encounter coding:');
  res06_fn_0626(2, $0E, LightCyan, 'tom wahl');
  res06_fn_0626($14, $0E, LightCyan, 'paul murray');
  res06_fn_0626(2, $0F, LightCyan, 'fred butts');
  res06_fn_0626($14, $0F, LightCyan, 'russ brown');
  res06_fn_0626(2, $10, LightCyan, 'darla marasco');
  res06_fn_0626($14, $10, LightCyan, 'victor penman');
  res06_fn_0626(2, $11, LightCyan, 'susan halbleib');
  res06_fn_0626($14, $11, LightCyan, 'dave shelley');
  res06_fn_0626(2, $13, Yellow, 'project manager');
  res06_fn_0626($14, $13, Yellow, 'developer:');
  res06_fn_0626(2, $14, LightCyan, 'victor penman');
  res06_fn_0626($14, $14, LightCyan, 'george mac donald');
  res06_fn_0626(2, $16, Yellow, 'testing:');
  res06_fn_0626($0B, $16, LightCyan, 'joel billings,steve salyer');
  res06_fn_0626(2, $17, LightCyan, 'james kucera,robert daly,rick white');
  WaitKeyOrTimeout($0A);
end;
{ ovl01:0627. Shows the title sequence: backs up GameDir and clears it, loads the title
  picture (res07_fn_0111) and shows it (res07_fn_1951), waits (WaitKeyOrTimeout), then, when
  the F flag (ds49D1) is set, reloads, reshows, sets the palette (res07_fn_2595) and waits
  for a key or a deadline (res06_fn_0C3F ticks) with an EGA-only animation that never runs
  (QUIRK ovl01:0729: Total is Random(4), always below 50000), then calls FlushKeyboard, which
  does nothing (QUIRK 0899:010A), and shows the credits (ShowCredits). With F clear it only
  restores GameDir and returns. Entry point (no callers in the map). Side effects: screen,
  GameDir. }
procedure ShowTitleScreen;
var
  Pic: PT8x8Bank;
  Total: Longint;
  I: Byte;
  DirBackup: String40;
  Deadline: Longint;
begin
  Total := 0;
  Pic := nil;
  DirBackup := GameDir;
  GameDir := '';
  res07_fn_0111('title', 1, 0, 0, Pic);
  res07_fn_1951(0, 0, Pic);
  WaitKeyOrTimeout(5);
  if ds49D1 = 0 then
    GameDir := DirBackup
  else
  begin
    res07_fn_0111('title', 2, 0, 0, Pic);
    GameDir := DirBackup;
    res07_fn_1951(0, 0, Pic);
    res07_fn_2595(Pic);
    Deadline := res06_fn_0C3F + 500;
    repeat
      if VideoAdapter = 1 then
      begin
        Inc(Total, Random(4));
        if Total > 50000 then
        begin
          Total := 0;
          for I := 0 to Random(3) + 1 do
          begin
            res07_fn_2A0D(1, 9);
            Delay($96);
            res07_fn_2A0D(1, $0B);
            Delay($64);
            res07_fn_2A0D(1, $0F);
            Delay($32);
            res07_fn_2A0D(1, $0B);
            Delay($64);
            res07_fn_2A0D(1, 9);
            Delay($96);
            res07_fn_2A0D(1, 1);
          end;
        end;
      end;
    until KeyPressed or (res06_fn_0C3F >= Deadline);
    FlushKeyboard;
    ShowCredits;
  end;
end;

begin
end.

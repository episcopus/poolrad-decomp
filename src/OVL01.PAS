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

{ ovl01:0000. Waits for a keypress or a timeout: loops until the GameClock tick count
  reaches Start plus 100 times Pause, or a key is waiting (KeyPressed), then calls
  FlushKeyboard, which does nothing (QUIRK 0899:010A: its first statement is Exit), so a
  pending key still reaches the next screen. Called by the credits (Pause 10) and the title
  sequence (Pause 5). }
procedure WaitKeyOrTimeout(Pause: Word);
var
  Start: Longint;             { GameClock when the wait began }
  Limit: Longint;             { Start plus 100 times Pause: the tick count that ends the wait }
begin
  Start := GameClock;
  Limit := 100 * Pause + Start;
  repeat
  until (GameClock >= Limit) or KeyPressed;
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
{ ovl01:0627. Shows the title sequence: backs up GameDir (into a String40, so a directory of
  more than 40 characters comes back cut: StrLCopy limit $28 at ovl01:0647) and clears it, loads
  the title picture (res07_fn_0111) and shows it (res07_fn_1951), waits (WaitKeyOrTimeout), then,
  when the F flag (ds49D1) is set, reloads, reshows, frees the title picture (res07_fn_2595) and
  waits for a key or a deadline (GameClock ticks, 500 after the start). On EGA each pass of
  that wait adds Random(4) to the running sum Total (ovl01:0721..0726); when the sum passes 50000
  the palette animation runs (res07_fn_2A0D with Delay) and the sum starts again from 0
  (ovl01:073E..0743). QUIRK ovl01:0729: whether the animation ever fires depends on how many
  passes the loop makes before the deadline, so on the CPU speed (about 33,000 passes at the
  mean of 1.5); it did not fire in the oracle run (whitepaper 5.8), on period hardware it is not
  known. Then calls FlushKeyboard, which does nothing (QUIRK 0899:010A), and shows the credits
  (ShowCredits). With F clear it only restores GameDir and returns. Entry point (no callers in
  the map). Side effects: screen, GameDir. }
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
    Deadline := GameClock + 500;
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
    until KeyPressed or (GameClock >= Deadline);
    FlushKeyboard;
    ShowCredits;
  end;
end;

begin
end.

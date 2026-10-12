unit OVL01;
{ ovl01: overlay unit, 2062 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure WaitKeyOrTimeout(Pause: Word);
procedure ShowCredits;
procedure ovl01_e1;
implementation
uses Crt, POOLVARS, RES04, RES06, RES07, RES09;

const
  Green = $0A;                { EGA text colour of the credit names }
  LightCyan = $0B;            { EGA text colour of most credit lines }
  Yellow = $0E;               { EGA text colour of the headers }

{ ovl01:0000. Waits for a keypress or a timeout: loops until the res06_fn_0C3F tick count
  reaches Start plus 100 times Pause, or a key is waiting (KeyPressed), then drains the
  keyboard buffer (FlushKeyboard) so the key does not leak into the next screen. Called by
  the credits (Pause 10) and the title sequence (Pause 5). }
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
  timeout (WaitKeyOrTimeout). Called by the title sequence (ovl01_e1). }
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
{ ovl01:0627: retf 0: 0 bytes of parameters; 60 bytes of locals }
{@stub} procedure ovl01_e1; begin end;

begin
end.

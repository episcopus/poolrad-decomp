unit OVL01;
{ ovl01: overlay unit, 2062 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure WaitKeyOrTimeout(Pause: Word);
procedure ovl01_fn_0206;
procedure ovl01_e1;
implementation
uses Crt, POOLVARS, RES04, RES06, RES07, RES09;

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
{ ovl01:0206: retf 0: 0 bytes of parameters; 38 bytes of locals }
{@stub} procedure ovl01_fn_0206; begin end;
{ ovl01:0627: retf 0: 0 bytes of parameters; 60 bytes of locals }
{@stub} procedure ovl01_e1; begin end;

begin
end.

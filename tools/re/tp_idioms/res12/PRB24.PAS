{ Probe for res12:2228 (playbook 30).
  Question: for `if S in [0,1] then A else B`, does TP 6.0 emit
  `lcall System_SetIn; jne <then>` or `jne <else>`? The original 00BA:22D7 has
  `lcall System_SetIn; jne 0x2315` and 0x2315 is the `HP := Remaining` (then) branch. }
{$A-,F+,S-,R-,G-,I-}
program Res12Probe24;

var
  S, Are: Byte;

procedure P;
begin
  if S in [0, 1] then
    Are := 1
  else
    Are := 2;
end;

procedure Q;
begin
  if not (S in [0, 1]) then
    Are := 2
  else
    Are := 1;
end;

begin
  P;
  Q;
end.

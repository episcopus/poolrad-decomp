{ Probe for res12:23B7 (playbook 30).
  Question: for a Byte function assigning the result directly in an if/else, does TP 6.0 use
  sub sp,2 and store to [bp-1] with `mov al,[bp-1]` at the end (the original 00BA:23B7)? }
{$A-,F+,S-,R-,G-,I-}
program Res12Probe25;

var
  X: Byte;

function Direct(X: Byte): Byte; far;
begin
  if X = 0 then
    Direct := 1
  else
    Direct := 0;
end;

function WithLocal(X: Byte): Byte; far;
var
  R: Byte;
begin
  if X = 0 then
    R := 1
  else
    R := 0;
  WithLocal := R;
end;

begin
  X := Direct(1) + WithLocal(1);
end.

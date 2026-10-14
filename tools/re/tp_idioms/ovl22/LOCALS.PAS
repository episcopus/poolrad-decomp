{ Probe: the stack offsets TP 6.0 gives declared locals in a far procedure with a
  far pointer, a Boolean, two ShortInts and a Byte, so ovl22_e5's frame (OK at [bp-1],
  X at [bp-3], Y at [bp-4], Dir at [bp-5], Caster at [bp-9]) can be reproduced. }
{$A-,F+,S-,R-,G-,I-}
program Locals;

type
  P = ^Byte;

var
  B: Byte;

procedure Q1; far;
var
  Caster: P;
  OK: Boolean;
  X, Y: ShortInt;
  Dir: Byte;
begin
  Caster := nil;
  OK := True;
  X := 1; Y := 2; Dir := 3;
  if OK then B := Dir + X + Y;
end;

procedure Q2; far;
var
  OK: Boolean;
  X, Y: ShortInt;
  Dir: Byte;
  Caster: P;
begin
  Caster := nil;
  OK := True;
  X := 1; Y := 2; Dir := 3;
  if OK then B := Dir + X + Y;
end;

begin
  Q1; Q2;
end.

{ Probe: how TP 6.0 stores a Byte-valued far function's result into a Boolean local that is
  passed as a var Boolean parameter. ovl22:30D9 (MonsterBreath) shows `mov byte [bp-1],al`
  after the res12_fn_2637 call, and [bp-1] is the var Boolean DamageTargetInCell was given, so
  the source must cast: `Blocked := Boolean(res12_fn_2637(Who));`. The cast of a Byte value to
  Boolean (same size) compiles to no code, so the plain store survives. A direct Byte-to-Boolean
  var (without the cast) is a compile error (Error 26: Type mismatch), and `Flag := Fn <> 0`
  would add a compare. }
{$A-,F+,S-,R-,G-,I-}
program BoolCast;

function Fn: Byte; far;
begin
  Fn := 1;
end;

procedure Sink(var Flag: Boolean); far;
begin
  Flag := True;
end;

procedure Caller; far;
var
  Flag: Boolean;
  X, Y: ShortInt;
begin
  Flag := Boolean(Fn);
  X := 0;
  Y := 0;
  Sink(Flag);
end;

begin
  Caller;
end.

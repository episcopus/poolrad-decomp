program INDEX;
{ Probe: find the exact source that compiles `mov al,[L]; inc al; cwde` (ovl22:2CF0). }
{$A-}
type
  T = array[0..7, 0..13] of LongInt;
var
  A: T;
  G: LongInt;

procedure Q1; { ShortInt L, L + 1 }
var L: ShortInt; C: ShortInt;
begin G := A[C, L + 1]; end;

procedure Q2; { ShortInt L, Succ }
var L: ShortInt; C: ShortInt;
begin G := A[C, Succ(L)]; end;

procedure Q3; { Byte L, ShortInt(L + 1) }
var L: Byte; C: ShortInt;
begin G := A[C, ShortInt(L + 1)]; end;

procedure Q4; { Byte L, ShortInt(L) + 1 }
var L: Byte; C: ShortInt;
begin G := A[C, ShortInt(L) + 1]; end;

procedure Q5; { ShortInt L, Succ with byte cast }
var L: ShortInt; C: ShortInt;
begin G := A[C, Succ(Byte(L))]; end;

procedure Q6; { ShortInt L, L + 1 as byte }
var L: ShortInt; C: ShortInt;
begin G := A[C, ShortInt(Byte(L) + 1)]; end;

begin
  Q1; Q2; Q3; Q4; Q5; Q6;
end.

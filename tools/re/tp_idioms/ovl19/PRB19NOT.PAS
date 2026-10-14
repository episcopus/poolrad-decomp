program PRB19NOT;
{ SellItem (ovl19:1CEE) tests a kind byte against $49 and then $1C in one condition. The original
  jumps to the divide branch on the first miss and falls into it after the second test; the plain
  `if (K = $49) and (K = $1C) then Mul else Div` lays the multiply branch first (cmp; jne Div; cmp;
  jne Div; Mul). The negated form `if not (...) then Div else Mul` gives the original's layout. }
{$A-,O+,F+,S-,R-,G-,I-}
const
  KindA = $49;
  KindB = $1C;

procedure ProbePlain(Kind: Byte; var Done: Byte);
begin
  if (Kind = KindA) and (Kind = KindB) then
    Done := 1
  else
    Done := 2;
end;

procedure ProbeNot(Kind: Byte; var Done: Byte);
begin
  if not ((Kind = KindA) and (Kind = KindB)) then
    Done := 2
  else
    Done := 1;
end;

var
  Flag: Byte;

begin
  ProbePlain(Flag, Flag);
  ProbeNot(Flag, Flag);
end.

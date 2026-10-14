{ TP 6.0 does not accept an Integer variable as a var Word parameter either (Error 26),
  so the chain ChooseFromList/ChooseSpellFromList/ovl22_e1 must have ONE type throughout. }
{$A-,F+,S-,R-,G-,I-}
program InToWd;
procedure P(var X: Word);
begin
  X := 1;
end;
var
  I: Integer;
begin
  P(I);
end.

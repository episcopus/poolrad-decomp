{ A variable typecast is a variable reference, so it can be passed to a var parameter of the
  other signedness: TP 6.0 accepts P(Integer(W)) with W: Word although P(W) is Error 26
  (WDTOIN.PAS). ovl22:008A (the spell menu picker) keeps its Choice a Word, like its callers
  ovl19:299C and ovl15, and hands Integer(Choice) to ChooseFromList (var Choice: Integer). }
{$A-,F+,S-,R-,G-,I-}
program VarCast;
procedure P(var X: Integer);
begin
  X := 1;
end;
var
  W: Word;
begin
  P(Integer(W));
  if Integer(W) < 0 then
    W := 0;
end.

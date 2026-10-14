{ TP 6.0 does not accept a Word variable as a var Integer parameter (Error 26).
  Evidence for blocking ovl22_e1: its Choice must reach ChooseFromList (ovl25:0D9A,
  var Choice: Integer, used with OVL05/OVL06/OVL07), but ovl19's ChooseSpellFromList
  and ovl15's Choice are declared Word. `make tpc SRC=.../WDTOIN.PAS` prints the error. }
{$A-,F+,S-,R-,G-,I-}
program WdToIn;
procedure P(var X: Integer);
begin
  X := 1;
end;
var
  W: Word;
begin
  P(W);
end.

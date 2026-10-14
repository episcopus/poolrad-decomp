{ NoChoice = $FFFF cannot be assigned to an Integer (Error 76: Constant out of range), so
  ovl15's Choice is Word. Its 3 routines and ovl19 would need Choice: Integer and NoChoice = -1
  to accept ovl22_e1's (Integer) Choice, which ChooseFromList forces. }
{$A-,F+,S-,R-,G-,I-}
program NoConst;
const NoChoice = $FFFF;
var C: Integer;
begin
  C := NoChoice;
end.

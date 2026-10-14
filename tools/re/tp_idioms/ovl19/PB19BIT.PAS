program PB19BIT;
{ Does TP 6.0 compile `X > $7F` and `X >= $80` to the same bytes, in a boolean assignment and
  in an if test, and `X < $80` against `X <= $7F`? The ovl19 review asks for one name per B84 /
  affect bit; the answer decides whether one constant can serve both spellings. }
{$A-,O+,F+,S-,R-,G-,I-}
var
  B: Byte;
  Flag: Boolean;
begin
  Flag := B > $7F;
  Flag := B >= $80;
  Flag := B < $80;
  Flag := B <= $7F;
  if B > $7F then
    Flag := True;
  if B >= $80 then
    Flag := True;
  if B < $80 then
    Flag := True;
  if B <= $7F then
    Flag := True;
end.

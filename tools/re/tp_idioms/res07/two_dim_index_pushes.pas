program T5;
{$A-,O+,F+,S-,R-,G-,I-}
type
  TPal = array[0..7] of Byte;
  PPal = ^TPal;
var
  Tab: array[0..15, 0..3] of Byte;
  Out: array[0..7] of Byte;
function Pick(Index: Byte; Source: PPal): Byte;
begin
  Pick := Source^[Index shr 1] and $0F;
end;
procedure Vf(P: PPal; Col: Byte);
var K: Byte;
begin
  K := 2;
  Out[K] := Out[K] or Tab[Pick(Col, P), K];
end;
begin
  Vf(nil, 1);
end.

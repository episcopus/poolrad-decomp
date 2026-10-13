program T2;
{$A-,O+,F+,S-,R-,G-,I-}
type
  TPal = array[0..7] of Byte;
  PPal = ^TPal;
var
  Tab: array[0..63] of Byte;
  Out: array[0..7] of Byte;
function Pick(Index: Byte; Source: PPal): Byte;
begin
  Pick := Source^[Index shr 1] and $0F;
end;
procedure V4(P: PPal; Col: Byte);
var
  K: Byte;
  Data: array[0..0] of Byte;
begin
  K := 2;
  Out[K] := Out[K] or Tab[K + Pick(Col, P) * 4];
end;
procedure V5(P: PPal; Col: Byte);
var
  K: Byte;
begin
  K := 2;
  Out[K] := Out[K] or Tab[Pick(Col, P) * 4 + K];
end;
begin
  V4(nil, 1); V5(nil, 1);
end.

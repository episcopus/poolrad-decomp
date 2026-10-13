program T3;
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
procedure Va(P: PPal; Col: Byte);
var K: Byte;
begin
  K := 2;
  Out[K] := Out[K] or Tab[(Pick(Col, P) shl 2) + K];
end;
procedure Vb(P: PPal; Col: Byte);
var K: Byte;
begin
  K := 2;
  Out[K] := Out[K] or Tab[K + (Pick(Col, P) shl 2)];
end;
procedure Vc(P: PPal; Col: Byte);
var K: Byte;
begin
  K := 2;
  Tab[Pick(Col, P) * 4 + K] := Out[K] or Tab[Pick(Col, P) * 4 + K];
end;
begin
  Va(nil, 1); Vb(nil, 1); Vc(nil, 1);
end.

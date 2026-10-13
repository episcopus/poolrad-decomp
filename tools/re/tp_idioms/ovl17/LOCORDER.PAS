program LocOrder;
type
  PCharX = ^TRec;
  TRec = record Next: PCharX; B: Byte; end;
var
  G: Integer;
  Q: PCharX;
procedure DoIt(A: PCharX; var Res: Integer);
var
  P: PCharX;
  Used: array[0..7] of Byte;
  Who: PCharX;
begin
  P := A;
  Used[0] := 1;
  Who := A;
  Res := Ord(P = Who);
end;
begin
  DoIt(Q, G);
end.

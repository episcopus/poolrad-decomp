program DsNil;
type
  PCharX = ^TRec;
  TRec = record Next: PCharX; B: Byte; end;
var
  ds5D96: LongInt;
  Q: PCharX;
procedure A(Char: PCharX);
begin
  if PCharX(ds5D96) = nil then
    ds5D96 := LongInt(Char);
end;
procedure B(Char: PCharX);
begin
  if ds5D96 = 0 then
    ds5D96 := LongInt(Char);
end;
begin
  A(Q); B(Q);
end.

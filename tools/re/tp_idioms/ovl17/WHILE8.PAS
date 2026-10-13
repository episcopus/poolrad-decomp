program While8;
type
  PCharX = ^TRec;
  TRec = record Next: PCharX; Icon: Byte; end;
var
  Q: PCharX;
  U: Boolean;
procedure DoIt(Who: PCharX; var Used: Boolean);
begin
  Who^.Icon := 0;
  while (Who^.Icon < 8) and Used do
    Inc(Who^.Icon);
end;
begin
  DoIt(Q, U);
end.

program SelAssign;
type
  PCharX = ^TRec;
  TRec = record Next: PCharX; Icon: Byte; end;
var
  SelGlobal: PCharX;
  M: PCharX;
procedure A(Member: PCharX);
var
  Sel: PCharX;
begin
  SelGlobal := Member;
  Sel := SelGlobal;
  Sel^.Icon := 0;
end;
procedure B(Member: PCharX);
begin
  SelGlobal := Member;
  with SelGlobal^ do
    Icon := 0;
end;
begin
  A(M); B(M);
end.

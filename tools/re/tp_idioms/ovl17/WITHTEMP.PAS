program WithTemp;
type
  PCharX = ^TRec;
  TRec = record Next: PCharX; Icon: Byte; end;
var
  SelGlobal: PCharX;
  M: PCharX;
procedure C(Member: PCharX);
var
  P: PCharX;
  Used: array[0..7] of Boolean;
begin
  P := Member;
  Used[0] := True;
  with SelGlobal^ do
  begin
    Icon := 0;
    while (Icon < 8) and Used[Icon] do
      Inc(Icon);
  end;
end;
begin
  C(M);
end.

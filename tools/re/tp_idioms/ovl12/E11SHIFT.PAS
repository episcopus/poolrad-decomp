program E11SHIFT;
{ Probe for ovl12:0400 (ComputerTakesOver). Compile with make tpc SRC=tools/re/tp_idioms/ovl12/E11SHIFT.PAS DISASM=1.
  Expected (the original's shapes): Div_Byte64 and Div_Byte128 use mov cl,n; shr ax,cl; Shr_Byte6 uses mov cx,6.
  ShortIntShl uses cwde then mov cl,6; shl ax,cl. LessEq7F gives cmp 7Fh; ja, LessThan80 gives cmp 80h; jae. }
var
  Y: Byte;
  Z: Byte;
procedure Div_Byte64(X: Byte);
begin
  Y := (X and $40) div 64;
end;
procedure Div_Byte128(X: Byte);
begin
  Y := X div 128;
end;
procedure Shr_Byte6(X: Byte);
begin
  Y := (X and $40) shr 6;
end;
procedure ShortIntShl(X: Byte);
begin
  Y := ShortInt(X) * 64;
end;
procedure LessEq7F(X: Byte);
begin
  if X <= $7F then Y := 1;
end;
procedure LessThan80(X: Byte);
begin
  if X < $80 then Y := 1;
end;
begin
  Div_Byte64(1);
  Div_Byte128(2);
  Shr_Byte6(3);
  ShortIntShl(4);
  LessEq7F(5);
  LessThan80(6);
end.

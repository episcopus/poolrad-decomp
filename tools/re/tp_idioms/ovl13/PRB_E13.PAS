{ Probe for ovl13 e13 (ovl13:1BF8): the ether scan's for-loop bound test, the
  `Status in [6,7,8]` set test and the BodyTable X/Y compares. Compile with the pinned
  TP 6.0 and disassemble: which of the variants gives `ja skip`, `jne skip` and an 8-bit
  `mov al,[field]; cmp al,[local]`. }
program PRB_E13;
type
  TB = record Who: Pointer; X, Y: ShortInt; Tile: Byte; end;
var
  Tab: array[1..8] of TB;
  I: Byte;
  Count: Byte;
  Found: Byte;
  Xb, Yb: Byte;
  Xs, Ys: ShortInt;
  St: Byte;

{ Variant A: for with a Byte bound and a Byte loop counter. }
procedure A;
begin
  for I := 1 to Count do
    if Tab[I].Who <> nil then
      Found := I;
end;

{ Variant B: the set test `Status in [6,7,8]`. }
procedure B;
begin
  if St in [6, 7, 8] then
    Found := 1;
end;

{ Variant C: ShortInt field compared with a ShortInt local. }
procedure C;
begin
  if Tab[I].X = Xs then
    Found := 1;
  if Tab[I].Y = Ys then
    Found := 2;
end;

{ Variant D: ShortInt field compared with a Byte local. }
procedure D;
begin
  if Tab[I].X = Xb then
    Found := 1;
end;
begin
  A;
  B;
  C;
  D;
end.

program GUARD;
{ Probe: find the source of ovl22:2A5C's guard shape `jne BODY; ... je AFTER` with no extra jmp. }
type
  TL = record X1, Y1, X2, Y2: Integer; First: Byte; end;
var
  L: TL;
  G: Byte;

procedure G7;
begin
  repeat
    G := 0;
    if (L.X1 <> L.X2) or (L.Y1 <> L.Y2) then
      repeat
        G := 1;
      until (G = 9) or (L.First >= 8)
    else
      G := 0;
    G := 2;
  until G = 99;
end;

procedure G8;
begin
  repeat
    G := 0;
    if (L.X1 <> L.X2) or (L.Y1 <> L.Y2) then
    begin
      repeat
        G := 1;
      until (G = 9) or (L.First >= 8);
    end;
    G := 2;
  until G = 99;
end;

begin
  G7;
  G8;
end.

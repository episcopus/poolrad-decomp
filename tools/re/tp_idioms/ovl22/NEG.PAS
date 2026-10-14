program NEG;
{ Probe: which source form negates a byte local as `mov dx,ax; xor ax,ax; sub ax,dx` (the original's
  ovl22:2B71 shape) rather than `neg ax`. }
var
  S: ShortInt;
  B: Byte;
  I: Integer;

procedure NegShortInt;
begin
  S := -S;
end;

procedure SubShortInt;
begin
  S := 0 - S;
end;

procedure MulShortInt;
begin
  S := S * -1;
end;

procedure NegInteger;
begin
  I := -I;
end;

begin
  NegShortInt;
  SubShortInt;
  MulShortInt;
  NegInteger;
end.

{ Probe: pointer nil test at the top of a for-loop body (ovl22:08C3's is
  `or ax,[seg]; jne body; jmp loopbottom`). }
{$A-,F+,S-,R-,G-,I-}
program LoopNil;

type
  P = ^Byte;

var
  Arr: array[0..20] of P;
  B: Byte;
  S: Byte;

procedure Q; far;
var
  I: Byte;
  T: P;
begin
  for I := 1 to B do
  begin
    if Arr[I] <> nil then
    begin
      T := Arr[I];
      S := T^;
    end;
  end;
end;

procedure W; far;
var
  I: Byte;
begin
  I := 1;
  while I <= B do
  begin
    if Arr[I] <> nil then
      S := 1;
    Inc(I);
  end;
end;

begin
  Q;
  W;
end.

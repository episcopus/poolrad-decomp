{ Probe for ovl17_e7's table indexing (playbook 30). The original reads ds08C5[18 + B9E*5 + Roll]
  as `di := B9E*5 + Roll; mov al,[di+0x8d7]`: the +18 is folded into the array's base displacement.
  Question: which source shape makes the compiler fold the constant instead of adding it in a
  register? }
{$F+,S-,R-,I-}
program IdxProbe;

var
  Arr: array[0..$3A] of Char;
  B: Byte;
  N: Byte;

function F(R: Byte): Byte; begin F := R; end;

procedure T1; begin B := Ord(Arr[F(1) + N * 5 + 18]); end;
procedure T2; begin B := Ord(Arr[N * 5 + F(1) + 18]); end;
procedure T3; begin B := Ord(Arr[18 + N * 5 + F(1)]); end;

begin
  T1;
  T2;
  T3;
end.

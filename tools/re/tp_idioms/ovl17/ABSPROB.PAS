{ Probe for ovl17_e7's table base (playbook 30). The original reads the body/head bank tables at
  DS:08D7/08E1/08EB/08F5/08C7 (inside the region POOLVARS calls ds08C5) as `[di + 0x8d7]`: the
  constant is folded into the displacement. Question: does a record field alias with `absolute`
  fold the field offset into the base? }
{$F+,S-,R-,I-}
program AbsProbe;

type
  TBanks = record
    Pad: array[0..1] of Byte;      { +0 }
    Head: array[0..7] of Byte;     { +2 }
    Pad2: array[0..7] of Byte;     { +10, up to +18 }
    Body0: array[0..9] of Byte;    { +18 }
  end;

var
  Arr: array[0..$3A] of Char;
  Banks: TBanks absolute Arr;
  B: Byte;
  N: Byte;

function F(R: Byte): Byte; begin F := R; end;

procedure T;
begin
  B := Banks.Body0[F(1) + N * 5];
end;

begin
  T;
end.
